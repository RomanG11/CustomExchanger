pragma solidity ^0.4.21;

//standart library for uint
library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0 || b == 0){
        return 0;
    }
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

  function pow(uint256 a, uint256 b) internal pure returns (uint256){ //power function
    if (b == 0){
      return 1;
    }
    uint256 c = a**b;
    assert (c >= a);
    return c;
  }
}

contract AccountLevels {
  //given a user, returns an account level
  //0 = regular user (pays take fee and make fee)
  //1 = market maker silver (pays take fee, no make fee, gets rebate)
  //2 = market maker gold (pays take fee, no make fee, gets entire counterparty's take fee as rebate)
  function accountLevel(address user) public constant returns(uint);
}


/**
 * The ERC223Comparible abstract contract
 */
contract ERC223Comparible {

  function totalSupply() public constant returns (uint256 supply);
  function balanceOf(address _owner) public constant returns (uint256 balance);
  function transfer(address _to, uint256 _value) public returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

  function approve(address _spender, uint256 _value) public returns (bool success);
  function allowance(address _owner, address _spender) public constant returns (uint256 remaining);

  function tokenFallback(address _from, uint _value, bytes _data) public;
}


//EtherDelta abstract contract
contract EtherDelta { 
  mapping (address => mapping (address => uint)) public tokens; 
  mapping (address => mapping (bytes32 => bool)) public orders;
  mapping (address => mapping (bytes32 => uint)) public orderFills;

  uint public feeMake; //percentage times (1 ether)
  uint public feeTake; //percentage times (1 ether)
  uint public feeRebate; //percentage times (1 ether)
  
  address public admin; //the admin address
  address public accountLevelsAddr; //the address of the AccountLevels contract

  function deposit() public payable;
  function withdraw(uint) public;
  function depositToken(address,uint) public;
  function withdrawToken(address,uint) public;
  function balanceOf(address,address) public constant returns (uint);
  function trade(address,uint,address,uint,uint,uint,address,uint8,bytes32,bytes32,uint) public;
  function testTrade(address,uint,address,uint,uint,uint,address,uint8,bytes32,bytes32,uint,address) public constant returns(bool);
  function availableVolume(address,uint,address,uint,uint,uint,address,uint8,bytes32,bytes32) public constant returns(uint);
  function amountFilled(address,uint,address,uint,uint,uint,address,uint8,bytes32,bytes32) public constant returns(uint);
  function cancelOrder(address,uint,address,uint,uint,uint,uint8,bytes32,bytes32) public;
}

//standart contract to identify owner
contract Ownable {

  address public owner;

  address public newOwner;

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  function Ownable() public {
    owner = msg.sender;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    require(_newOwner != address(0));
    newOwner = _newOwner;
  }

  function acceptOwnership() public {
    if (msg.sender == newOwner) {
      owner = newOwner;
    }
  }
}

/**
 * The EtherDeltaCustomConnector contract makes all functionality
 */
contract EtherDeltaCustomConnector is Ownable {
    
  using SafeMath for uint256;

  //initializing etherDelta contract to connect with him
  EtherDelta public etherDelta;

  //initializing standard Token contract
  ERC223Comparible Token;

  //Constructor
  function EtherDeltaCustomConnector (address _etherDeltaAddress) public {
    owner = msg.sender;
    etherDelta = EtherDelta(_etherDeltaAddress);
    // accountLevel = AccountLevels(EtherDelta.accountLevelsAddr());
  }

  //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping (address => uint)) public tokenBalances;
  mapping (address => mapping (address => uint)) public etherDeltaTokenBalances;

  //someone can add some balance in this contract
  function () public payable {
    require(msg.value > 0);
    tokenBalances[0][msg.sender] += msg.value;
  }

  //Start token functions

  //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
  function depositTokensToThis (address _token, uint _value) public{
    require(_token != address(0));

    Token = ERC223Comparible(_token);
    require(Token.allowance(msg.sender,address(this)) >= _value);

    Token.transferFrom(msg.sender,address(this),_value);

    tokenBalances[_token][msg.sender] += _value;
  }

  // withdraw tokens from this contract
  function withdrawTokensFromThis (address _token, uint _value) public {
    require(_token != address(0));

    Token = ERC223Comparible(_token);
    require(tokenBalances[_token][msg.sender] >= _value);

    Token.transfer(msg.sender,_value);

    tokenBalances[_token][msg.sender] -= _value;
  }

  // withdraw ETH from this contract
  function withdrawEth (uint _value) public{
    require (tokenBalances[0][msg.sender] >= _value);

    msg.sender.transfer(_value);

    tokenBalances[0][msg.sender] -= _value;
  }
  //End token functions

  //Start EtherDelta Connection

  //etherDelta get functions
  function getThisAddressTokens (address _token) public view returns(uint) {
     //mapping of token addresses to mapping of account balances (token=0 means Ether)
    return etherDelta.tokens(_token,address(this));
  }

  function isOrderActive (address _user, bytes32 _order) public view returns(bool) {
    //mapping of user accounts to mapping of order hashes to booleans (true = submitted by user, equivalent to offchain signature)
    return etherDelta.orders(_user,_order);
  }

  function getOrderAmount (address _user, bytes32 _order) public view returns(uint) {
    //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)
    return etherDelta.orderFills(_user,_order);
  }

  //function to test is the trade can be done
  function testTrade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount, address sender) public constant returns(bool) {
    return etherDelta.testTrade(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s, amount, sender);
  }

  function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) public constant returns(uint) {
    return etherDelta.availableVolume(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s);
  }

  function amountFilled(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) public constant returns(uint) {
    return etherDelta.amountFilled(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s);
  }

  function balanceOf(address token, address user) public constant returns (uint) {
    return etherDelta.balanceOf(token,user);
  }
  // end EtherDelta get functions

  //deposit ether from this contract to etherDelta
  function deposit(uint amount) public {
    tokenBalances[0][msg.sender] = tokenBalances[0][msg.sender].sub(amount);
    etherDeltaTokenBalances[0][msg.sender] = etherDeltaTokenBalances[0][msg.sender].add(amount);

    etherDelta.deposit.value(amount);
  }

  //withdraw ether from etherDelta
  function withdraw (uint amount) public {
    tokenBalances[0][msg.sender] = tokenBalances[0][msg.sender].add(amount);
    etherDeltaTokenBalances[0][msg.sender] = etherDeltaTokenBalances[0][msg.sender].sub(amount);

    etherDelta.withdraw(amount);
  }

  //deposit tokens from this contract to etherDelta
  function depositToken (address token, uint amount) public {
    Token = ERC223Comparible(token);
    Token.approve(etherDelta,amount);
    
    tokenBalances[token][msg.sender] = tokenBalances[token][msg.sender].sub(amount);
    etherDeltaTokenBalances[token][msg.sender] = etherDeltaTokenBalances[token][msg.sender].add(amount);

    etherDelta.depositToken(token, amount);
  }

  //withdraw tokens from etherDelta
  function withdrawToken (address token, uint amount) public {
    etherDelta.withdrawToken(token, amount);
    
    tokenBalances[token][msg.sender] = tokenBalances[token][msg.sender].add(amount);
    etherDeltaTokenBalances[token][msg.sender] = etherDeltaTokenBalances[token][msg.sender].sub(amount);
  }

  function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount) public {
    //amount is in amountGet terms
    // require (testTrade(tokenGet, amountGet, tokenGive,amountGive, expires, nonce, user, v, r, s, amount, address(this)));
    require(etherDeltaTokenBalances[tokenGet][msg.sender] >= amountGive);




    etherDelta.trade(tokenGet, amountGet, tokenGive,amountGive, expires, nonce, user, v, r, s, amount);
    

    uint feeTakeXfer = amount.mul(etherDelta.feeTake()) / (1 ether); //0

  
    etherDeltaTokenBalances[tokenGet][msg.sender] = etherDeltaTokenBalances[tokenGet][msg.sender].sub(amount.add(feeTakeXfer));
    etherDeltaTokenBalances[tokenGive][msg.sender] = etherDeltaTokenBalances[tokenGive][msg.sender].add(amountGive.mul(amount) / amountGet);
  }
  //End EtherDelta Connections
}