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
    // The UniswapV2Router contract for the Honeyswap DEX
    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x1C232F01118CB8B424793ae03F870aa7D0ac7f77);
    // The bridged BZZ token on Gnosis Chain
    ERC20 private constant bzz = ERC20(0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da);
    // Configure the wxDAI token - normal ERC20 will do as deposit/withdraw is handled by the router
    ERC20 private constant wxDAI = ERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);
    // Configure the chainlog
    ChainLog private constant log = ChainLog(0x4989F405b9c449Ccf3FdEa0f60B613afF1E55E14);
    // The postage stamp contract
    IPostageStamp private postageStamp;

    // keys
    bytes32 private constant POSTAGE_STAMP_KEY = bytes32("SWARM_POSTAGE_STAMP");

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
    ) public payable {
        // Check to make sure postage stamp is not paused
        if (postageStamp.paused()) {
            recover();
        }

        // Swap xDAI to BZZ
        swapxDAItoBzz(calc(initialBalancePerChunk, depth));

        // Create the batch
        postageStamp.createBatch(owner, initialBalancePerChunk, depth, bucketDepth, nonce, immutableFlag);
    }

    /**
     * Get a quote for how much xDAI we need to purchase a batch for a given amount of BZZ.
     * @param initialBalancePerChunk BZZ paid down per chunk
     * @param depth The depth, and therefore size of the batch to purchase
     */
    function quotexDAI(uint256 initialBalancePerChunk, uint8 depth) public view returns (uint256) {
        // Get the amount of xDAI required to purchase the BZZ
        return getxDAIForExactBZZQuote(calc(initialBalancePerChunk, depth));
    }

    /**
     * Get a quote for how much xDAI we need to purchase a batch for a given amount of time.
     * @param depth The depth of the postage batch
     * @param _seconds How long the postage batch should be valid for
     */
    function quotexDAIForTime(uint8 depth, uint256 _seconds) public view returns (uint256, uint256) {
        // Get the amount of blocks required to cover the time
        uint256 blocks = _seconds / 5;

        // Get the initial balance per chunk
        uint256 initalBalancePerChunk = blocks * postageStamp.lastPrice();

        // Return the amount of xDAI for BZZ on a batch to cover the time
        return (initalBalancePerChunk, getxDAIForExactBZZQuote(calc(initalBalancePerChunk, depth)));
    }

    /**
     * A helper function to get the amount of xDAI required to purchase a given amount of BZZ.
     * @param wad The amount of BZZ to purchase
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
