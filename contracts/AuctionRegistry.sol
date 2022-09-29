// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error AuctionRegistry__NotAuctionOwner();
error AuctionRegistry__NoRegisteredDeed();
error AuctionRegistry__NoAuction();
error AuctionRegistry__DeadlineExpired();
error AuctionRegistry__InvalidBidAmount();
error AuctionRegistry__EthTransferFailed();

contract AuctionRegistry is Ownable {
    /// @notice Contract address of DeedToken contract
    address deedTokenAddress;

    /// @notice Storage list of created auctions
    Auction[] auctions;

    mapping(uint256 => address) auctionIdToOwner;
    mapping(uint256 => uint256) auctionIdToIdx;
    mapping(address => uint256[]) auctionOwnerToAuctionIdx;
    mapping(uint256 => Bid[]) auctionIdxToBids;

    /// @notice Event emitted on successful auction creation
    /// @param auctionOwner Owner of created auction
    /// @param auctionIdx Idx of auction in the auctions collection
    /// @param startPrice Start price for auction
    /// @param deadLine Deadline timestamp before auction can be finalized
    event AuctionCreated(
        address indexed auctionOwner,
        uint256 auctionIdx,
        uint256 startPrice,
        uint256 deadLine
    );

    /// @notice Event emitted on successful auction bid
    /// @param bidder Bidder's address
    /// @param bidAmount Bid amount
    event BidCreated(address indexed bidder, uint256 indexed bidAmount);

    /// @notice Possible states for contract auction
    enum AuctionState {
        ACTIVE,
        FINALIZE,
        CANCELLED
    }

    /// @notice Auction struct representation
    struct Auction {
        string name;
        string metadata;
        uint256 startPrice;
        uint256 blockDeadline;
        uint256 deedId;
        address payable owner;
        AuctionState auctionState;
    }

    /// @notice Bid struct representation
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

    // create a new auction
    function createAuction(
        string memory _name,
        string memory _metadata,
        uint256 _startPrice,
        uint256 _blockDeadline,
        uint256 _deedId
    ) external returns (bool) {
        address auctionOwner = auctionIdToOwner[_deedId];
        if (auctionOwner == address(0))
            revert AuctionRegistry__NoRegisteredDeed();
        if (auctionOwner != _msgSender())
            revert AuctionRegistry__NotAuctionOwner();
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

        emit AuctionCreated(
            auctionOwner,
            newAuctionIdx,
            _startPrice,
            _blockDeadline
        );
        return true;
    }

    function bidOnAuction(uint256 _auctionId) external payable {
        if (auctionIdToOwner[_auctionId] == address(0))
            revert AuctionRegistry__NoAuction();
        uint256 auctionIdx = auctionIdToIdx[_auctionId];

        Auction memory auction = auctions[auctionIdx];

        if (auction.owner == _msgSender()) revert();
        if (block.timestamp > auction.blockDeadline)
            revert AuctionRegistry__DeadlineExpired();

        // check bid amount is higher than prev bid
        Bid memory lastBid;
        uint tempAmount = auction.startPrice;
        uint256 bidAmount = msg.value;
        uint256 bidsLength = auctionIdxToBids[auctionIdx].length;

        if (bidsLength > 0) {
            lastBid = auctionIdxToBids[auctionIdx][bidsLength - 1];
            tempAmount = lastBid.bidAmount;
        }

        if (tempAmount < bidAmount) revert AuctionRegistry__InvalidBidAmount();

        if (bidsLength > 0) {
            (bool success, ) = lastBid.bidder.call{value: lastBid.bidAmount}(
                ""
            );
            if (!success) revert AuctionRegistry__EthTransferFailed();
        }

        Bid memory newBid;
        newBid.bidder = payable(_msgSender());
        newBid.bidAmount = bidAmount;
        auctionIdxToBids[auctionIdx].push(newBid);
        emit BidCreated(_msgSender(), bidAmount);
    }

    function cancelAuction(uint256 _auctionId) external {
        if (auctionIdToOwner[_auctionId] != _msgSender())
            revert AuctionRegistry__NotAuctionOwner();

        uint256 auctionIdx = auctionIdToIdx[_auctionId];
        Auction memory auction = auctions[auctionIdx];

        if (auction.blockDeadline > block.timestamp) revert();

        uint256 bidsLength = auctionIdxToBids[_auctionId].length;

        if (bidsLength > 0) {
            Bid memory lastBid = auctionIdxToBids[_auctionId][bidsLength - 1];
            (bool success, ) = lastBid.bidder.call{value: lastBid.bidAmount}(
                ""
            );
            if (!success) revert AuctionRegistry__EthTransferFailed();
        }

        // transfer auction back to owner
        IERC721(deedTokenAddress).transferFrom(
            address(this),
            auction.owner,
            _auctionId
        );

        auctionIdToOwner[_auctionId] = address(0);
        auctionIdToIdx[_auctionId] = 0;
        auction.auctionState = AuctionState.CANCELLED;
    }

    function finalizeAuction(uint256 _auctionId) external {}
}
