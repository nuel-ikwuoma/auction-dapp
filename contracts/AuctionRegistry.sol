// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionRegistry is Ownable {
    address deedTokenAddress;
    uint256 nextAuctionID;

    mapping(uint256 => address) auctionIdToOwner;

    // struct Auction {
    //     uint256 auctionID,

    // }

    constructor() {}

    // called immediately after deploying deedToken to set its contract address
    function setDeedTokenContract(address _deedToken) external onlyOwner {
        deedTokenAddress = _deedToken;
    }

    function setIDToAuctionOwner(address _owner) external returns (bool) {
        // to be called by dEEdtoken contract
        if (_msgSender() == deedTokenAddress) {
            auctionIdToOwner[nextAuctionID] = _owner;
            nextAuctionID++;
            return true;
        }
        return false;
    }
}
