// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library Market {
    /// @notice Storage layout for a market
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the market expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision (e.g. 75% = 750000)
    /// @param minDebt Minimum debt amount that must be minted
    /// @param settlePrice Settlement price for the underlying asset, set when market is settled
    /// @param positions Mapping of user addresses to their positions in this market
    struct Storage {
        bytes32 assetId;
        address collateral;
        uint40 expiration;
        uint24 ltv;
        uint24 liquidationThreshold;
        uint128 minDebt;
        uint256 settlePrice;
        mapping(address user => Position) positions;
    }

    /// @notice Position details for a user in a market
    /// @param collateral Amount of collateral deposited
    /// @param debt Amount of debt minted
    struct Position {
        uint128 collateral;
        uint128 debt;
    }

    // bytes32(uint256(keccak256('app.storage.Market')) - 1)
    bytes32 internal constant POSITION = 0xef55ba0a8b5f8f7b0c7a8239a99fa92e8d6335c136bc2eb00cd401bc577b949f;

    function loadMap() private pure returns (mapping(address => Storage) storage $) {
        assembly {
            $.slot := POSITION
        }
    }

    function load(address debtToken) internal view returns (Storage storage) {
        return loadMap()[debtToken];
    }
}
