// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionRegistry is Ownable {
    address deedTokenAddress;
    // uint256 nextAuctionID;

    Auction[] auctions;

    mapping(uint256 => address) auctionIdToOwner;
    mapping(uint256 => uint256) auctionIdToIdx;
    mapping(address => uint256[]) auctionOwnerToAuctionIdx;
    mapping(uint256 => Bid[]) auctionIdxToBids;

    enum AuctionState {
        ACTIVE,
        FINALIZE
    }

    struct Auction {
        string name;
        string metadata;
        uint256 startPrice;
        uint256 blockDeadline;
        uint256 deedId;
        address payable owner;
        AuctionState auctionState;
    }

    struct Bid {
        address payable bidder;
        uint256 bidAmount;
    }

    constructor() {}

    // called immediately after deploying deedToken to set its contract address
    function setDeedTokenContract(address _deedToken) external onlyOwner {
        deedTokenAddress = _deedToken;
    }

    function setIDToAuctionOwner(address _owner, uint256 _tokenId)
        external
        returns (bool)
    {
        // to be called by dEEdtoken contract
        if (_msgSender() == deedTokenAddress) {
            auctionIdToOwner[_tokenId] = _owner;
            return true;
        }
        return false;
    }

    function createAuction(
        string memory _name,
        string memory _metadata,
        uint256 _startPrice,
        uint256 _blockDeadline,
        uint256 _deedId
    ) external {
        address auctionOwner = auctionIdToOwner[_deedId];
        require(auctionOwner != address(0), "deed not sent to registry");
        uint256 newAuctionIdx = auctions.length;
        Auction memory newAuction;
        newAuction.name = _name;
        newAuction.metadata = _metadata;
        newAuction.startPrice = _startPrice;
        newAuction.blockDeadline = _blockDeadline;
        newAuction.deedId = _deedId;
        newAuction.owner = payable(auctionOwner);
        newAuction.auctionState = AuctionState.ACTIVE;

        auctionIdToIdx[_deedId] = newAuctionIdx;
        auctionOwnerToAuctionIdx[auctionOwner].push(newAuctionIdx);
        auctions.push(newAuction);
    }
}
