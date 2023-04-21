// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "forge-std/console.sol";

//  * @title Multi-Currency NFT Marketplace with Auction Support
//  *
//  * @dev This contract includes the following functionality:
//  *  - create, buy, and bid on ERC721 NFTs
//  *  - supports multiple currencies, including Ether and ERC20 tokens
//  *  - allows the owner to add and remove supported currencies
//  *  - offers two modes of sale: standard purchase and auction
//  *  - deducts a percentage fee from each sale and sends it to the treasury
//  */
contract ERC721Marketplace is OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // _______________ Storage _______________
    uint256 public treasuryPercentage;
    address public treasury;

    address public USDT;
    address public ETH;

    mapping(address => Currency) public allowedCurrencies;

    uint256 public nextListingId;
    mapping(uint256 => Listing) public listings;

    uint256 public constant PERCENT_DIVIDER = 100;
    uint256 public constant MAX_TERM = 30 days;

    // _______________ Structs _______________
    struct Listing {
        address nftAddress;
        uint256 tokenId;
        address seller;
        uint256 price;
        uint256 deadline;
        bool isAuction;
        uint256 auctionEndTime;
        uint256 minBid;
        address[] bidders;
        mapping(address => uint256) bids;
        address currency;
    }

    struct Currency {
        IERC20 token;
        AggregatorV3Interface priceFeed;
        uint256 decimals;
    }

    // _______________ Errors _______________
    error ZeroAddress();
    error ZeroPrice();
    error ZeroBid();
    error NonERC20();
    error CurrencyAlreadyAllowed();
    error CurrencyNotAvailable();
    error TooLongTerm(uint256 actualTerm);
    error ItemAlreadyOnListing();
    error SenderIsNotItemOwner();
    error SenderIsItemOwner();
    error NonStandardPurchase();
    error NonAuction();
    error Expired(uint256 latestTime, uint256 deadline);
    error BidIsTooLow(uint256 minbid, uint256 bid);
    error InvalidPercentage(uint256 percentage);
    error WinnerHasNotBid();
    error AuctionNotOver();
    error NonApprovedNFT();
    error NoRefundAvailable();
    error InsufficientEtherSent(uint256 sendedAmount);
    error FailedToSendEther();

    //_______________ Events __________________
    event NewListing(uint256 listingId);
    event ListingPurchased(uint256 listingId, address buyer);
    event NewBid(uint256 listingId, address bidder, uint256 bidAmount);
    event BidWithdrawn(uint256 listingId, address bidder);
    event AuctionResult(uint256 listingId, address winner, uint256 winningBid);
    event TreasuryChanged(address treasury);
    event TreasuryPercentageChanged(uint256 treasuryPercentage);
    event CurrencyAdded(address tokenAddress, address priceFeedAddress);
    event CurrencyRemoved(address tokenAddress);
    event PriceUpdated(uint256 listingId, uint256 newPrice);
    event DeadlineUpdated(uint256 listingId, uint256 newDeadline);
    event RefundWithdrawn(uint256 listingId, uint256 startIndex, uint256 endIndex);
    event UsdtSetted(address usdt);
    event EthSetted(address weth);

    // _______________ Modifiers _______________
    modifier listingExists(uint256 listingId) {
        require(listings[listingId].seller != address(0), "Listing not found");
        _;
    }

    // _______________ Constructor ______________
    function initialize(address _usdt, address _weth) external initializer {
        __Ownable_init();
        treasuryPercentage = 50;
        treasury = msg.sender;
        USDT = _usdt;
        ETH = _weth;
    }

    receive() external payable {
        require(msg.sender != ETH, "Do not send Ether directly");
    }

    // _______________ Admin functions _______________
    /// @dev Allows the owner to set the treasury address
    /// @param _treasury The address of the treasury
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasuryChanged(_treasury);
    }

    /// @dev Allows the owner to set the percentage of each sale that is sent to the treasury
    /// @param _treasuryPercentage The percentage of each sale that is sent to the treasury
    function setTreasuryPercentage(uint256 _treasuryPercentage) external onlyOwner {
        if (_treasuryPercentage > PERCENT_DIVIDER) revert InvalidPercentage(_treasuryPercentage);
        treasuryPercentage = _treasuryPercentage;
        emit TreasuryPercentageChanged(_treasuryPercentage);
    }

    /// @dev Allows the owner to set the USDT address
    /// @param _usdt The address of the USDT token
    function setUSDT(address _usdt) external onlyOwner {
        if (_usdt == address(0)) revert ZeroAddress();
        if (IERC20(_usdt).totalSupply() == 0) revert NonERC20();
        USDT = _usdt;
        emit UsdtSetted(_usdt);
    }

    /// @dev Allows the owner to set the ETH address
    /// @param _weth The address of the WETH
    function setEth(address _weth) external onlyOwner {
        if (_weth == address(0)) revert ZeroAddress();
        ETH = _weth;
        emit EthSetted(_weth);
    }

    /// @dev Allows the owner to add a new currency to the marketplace
    /// @param tokenAddress The address of the ERC20 token
    /// @param priceFeedAddress The address of the Chainlink price feed for the token
    function addAllowedCurrency(address tokenAddress, address priceFeedAddress, uint256 decimals) public onlyOwner {
        if (allowedCurrencies[tokenAddress].token != IERC20(address(0))) {
            revert CurrencyAlreadyAllowed();
        }
        if (IERC20(tokenAddress).totalSupply() == 0) {
            revert NonERC20();
        }
        allowedCurrencies[tokenAddress] =
            Currency(IERC20(tokenAddress), AggregatorV3Interface(priceFeedAddress), decimals);
        emit CurrencyAdded(tokenAddress, priceFeedAddress);
    }

    /// @dev Allows the owner to remove a currency from the marketplace
    /// @param tokenAddress The address of the ERC20 token
    function removeAllowedCurrency(address tokenAddress) external onlyOwner {
        if (allowedCurrencies[tokenAddress].token == IERC20(address(0))) {
            revert CurrencyNotAvailable();
        }
        delete allowedCurrencies[tokenAddress];
        emit CurrencyRemoved(tokenAddress);
    }

    // _______________ External functions _______________
    /// @dev Allows a user to create an auction listing
    /// @param nftAddress Address of the NFT contract
    /// @param tokenId Id of the NFT
    /// @param auctionEndTime The end time of the auction
    /// @param minBid The minimum bid of the auction
    /// @param currency The currency of the auction
    function createAuctionListing(
        address nftAddress,
        uint256 tokenId,
        uint256 auctionEndTime,
        uint256 minBid,
        address currency
    )
        external
    {
        if (auctionEndTime > MAX_TERM) revert TooLongTerm(auctionEndTime);
        if (minBid == 0) revert ZeroBid();
        if (currency == address(0)) revert ZeroAddress();
        if (allowedCurrencies[currency].token == IERC20(address(0))) revert CurrencyNotAvailable();

        _createListing(nftAddress, tokenId, 0, 0, true, auctionEndTime, minBid, currency);
    }

    /// @dev Allows a user to create a stansars purcase listing
    /// @param nftAddress The address of the NFT contract
    /// @param tokenId The ID of the NFT
    /// @param price The price of the NFT
    /// @param deadline The deadline of the listing
    function createPurchaseListing(address nftAddress, uint256 tokenId, uint256 price, uint256 deadline) external {
        if (deadline > MAX_TERM) revert TooLongTerm(deadline);
        if (price == 0) revert ZeroPrice();

        _createListing(nftAddress, tokenId, price, deadline, false, 0, 0, USDT);
    }

    /// @dev Allows a user to purchase a listing
    /// @param listingId The ID of the listing
    /// @param currencyAddress The address of the ERC20 token for which to buy NFT
    function buyListing(uint256 listingId, address currencyAddress) external payable listingExists(listingId) {
        Listing storage listing = listings[listingId];
        if (listing.isAuction) revert NonStandardPurchase();
        if (listing.seller == msg.sender) revert SenderIsItemOwner();
        if (block.timestamp > listing.deadline) revert Expired(block.timestamp, listing.deadline);

        uint256 currencyAmount;
        if (currencyAddress == ETH) {
            currencyAmount = getCurrencyAmount(listing.price, currencyAddress);
            if (msg.value < currencyAmount) revert InsufficientEtherSent(msg.value);
        } else {
            if (allowedCurrencies[currencyAddress].priceFeed == AggregatorV3Interface(address(0))) {
                revert CurrencyNotAvailable();
            }
            currencyAmount = getCurrencyAmount(listing.price, currencyAddress);
            allowedCurrencies[currencyAddress].token.safeTransferFrom(msg.sender, listing.seller, currencyAmount);
        }

        uint256 feeAmount = (currencyAmount * treasuryPercentage) / (PERCENT_DIVIDER);
        if (listing.currency == ETH) {
            (bool successTreasury,) = payable(treasury).call{ value: feeAmount }("");
            if (!successTreasury) revert FailedToSendEther();
            (bool successSeller,) = payable(listing.seller).call{ value: currencyAmount - feeAmount }("");
            if (!successSeller) revert FailedToSendEther();
        } else {
            allowedCurrencies[listing.currency].token.safeTransferFrom(listing.seller, treasury, feeAmount);
        }
        IERC721(listing.nftAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);
        delete listings[listingId];
        emit ListingPurchased(listingId, msg.sender);
    }

    // ___________________ For Bidders ___________________
    /// @dev Allows a user to place a bid on an auction
    /// @param listingId The ID of the listing
    /// @param bidAmount The amount of the bid
    function placeBid(uint256 listingId, uint256 bidAmount) external payable listingExists(listingId) {
        Listing storage listing = listings[listingId];
        if (!listing.isAuction) revert NonAuction();
        if (listing.seller == msg.sender) revert SenderIsItemOwner();
        if (block.timestamp > listing.auctionEndTime) revert Expired(block.timestamp, listing.auctionEndTime);

        if (listing.currency == ETH) {
            bidAmount = msg.value;
            if (bidAmount < listing.minBid) revert BidIsTooLow(listing.minBid, bidAmount);
        } else {
            if (bidAmount < listing.minBid) revert BidIsTooLow(listing.minBid, bidAmount);
            listing.bidders.push(msg.sender);
            listing.bids[msg.sender] = bidAmount;
            allowedCurrencies[listing.currency].token.safeTransferFrom(msg.sender, address(this), bidAmount);
        }

        emit NewBid(listingId, msg.sender, bidAmount);
    }

    /// @dev Allows a user to withdraw a bid on an auction
    /// @param listingId The ID of the listing
    function withdrawBid(uint256 listingId) external listingExists(listingId) {
        Listing storage listing = listings[listingId];

        uint256 bidAmount = listing.bids[msg.sender];
        if (bidAmount == 0) revert ZeroBid();

        allowedCurrencies[listing.currency].token.safeTransfer(msg.sender, bidAmount);
        delete listing.bids[msg.sender];

        emit BidWithdrawn(listingId, msg.sender);
    }

    //______________________ For Sellers ______________________
    /// @dev Allows a user to update the deadline of a listing
    /// @param listingId The ID of the listing
    /// @param deadline The new deadline
    function updateDeadline(uint256 listingId, uint256 deadline) external listingExists(listingId) {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert SenderIsNotItemOwner();
        if (deadline > MAX_TERM) revert TooLongTerm(deadline);
        listing.deadline = deadline + block.timestamp;
        emit DeadlineUpdated(listingId, deadline);
    }

    /// @dev Allows a user to update the price of a listing
    /// @param listingId The ID of the listing
    /// @param price The new price
    function updatePrice(uint256 listingId, uint256 price) external listingExists(listingId) {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert SenderIsNotItemOwner();
        listing.price = price;
        emit PriceUpdated(listingId, price);
    }

    /// @dev Allows a user to finalize an auction
    /// @param listingId The ID of the listing
    /// @param winner The address of the winner
    function finalizeAuction(uint256 listingId, address winner) external nonReentrant listingExists(listingId) {
        Listing storage listing = listings[listingId];
        if (!listing.isAuction) revert NonAuction();
        if (block.timestamp <= listing.auctionEndTime) revert AuctionNotOver();
        if (listing.seller != msg.sender) revert SenderIsNotItemOwner();
        if (listing.bids[winner] == 0) revert WinnerHasNotBid();

        uint256 winningBid = listing.bids[winner];
        uint256 feeAmount = (winningBid * (treasuryPercentage)) / (PERCENT_DIVIDER);
        if (listing.currency == ETH) {
            (bool successTreasury,) = payable(treasury).call{ value: feeAmount }("");
            if (!successTreasury) revert FailedToSendEther();
            (bool successSeller,) = payable(listing.seller).call{ value: winningBid - feeAmount }("");
            if (!successSeller) revert FailedToSendEther();
        } else {
            allowedCurrencies[listing.currency].token.safeTransfer(treasury, feeAmount);
            allowedCurrencies[listing.currency].token.safeTransfer(listing.seller, winningBid - feeAmount);
        }
        IERC721(listing.nftAddress).transferFrom(address(this), winner, listing.tokenId);

        listing.bids[winner] = 0;

        delete listings[listingId];
        emit AuctionResult(listingId, winner, winningBid);
    }

    // _______________ Internal functions _______________
    /// @dev Creates a new listing
    /// @param nftAddress The address of the NFT contract
    /// @param tokenId The ID of the NFT
    /// @param price The price of the listing
    /// @param deadline The deadline of the listing
    /// @param isAuction Whether the listing is an auction
    /// @param auctionEndTime The end time of the auction
    /// @param minBid The minimum bid of the auction
    /// @param currency The currency of the listing
    function _createListing(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        bool isAuction,
        uint256 auctionEndTime,
        uint256 minBid,
        address currency
    )
        internal
    {
        if (listings[nextListingId].seller != address(0)) revert ItemAlreadyOnListing();
        if (IERC721(nftAddress).ownerOf(tokenId) != msg.sender) revert SenderIsNotItemOwner();
        if (!IERC721(nftAddress).isApprovedForAll(msg.sender, address(this))) revert NonApprovedNFT();

        IERC721(nftAddress).transferFrom(msg.sender, address(this), tokenId);

        listings[nextListingId].nftAddress = nftAddress;
        listings[nextListingId].tokenId = tokenId;
        listings[nextListingId].seller = msg.sender;
        listings[nextListingId].price = price;
        listings[nextListingId].deadline = deadline + block.timestamp;
        listings[nextListingId].isAuction = isAuction;
        listings[nextListingId].auctionEndTime = auctionEndTime + block.timestamp;
        listings[nextListingId].minBid = minBid;
        listings[nextListingId].bidders = new address[](0);
        listings[nextListingId].currency = currency;

        emit NewListing(nextListingId);
        nextListingId++;
    }

    // _______________ View functions _______________
    /// @dev Returns the amount of currency for a given amount of USDT
    /// @param usdtAmount The amount of USDT
    /// @param currencyAddress The address of the ERC20 token
    /// @return The amount of currency
    function getCurrencyAmount(uint256 usdtAmount, address currencyAddress) public view returns (uint256) {
        (, int256 price,,,) = allowedCurrencies[currencyAddress].priceFeed.latestRoundData();
        uint256 decimalAdjustment = 10 ** uint256(allowedCurrencies[currencyAddress].decimals);
        return (usdtAmount * (uint256(price))) / decimalAdjustment;
    }

    /// @dev Returns the amount of USDT for a given amount of currency
    /// @param currencyAmount The amount of currency
    /// @param currencyAddress The address of the ERC20 token
    /// @return The amount of USDT
    function getUsdAmount(uint256 currencyAmount, address currencyAddress) public view returns (uint256) {
        (, int256 price,,,) = allowedCurrencies[currencyAddress].priceFeed.latestRoundData();
        uint256 decimalAdjustment = 10 ** uint256(allowedCurrencies[currencyAddress].decimals);
        return (currencyAmount * decimalAdjustment) / (uint256(price));
    }

    /// @dev Returns the next listing ID
    function getListingCount() external view returns (uint256) {
        return nextListingId;
    }

    /// @dev Returns the bidders for a given listing
    /// @param listingId The ID of the listing
    /// @return The bidders
    function getListingBids(uint256 listingId) external view listingExists(listingId) returns (address[] memory) {
        return listings[listingId].bidders;
    }

    /// @dev Returns the bid amount for a given listing and bidder
    /// @param listingId The ID of the listing
    /// @param bidder The address of the bidder
    /// @return The bid amount
    function getListingBidAmount(
        uint256 listingId,
        address bidder
    )
        external
        view
        listingExists(listingId)
        returns (uint256)
    {
        return listings[listingId].bids[bidder];
    }

    /// @dev Returns the listing details
    /// @param listingId The ID of the listing
    function getListing(uint256 listingId)
        external
        view
        returns (
            address nftAddress,
            uint256 tokenId,
            address seller,
            uint256 price,
            uint256 deadline,
            bool isAuction,
            uint256 auctionEndTime,
            uint256 minBid,
            address currency
        )
    {
        Listing storage listing = listings[listingId];
        nftAddress = listing.nftAddress;
        tokenId = listing.tokenId;
        seller = listing.seller;
        price = listing.price;
        deadline = listing.deadline;
        isAuction = listing.isAuction;
        auctionEndTime = listing.auctionEndTime;
        minBid = listing.minBid;
        currency = listing.currency;
    }
}
