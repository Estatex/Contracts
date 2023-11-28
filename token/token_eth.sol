// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";


contract EstateX is ERC20Burnable, AccessControlEnumerable {

    struct Tax {  
        address accounts;
        uint256 fee;
    }

    uint256 public taxFee = 1;

    mapping(uint256 => Tax) public _tax;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant maxSupply = 12600000000 * 10 ** 9;

    event FeeUpdated(uint256 txFee, Tax[]);

    constructor(address _capitalFundAddress, address _passiveIncomeAddress, address _operationsAndDevelopmentAddress, address _communityAddress) ERC20("EstateX", "ESX") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _tax[1] = Tax(_capitalFundAddress, 50);
        _tax[2] = Tax(_passiveIncomeAddress, 30);
        _tax[3] = Tax(_operationsAndDevelopmentAddress, 10);
        _tax[4] = Tax(_communityAddress, 10);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 txFee = 0;
        address from =_msgSender();
        bool fees = true;
        if (hasRole(DEFAULT_ADMIN_ROLE, from) || hasRole(DEFAULT_ADMIN_ROLE, to)) {
            fees = false;
        }
        txFee = fees ? amount * taxFee / 100 : txFee;
    
        require(amount >= txFee, "SafeMath: Subtraction overFlow");
        uint256 rAmount;
        unchecked {
            rAmount = amount - txFee;
        }
        super._transfer(from, to, rAmount);
        if(txFee != 0) {
            for(uint256 i = 1; i <= 4; i++) {
                super._transfer(from, _tax[i].accounts, getTaxFee(txFee, _tax[i].fee));
            }
        }
        return true;
    }

    function getTaxFee(uint256 amount, uint256 _fee) internal pure returns(uint256) {
        return amount * _fee / 100;
    }

    function setFee(uint256 _taxFee, Tax[] memory taxFeeSplit) external  returns(bool) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Must have admin role to set fee");
        taxFee = _taxFee;
        uint256 totalFee;
        require(taxFeeSplit.length == 4, "fee length mismatch");
        _tax[1] = taxFeeSplit[0];
        _tax[2] = taxFeeSplit[1];
        _tax[3] = taxFeeSplit[2];
        _tax[4] = taxFeeSplit[3];
        totalFee = taxFeeSplit[0].fee + taxFeeSplit[1].fee + taxFeeSplit[2].fee + taxFeeSplit[3].fee;
        require(totalFee == 100, "fee percentage should be equal to hundred");
        emit FeeUpdated(taxFee, taxFeeSplit);
        return true;
    }

    function mint(address to, uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role to mint");
        require(totalSupply()+amount <=maxSupply, "Cannot mint more than maxsupply");
        
        _mint(to, amount);
    }

}