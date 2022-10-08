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
error AuctionRegistry__ActiveAuctionWithBids();
error AuctionRegistry__FinalizedOrCancelled();
error AuctionRegistry__AlreadyFinalizedOrCancelled();
error AuctionRegistry__DeadlineNotExpired();
error AuctionRegistry__OwnerOfAuction();

contract AuctionRegistry is Ownable {
    /// @notice Contract address of DeedToken contract
    address deedTokenAddress;

    /// @notice Lock mechanism for re-entrancy guarded ETH transfer
    bool lock;

    /// @notice Storage list of created auctions
    Auction[] auctions;

    mapping(uint256 => address) auctionIdToOwner;
    mapping(uint256 => uint256) auctionIdToIdx;
    mapping(address => uint256[]) auctionOwnerToAuctionIdx;
    mapping(uint256 => Bid[]) auctionIdxToBids;

    //////////////////////////////
    //         Events          //
    /////////////////////////////

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

    /// @notice Event emitted on auction cancellation
    event AuctionCancelled(address indexed owner, uint256 auctionIdx);

    /// @notice Event emitted on successful auction finalization
    event AuctionFinalized(address indexed owner, uint256 auctionIdx);

    /// @notice Possible states for contract auction
    enum AuctionState {
        ACTIVE,
        FINALIZED,
        CANCELLED
    }

    /// @notice Auction struct representation
    struct Auction {
        string name;
        string metadata;
        uint256 startPrice;
        uint256 blockDeadlineToBidOnAuction;
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

    /// @notice called immediately after deployment to set deedToken contract address
    function setDeedTokenContract(address _deedToken) external onlyOwner {
        deedTokenAddress = _deedToken;
    }

    /// @notice register deed toked ID for incoming auction owner
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

    /// @notice creates a new auction
    function createAuction(
        string memory _name,
        string memory _metadata,
        uint256 _startPrice,
        uint256 _blockDeadlineToBidOnAuction,
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
        newAuction.blockDeadlineToBidOnAuction = _blockDeadlineToBidOnAuction;
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
            _blockDeadlineToBidOnAuction
        );
        return true;
    }

    /// @notice Bid on an active auction
    function bidOnAuction(uint256 _auctionId) external payable {
        if (auctionIdToOwner[_auctionId] == address(0))
            revert AuctionRegistry__NoAuction();

        uint256 auctionIdx = auctionIdToIdx[_auctionId];
        Auction memory auction = auctions[auctionIdx];
        AuctionState auctionState = auction.auctionState;

        // owner shouldnt bid on his/her auction
        if (auction.owner == _msgSender())
            revert AuctionRegistry__OwnerOfAuction();

        if (block.timestamp > auction.blockDeadlineToBidOnAuction)
            revert AuctionRegistry__DeadlineExpired();

        if (_isFinalizedOrCancelled(auctionState)) {
            revert AuctionRegistry__AlreadyFinalizedOrCancelled();
        }

        // check bid amount is higher than prev bid
        Bid memory lastBid;
        uint256 tempAmount = auction.startPrice;
        uint256 bidAmount = msg.value;
        uint256 bidsLength = auctionIdxToBids[auctionIdx].length;

        if (bidsLength > 0) {
            lastBid = auctionIdxToBids[auctionIdx][bidsLength - 1];
            tempAmount = lastBid.bidAmount;
            // check  for correct bid amount
            if (bidAmount < tempAmount)
                revert AuctionRegistry__InvalidBidAmount();
            // there's a correct bid amount
            _reentrantSafeSendETH(lastBid.bidder, tempAmount);
        }

        // If there's no previous bids, tempAmount would be the startPrice
        if (bidAmount < tempAmount) revert AuctionRegistry__InvalidBidAmount();

        Bid memory newBid;
        newBid.bidder = payable(_msgSender());
        newBid.bidAmount = bidAmount;
        auctionIdxToBids[auctionIdx].push(newBid);
        emit BidCreated(_msgSender(), bidAmount);
    }

    /// @notice Auction owner can cancelled an active and unbidded auction
    function cancelAuction(uint256 _auctionId) external {
        if (auctionIdToOwner[_auctionId] != _msgSender())
            revert AuctionRegistry__NotAuctionOwner();

        uint256 auctionIdx = auctionIdToIdx[_auctionId];
        Auction memory auction = auctions[auctionIdx];
        address owner = auction.owner;

        uint256 bidsLength = auctionIdxToBids[auctionIdx].length;
        AuctionState auctionState = auction.auctionState;

        // disallow cancelling active auction with bids
        if (auctionState == AuctionState.ACTIVE && bidsLength > 0) {
            revert AuctionRegistry__ActiveAuctionWithBids();
        }
        if (_isFinalizedOrCancelled(auctionState)) {
            revert AuctionRegistry__AlreadyFinalizedOrCancelled();
        }

        // transfer auction back to owner
        _transferAndResetAuction(owner, _auctionId);
        auction.auctionState = AuctionState.CANCELLED;
        emit AuctionCancelled(owner, auctionIdx);
    }

    ///  @notice finalizes an auction sending deed/ETH to respective addresses
    function finalizeAuction(uint256 _auctionId) external {
        // check auction exists with active state
        address payable owner = payable(auctionIdToOwner[_auctionId]);
        if (owner == address(0)) {
            revert AuctionRegistry__NoAuction();
        }
        uint256 auctionIdx = auctionIdToIdx[_auctionId];
        Auction memory auction = auctions[auctionIdx];
        AuctionState auctionState = auction.auctionState;

        // already finalized or cancelled
        if (_isFinalizedOrCancelled(auctionState)) {
            revert AuctionRegistry__AlreadyFinalizedOrCancelled();
        }

        // deadline exceeded
        if (auction.blockDeadlineToBidOnAuction < block.timestamp) {
            revert AuctionRegistry__DeadlineNotExpired();
        }
        // last bidder
        uint256 bidsLength = auctionIdxToBids[auctionIdx].length;
        if (bidsLength > 0) {
            Bid memory lastBid = auctionIdxToBids[auctionIdx][bidsLength - 1];
            _reentrantSafeSendETH(owner, lastBid.bidAmount);
            _transferAndResetAuction(lastBid.bidder, _auctionId);
            auction.auctionState = AuctionState.FINALIZED;
        } else {
            // no bid
            _transferAndResetAuction(owner, _auctionId);
            auction.auctionState = AuctionState.FINALIZED;
        }
        emit AuctionFinalized(owner, auctionIdx);
    }

    //////////////////////////////
    //     Getter Functions     //
    /////////////////////////////

    /// @notice get Auction at the specified index `_auctionIdx`
    function getAuction(uint256 _auctionIdx)
        external
        view
        returns (
            string memory _name,
            string memory _metadata,
            uint256 _startPrice,
            uint256 _blockDeadlineToBidOnAuction,
            // uint256 _deedId,
            address _owner,
            AuctionState _auctionState
        )
    {
        if (_auctionIdx >= auctions.length) {
            revert AuctionRegistry__NoAuction();
        }
        Auction memory auction = auctions[_auctionIdx];
        _name = auction.name;
        _metadata = auction.metadata;
        _startPrice = auction.startPrice;
        _blockDeadlineToBidOnAuction = auction.blockDeadlineToBidOnAuction;
        _owner = auction.owner;
        _auctionState = auction.auctionState;
    }

    /// @notice get all auction(s) owner by the account `_auctionOwner`
    function getAuctionsOfOwner(address _auctionOwner)
        external
        view
        returns (Auction[] memory _auctions)
    {
        uint256[] memory _auctionIdx = auctionOwnerToAuctionIdx[_auctionOwner];
        for (uint256 i = 0; i < _auctionIdx.length; i++) {
            _auctions[i] = auctions[_auctionIdx[i]];
        }
    }

    /// @notice get bids on an auction
    function getBidsOnAuction(uint256 _auctionIdx)
        external
        view
        returns (Bid[] memory _bids)
    {
        if (_auctionIdx >= auctions.length) {
            revert AuctionRegistry__NoAuction();
        }
        _bids = auctionIdxToBids[_auctionIdx];
    }

    /// @notice get address of deed token contract
    function getDeedContractAddress() external view returns (address) {
        return deedTokenAddress;
    }

    //////////////////////////////
    //    Private Functions    //
    /////////////////////////////

    /// @notice checks if auction is finalized or cancelled already
    function _isFinalizedOrCancelled(AuctionState _auctionState)
        private
        pure
        returns (bool)
    {
        bool isFinalized = _auctionState == AuctionState.FINALIZED;
        bool isCancelled = _auctionState == AuctionState.CANCELLED;
        if (isFinalized || isCancelled) {
            return true;
        }
        return false;
    }

    /// @notice Transfer deed from `contract` to address `to` and reset the states
    function _transferAndResetAuction(address _to, uint256 _auctionId) private {
        IERC721(deedTokenAddress).transferFrom(address(this), _to, _auctionId);
        auctionIdToOwner[_auctionId] = address(0);
        auctionIdToIdx[_auctionId] = 0;
    }

    /// @notice ETH transfer to address `to` with simple lock mechanism
    function _reentrantSafeSendETH(address payable _to, uint256 _amount)
        private
    {
        if (!lock) {
            lock = true;
            (bool success, ) = _to.call{value: _amount}("");
            if (!success) revert AuctionRegistry__EthTransferFailed();
        }
        lock = true;
    }
}
