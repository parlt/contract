// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface INODERewardManagement {
    function getNodePrice(uint256 _type) external view returns (uint256);

    function createNode(address account, string memory name, uint256 expireTime, uint256 _type) external;
    
    function _getRewardAmountOf(address account) external view returns (uint256);

    function _getRewardAmountOf(address account, uint256 index) external view returns (uint256);

    function _cashoutNodeReward(address account, uint256 index) external returns (uint256);

    function _cashoutAllNodesReward(address account) external returns (uint256);

    function _getNodeNumberOf(address account) external view returns (uint256);

    function _isNodeOwner(address account) external view returns (bool);

    function _changeNodePrice(uint256 newNodePriceOne, uint256 newNodePriceFive, uint256 newNodePriceTen) external;

    function _changeClaimInterval(uint256 newInterval) external;

    function claimInterval() external view returns (uint256);

    function _changeRewardsPerMinute(uint256 newPriceOne, uint256 newPriceFive, uint256 newPriceTen) external;

    function rewardsPerMinuteOne() external view returns (uint256);

    function rewardsPerMinuteFive() external view returns (uint256);

    function rewardsPerMinuteTen() external view returns (uint256);

    function _getNodesName(address account) external view returns (string memory);

    function _getNodesCreationTime(address account) external view returns (string memory);

    function _getNodesExpireTime(address account) external view returns (string memory);

    function _getNodesRewardAvailable(address account) external view returns (string memory);

    function _getNodesLastClaimTime(address account) external view returns (string memory);

    function totalRewardStaked() external view returns (uint256);

    function totalNodesCreated() external view returns (uint256);
}