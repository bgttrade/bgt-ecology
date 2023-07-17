// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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

contract StakingPool is Ownable {

    function balance(BGT bgtToken) external view returns (uint256) {
        return bgtToken.balanceOf(address(this));
    }

    function withdraw(BGT bgtToken, address to, uint256 amount) external onlyOwner {
        bgtToken.transfer(to, amount);
    }
}

contract StakingNodeBGT is Ownable, Initializable {
    
    BGT private bgtToken;
    address private bgtPool;
    address private exchequerPool;
    uint256 private totalQuantity;
    uint256 private quantity;
    mapping(address => address) private stakingPools;
    mapping(address => uint256) private pledges;
    mapping(address => uint256) private balances;
    mapping(address => bool) private _minters;
    string updateDate;
    uint256 totalInterest;
    uint256 totalClaim;

    event NodeApplication(address indexed applicant, uint256 amount, uint256 pledges);
    event ApplicationCanceled(address indexed applicant, uint amount);
    event InterestClaimed(address indexed account, uint interest);

    function initialize() public initializer {
        _transferOwnership(_msgSender());
    }

    function init(address _bgtTokenAddress, address _bgtPool) external onlyOwner {
        require(quantity == 0 && exchequerPool == address(0), "");
        bgtToken = BGT(_bgtTokenAddress);
        quantity = 100 * (10 ** bgtToken.decimals());
        bgtPool = _bgtPool;
        exchequerPool = 0x2A0eecF2B7E961E03676536D9a59dBdAE3a014b7;
    }

    function setBgtPool(address _bgtPool) external onlyOwner {
        bgtPool = _bgtPool;
    }

    function setQuantity(uint256 quantity_) external onlyOwner
    {
        quantity = quantity_ * (10 ** bgtToken.decimals());
    }

    function setMinter(address account, bool isMinter_) external onlyOwner {
        _minters[account] = isMinter_;
        if (isMinter_ == false)
        {
            delete _minters[account];
        }
    }

    function isMinter(address account) public view returns(bool) {
        return _minters[account];
    }

    modifier onlyMinter(){
        require(_minters[_msgSender()] == true, "Ownable: caller is not the minter");
        _;
    }

    function createPool(address account) internal {
        if (account != address(0) && stakingPools[account] == address(0))
        {
            StakingPool pool = new StakingPool();
            stakingPools[account] = address(pool);
        }
    }

    function getPledges(address account) external view returns (uint256) {
        return pledges[account];
    }

    function isApplied(address account) external view returns (bool) {
        return bool(pledges[account] >= quantity);
    }

    function applyForNode() external {
        address account = msg.sender;
        require(quantity > pledges[account], "You've applied for a node");
        uint256 amount = quantity - pledges[account];
        require(bgtToken.allowance(account, address(this)) >= amount, "Insufficient allowance");

        // Update the balance and the dpos
        pledges[account] += amount;
        totalQuantity += amount;
        // Transfer BGT tokens from user to the contract
        createPool(account);
        bgtToken.transferFrom(account, stakingPools[account], amount);
    
        emit NodeApplication(account, amount, pledges[msg.sender]);
    }

    function cancelApplication() external {
        address account = msg.sender;
        require(pledges[account] > 0, "You have not applied for a node");

        uint amount = pledges[account];

        // Transfer the pledged USDT back to the user
        StakingPool(stakingPools[account]).withdraw(bgtToken, account, amount);

        // Update the node application status and canceled application status
        pledges[account] = 0;
        totalQuantity -= amount;

        emit ApplicationCanceled(account, amount);
    }

    function writeInterest(string memory _date, address[] memory _senders, uint256[] memory _amounts) external onlyMinter
    {
        require(keccak256(bytes(updateDate)) != keccak256(bytes(_date)), "");
        require(_senders.length == _amounts.length, "");

        for (uint i=0; i<_senders.length; i++)
        {
            balances[_senders[i]] += _amounts[i];
            totalInterest += _amounts[i];
        }
    }


    function getInterest(address account) public view returns (uint256) {
        return balances[account];
    }

    function claimInterest() external {

        require(balances[msg.sender] > 0, "No interest available");

        uint256 interest = balances[msg.sender];
        balances[msg.sender] = 0;
        // Transfer the interest to the user
        bgtToken.transferFrom(bgtPool, address(this), interest);
        totalClaim += interest;

        uint256 userInterest = interest * 95 / 100;
        uint256 revenue = interest - userInterest;
        bgtToken.transfer(msg.sender, userInterest);
        bgtToken.transfer(exchequerPool, revenue);

        emit InterestClaimed(msg.sender, interest);
    }

    function getInfo() external view returns (uint256 totalQuantity_, uint256 totalInterest_, uint256 totalClaim_)
    {
        return (totalQuantity, totalInterest, totalClaim);
    }
}