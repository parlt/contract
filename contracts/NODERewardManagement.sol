// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/SafeMath.sol";

contract NODERewardManagement {
    using SafeMath for uint256;

    struct NodeEntity {
        uint256 creationTime;
        uint256 lastClaimTime;
		uint256 dividendsPaid;
		uint256 expireTime;
        uint256 rewardsPerMinute;
    }

    mapping(address => NodeEntity[]) private _nodesOfUser;
	mapping(address => bool) public _managers;

    uint256 public nodePriceOne;
    uint256 public nodePriceFive;
    uint256 public nodePriceTen;

	uint256 public rewardsPerMinuteOne;
	uint256 public rewardsPerMinuteFive;
	uint256 public rewardsPerMinuteTen;

    bool public distribution = false;

    uint256 public totalNodesCreated = 0;
    uint256 public totalRewardStaked = 0;

	uint256 public claimInterval = 60;
	
	uint256 public stakeNodeStartAmount = 0 * 10 ** 18;
	uint256 public nodeStartAmount = 1 * 10 ** 18;
	
	event NodeCreated(address indexed from, string name, uint256 index, uint256 totalNodesCreated, uint256 _type);
	
    constructor(
        uint256 _nodePriceOne,
        uint256 _nodePriceFive,
        uint256 _nodePriceTen,
        uint256 _rewardsPerMinuteOne,
        uint256 _rewardsPerMinuteFive,
        uint256 _rewardsPerMinuteTen
    ) {
		_managers[msg.sender] = true;
        nodePriceOne = _nodePriceOne;
        nodePriceFive = _nodePriceFive;
        nodePriceTen = _nodePriceTen;
        rewardsPerMinuteOne = _rewardsPerMinuteOne;
        rewardsPerMinuteFive = _rewardsPerMinuteFive;
        rewardsPerMinuteTen = _rewardsPerMinuteTen;
    }

    modifier onlyManager() {
        require(_managers[msg.sender] == true, "Only managers can call this function");
        _;
    }
	
	function addManager(address manager) external onlyManager {
		_managers[manager] = true;
	}

    function createNode(address account, string memory name, uint256 expireTime, uint256 _type) external onlyManager {
		uint256 realExpireTime = 0;
		if (expireTime > 0) {
			realExpireTime = block.timestamp + expireTime;
		}
        uint256 rewardsPerMinute;
        if (_type == uint256(1)) {
            rewardsPerMinute = rewardsPerMinuteOne;
        } else if (_type == uint256(2)) {
            rewardsPerMinute = rewardsPerMinuteFive;
        } else if (_type == uint256(3)) {
            rewardsPerMinute = rewardsPerMinuteTen;
        }
        _nodesOfUser[account].push(
            NodeEntity({
                creationTime: block.timestamp,
                lastClaimTime: block.timestamp,
				dividendsPaid: 0,
				expireTime: realExpireTime,
                rewardsPerMinute: rewardsPerMinute
            })
        );
        totalNodesCreated++;
		emit NodeCreated(account, name, _nodesOfUser[account].length, totalNodesCreated, _type);
    }
	
	function dividendsOwing(NodeEntity memory node) private view returns (uint256 availableRewards) {
		uint256 currentTime = block.timestamp;
		if (currentTime > node.expireTime && node.expireTime > 0) {
			currentTime = node.expireTime;
		}
		uint256 minutesPassed = (currentTime).sub(node.creationTime).div(claimInterval);
		return minutesPassed.mul(node.rewardsPerMinute).add(node.expireTime > 0 ? stakeNodeStartAmount : nodeStartAmount).sub(node.dividendsPaid);
	}
	
	function _checkExpired(NodeEntity memory node) private view returns (bool isExpired) {
		return (node.expireTime > 0 && node.expireTime <= block.timestamp);
	}

    function _getNodeByIndex(
        NodeEntity[] storage nodes,
        uint256 index
    ) private view returns (NodeEntity storage) {
        uint256 numberOfNodes = nodes.length;
        require(
            numberOfNodes > 0,
            "CASHOUT ERROR: You don't have nodes to cash-out"
        );
        require(index < numberOfNodes, "CASHOUT ERROR: Invalid node");
        return nodes[index];
    }

    function _cashoutNodeReward(address account, uint256 index)
        external
		onlyManager
        returns (uint256)
    {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(
            numberOfNodes > 0,
            "CASHOUT ERROR: You don't have nodes to cash-out"
        );
        NodeEntity storage node = _getNodeByIndex(nodes, index);
        uint256 rewardNode = dividendsOwing(node);
        node.dividendsPaid += rewardNode;
        return rewardNode;
    }

    function _cashoutAllNodesReward(address account)
        external
		onlyManager
        returns (uint256)
    {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, "NODE: NO NODE OWNER");
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        for (uint256 i = 0; i < nodesCount; i++) {
            _node = nodes[i];
			uint256 rewardNode = dividendsOwing(_node);
            rewardsTotal += rewardNode;
            _node.dividendsPaid += rewardNode;
        }
        return rewardsTotal;
    }


    function _getRewardAmountOf(address account)
        external
        view
        returns (uint256)
    {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        uint256 nodesCount;
        uint256 rewardCount = 0;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

		NodeEntity storage _node;
        for (uint256 i = 0; i < nodesCount; i++) {
			_node = nodes[i];
            rewardCount += dividendsOwing(_node);
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 index)
        external
        view
        returns (uint256)
    {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(
            numberOfNodes > 0,
            "CASHOUT ERROR: You don't have nodes to cash-out"
        );
        NodeEntity storage node = _getNodeByIndex(nodes, index);
        uint256 rewardNode = dividendsOwing(node);
        return rewardNode;
    }

    function _getNodeRewardAmountOf(address account, uint256 index)
        external
        view
        returns (uint256)
    {
		NodeEntity memory node = _getNodeByIndex(_nodesOfUser[account], index);
        return dividendsOwing(node);
    }
	

    function _getNodesExpireTime(address account)
        external
        view
        returns (string memory)
    {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _expireTimes = uint2str(nodes[0].expireTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            _expireTimes = string(
                abi.encodePacked(
                    _expireTimes,
                    separator,
                    uint2str(_node.expireTime)
                )
            );
        }
        return _expireTimes;
    }


    function _getNodesCreationTime(address account)
        external
        view
        returns (string memory)
    {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _creationTimes = uint2str(nodes[0].creationTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _creationTimes = string(
                abi.encodePacked(
                    _creationTimes,
                    separator,
                    uint2str(_node.creationTime)
                )
            );
        }
        return _creationTimes;
    }

    function _getNodesRewardAvailable(address account)
        external
        view
        returns (string memory)
    {
        require(isNodeOwner(account), "GET REWARD: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _rewardsAvailable = uint2str(dividendsOwing(nodes[0]));
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _rewardsAvailable = string(
                abi.encodePacked(
                    _rewardsAvailable,
                    separator,
                    uint2str(dividendsOwing(_node))
                )
            );
        }
        return _rewardsAvailable;
    }

    function _getNodesLastClaimTime(address account)
        external
        view
        returns (string memory)
    {
        require(isNodeOwner(account), "LAST CLAIME TIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _lastClaimTimes = uint2str(nodes[0].lastClaimTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _lastClaimTimes = string(
                abi.encodePacked(
                    _lastClaimTimes,
                    separator,
                    uint2str(_node.lastClaimTime)
                )
            );
        }
        return _lastClaimTimes;
    }
	
	function getNodes(address user) external view returns (NodeEntity[] memory nodes) {
		return _nodesOfUser[user];
	}

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _changeStakeNodeStartAmount(uint256 newStartAmount) external onlyManager {
        stakeNodeStartAmount = newStartAmount;
    }

    function _changeNodeStartAmount(uint256 newStartAmount) external onlyManager {
        nodeStartAmount = newStartAmount;
    }

    function _changeNodePrice(uint256 newNodePriceOne, uint256 newNodePriceFive, uint256 newNodePriceTen) external onlyManager {
        nodePriceOne = newNodePriceOne;
        nodePriceFive = newNodePriceFive;
        nodePriceTen = newNodePriceTen;
    }

    function _changeRewardsPerMinute(uint256 newPriceOne, uint256 newPriceFive, uint256 newPriceTen) external onlyManager {
        rewardsPerMinuteOne = newPriceOne;
        rewardsPerMinuteFive = newPriceFive;
        rewardsPerMinuteTen = newPriceTen;
    }
	
	function _changeClaimInterval(uint256 newInterval) external onlyManager {
        claimInterval = newInterval;
    }

    function getNodePrice(uint256 _type) external view returns (uint256) {
        if (_type == 1) {
            return nodePriceOne;
        } else if (_type == 2) {
            return nodePriceFive;
        } else if (_type == 3) {
            return nodePriceTen;
        }
    }

    function _getNodeNumberOf(address account) external view returns (uint256) {
        return _nodesOfUser[account].length;
    }

    function isNodeOwner(address account) private view returns (bool) {
        return _nodesOfUser[account].length > 0;
    }

    function _isNodeOwner(address account) external view returns (bool) {
        return isNodeOwner(account);
    }
}