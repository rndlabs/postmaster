// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IPostageStamp {
    struct Batch {
        // Owner of this batch (0 if not valid).
        address owner;
        // Current depth of this batch.
        uint8 depth;
        //
        uint8 bucketDepth;
        // Whether this batch is immutable.
        bool immutableFlag;
        // Normalised balance per chunk.
        uint256 normalisedBalance;
        //
        uint256 lastUpdatedBlockNumber;
    }

    function paused() external view returns (bool);

    function batches(bytes32 batchId) external view returns (Batch memory);
    function bzzToken() external view returns (address);
    function minimumBucketDepth() external view returns (uint8);
    function validChunkCount() external view returns (uint256);
    function pot() external view returns (uint256);
    function minimumValidityBlocks() external view returns (uint256);
    function lastPrice() external view returns (uint256);
    function lastUpdatedBlock() external view returns (uint256);
    function lastExpiryBalance() external view returns (uint256);

    function createBatch(
        address owner,
        uint256 initialBalancePerChunk,
        uint8 depth,
        uint8 bucketDepth,
        bytes32 nonce,
        bool immutableFlag
    ) external;
    function topUp(bytes32 batchId, uint256 topupAmountPerChunk) external;
    function increaseDepth(bytes32 batchId, uint8 newDepth) external;
    function remainingBalance(bytes32 batchId) external view returns (uint256);
    function currentTotalOutPayment() external view returns (uint256);
    function minimumInitialBalancePerChunk() external view returns (uint256);
    function totalPot() external view returns (uint256);

    function batchOwner(bytes32 batchId) external view returns (address);
    function batchDepth(bytes32 batchId) external view returns (uint8);
    function batchBucketDepth(bytes32 batchId) external view returns (uint8);
    function batchImmutableFlag(bytes32 batchId) external view returns (bool);
    function batchNormalisedBalance(bytes32 batchId) external view returns (uint256);
    function batchLastUpdatedBlockNumber(bytes32 batchId) external view returns (uint256);
}
