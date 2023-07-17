// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

struct NetWork {
    uint256 id;
    uint level;
    uint time;
    address sender_;
    address super_;
}

interface BGT  {

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
 
    function burn(uint256 amount) external;
}

interface DEX {

    function getPrice(address _tokenContract) external view returns (uint256);
}

struct AnnualInterestRateConfig {
    uint index;
    uint256 rQuantity;
    uint256 annualInterestRate;
}

struct DPosMove {
    address root;
    uint256 dpos;
}

struct AccountInfo {
    address account;
    uint256 dpos;
    uint time;
}

library Math {

    function MAX(uint256 x, uint256 y) internal pure returns (uint256)
    {
        return (x >= y ? x : y);
    }

    function MIN(uint256 x, uint256 y) internal pure returns (uint256)
    {
        return (x <= y ? x : y);
    }
}

contract StakingPool is Ownable {

    function balance(BGT bgtToken) external view returns (uint256) {
        return bgtToken.balanceOf(address(this));
    }

    function withdraw(BGT bgtToken, address to, uint256 amount) external onlyOwner {
        bgtToken.transfer(to, amount);
    }
}

contract StakingBGT is Ownable, Initializable {
    address private exchequerPool;
    address private bgtPool;
    address private bgtTokenAddress;
    BGT private bgtToken;
    DEX private dex;
    uint256 private totalPos;
    mapping(address => uint256) private poss;
    mapping(address => uint256) private interests;
    mapping(address => uint256) private lastUpdateTime;
    mapping(uint => AnnualInterestRateConfig) private annualInterestRateConfig;
    uint[] private poolLevelUpdateTimes;
    uint256 private nextRQuantity;
    uint256 private annualEarnings;
    mapping(address => address) private stakingPools;

    event Deposit(address indexed account, uint256 amount, uint256 pos);
    event Withdrawal(address indexed account, uint256 amount, uint256 pos);
    event InterestClaimed(address indexed account, uint interest);

    function initialize() public initializer() {
        _transferOwnership(_msgSender());
    }

    function setPool(address _bgtPool, address _exchequerPool) external onlyOwner
    {
        exchequerPool = _exchequerPool;
        bgtPool = _bgtPool;
    }

    function init(address _bgtTokenAddress) external onlyOwner {
        require(bgtTokenAddress == address(0), "");
        bgtTokenAddress = _bgtTokenAddress;
        bgtToken = BGT(bgtTokenAddress);
    }


    function setDex(address _dex) external onlyOwner {
        dex = DEX(_dex);
    }

    function setBgtPool(address _bgtPool) external onlyOwner {
        bgtPool = _bgtPool;
    }

    function getBgtAddress() external view returns (address)
    {
        return bgtTokenAddress;
    }

    function getDPosDquity() internal view returns (uint256) {
        uint256 price = dex.getPrice(bgtTokenAddress);
        uint256 dquity;
        uint dec = BGT(bgtTokenAddress).decimals();
        if (price >= 1e18)
        {
            uint i = 0;
            while (true)
            {
                if (price < 1e18 * (15 ** (i+1))/(10 ** (i+1)))
                    break;
                i++;
            }
            dquity = 5000 * (10 ** dec) * (10 ** i) / (15 ** i);
        }
        else 
        {
            uint i = 0;
            while (true)
            {
                if (price > 1e18 * (10 ** (i+1))/(15 ** (i+1)))
                    break;
                i++;
            }
            dquity = 5000 * (10 ** dec) * (15 ** (i+1)) / (10 ** (i+1));
        }
        return dquity;
    }

    function setAnnualEarnings(uint256 _annualEarnings) public onlyOwner {

        annualEarnings = _annualEarnings * 10 ** bgtToken.decimals();

        if (poolLevelUpdateTimes.length == 0)
        {
            poolLevelUpdateTimes.push(0);
        }
        else 
        {
            poolLevelUpdateTimes.push(block.timestamp);
        }
        nextRQuantity = _setConfig(poolLevelUpdateTimes.length - 1, 0);
    }

    function createPool(address account) internal {
        if (account != address(0) && stakingPools[account] == address(0))
        {
            StakingPool pool = new StakingPool();
            stakingPools[account] = address(pool);
            if (poss[account] > 0) 
                bgtToken.transfer(stakingPools[account], poss[account]);
        }
    }

    function addPoss(address account, uint256 amount) internal {
        poss[account] += amount;
        totalPos += amount;
        bgtToken.transferFrom(account, stakingPools[account], amount);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        address account = msg.sender;
        require(bgtToken.allowance(account, address(this)) >= amount, "Insufficient allowance");
        settlementInterest(account);
        
        createPool(account);
        addPoss(account, amount);
        
        upgrades();

        emit Deposit(msg.sender, amount, poss[account]);
    }

    function decPoss(address account, uint256 amount) internal {
        poss[account] -= amount;
        totalPos -= amount;
        StakingPool(stakingPools[account]).withdraw(bgtToken, account, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount <= poss[msg.sender], "Insufficient balance");
        require(amount > 0, "Amount must be greater than zero");
        address account = msg.sender;
        settlementInterest(account);

        createPool(account);
        decPoss(account, amount);
        
        emit Withdrawal(account, amount, poss[msg.sender]);
    }

    function claimInterest() external {
        address account = msg.sender;
        settlementInterest(account);

        createPool(account);

        uint256 interest = interests[account];
        require(interest > 0, "No interest available");

        interests[account] = 0;
        // Transfer the interest to the user
        uint256 userInterest = interest * 95 / 100;
        uint256 revenue = interest - userInterest;
        bgtToken.transfer(account, userInterest );
        bgtToken.transfer(exchequerPool, revenue);

        emit InterestClaimed(account, interest);
    }

    function upgrades() internal {
        
        if (totalPos >= nextRQuantity)
        {
            poolLevelUpdateTimes.push(block.timestamp);
            nextRQuantity = _setConfig(poolLevelUpdateTimes.length - 1, nextRQuantity);
        }
    }

    function doSettlementInterest() external {
        address account = msg.sender;
        require(poss[account] > 0, "There are no tasks to do");

        uint256 total = poss[account];

        uint currentTime = block.timestamp;
        uint lastUpdate = lastUpdateTime[account];

        uint userIndex = getIndex(account);
        
        uint length = poolLevelUpdateTimes.length > 30 ? 30 : poolLevelUpdateTimes.length;
        uint interest = 0;
        for (uint i=userIndex; i<length; i++)
        {
            uint endTime = (i == poolLevelUpdateTimes.length - 1) ? currentTime : poolLevelUpdateTimes[i+1];
            uint elapsedTime = endTime - Math.MAX(lastUpdate, poolLevelUpdateTimes[i]);
            interest += annualInterestRateConfig[i].annualInterestRate * elapsedTime * total / (365 days) / 100;
        }

        if (interest > 0)
        {
            // Update the last update time
            interests[account] += interest;
            bgtToken.transferFrom(bgtPool, address(this), interest);
        }
        lastUpdateTime[account] = block.timestamp;
    }

    function getInterest(address account) public view returns (uint256) {
        uint256 interest = calculateInterest(account);
        interest += interests[account];
        return interest;
    }

    function settlementInterest(address account) internal {
        uint256 interest = calculateInterest(account);
        if (interest > 0)
        {
            // Update the last update time
            interests[account] += interest;
            bgtToken.transferFrom(bgtPool, address(this), interest);
        }
        lastUpdateTime[account] = block.timestamp;
    }

    function calculateInterest(address account) internal view returns (uint256) {
        if (poss[account] == 0)
            return 0;

        uint256 total = poss[account];

        uint userIndex = getIndex(account);
        
        uint interest = 0;
        for (uint i=userIndex; i<poolLevelUpdateTimes.length; i++)
        {
            uint endTime = (i == poolLevelUpdateTimes.length - 1) ? block.timestamp : poolLevelUpdateTimes[i+1];
            uint elapsedTime = endTime - Math.MAX(lastUpdateTime[account], poolLevelUpdateTimes[i]);
            interest += annualInterestRateConfig[i].annualInterestRate * elapsedTime * total / (365 days) / 100;
        }
        return interest;
    }

    function getIndex(address account) public view returns (uint) {
        uint index = poolLevelUpdateTimes.length - 1;
        uint i = poolLevelUpdateTimes.length;
        while (true)
        {
            i--;
            if (lastUpdateTime[account] >= poolLevelUpdateTimes[i] || i == 0)
            {
                index = i;
                break; 
            }
        }
        return index;
    }

    function getPoolLevelUpdateTimesLength() public view returns (uint)
    {
        return poolLevelUpdateTimes.length;
    }

    function getPoolLevelUpdateTimesAtIndex(uint index) public view returns (uint256)
    {
        return poolLevelUpdateTimes[index];
    }

    function getAnnualInterestRateConfigAtIndex(uint index) public view returns (AnnualInterestRateConfig memory)
    {
        return annualInterestRateConfig[index];
    }

    function getNextRQuantity() public view returns (uint256)
    {
        return nextRQuantity;
    }

    function _setConfig(uint256 _index, uint256 _rQuantity) internal returns (uint256) {
        uint256 _nextRQuantity = _rQuantity == 0 ? 18000000 * 10 ** bgtToken.decimals() : (_rQuantity * (5263157 + 100000000) / 100000000);
        uint256 _annualInterestRate = 100 * annualEarnings * 7 / 30 / _nextRQuantity;
        annualInterestRateConfig[_index] = AnnualInterestRateConfig(_index, _rQuantity, _annualInterestRate);
        return _nextRQuantity;
    }

    function getStakingPool(address account) external view returns (address)
    {
        return stakingPools[account];
    }

    function getVersion() public pure returns (string memory)
    {
        return "v1.2";
    }
}