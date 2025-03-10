// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Ownable} from "./Ownable.sol";

contract DiamondCutFacet is IDiamondCut, Ownable {
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external onlyOwner {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
