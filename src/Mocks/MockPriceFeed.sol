// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Mock interface to simulate the AggregatorV3Interface used in the ERC721Marketplace contract
interface IMockAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId,
        uint256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract MockPriceFeed is IMockAggregatorV3 {
    uint8 public override decimals;
    uint256 public price;

    constructor(uint8 _decimals, uint256 _price) {
        decimals = _decimals;
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        uint256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, price, block.timestamp, block.timestamp, 0);
    }
}