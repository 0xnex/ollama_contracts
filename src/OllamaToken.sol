// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract OllamaToken is Ownable, ERC20Capped, Pausable {
    mapping(address => bool) public blacklist;

    event UpdateBlackList(address indexed, bool ifInBlacklist);

    constructor() ERC20Capped(100_000_000e18) ERC20("Ollma", "OLMA") Pausable() Ownable(msg.sender) {}

    error invalid_paramter_len();

    error in_blacklist();

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateBlacklist(address[] calldata holders, bool[] calldata data) external onlyOwner {
        uint256 len = holders.length;

        if (data.length != len) {
            revert invalid_paramter_len();
        }

        for (uint256 i; i < len; i++) {
            blacklist[holders[i]] = data[i];
            emit UpdateBlackList(holders[i], data[i]);
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        if (blacklist[from] || blacklist[to]) {
            revert in_blacklist();
        }

        super._update(from, to, value);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
