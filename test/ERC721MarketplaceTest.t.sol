// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";
import {ERC721Marketplace} from "../src/ERC721Marketplace.sol";
import {ERC721Mock} from "../src/Mocks/ERC721Mock.sol";
import {ERC20Mock} from "../src/Mocks/ERC20Mock.sol";
import {ERC20MockWithoutTotalSupply} from "../src/Mocks/ERC20MockWithoutTotalSupply.sol";
import {MockPriceFeed} from "../src/Mocks/MockPriceFeed.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract ERC721MarketplaceTest is Test {
    ERC721Marketplace public marketplace;
    ERC721Mock public nft;
    ERC20Mock public tokenUSDT;
    ERC20Mock public tokenWETH;
    ERC20MockWithoutTotalSupply public tokenInv;
    MockPriceFeed public priceFeed;
    address public alice = address(11);
    address public bob = address(12);
    address public charlie = address(13);
    address public owner = address(14);
    address public treasury = address(15);

    function setUp() public {
        vm.startPrank(owner);

        tokenUSDT = new ERC20Mock("USDT", "UT");
        tokenWETH = new ERC20Mock("WETH", "WT");
        nft = new ERC721Mock("TestNFT", "TNFT");

        uint8 decimalsForFeed = 6;
        uint256 priceForFeed = 1;
        priceFeed = new MockPriceFeed(decimalsForFeed, priceForFeed);

        marketplace = new ERC721Marketplace();
        marketplace.initialize(address(tokenUSDT), address(tokenWETH));

        nft.mint(alice);

        uint256 decimals = 6;
        marketplace.addAllowedCurrency(
            address(tokenUSDT),
            address(priceFeed),
            decimals
        );
        vm.stopPrank();
    }

    function testSetUp() public {
        assertEq(marketplace.owner(), owner);
        assertEq(marketplace.USDT(), address(tokenUSDT));
        assertEq(marketplace.ETH(), address(tokenWETH));
        assertEq(marketplace.treasuryPercentage(), 50);
        assertEq(marketplace.treasury(), owner);
    }

    function testSetTreasury() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        assertEq(marketplace.treasury(), treasury);
    }

    function testSetTreasuryWithZeroAddressRevert() public {
        vm.startPrank(owner);

        bytes4 selector = bytes4(keccak256("ZeroAddress()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        marketplace.setTreasury(address(0));
        vm.stopPrank();
    }

    function testSetTreasuryNotAsOwnerRevert() public {
        vm.startPrank(charlie);
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setTreasury(treasury);
        vm.stopPrank();
    }

    function testSetTreasuryPercentageNotAsOwnerRevert() public {
        uint256 treasuryPercentage = 50;
        vm.startPrank(charlie);
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setTreasuryPercentage(treasuryPercentage);
        vm.stopPrank();
    }

    function testSetInvalidTreasuryPercentageRevert() public {
        uint256 invalidTreasuryPercentage = 50000;
        vm.startPrank(owner);

        bytes4 selector = bytes4(keccak256("InvalidPercentage(uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, invalidTreasuryPercentage)
        );

        marketplace.setTreasuryPercentage(invalidTreasuryPercentage);
        vm.stopPrank();
    }

    function testSetUSDT() public {
        vm.startPrank(owner);
        tokenUSDT = new ERC20Mock("USDT1", "UT1");
        marketplace.setUSDT(address(tokenUSDT));
        assertEq(address(tokenUSDT), marketplace.USDT());
        vm.stopPrank();
    }

    function testSetUSDTNotAsOwnerRevert() public {
        vm.startPrank(charlie);
        tokenUSDT = new ERC20Mock("USDT1", "UT1");
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setUSDT(address(tokenUSDT));
        vm.stopPrank();
    }

    function testSetUSDTWithZeroAddressRevert() public {
        vm.startPrank(owner);
        tokenUSDT = new ERC20Mock("USDT1", "UT1");
        bytes4 selector = bytes4(keccak256("ZeroAddress()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        marketplace.setUSDT(address(0));
        vm.stopPrank();
    }

    // function testSetUSDTWithNonERC20Revert() public {
    //     vm.startPrank(owner);
    //     bytes4 selector = bytes4(keccak256("NonERC20()"));
    //     vm.expectRevert(abi.encodeWithSelector(selector));

    //     tokenInv = new ERC20MockWithoutTotalSupply("Test", "TST");
    //     marketplace.setUSDT(address(tokenInv));
    //     vm.stopPrank();
    // }

    function testSetEth() public {
        vm.startPrank(owner);
        marketplace.setEth(address(25));
        assertEq(address(25), marketplace.ETH());
        vm.stopPrank();
    }

    function testSetEthWithZeroAddressRevert() public {
        vm.startPrank(owner);
        bytes4 selector = bytes4(keccak256("ZeroAddress()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        marketplace.setEth(address(0));
        vm.stopPrank();
    }

    function testCreatePurchaseListing() public {
        uint256 tokenId = 1;
        uint256 price = 1000;
        uint256 deadline = 1 days;

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        nft.approve(address(marketplace), tokenId);
        nft.setApprovalForAll(address(marketplace), true);

        marketplace.createPurchaseListing(
            address(nft),
            tokenId,
            price,
            deadline
        );

        uint256 listingId = 0;
        (
            address nftAddress,
            uint256 nftId,
            address seller,
            uint256 listingPrice,
            uint256 listingDeadline,
            bool isAuction,
            uint256 auctionEndTime,
            uint256 minBid,
            address currency
        ) = marketplace.getListing(listingId);

        assertEq(seller, alice);
        assertEq(listingPrice, price);
        assertEq(currency, marketplace.USDT());
        assertEq(minBid, 0);
        assertEq(nftAddress, address(nft));
        assertEq(nftId, tokenId);
        assertEq(listingDeadline, deadline + block.timestamp);
        assertFalse(isAuction);
        // assertEq(auctionEndTime, 0);
        vm.stopPrank();
    }

    function testCreatePurchaseListingWithInvalidDeadlineRevert() public {
        uint256 tokenId = 1;
        uint256 price = 1000;
        uint256 deadline = 500 days;

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        nft.approve(address(marketplace), tokenId);
        nft.setApprovalForAll(address(marketplace), true);

        bytes4 selector = bytes4(keccak256("TooLongTerm(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, deadline));

        marketplace.createPurchaseListing(
            address(nft),
            tokenId,
            price,
            deadline
        );

        vm.stopPrank();
    }

    function testCreatePurchaseListingWithZeroPriceRevert() public {
        uint256 tokenId = 1;
        uint256 price = 0;
        uint256 deadline = 5 days;

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        nft.approve(address(marketplace), tokenId);
        nft.setApprovalForAll(address(marketplace), true);

        bytes4 selector = bytes4(keccak256("ZeroPrice()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        marketplace.createPurchaseListing(
            address(nft),
            tokenId,
            price,
            deadline
        );

        vm.stopPrank();
    }

    function testBuyListing() public {
        uint256 tokenId = 1;
        uint256 price = 1000;
        uint256 deadline = 1 days;

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        nft.approve(address(marketplace), tokenId);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createPurchaseListing(
            address(nft),
            tokenId,
            price,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, price);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 listingId = 0;
        tokenUSDT.approve(address(marketplace), price);
        marketplace.buyListing(listingId, address(tokenUSDT));

        assertEq(nft.ownerOf(tokenId), bob);
        vm.stopPrank();
    }

    function testCreateAuctionListing() public {
        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );

        (
            address nftAddress,
            uint256 nftId,
            address seller,
            uint256 listingPrice,
            uint256 listingDeadline,
            bool isAuction,
            uint256 endTime,
            uint256 minimumBid,
            address currency
        ) = marketplace.getListing(0);

        assertEq(nftAddress, address(nft));
        assertEq(seller, alice);
        assertTrue(isAuction);
        assertEq(endTime, auctionEndTime + block.timestamp);
        assertEq(minimumBid, minBid);
        assertEq(currency, address(tokenUSDT));
        assertEq(nftId, tokenId);
        assertEq(listingPrice, 0);
        // assertEq(listingDeadline, 0);
        vm.stopPrank();
    }

    function testPlaceBid() public {
        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);

        uint256 bidAmount = marketplace.getListingBidAmount(0, bob);
        assertEq(bidAmount, minBid);
        vm.stopPrank();
    }

    function testFinalizeAuction() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);
        vm.stopPrank();

        vm.startPrank(alice);
        // Wait for the auction to end
        vm.warp(block.timestamp + auctionEndTime + 1);

        marketplace.finalizeAuction(listingId, bob);

        assertEq(nft.ownerOf(tokenId), bob);
        assertGe(tokenUSDT.balanceOf(alice), 0);
        assertGe(tokenUSDT.balanceOf(treasury), 0);
        vm.stopPrank();
    }

    function testFinalizeAuctionAsNotItemOwnerRevert() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);
        vm.stopPrank();

        vm.startPrank(charlie);
        // Wait for the auction to end
        vm.warp(block.timestamp + auctionEndTime + 1);

        bytes4 selector = bytes4(keccak256("SenderIsNotItemOwner()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        marketplace.finalizeAuction(listingId, bob);
        vm.stopPrank();
    }

    function testFinalizeAuctionWithWinnerHasNotBidRevert() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);
        vm.stopPrank();

        vm.startPrank(alice);
        // Wait for the auction to end
        vm.warp(block.timestamp + auctionEndTime + 1);

        vm.expectRevert();

        marketplace.finalizeAuction(listingId, treasury);
        vm.stopPrank();
    }

    function testFinalizeAuctionBeforeEndTimeRevert() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);
        vm.stopPrank();

        vm.startPrank(alice);
        // Wait for the auction to end
        vm.warp(block.timestamp + 1 minutes);

        bytes4 selector = bytes4(keccak256("AuctionNotOver()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        marketplace.finalizeAuction(listingId, bob);
        vm.stopPrank();
    }

    function testFinalizeAuctionForNonAuctionRevert() public {
        vm.startPrank(owner);
        marketplace.setTreasury(treasury);
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 tokenId2 = 2;
        uint256 auctionEndTime = 1 days;
        uint256 minBid = 100;
        uint256 listingId = 0;
        uint256 listingId2 = 1;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        marketplace.createAuctionListing(
            address(nft),
            tokenId,
            auctionEndTime,
            minBid,
            address(tokenUSDT)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        tokenUSDT.mint(bob, minBid);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenUSDT.approve(address(marketplace), minBid);
        marketplace.placeBid(listingId, minBid);
        vm.stopPrank();

        vm.startPrank(owner);
        nft.mint(alice);
        vm.stopPrank();

        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        uint256 price = 1000;
        uint256 deadline = 1 days;
        marketplace.createPurchaseListing(
            address(nft),
            tokenId2,
            price,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // Wait for the auction to end
        vm.warp(block.timestamp + auctionEndTime + 1);

        bytes4 selector = bytes4(keccak256("NonAuction()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        marketplace.finalizeAuction(listingId2, bob);
        vm.stopPrank();
    }
}
