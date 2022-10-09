// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IAuctionRegistry {
    function setIDToAuctionOwner(address _owner, uint256 _tokenId) external;
}
