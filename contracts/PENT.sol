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
    address public futurUsePool;
    address public distributionPool;
	address public stakingPool = 0x1A4C49cf5d526edaf8955c176ED3cA5531D1270E;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public futurFee;
    uint256 public totalFees;

    uint256 public cashoutFee;

    uint256 private rwSwap;
    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount;
	uint256[] private nodeFees;

    mapping(address => bool) public _isBlacklisted;
	mapping(address => bool) public _isExcluded;
    mapping(address => bool) public automatedMarketMakerPairs;

	bool private protectSale = false;

	uint256 public maxTxAmount = 25 * 10 ** 18;

	struct StakePosition {
        uint256 creationTime;
        uint256 expireTime;
        uint256 balance;
		uint256 id;
    }

	mapping(address => StakePosition[]) public stakePositions;
	uint256 stakePositionIndex = 0;

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

        console.log("here");

        nodeRewardManagement = INODERewardManagement(_nodeRewardManagement);

        require(uniV2Router != address(0), "ROUTER CANNOT BE ZERO");
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniV2Router);

        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        futurUsePool = addresses[4];
        distributionPool = addresses[5];

        require(futurUsePool != address(0) && distributionPool != address(0), "FUTUR & REWARD ADDRESS CANNOT BE ZERO");

        require(
            fees[0] != 0 && fees[1] != 0 && fees[2] != 0 && fees[3] != 0,
            "CONSTR: Fees equal 0"
        );
        futurFee = fees[0];
        rewardsFee = fees[1];
        liquidityPoolFee = fees[2];
        cashoutFee = fees[3];
        rwSwap = fees[4];


		nodeFees = [8000000000000000000, 7330000000000000000, 6670000000000000000, 6000000000000000000, 5330000000000000000, 4670000000000000000, 4000000000000000000, 3880000000000000000, 3770000000000000000, 3650000000000000000, 3540000000000000000, 3420000000000000000, 3310000000000000000, 3190000000000000000, 3080000000000000000, 2960000000000000000, 2850000000000000000, 2730000000000000000, 2620000000000000000, 2500000000000000000, 2299999999999999700, 2100000000000000000, 1900000000000000000, 1700000000000000000, 1500000000000000000, 1300000000000000000, 1100000000000000100, 900000000000000000, 700000000000000000, 500000000000000000];
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);

        require(addresses.length > 0 && balances.length > 0, "CONSTR: addresses array length must be greater than zero");
        require(addresses.length == balances.length, "CONSTR: addresses arrays length mismatch");

        address[] memory _addresses = addresses; 
        uint256[] memory _balances = balances;

        for (uint256 i = 0; i < _addresses.length; i++) {
			_isExcluded[_addresses[i]] = true;
            _mint(_addresses[i], _balances[i] * (10**18));
        }
        require(totalSupply() == 20456743e18, "CONSTR: totalSupply must equal 20 million");
        require(swapAmount > 0, "CONSTR: Swap amount incorrect");
        swapTokensAmount = swapAmount * (10**18);
		
		protectSale = true;
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "TKN: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateFuturWall(address payable wall) external onlyOwner {
        futurUsePool = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        distributionPool = wall;
    }

	function updateStakingPool(address payable wall) external onlyOwner {
        stakingPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateLiquidityFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateFuturFee(uint256 value) external onlyOwner {
        futurFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        cashoutFee = value;
    }

    function updateRwSwapFee(uint256 value) external onlyOwner {
        rwSwap = value;
    }

	function changeMaxTxAmount(uint256 value) external onlyOwner {
		maxTxAmount = value;
	}

	function changeProtectSale(bool value) external onlyOwner {
		protectSale = value;
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

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            !_isBlacklisted[from] && !_isBlacklisted[to],
            "Blacklisted address"
        );
		
		
		
		if (from != owner() && to != owner() && from != address(this) && to != address(this) && !_isExcluded[from] && !_isExcluded[to]) {
			require(amount <= maxTxAmount, "Please transfer under the max transaction amount");
			if (protectSale && from == uniswapV2Pair) {
				_isBlacklisted[to] = true;
			}
		}
		
        super._transfer(from, to, amount);
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance).sub(initialETHBalance);
        payable(destination).transfer(newBalance);
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

	function getStakePositions(address staker) public view returns (StakePosition[] memory positions){
		return stakePositions[staker];
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

	function withdrawStakingPosition(uint256 index) public {
		address staker = msg.sender;
		StakePosition storage position = stakePositions[staker][index];
		require(position.expireTime <= block.timestamp, "You are not eligible to claim this position yet");
		require(position.balance > 0, "There is nothing to claim from this position");
		
		uint256 amount = position.balance;
		position.balance = 0;
		super._transfer(stakingPool, msg.sender, amount);
		
	}

    function createNodeWithTokens(string memory name, uint256 _type) public {
        _createNodeWithTokens(name, _type, false);
    }

    function _createNodeWithTokens(string memory name, uint256 _type, bool isFusion) private {
        require(bytes(name).length > 3 && bytes(name).length < 20, "NODE CREATION: NAME SIZE INVALID");
        if (_type == 4) {
            require(isFusion, "NODE CREATION: ONLY BE ABLE TO BE MADE BY FUSING");
        }

		address sender = msg.sender;

	    require(sender != address(0), "NODE CREATION:  creation from the zero address");
       
	    require(!_isBlacklisted[sender], "NODE CREATION: Blacklisted address");
        
		require(sender != futurUsePool && sender != distributionPool, "NODE CREATION: futur and rewardsPool cannot create node");
        
		uint256 nodePrice = nodeRewardManagement.getNodePrice(_type, isFusion);
		require(balanceOf(sender) >= nodePrice, "NODE CREATION: Balance too low for creation.");
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
                distributionPool,
                rewardsPoolTokens
            );
			
            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);

            swapAndSendToFee(distributionPool, balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice);
        if (isFusion) {
            super._transfer(address(this), deadWallet, nodePrice);
        }
        nodeRewardManagement.createNode(sender, name, 0, _type);
    }

	function createNodeWithStakePosition(string memory name, uint256 stakeDays, uint256 _type, bool isFusion) public {
        require(bytes(name).length > 3 && bytes(name).length < 32, "NODE CREATION: NAME SIZE INVALID");
        
		address sender = msg.sender;
       
	    require(sender != address(0), "NODE CREATION:  creation from the zero address");
       
	    require(!_isBlacklisted[sender], "NODE CREATION: Blacklisted address");
        
		require(sender != futurUsePool && sender != distributionPool, "NODE CREATION: futur and rewardsPool cannot create node");
        require(stakeDays >= 1 && stakeDays <= 30, "Stake time must be between 1 and 30 days");
		
		uint256 duration = stakeDays * 1 days;
		uint256 nodeFee = nodeFees[stakeDays - 1];
		
		uint256 nodePrice = nodeRewardManagement.getNodePrice(_type, isFusion);
		require(balanceOf(sender) >= nodePrice + nodeFee, "NODE CREATION: Balance too low for creation.");
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
                distributionPool,
                rewardsPoolTokens
            );
			
            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);

            swapAndSendToFee(distributionPool, balanceOf(address(this)));

            swapping = false;
        }
		
        super._transfer(sender, address(this), nodePrice + nodeFee);
		createStakePosition(nodePrice, duration);
        nodeRewardManagement.createNode(sender, name, duration, _type);
    }

    function cashoutReward(uint256 blocktime) public {
        address sender = msg.sender;
        require(sender != address(0), "CSHT:  creation from the zero address");
        require(!_isBlacklisted[sender], "MANIA CSHT: Blacklisted address");
        require(
            sender != futurUsePool && sender != distributionPool,
            "CSHT: futur and rewardsPool cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManagement._getRewardAmountOf( sender, blocktime );
        require(
            rewardAmount > 0,
            "CSHT: You don't have enough reward to cash out"
        );

		uint256 feeAmount = rewardAmount.mul(cashoutFee).div(100);
		rewardAmount = rewardAmount.sub(feeAmount);
        if (swapLiquify && cashoutFee > 0) {
			super._transfer(distributionPool, address(this), feeAmount);
			swapAndSendToFee(futurUsePool, feeAmount);
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManagement._cashoutNodeReward(sender, blocktime);
    }

    function cashoutAll() public {
        address sender = msg.sender;
        require(
            sender != address(0),
            "MANIA CSHT:  creation from the zero address"
        );
        require(!_isBlacklisted[sender], "MANIA CSHT: Blacklisted address");
        require(
            sender != futurUsePool && sender != distributionPool,
            "MANIA CSHT: futur and rewardsPool cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManagement._getRewardAmountOf(sender);
        require(
            rewardAmount > 0,
            "MANIA CSHT: You don't have enough reward to cash out"
        );
		
        uint256 feeAmount = rewardAmount.mul(cashoutFee).div(100);
		rewardAmount = rewardAmount.sub(feeAmount);

        if (swapLiquify && cashoutFee > 0) {
			super._transfer(distributionPool, address(this), feeAmount);
			swapAndSendToFee(futurUsePool, feeAmount);
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManagement._cashoutAllNodesReward(sender);
    }

    function cashoutAllInternal(address account) private {
        address sender = account;
        require(
            sender != address(0),
            "MANIA CSHT:  creation from the zero address"
        );
        require(!_isBlacklisted[sender], "MANIA CSHT: Blacklisted address");
        require(
            sender != futurUsePool && sender != distributionPool,
            "MANIA CSHT: futur and rewardsPool cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManagement._getRewardAmountOf(sender);
        require(
            rewardAmount > 0,
            "MANIA CSHT: You don't have enough reward to cash out"
        );
		
        uint256 feeAmount = rewardAmount.mul(cashoutFee).div(100);
		rewardAmount = rewardAmount.sub(feeAmount);

        if (swapLiquify && cashoutFee > 0) {
			super._transfer(distributionPool, address(this), feeAmount);
			swapAndSendToFee(futurUsePool, feeAmount);
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManagement._cashoutAllNodesReward(sender);
    }

    function changeSwapLiquify(bool newVal) public onlyOwner {
        swapLiquify = newVal;
    }

    function getNodeNumberOf(address account) public view returns (uint256) {
        return nodeRewardManagement._getNodeNumberOf(account);
    }

    function getRewardAmountOf(address account)
        public
        view
        onlyOwner
        returns (uint256)
    {
        return nodeRewardManagement._getRewardAmountOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getRewardAmountOf(msg.sender);
    }

	function changeNodeFees(uint256[] memory newNodeFees) public onlyOwner {
		require(newNodeFees.length == 30, "Must have 30 items");
		nodeFees = newNodeFees;
	}

    function changeNodePrices(uint256 newNodePriceOne, uint256 newNodePriceFive, uint256 newNodePriceTen) public onlyOwner {
        nodeRewardManagement._changeNodePrice(newNodePriceOne, newNodePriceFive, newNodePriceTen);
    }

    function getNodePrice(uint256 _type, bool isFusion) public view returns (uint256) {
        return nodeRewardManagement.getNodePrice(_type, isFusion);
    }

    function changeClaimInterval(uint256 newInterval) public onlyOwner {
        nodeRewardManagement._changeClaimInterval(newInterval);
    }

    function getClaimInterval() public view returns (uint256) {
        return nodeRewardManagement.claimInterval();
    }

    function changeRewardsPerMinute(uint256 newPriceOne, uint256 newPriceFive, uint256 newPriceTen, uint256 newPriceOMEGA) public onlyOwner {
        nodeRewardManagement._changeRewardsPerMinute(newPriceOne, newPriceFive, newPriceTen, newPriceOMEGA);
    }

    function getRewardsPerMinute() public view returns (uint256, uint256, uint256) {
        return (nodeRewardManagement.rewardsPerMinuteOne(), nodeRewardManagement.rewardsPerMinuteFive(), nodeRewardManagement.rewardsPerMinuteTen() );
    }

    function getNodesType() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesType(msg.sender);
    }

    function getNodesName() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesName(msg.sender);
    }

    function getNodesCreatime() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesCreationTime(msg.sender);
    }

	function getNodesExpireTime() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesExpireTime(msg.sender);
    }

    function getNodesRewards() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesRewardAvailable(msg.sender);
    }

    function getNodesLastClaims() public view returns (string memory) {
        require(msg.sender != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManagement._isNodeOwner(msg.sender),
            "NO NODE OWNER"
        );
        return nodeRewardManagement._getNodesLastClaimTime(msg.sender);
    }

    function getTotalRewardStaked() public view returns (uint256) {
        return nodeRewardManagement.totalRewardStaked();
    }

    function getTotalNodesCreated() public view returns (uint256) {
        return nodeRewardManagement.totalNodesCreated();
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

    function fusionNode(uint256 _method, address _account, string memory name) public {
        // cashoutAllInternal(_account);
        nodeRewardManagement.fusionNode(_method, _account);
        _createNodeWithTokens(name, _method.add(1), true);
    }
}