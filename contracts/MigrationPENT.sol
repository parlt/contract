// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/INODERewardManagement.sol";

import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";

import "./types/Ownable.sol";

contract MigrationPENT is Ownable {
    using SafeMath for uint256;

    address immutable oldPENT;
    INODERewardManagement immutable oldManagement;

    address immutable newPENT;
    INODERewardManagement immutable newManagement;

    bool public enableMigration = true;

    mapping(address => bool) public migratedUser;

    struct NodeEntity {
        uint256 creationTime;
        uint256 lastClaimTime;
		uint256 expireTime;
        string name;
        uint256 nodeType;
        uint256 created;
        uint256 isStake;
    }

    constructor(
    ) {
    }

    function setContracts(
        address _oldPENT,
        address _oldManagement,
        address _newPENT,
        address _newManagement
    ) public onlyOwner {
        require(_oldPENT != address(0) && _oldManagement != address(0) && _newPENT != address(0) && _newManagement != address(0), "Zero Address");
        oldPENT = _oldPENT;
        newPENT = _newPENT;

        oldManagement = INODERewardManagement(_oldManagement);
        newManagement = INODERewardManagement(_newManagement);
    }

    function toggleMigration() public onlyOwner {
        enableMigration = !enableMigration;
    }

    function migration(NodeEntity[] memory _nodesArray) public {
        address account = msg.sender;

        require(migratedUser[account] == false, "Already Migrated");
        migratedUser[account] = true;

        uint256 oldLesserNodeCount;
        uint256 oldCommonNodeCount;
        uint256 oldLegendaryNodeCount;

        uint256 checkLesserNodeCount;
        uint256 checkCommonNodeCount;
        uint256 checkLegendaryNodeCount;

        (oldLesserNodeCount, oldCommonNodeCount, oldLegendaryNodeCount, ) = oldManagement._getNodeCounts(account);

        NodeEntity[] memory nodesArray = _nodesArray;
        NodeEntity memory _node;

        for (uint256 i = 0; i < nodesArray.length; i ++) {
            _node = nodesArray[i];

            if (_node.nodeType == 1) checkLesserNodeCount = checkLesserNodeCount + 1;
            if (_node.nodeType == 2) checkCommonNodeCount = checkCommonNodeCount + 1;
            if (_node.nodeType == 3) checkLegendaryNodeCount = checkLegendaryNodeCount + 1;
        }

        require(checkLesserNodeCount == oldLesserNodeCount && checkCommonNodeCount == oldCommonNodeCount && checkLegendaryNodeCount == oldLegendaryNodeCount, "Incorrect");

        for (uint256 i = 0; i < nodesArray.length; i ++) {
            _node = nodesArray[i];

            newManagement.migrateNode(account, _node.name, _node.creationTime, _node.lastClaimTime, _node.expireTime, _node.nodeType, _node.isStake);
        }

        uint256 balance = IERC20(oldPENT).balanceOf(account);

        IERC20(oldPENT).transferFrom(account, address(this), balance);
        IERC20(newPENT).transfer(account, balance);
    }

    function withdrawToken(address target) public onlyOwner {
        IERC20(newPENT).transfer(target, IERC20(newPENT).balanceOf(address(this)));
        IERC20(oldPENT).transfer(target, IERC20(oldPENT).balanceOf(address(this)));
    }
}