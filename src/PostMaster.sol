// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import "solmate/tokens/ERC20.sol";
import "./interfaces/IPostageStamp.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    // For swapping ETH to tokens
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    // For quotes
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface ChainLog {
    function getAddress(bytes32 _key) external view returns (address addr);
}

/**
 * @title Datacoop PostMaster
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @notice Allow an xDAI to Swarm batch to be created.
 * @dev This contract makes use of:
 *     - `UniswapV2Router02` to swap directly from xDAI to BZZ.
 *     - `PostageStamp` to create the batch.
 */
contract PostMaster {
    // --- constants
    // The UniswapV2Router contract for the Honeyswap DEX
    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x1C232F01118CB8B424793ae03F870aa7D0ac7f77);
    // The bridged BZZ token on Gnosis Chain
    ERC20 private constant bzz = ERC20(0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da);
    // Configure the wxDAI token - normal ERC20 will do as deposit/withdraw is handled by the router
    ERC20 private constant wxDAI = ERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);
    // Configure the chainlog
    ChainLog private constant log = ChainLog(0x4989F405b9c449Ccf3FdEa0f60B613afF1E55E14);
    // ChainLog key for PostageStamp
    bytes32 private constant POSTAGE_STAMP_KEY = bytes32("SWARM_POSTAGE_STAMP");
    // Blocktime
    uint256 private constant BLOCKTIME = 5;

    // The postage stamp contract
    IPostageStamp private postageStamp;

    // errors
    error PostageStampNotFound();
    error PostageStampPaused();
    error InvalidPostageBatchTime();

    constructor() {
        // Get the postage stamp contract
        postageStamp = IPostageStamp(log.getAddress(POSTAGE_STAMP_KEY));

        // Sanity checks
        if (!(address(postageStamp) != address(0))) revert PostageStampNotFound();
        if (!(postageStamp.paused() == false)) revert PostageStampPaused();

        // Approve the postage stamp contract to spend our BZZ
        bzz.approve(address(postageStamp), type(uint256).max);
    }

    modifier checkPostageStampPaused() {
        // Check to make sure postage stamp is not paused
        if (postageStamp.paused()) {
            recover();
        }
        _;
    }

    /**
     * Purchase a postage batch.
     * @param owner The `owner` of the postage batch
     * @param initialBalancePerChunk The amount of BZZ to pay down per chunk
     * @param depth The depth, and therefore size of the batch to purchase
     * @param bucketDepth A parameter which seems to do nothing 🗑🚮
     * @param nonce The nonce of the batch to purchase
     * @param immutableFlag Whether the batch is immutable
     */
    function purchase(
        address owner,
        uint256 initialBalancePerChunk,
        uint8 depth,
        uint8 bucketDepth,
        bytes32 nonce,
        bool immutableFlag
    ) public payable checkPostageStampPaused {
        // Swap xDAI to BZZ
        swapxDAItoBzz(calc(initialBalancePerChunk, depth));

        // Create the batch
        postageStamp.createBatch(owner, initialBalancePerChunk, depth, bucketDepth, nonce, immutableFlag);
    }

    /**
     * Purchase a set of postage batches. This is useful if you want to upload data and not
     * waste any space in the batches.
     * @param owner The `owner` of the new postage batches
     * @param initialBalancePerChunk The amount of BZZ to pay down per chunk
     * @param depths For each batch, the depth, and therefore size of the batch to purchase
     * @param bucketDepth A parameter which seems to do nothing 🗑🚮
     * @param nonces The nonces of the batches to purchase. These are used to generate the batch IDs.
     * @param immutableFlag Whether the set of batches is immutable
     * @param wad The calculated amount of BZZ to purchase
     */
    function purchaseMany(
        address owner,
        uint256 initialBalancePerChunk,
        uint8[] calldata depths,
        uint8 bucketDepth,
        bytes32[] calldata nonces,
        bool immutableFlag,
        uint256 wad
    ) public payable checkPostageStampPaused {
        require(depths.length == nonces.length, "PostMaster: depths and nonces must be the same length");

        // Swap xDAI to BZZ
        swapxDAItoBzz(wad);

        // Create all the batches
        unchecked {
            for (uint256 i = 0; i < depths.length; i++) {
                postageStamp.createBatch(
                    owner, initialBalancePerChunk, depths[i], bucketDepth, nonces[i], immutableFlag
                );
            }
        }
    }

    /**
     * Get a quote for how much xDAI we need to purchase a batch for a given amount of BZZ.
     * @param initialBalancePerChunk BZZ paid down per chunk
     * @param depth The depth, and therefore size of the batch to purchase
     */
    function quotexDAI(uint256 initialBalancePerChunk, uint8 depth) public view returns (uint256, uint256) {
        // Get the amount of xDAI required to purchase the BZZ
        uint256 t = initialBalancePerChunk * BLOCKTIME / postageStamp.lastPrice();
        return (t, getxDAIForExactBZZQuote(calc(initialBalancePerChunk, depth)));
    }

    function quotexDAIMany(uint256 initialBalancePerChunk, uint8[] calldata depths)
        public
        view
        returns (uint256 xdaiRequired, uint256 bzzRequired)
    {
        // iterate through all the batches and calculate the total amount of BZZ required
        for (uint256 i = 0; i < depths.length; i++) {
            bzzRequired += calc(initialBalancePerChunk, depths[i]);
        }

        // we do the quote at the end as there may be slippage on the BZZ price
        xdaiRequired = getxDAIForExactBZZQuote(bzzRequired);
    }

    /**
     * Given a desired amount of storage (measured in depth) for a given amount of time, get a
     * quote for how much xDAI we need to purchase a batch.
     * @param depth The depth of the postage batch
     * @param _seconds How long the postage batch should be valid for
     */
    function quotexDAIForTime(uint8 depth, uint256 _seconds)
        public
        view
        returns (uint256 initialBalancePerChunk, uint256 xdaiRequired)
    {
        // Get the initial balance per chunk
        initialBalancePerChunk = _seconds / BLOCKTIME * postageStamp.lastPrice();

        // Return the amount of xDAI for BZZ on a batch to cover the time
        xdaiRequired = getxDAIForExactBZZQuote(calc(initialBalancePerChunk, depth));
    }

    /**
     * Given a desired amount of storage (expressed in multiple depths) for a given amount of time,
     * get a quote for how much xDAI we need to purchase the batches.
     * @param depth An array of batch depths to purchase
     * @param _seconds How long the postage batches should be valid for
     * @return initialBalancePerChunk to set when purchasing the batch
     * @return xdaiRequired to send along with the purchase
     */
    function quotexDAIForTimeMany(uint8[] calldata depth, uint256 _seconds)
        public
        view
        returns (uint256 initialBalancePerChunk, uint256 xdaiRequired, uint256 bzzRequired)
    {
        // Get the initial balance per chunk
        initialBalancePerChunk = _seconds / BLOCKTIME * postageStamp.lastPrice();

        unchecked {
            // iterate through all the batches and calculate the total amount of BZZ required
            for (uint256 i = 0; i < depth.length; i++) {
                bzzRequired += calc(initialBalancePerChunk, depth[i]);
                xdaiRequired += getxDAIForExactBZZQuote(bzzRequired);
            }
        }
    }

    /**
     * Given that we want a fixed amount of BZZ, get a quote for how much xDAI we need.
     * @param wad The amount of BZZ to purchase.
     */
    function getxDAIForExactBZZQuote(uint256 wad) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(wxDAI);
        path[1] = address(bzz);

        uint256[] memory amounts = router.getAmountsIn(wad, path);
        return amounts[0]; // Return the amount of ETH required
    }

    /**
     * @dev Basically, if the postage stamp contract is paused, we suspect that the contract has been upgraded.
     *      In this case, we need to recover the contract and update our reference to it and handle any BZZ approvals.
     */
    function recover() private {
        // Record the current postage stamp contract
        IPostageStamp currentPostageStamp = postageStamp;

        // Get the new postage stamp contract
        postageStamp = IPostageStamp(log.getAddress(POSTAGE_STAMP_KEY));

        // Sanity checks
        if (!(address(postageStamp) != address(0))) revert PostageStampNotFound();
        if (!(postageStamp.paused() == false)) revert PostageStampPaused();

        // Handle BZZ approvals - revoke from the old contract and approve the new one
        bzz.approve(address(currentPostageStamp), 0);
        bzz.approve(address(postageStamp), type(uint256).max);
    }

    /**
     * A helper function to do the swap from xDAI to BZZ.
     * @param wad The amount of BZZ to purchase
     */
    function swapxDAItoBzz(uint256 wad) private {
        address[] memory path = new address[](2);
        path[0] = address(wxDAI);
        path[1] = address(bzz);

        // Perform the swap
        router.swapETHForExactTokens{value: msg.value}(wad, path, address(this), block.timestamp);

        // Handle any leftover xDAI
        uint256 remainingxDAI = address(this).balance;
        if (remainingxDAI > 0) {
            payable(msg.sender).transfer(remainingxDAI);
        }
    }

    /**
     * Calculate how many chunks our batch will rent.
     * @param initialBalancePerChunk how much BZZ per chunk
     * @param depth of data for storing
     */
    function calc(uint256 initialBalancePerChunk, uint8 depth) private pure returns (uint256) {
        return initialBalancePerChunk * (1 << depth);
    }
}
