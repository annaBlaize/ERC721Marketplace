// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ERC721Marketplace.sol";

contract ERC721MarketplaceTest is Test {
    using Counters for Counters.Counter;

    ERC721Marketplace private marketplace;
    ERC721 private nft;
    ERC20 private token;

    Counters.Counter private _tokenIds;

    function beforeEach() public {
        marketplace = new ERC721Marketplace();
        nft = new ERC721("TestNFT", "TNFT");
        token = new ERC20("TestToken", "TT");

        // Mint a sample NFT for testing
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        nft._mint(msg.sender, newItemId);
    }

    function testCreatePurchaseListing() public {
        uint256 tokenId = 1;
        uint256 price = 1000;
        uint256 deadline = 1 days;

        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createPurchaseListing(address(nft), tokenId, price, deadline);

        (address nftAddress, , address seller, uint256 listingPrice, , , , , address currency) = marketplace.getListing(0);

        assertEq(nftAddress, address(nft));
        assertEq(seller, msg.sender);
        assertEq(listingPrice, price);
        assertEq(currency, marketplace.USDT());
    }

    function testBuyListing() public {
        uint256 tokenId = 1;
        uint256 price = 1000;
        uint256 deadline = 1 days;

        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createPurchaseListing(address(nft), tokenId, price, deadline);

        token.transfer(msg.sender, price);
        token.approve(address(marketplace), price);
        marketplace.buyListing(0, address(token));

        assertEq(nft.ownerOf(tokenId), msg.sender);
    }

    function testCreateAuctionListing() public {
        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;

        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(address(nft), tokenId, auctionEndTime, minBid, address(token));

        (address nftAddress, , address seller, , , bool isAuction, uint256 endTime, uint256 minimumBid, address currency) = marketplace.getListing(0);

        assertEq(nftAddress, address(nft));
        assertEq(seller, msg.sender);
        assertTrue(isAuction);
        assertEq(endTime, auctionEndTime + block.timestamp);
        assertEq(minimumBid, minBid);
        assertEq(currency, address(token));
    }

    function testPlaceBid() public {
        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;

        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(address(nft), tokenId, auctionEndTime, minBid, address(token));

        token.transfer(msg.sender, minBid);
        token.approve(address(marketplace), minBid);
        marketplace.placeBid(0, minBid);

        uint256 bidAmount = marketplace.getListingBidAmount(0, msg.sender);
        assertEq(bidAmount, minBid);
    }

    function testFinalizeAuction() public {
        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;

        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(address(nft), tokenId, auctionEndTime, minBid, address(token));

        token.transfer(msg.sender, minBid);
        token.approve(address(marketplace), minBid);
        marketplace.placeBid(0, minBid);

        // Wait for the auction to end
        vm.warp(block.timestamp + auctionEndTime + 1);

        marketplace.finalizeAuction(0, msg.sender);

        assertEq(nft.ownerOf(tokenId), msg.sender);
    }
}