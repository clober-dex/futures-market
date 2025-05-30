// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library Constant {
    bytes32 constant SALT = bytes32(uint256(3));
    address constant PYTH_FEED_ADDRESS = 0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5;
    uint256 constant PRICE_UPDATE_INTERVAL = 3 days;

    function getFacetData(address oracle, address debtTokenImpl)
        internal
        pure
        returns (string[] memory, bytes[] memory)
    {
        string[] memory facetNames = new string[](5);
        bytes[] memory facetArgs = new bytes[](5);

        facetNames[0] = "FlashLoanFacet";
        facetArgs[0] = abi.encode("");
        facetNames[1] = "MarketManagerFacet";
        facetArgs[1] = abi.encode(oracle, debtTokenImpl);
        facetNames[2] = "MarketPositionFacet";
        facetArgs[2] = abi.encode(oracle);
        facetNames[3] = "MarketViewFacet";
        facetArgs[3] = abi.encode("");
        facetNames[4] = "UtilsFacet";
        facetArgs[4] = abi.encode("");

        return (facetNames, facetArgs);
    }
}
