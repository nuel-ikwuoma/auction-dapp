// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "./AuctionRegistry.sol";

/// @title A simple deed registry using ERC721 standard
/// @author Emmanuel Ikwuoma
/// @notice This contract allows anyone to create a deed with aim for auctioning
contract DeedRegistry is ERC721URIStorage {
    /// @notice Instance of auction registry contract
    AuctionRegistry immutable auctionRegistry;

    /// @notice Event emitted on successful deed creation
    /// @param deedOwner The deed's owner address
    /// @param deedID  The deed's ID
    event DeedRegistered(address indexed deedOwner, uint256 indexed deedID);

    /// @notice Contract constructor
    /// @dev Creates ERC721 based deed repository contract
    /// @param _name The name of the deed token
    /// @param _symbol The symbol of the deed token
    constructor(
        string memory _name,
        string memory _symbol,
        address _auctionRegistry
    ) ERC721(_name, _symbol) {
        auctionRegistry = AuctionRegistry(_auctionRegistry);
    }

    /// @notice Mints a unique deed to calling address
    /// @param _deedID The unique id of deed token to be minted
    /// @param _deedURI The deed's token URI
    function registerDeed(uint256 _deedID, string memory _deedURI) public {
        _mint(_msgSender(), _deedID);
        _setTokenURI(_deedID, _deedURI);
        emit DeedRegistered(_msgSender(), _deedID);
    }

    /// @notice Sets the URI of an existing deed token
    /// @dev Only owner or an approved operator can set token URI
    /// @param _deedID The deed's token id to be set
    /// @param _deedURI  The deed's URI to be set
    /// @return boolean indicating success/failure
    function setDeedURI(uint256 _deedID, string memory _deedURI)
        public
        returns (bool)
    {
        address owner = ownerOf(_deedID);
        if (owner == _msgSender() || isApprovedForAll(owner, _msgSender())) {
            _setTokenURI(_deedID, _deedURI);
            return true;
        }
        return false;
    }

    /// @notice Hook to register deed after token transfer to Auction contract
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId);
        if (to == address(auctionRegistry)) {
            auctionRegistry.setIDToAuctionOwner(from, tokenId);
        }
    }
}
