// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


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
    address private stakingBGT;
    address private stakingNodeBGT;
    BGT private bgtToken;

    uint256 unlockAmountNode;
    uint256 lockAmount;
    bool isLockPool = false;

    constructor (address _stakingBGT, address _stakingNodeBGT) {
        stakingBGT = _stakingBGT;
        stakingNodeBGT = _stakingNodeBGT;
    }

    function set(address _bgtToken) external onlyOwner
    {
        bgtToken = BGT(_bgtToken);
    }

    function setUnlockAmountNode(uint256 _unlockAmountNode) external onlyOwner {
        unlockAmountNode = _unlockAmountNode;
    }

    function updateApprove() internal {
        uint256 unlockAmount = this.balanceBGT() - lockAmount;
        require(unlockAmountNode < unlockAmount, "nodeAllowance error");
        uint256 unlockAmountXPos = unlockAmount - unlockAmountNode;
        bgtToken.approve(stakingBGT, unlockAmountXPos);
        bgtToken.approve(stakingNodeBGT, unlockAmountNode);
    }

    function setLockAmount(uint256 _value) external onlyOwner {
        uint256 balance = this.balanceBGT();
        lockAmount = _value * (10 ** bgtToken.decimals());
        require(lockAmount <= balance, "");
        updateApprove();
    }

    function balanceBGT() external view returns (uint256) {
        return bgtToken.balanceOf(address(this));
    }

    function allowanceBGT() external view returns (uint256 xpos, uint256 node) {
        return (bgtToken.allowance(address(this), stakingBGT), bgtToken.allowance(address(this), stakingNodeBGT));
    }
    
    function lockPool() external onlyOwner {
        isLockPool = true;
    }

    function getLockPool() external view returns (bool) {
        return isLockPool;
    }

    function withdraw(address _tokenAddress, uint256 _amount) external onlyOwner {
        require(isLockPool == false, "The pool is locked");
        BGT(_tokenAddress).transfer(msg.sender, _amount);
    }
}