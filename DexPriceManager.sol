// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DexPriceManager is Ownable {

    mapping(address => bool) private _admins;
    mapping(address => uint256) private prices;

    function setAdmin(address account, bool isAdmin_) external onlyOwner {
        _admins[account] = isAdmin_;
        if (isAdmin_ == false)
        {
            delete _admins[account];
        }
    }

    function isAdmin(address account) public view returns(bool) {
        return _admins[account];
    }

    modifier onlyAdmin() {
        require(_admins[_msgSender()] == true, "Ownable: caller is not the admin");
        _;
    }

    function setPrice(address _tokenContract, uint256 _price) onlyAdmin external 
    {
        prices[_tokenContract] = _price;
    }

    function getPrice(address _tokenContract) external view returns (uint256)
    {
        return prices[_tokenContract];
    }
}