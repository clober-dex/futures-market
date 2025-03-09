// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Modifiers} from "./Modifiers.sol";

contract DiamondCutFacet is IDiamondCut, Modifiers {
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external onlyOwner {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
