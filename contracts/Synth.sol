/*
-----------------------------------------------------------------
MODULE DESCRIPTION
-----------------------------------------------------------------

Synthetix-backed stablecoin contract.

This contract issues synths, which are tokens that mirror various
flavours of fiat currency.

Synths are issuable by Synthetix Network Token (OKS) holders who
have to lock up some value of their OKS to issue S * Cmax synths.
Where Cmax issome value less than 1.

A configurable fee is charged on synth exchanges and deposited
into the fee pool, which Synthetix holders may withdraw from once
per fee period.

-----------------------------------------------------------------
*/

pragma solidity 0.4.25;

import "./ExternStateToken.sol";
import "./interfaces/IFeePool.sol";
import "./interfaces/ISynthetix.sol";
import "./Proxy.sol";

contract Synth is ExternStateToken {

    /* ========== STATE VARIABLES ========== */

    // Address of the FeePoolProxy
    address public feePoolProxy;
    // Address of the SynthetixProxy
    address public synthetixProxy;

    // Currency key which identifies this Synth to the Synthetix system
    bytes32 public currencyKey;

    uint8 constant DECIMALS = 18;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _proxy, TokenState _tokenState, address _synthetixProxy, address _feePoolProxy,
        string _tokenName, string _tokenSymbol, address _owner, bytes32 _currencyKey, uint _totalSupply
    )
        ExternStateToken(_proxy, _tokenState, _tokenName, _tokenSymbol, _totalSupply, DECIMALS, _owner)
        public
    {
        require(_proxy != address(0), "_proxy cannot be 0");
        require(_synthetixProxy != address(0), "_synthetixProxy cannot be 0");
        require(_feePoolProxy != address(0), "_feePoolProxy cannot be 0");
        require(_owner != 0, "_owner cannot be 0");
        require(ISynthetix(_synthetixProxy).synths(_currencyKey) == Synth(0), "Currency key is already in use");

        feePoolProxy = _feePoolProxy;
        synthetixProxy = _synthetixProxy;
        currencyKey = _currencyKey;
    }

    /* ========== SETTERS ========== */

    /**
     * @notice Set the SynthetixProxy should it ever change.
     * The Synth requires Synthetix address as it has the authority
     * to mint and burn synths
     * */
    function setSynthetixProxy(ISynthetix _synthetixProxy)
        external
        optionalProxy_onlyOwner
    {
        synthetixProxy = _synthetixProxy;
        emitSynthetixUpdated(_synthetixProxy);
    }

    /**
     * @notice Set the FeePoolProxy should it ever change.
     * The Synth requires FeePool address as it has the authority
     * to mint and burn for FeePool.claimFees()
     * */
    function setFeePoolProxy(address _feePoolProxy)
        external
        optionalProxy_onlyOwner
    {
        feePoolProxy = _feePoolProxy;
        emitFeePoolUpdated(_feePoolProxy);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice ERC20 transfer function
     * forward call on to _internalTransfer */
    function transfer(address to, uint value)
        public
        optionalProxy
        returns (bool)
    {
        return super._internalTransfer(messageSender, to, value);
    }

    /**
     * @notice ERC20 transferFrom function
     */
    function transferFrom(address from, address to, uint value)
        public
        optionalProxy
        returns (bool)
    {
        // Skip allowance update in case of infinite allowance
        if (tokenState.allowance(from, messageSender) != uint(-1)) {
            // Reduce the allowance by the amount we're transferring.
            // The safeSub call will handle an insufficient allowance.
            tokenState.setAllowance(from, messageSender, tokenState.allowance(from, messageSender).sub(value));
        }

        return super._internalTransfer(from, to, value);
    }

    // Allow synthetix to issue a certain number of synths from an account.
    function issue(address account, uint amount)
        external
        onlySynthetixOrFeePool
    {
        tokenState.setBalanceOf(account, tokenState.balanceOf(account).add(amount));
        totalSupply = totalSupply.add(amount);
        emitTransfer(address(0), account, amount);
        emitIssued(account, amount);
    }

    // Allow synthetix or another synth contract to burn a certain number of synths from an account.
    function burn(address account, uint amount)
        external
        onlySynthetixOrFeePool
    {
        tokenState.setBalanceOf(account, tokenState.balanceOf(account).sub(amount));
        totalSupply = totalSupply.sub(amount);
        emitTransfer(account, address(0), amount);
        emitBurned(account, amount);
    }

    // Allow owner to set the total supply on import.
    function setTotalSupply(uint amount)
        external
        optionalProxy_onlyOwner
    {
        totalSupply = amount;
    }

    /* ========== MODIFIERS ========== */

    modifier onlySynthetixOrFeePool() {
        bool isSynthetix = msg.sender == address(Proxy(synthetixProxy).target());
        bool isFeePool = msg.sender == address(Proxy(feePoolProxy).target());

        require(isSynthetix || isFeePool, "Only Synthetix, FeePool allowed");
        _;
    }

    /* ========== EVENTS ========== */

    event SynthetixUpdated(address newSynthetix);
    bytes32 constant SYNTHETIXUPDATED_SIG = keccak256("SynthetixUpdated(address)");
    function emitSynthetixUpdated(address newSynthetix) internal {
        proxy._emit(abi.encode(newSynthetix), 1, SYNTHETIXUPDATED_SIG, 0, 0, 0);
    }

    event FeePoolUpdated(address newFeePool);
    bytes32 constant FEEPOOLUPDATED_SIG = keccak256("FeePoolUpdated(address)");
    function emitFeePoolUpdated(address newFeePool) internal {
        proxy._emit(abi.encode(newFeePool), 1, FEEPOOLUPDATED_SIG, 0, 0, 0);
    }

    event Issued(address indexed account, uint value);
    bytes32 constant ISSUED_SIG = keccak256("Issued(address,uint256)");
    function emitIssued(address account, uint value) internal {
        proxy._emit(abi.encode(value), 2, ISSUED_SIG, bytes32(account), 0, 0);
    }

    event Burned(address indexed account, uint value);
    bytes32 constant BURNED_SIG = keccak256("Burned(address,uint256)");
    function emitBurned(address account, uint value) internal {
        proxy._emit(abi.encode(value), 2, BURNED_SIG, bytes32(account), 0, 0);
    }
}
