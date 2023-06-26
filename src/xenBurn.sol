// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


//  testing ---------------------------------------------------------------------------------------------------------------
import "forge-std/console.sol";

interface INewFomo3DGame {
    function players(address player) external view returns (uint, uint, string[] memory, string memory, uint);
}

interface IPriceOracle {
    function calculateAveragePrice() external view returns (uint256);
}

interface IBurnRedeemable {
    function onTokenBurned(address user, uint256 amount) external;
}

interface IBurnableToken {
    function burn(address user, uint256 amount) external;
}

contract xenBurn is IBurnRedeemable {
    
    address public xenCrypto;
    mapping(address => bool) private burnSuccessful;
    mapping(address => uint256) private lastCall;
    mapping(address => uint256) private callCount;
    uint public totalCount;
    address private uniswapPool = 0xC0d776E2223c9a2ad13433DAb7eC08cB9C5E76ae;
    IPriceOracle private priceOracle; 
    INewFomo3DGame private gameContract;
    bool private gameContractSet = false; 

    constructor(address _priceOracle, address _xenCrypto) {
        priceOracle = IPriceOracle(_priceOracle);
        xenCrypto = _xenCrypto;
    }

    event TokenBurned(address indexed user, uint256 amount, string playerName);


    // Modifier to allow only human users to perform certain actions
    modifier isHuman() {
       // require(msg.sender == tx.origin, "Only human users can perform this action");
        _;
    }

    // Modifier to enforce restrictions on the frequency of calls
    modifier gatekeeping() {
        require(
            lastCall[msg.sender] + 1 days <= block.timestamp ||
            callCount[msg.sender] <= (totalCount + 5),
            "Function can only be called once per 24 hours, or 5 times within the 24-hour period by different users"
        );
        _;
    }

    // Function to burn tokens by swapping ETH for the token
    function burnXenCrypto() public isHuman gatekeeping {

        console.log("regesterNFT function msg,sender", msg.sender, "tx.origin", tx.origin);

        require(address(this).balance > 0, "No ETH available");

        // Pull player's name from game contract
        (, , string[] memory names,,) = gameContract.players(msg.sender);
        require(names.length > 0, "Player must have registered name");
        

        // Amount to use for swap (98% of the contract's ETH balance)
        uint256 amountETH = address(this).balance * 98 / 100;

        // Get current token price from PriceOracle
        uint256 tokenPrice = priceOracle.calculateAveragePrice();

        // Get the current Uniswap V2 price for the swap
        uint256 currentPrice = IUniswapV2Router02(uniswapPool).getAmountsOut(amountETH, getPathForETHtoTOKEN())[1];

        // Validate the price returned from the PriceOracle
        require(
            tokenPrice >= currentPrice * 90 / 100 && tokenPrice <= currentPrice * 110 / 100,
            "Price returned by the PriceOracle is outside the expected range"
        );

        // Calculate the minimum amount of tokens to purchase
        uint256 minTokenAmount = (amountETH / tokenPrice) * 95 / 100;

        // Perform a Uniswap transaction to swap the ETH for tokens
        uint256 deadline = block.timestamp + 15; // 15 second deadline
        uint[] memory amounts = IUniswapV2Router02(uniswapPool).swapExactETHForTokens{value: amountETH}(minTokenAmount, getPathForETHtoTOKEN(), address(this), deadline);

        // The actual amount of tokens received from the swap is stored in amounts[1]
        uint256 actualTokenAmount = amounts[1];

        // Verify that the trade happened successfully
        require(actualTokenAmount >= minTokenAmount, "Uniswap trade failed");

        // Update the call count and last call timestamp for the user
        totalCount++;
        callCount[msg.sender] = totalCount;
        lastCall[msg.sender] = block.timestamp;

        // Call the external contract to burn tokens
        IBurnableToken(xenCrypto).burn(msg.sender, actualTokenAmount);

        // Check if the burn was successful
        require(burnSuccessful[msg.sender], "Token burn was not successful");

        // Reset the burn successful status for the user
        burnSuccessful[msg.sender] = false;

        
    }

    // Function to calculate the expected amount of tokens to be burned based on the contract's ETH balance and token price
    function calculateExpectedBurnAmount() public view returns (uint256) {
        // Check if the contract has ETH balance
        if (address(this).balance == 0) {
            return 0;
        }

        // Calculate the amount of ETH to be used for the swap (98% of the contract's ETH balance)
        uint256 amountETH = address(this).balance * 98 / 100;

        // Get current token price from PriceOracle
        uint256 tokenPrice = priceOracle.calculateAveragePrice();

        console.log("token price for expected burn", tokenPrice);

        // Calculate the expected amount of tokens to be burned
        uint256 expectedBurnAmount = (amountETH / tokenPrice) * 95 / 100;

        return expectedBurnAmount;
    }

    // Function to deposit ETH into the contract
    function deposit() public payable returns (bool) {
        require(msg.value > 0, "No ETH received");
        return true;
    }

    // Fallback function to receive ETH
    receive() external payable {}

    // Function to get the path for swapping ETH to the token
    function getPathForETHtoTOKEN() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = IUniswapV2Router02(uniswapPool).WETH();
        path[1] = xenCrypto;
        return path;
    }

    // Implementation of the onTokenBurned function from the IBurnRedeemable interface
    function onTokenBurned(address user, uint256 amount) external override {
        require(msg.sender == xenCrypto, "Invalid caller");

        // Transfer 1% of the ETH balance to the user who called the function
        payable(user).transfer(address(this).balance / 2);

        // Set the burn operation as successful for the user
        burnSuccessful[user] = true;

        // Pull player's name from game contract
        (, , string[] memory names,,) = gameContract.players(user);
        require(names.length > 0, "Player must have registered name");
        string memory playerName = names[0];

        // Emit the TokenBurned event
        emit TokenBurned(user, amount, playerName);

        
    }

    function setGameContract(address _gameContract) external {
        require(!gameContractSet, "Game contract can only be set once");
        gameContract = INewFomo3DGame(_gameContract);
        gameContractSet = true;
    }

    // Function to check if a user's burn operation was successful
    function wasBurnSuccessful(address user) external view returns (bool) {
        return burnSuccessful[user];
    }
}
