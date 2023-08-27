// SPDX-License-Identifier: UNLICENSED
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/ERC20.sol)

pragma solidity 0.8.14;

import "../@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../@openzeppelin/contracts/access/Ownable.sol";


contract EstateX is ERC20, Ownable {

    struct Tax {  
        address accounts;
        uint256 fee;
    }

    uint256 public taxFee = 1;

    mapping(uint256 => Tax) public _tax;

    event FeeUpdated(uint256 txFee, Tax[]);

    constructor(address creator, address _capitalFundAddress, address _passiveIncomeAddress, address _operationsAndDevelopmentAddress, address _communityAddress) ERC20("EstateX", "ESX") {
        _mint(creator, 12600000000 * 10 ** decimals());

        _tax[1] = Tax(_capitalFundAddress, 50);
        _tax[2] = Tax(_passiveIncomeAddress, 30);
        _tax[3] = Tax(_operationsAndDevelopmentAddress, 10);
        _tax[4] = Tax(_communityAddress, 10);

    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function burn(uint256 amount) external onlyOwner returns(bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        uint256 txFee = 0;

        bool fees = true;
        if(from == owner() || to == owner()) {
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
    }

    function getTaxFee(uint256 amount, uint256 _fee) internal pure returns(uint256) {
        return amount * _fee / 100;
    }

    function setFee(uint256 _taxFee, Tax[] memory taxFeeSplit) external onlyOwner returns(bool) {
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

}