// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/INODERewardManagement.sol";

import "./types/ERC20.sol";
import "./types/Ownable.sol";

import "./PaymentSplitter.sol";

import "hardhat/console.sol";

contract PENT is ERC20, Ownable, PaymentSplitter {
    using SafeMath for uint256;

    INODERewardManagement public immutable nodeRewardManagement;

    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;
    address public vault;
    address public rewardsPool;
	address public stakingPool;
    address public treasury;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public vaultFee;
    uint256 public treasuryFee;

    uint256 public cashoutFee;

    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount;
	uint256[] private nodeFees;

    mapping(address => bool) public _isBlacklisted;
	mapping(address => bool) public _isExcluded;
    mapping(address => bool) public automatedMarketMakerPairs;

	bool private protectSale = false;
    bool public enableFreeTrading = false;

	uint256 public maxTxAmount = 50 * 10 ** 18;

	struct StakePosition {
        uint256 creationTime;
        uint256 expireTime;
        uint256 balance;
		uint256 id;
    }

	mapping(address => StakePosition[]) public stakePositions;
	uint256 stakePositionIndex = 0;

    uint256 public immutable deployedTime;

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(
        address indexed newLiquidityWallet,
        address indexed oldLiquidityWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );


    
    address public teamWallet;

    uint256 private transferAmountForTeam;

    uint256 private firstStepAmount = 1250000000000000000000;
    uint256 private secondStepAmount = 208330000000000000000;

    constructor(
        address[] memory payees,
        uint256[] memory shares,
        address[] memory addresses,
        uint256[] memory balances,
        uint256[] memory fees,
        uint256 swapAmount,
        address uniV2Router,
        address _nodeRewardManagement
    ) ERC20("PENT", "PENT") PaymentSplitter(payees, shares) {

        deployedTime = block.timestamp;

        nodeRewardManagement = INODERewardManagement(_nodeRewardManagement);

        require(uniV2Router != address(0), "ROUTER CANNOT BE ZERO");
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniV2Router);

        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        teamWallet = addresses[0];
        treasury = addresses[1];
        vault = addresses[2];
        rewardsPool = addresses[3];
        stakingPool = addresses[5];

        require(vault != address(0) && rewardsPool != address(0), "ADDRESS CANNOT BE ZERO");

        require(
            fees[0] != 0 && fees[1] != 0 && fees[2] != 0 && fees[3] != 0,
            "FEES EQUAL 0"
        );

        vaultFee = fees[0];
        rewardsFee = fees[1];
        liquidityPoolFee = fees[2];
        treasuryFee = fees[3];
        cashoutFee = fees[4];

		nodeFees = [8000000000000000000, 7330000000000000000, 6670000000000000000, 6000000000000000000, 5330000000000000000, 4670000000000000000, 4000000000000000000, 3880000000000000000, 3770000000000000000, 3650000000000000000, 3540000000000000000, 3420000000000000000, 3310000000000000000, 3190000000000000000, 3080000000000000000, 2960000000000000000, 2850000000000000000, 2730000000000000000, 2620000000000000000, 2500000000000000000, 2299999999999999700, 2100000000000000000, 1900000000000000000, 1700000000000000000, 1500000000000000000, 1300000000000000000, 1100000000000000100, 900000000000000000, 700000000000000000, 500000000000000000];

        require(addresses.length > 0 && balances.length > 0, "ADDRESS ARRAY ERROR");
        require(addresses.length == balances.length, "ADDRESS LENGTH MISMATCH");

        address[] memory _addresses = addresses; 
        uint256[] memory _balances = balances;

        for (uint256 i = 0; i < _addresses.length; i++) {
			_isExcluded[_addresses[i]] = true;
            _mint(_addresses[i], _balances[i] * (10**18));
        }
        require(totalSupply() == 20456743e18, "TOTALSUPPLY ERROR");
        require(swapAmount > 0, "SWAP AMOUNT ERROR");
        swapTokensAmount = swapAmount * (10**18);
		
		protectSale = true;
    }

	function getStakePositions(address staker) public view returns (StakePosition[] memory positions){
		return stakePositions[staker];
	}

    function getNodeNumberOf(address account) public view returns (uint256) {
        return nodeRewardManagement._getNodeNumberOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getRewardAmountOf(msg.sender);
    }

    function getFusionCost() public view returns(uint256, uint256, uint256) {
        return nodeRewardManagement._getFusionCost();
    }

    function getNodePrices() public view returns (uint256, uint256, uint256) {
        return nodeRewardManagement._getNodePrices();
    } 

    function getNodePrice(uint256 _type, bool isFusion) public view returns (uint256) {
        return nodeRewardManagement.getNodePrice(_type, isFusion);
    }

    function getTaxForFusion() public view returns (uint256, uint256, uint256) {
        return nodeRewardManagement._getTaxForFusion();
    }

    function getClaimInterval() public view returns (uint256) {
        return nodeRewardManagement.claimInterval();
    }

    function getRewardsPerMinute() public view returns (uint256, uint256, uint256) {
        return (nodeRewardManagement.rewardsPerMinuteOne(), nodeRewardManagement.rewardsPerMinuteFive(), nodeRewardManagement.rewardsPerMinuteTen() );
    }

    function getNodeCounts() public view returns (uint256, uint256, uint256, uint256) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodeCounts(msg.sender);
    }

    function getNodesInfo () public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesInfo(msg.sender);
    }

    function getNodesType() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesType(msg.sender);
    }

    function getNodesName() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesName(msg.sender);
    }

    function getNodesCreatime() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesCreationTime(msg.sender);
    }

	function getNodesExpireTime() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesExpireTime(msg.sender);
    }

    function getNodesRewards() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesRewardAvailable(msg.sender);
    }

    function getNodesLastClaims() public view returns (string memory) {
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesLastClaimTime(msg.sender);
    }

    function getTotalNodesCreated() public view returns (uint256) {
        return nodeRewardManagement.totalNodesCreated();
    }

	function withdrawStakingPosition(uint256 index) public {
		address staker = msg.sender;
		StakePosition storage position = stakePositions[staker][index];
		require(position.expireTime <= block.timestamp, "NOT ELIIGIBLE TO CLAIM");
		require(position.balance > 0, "NOTHING TO CLAIM");
		
		uint256 amount = position.balance;
		position.balance = 0;
		super._transfer(stakingPool, msg.sender, amount);
	}

	function createNodeWithStakePosition(string memory name, uint256 stakeDays, uint256 _type) public {
        require(bytes(name).length > 3 && bytes(name).length < 32, "NAME SIZE INVALID");
        require(_type > 0 && _type < 4, "NOT AVAILABLE"); 

		address sender = msg.sender;

	    require(sender != address(0), "ZERO ADDRESS");

	    require(!_isBlacklisted[sender], "BLACKLISTED ADDRESS");

		require(sender != vault && sender != rewardsPool, "CANNOT CREATE NODE");
        require(stakeDays >= 1 && stakeDays <= 30, "STAKE TIME ERROR");

		uint256 duration = stakeDays * 1 days;
		uint256 nodeFee = nodeFees[stakeDays - 1];

		uint256 nodePrice = nodeRewardManagement.getNodePrice(_type, false);
		require(balanceOf(sender) >= nodePrice + nodeFee, "BALANCE TOO LOW");
        uint256 contractTokenBalance = balanceOf(address(this));

        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;

        super._transfer(sender, address(stakingPool), nodePrice);

        if (
            swapAmountOk &&
            swapLiquify &&
            !swapping &&
            sender != owner() &&
            !automatedMarketMakerPairs[sender]
        ) {
            swapping = true;

            uint256 rewardsPoolTokens = contractTokenBalance
                .mul(rewardsFee)
                .div(100);

            super._transfer(
                address(this),
                rewardsPool,
                rewardsPoolTokens
            );

            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);

            uint256 vaultTokens = contractTokenBalance.mul(vaultFee).div(100);
            swapAndSendToFee(vault, vaultTokens);

            uint256 treasuryTokens = contractTokenBalance.mul(treasuryFee).div(100);
            swapAndSendToFee(treasury, treasuryTokens);

            swapping = false;
        }
		
        super._transfer(sender, address(this), nodeFee);
        swapAndSendToFee(treasury, nodeFee);
		createStakePosition(nodePrice, duration);
        nodeRewardManagement.createNode(sender, name, duration, _type, 1);
    }

    function cashoutReward(uint256 blocktime) public {
        address sender = msg.sender;
        require(sender != address(0), "ZERO ADDRESS");
        require(!_isBlacklisted[sender], "BLACKLISTED ADDRESS");
        require(
            sender != treasury && sender != rewardsPool && sender != vault,
            "CANNOT CASHOUT REWARDS"
        );
        uint256 rewardAmount = nodeRewardManagement._getRewardAmountOf( sender, blocktime );
        require(
            rewardAmount > 0,
            "NOT ENOUGH REWARD TO CASH OUT"
        );

		uint256 feeAmount = rewardAmount.mul(cashoutFee).div(100);
		rewardAmount = rewardAmount.sub(feeAmount);
        if (swapLiquify && cashoutFee > 0) {
			super._transfer(rewardsPool, address(this), feeAmount);
			swapAndSendToFee(treasury, feeAmount);
        }
        super._transfer(rewardsPool, sender, rewardAmount);
        nodeRewardManagement._cashoutNodeReward(sender, blocktime);
    }

    function cashoutAll() public {
        address sender = msg.sender;
        cashoutAllInternal(sender);
    }

    function createNodeWithTokens(string memory name, uint256 _type) public {
        require(_type > 0 &&  _type < 4, "NOT ALLOWED");
        _createNodeWithTokens(name, _type, false);
    }

    function fusionNode(uint256 _method, string memory name) public {
        address sender = msg.sender;
        cashoutAllInternal(sender);
        nodeRewardManagement.fusionNode(_method, sender);
        _createNodeWithTokens(name, _method.add(1), true);
    }

    // Only Owner

    function updateLockAmount(uint256 _firstStep, uint256 _secondStep) public onlyOwner {
        firstStepAmount = _firstStep;
        secondStepAmount = _secondStep;
    }

    function getRewardAmountOf(address account)
        public
        view
        onlyOwner
        returns (uint256)
    {
        return nodeRewardManagement._getRewardAmountOf(account);
    }

	function changeNodeFees(uint256[] memory newNodeFees) public onlyOwner {
		require(newNodeFees.length == 30, "ITEM ERROR");
		nodeFees = newNodeFees;
	}

    function changeNodePrices(uint256 newNodePriceOne, uint256 newNodePriceFive, uint256 newNodePriceTen) public onlyOwner {
        nodeRewardManagement._changeNodePrice(newNodePriceOne, newNodePriceFive, newNodePriceTen);
    }

    function changeClaimInterval(uint256 newInterval) public onlyOwner {
        nodeRewardManagement._changeClaimInterval(newInterval);
    }

    function toggleTrading() public onlyOwner {
        enableFreeTrading = !enableFreeTrading;
    }

    function changeRewardsPerMinute(uint256 newPriceOne, uint256 newPriceFive, uint256 newPriceTen, uint256 newPriceOMEGA) public onlyOwner {
        nodeRewardManagement._changeRewardsPerMinute(newPriceOne, newPriceFive, newPriceTen, newPriceOMEGA);
    }

	function manualswap(uint amount) public onlyOwner {
		if (amount > balanceOf(address(this))) amount = balanceOf(address(this));
		swapTokensForEth(amount);
	}

	function manualsend(uint amount) public onlyOwner {
		if (amount > address(this).balance) amount = address(this).balance;
		payable(owner()).transfer(amount);
	}

    // Fusion Node
    function toggleFusionMode() public onlyOwner {
        nodeRewardManagement.toggleFusionMode();
    }

    function setNodeCountForFusion(uint256 _nodeCountForLesser, uint256 _nodeCountForCommon, uint256 _nodeCountForLegendary) public onlyOwner {
        nodeRewardManagement.setNodeCountForFusion(_nodeCountForLesser, _nodeCountForCommon, _nodeCountForLegendary);
    }

    function setTaxForFusion(uint256 _taxForLesser, uint256 _taxForCommon, uint256 _taxForLegendary) public onlyOwner {
        nodeRewardManagement.setTaxForFusion(_taxForLesser, _taxForCommon, _taxForLegendary);
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "ALEADY SET");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateVaultWall(address payable wall) external onlyOwner {
        vault = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        rewardsPool = wall;
    }

    function updateTeamWalleet(address payable wall) external onlyOwner {
        teamWallet = wall;
    }

	function updateStakingPool(address payable wall) external onlyOwner {
        stakingPool = wall;
    }

    function updateTreasuryWall(address payable wall) external onlyOwner {
        treasury = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
    }

    function updateLiquidityFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
    }

    function updateVaultFee(uint256 value) external onlyOwner {
        vaultFee = value;
    }

    function updateTreasuryFee(uint256 value) external onlyOwner {
        treasuryFee = value;
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        cashoutFee = value;
    }

	function changeMaxTxAmount(uint256 value) external onlyOwner {
		maxTxAmount = value;
	}

	function changeProtectSale(bool value) external onlyOwner {
		protectSale = value;
	}

    function changeSwapLiquify(bool newVal) public onlyOwner {
        swapLiquify = newVal;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        _setAutomatedMarketMakerPair(pair, value);
    }

    function blacklistMalicious(address account, bool value)
        external
        onlyOwner
    {
        _isBlacklisted[account] = value;
    }

	function setIsExcluded(address account, bool value)
        external
        onlyOwner
    {
        _isExcluded[account] = value;
    }

    // Private

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "TRANSFER FROM ZERO ADDRESS");
        require(to != address(0), "TRANSFER TO ZERO ADDRESS");
        require(
            !_isBlacklisted[from] && !_isBlacklisted[to],
            "Blacklisted address"
        );

		if (from != owner() && to != owner() && from != address(this) && to != address(this) && !_isExcluded[from] && !_isExcluded[to]) {
			if (enableFreeTrading == false) {
                require(amount <= maxTxAmount, "MAX LIMIT AMOUNT ERROR");
            }
			if (protectSale && to == uniswapV2Pair) {
				_isBlacklisted[from] = true;
			}
		}

        if (from == address(teamWallet)) {
            uint256 monthsPassed = (block.timestamp).sub(deployedTime).div(2592000);
            if (monthsPassed < 8) {
                require(transferAmountForTeam + amount < firstStepAmount * (monthsPassed + 1), "Not Allowed");
            } else {
                require(transferAmountForTeam + amount < secondStepAmount * (monthsPassed + 1), "Not Allowed");
            }
        }

        super._transfer(from, to, amount);
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance).sub(initialETHBalance);
        (bool success, ) = destination.call{value: newBalance}("");
        require(success, "PAYMENT FAIL");
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

	function swapTokensForEth(uint256 tokenAmount) private {
		address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);
		
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
	}

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

	function createStakePosition(uint256 amount, uint256 duration) private {
		address staker = msg.sender;
		
		uint256 positionId = stakePositionIndex++;
		stakePositions[staker].push(
			StakePosition({
				creationTime: block.timestamp,
				expireTime: block.timestamp + duration,
				balance: amount,
				id: positionId
			})
		);
	}

    function _createNodeWithTokens(string memory name, uint256 _type, bool isFusion) private {
        require(bytes(name).length > 3 && bytes(name).length < 20, "NAME SIZE INVALID");
        if (_type == 4) {
            require(isFusion, "ONLY ENABLE WHEN FUSING");
        }

		address sender = msg.sender;

	    require(sender != address(0), "ZERO ADDRESS");
       
	    require(!_isBlacklisted[sender], "BLACKLISSTED ADDRESS");
        
		require(sender != vault && sender != rewardsPool && sender != treasury, "CANNOT CREATE NODE");
        
		uint256 nodePrice = nodeRewardManagement.getNodePrice(_type, isFusion);
		require(balanceOf(sender) >= nodePrice, "BALANCE TOO LOW");
        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;

        if (
            swapAmountOk &&
            swapLiquify &&
            !swapping &&
            sender != owner() &&
            !automatedMarketMakerPairs[sender]
        ) {
            swapping = true;

            uint256 rewardsPoolTokens = contractTokenBalance
                .mul(rewardsFee)
                .div(100);

            super._transfer(
                address(this),
                rewardsPool,
                rewardsPoolTokens
            );
			
            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);

            uint256 vaultTokens = contractTokenBalance.mul(vaultFee).div(100);
            swapAndSendToFee(vault, vaultTokens);

            uint256 treasuryTokens = contractTokenBalance.mul(treasuryFee).div(100);
            swapAndSendToFee(treasury, treasuryTokens);

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice);
        if (isFusion) {
            super._transfer(address(this), deadWallet, nodePrice);
        }
        nodeRewardManagement.createNode(sender, name, 0, _type, 0);
    }

    function cashoutAllInternal(address _account) private {
        address sender = _account;
        require(
            sender != address(0),
            "ZERO ADDRESS"
        );
        require(!_isBlacklisted[sender], "BLACKLISTED ADDRESS");
        require(
            sender != vault && sender != rewardsPool && sender != vault,
            "CANNOT CASHOUT REWARDS"
        );
        uint256 rewardAmount = nodeRewardManagement._getRewardAmountOf(sender);
        require(
            rewardAmount > 0,
            "NOT ENOUGH TO CASH OUT"
        );
		
        uint256 feeAmount = rewardAmount.mul(cashoutFee).div(100);
		rewardAmount = rewardAmount.sub(feeAmount);

        if (swapLiquify && cashoutFee > 0) {
			super._transfer(rewardsPool, address(this), feeAmount);
			swapAndSendToFee(vault, feeAmount);
        }
        super._transfer(rewardsPool, sender, rewardAmount);
        nodeRewardManagement._cashoutAllNodesReward(sender);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "ALREADY SET"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }
}