// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface IPriceOracle {
    function calculateAveragePrice() external view returns (uint256);
}

interface IBurnRedeemable {
    function onTokenBurned(address user, uint256 amount) external;
}

interface IBurnableToken {
    function burn(address user, uint256 amount) external;
}

interface IPlayerNameRegistryBurn {
    function getPlayerNames(address playerAddress) external view returns (string[] memory);
}

contract xenBurn is IBurnRedeemable {
    address public xenCrypto;
    mapping(address => bool) private burnSuccessful;
    mapping(address => uint256) private lastCall;
    mapping(address => uint256) private callCount;
    uint256 public totalCount;
    uint256 public totalBurned;
    address private uniswapPool = 0xC0d776E2223c9a2ad13433DAb7eC08cB9C5E76ae;
    IPriceOracle private priceOracle;
    IPlayerNameRegistryBurn private playerNameRegistry;

    constructor(address _priceOracle, address _xenCrypto, address _playerNameRegistry) {
        priceOracle = IPriceOracle(_priceOracle);
        xenCrypto = _xenCrypto;
        playerNameRegistry = IPlayerNameRegistryBurn(_playerNameRegistry);
    }

    event TokenBurned(address indexed user, uint256 amount, string playerName, uint256 timestamp);

    // Modifier to allow only human users to perform certain actions
    modifier isHuman() {
        // require(msg.sender == tx.origin, "Only human users can perform this action");
        _;
    }

    // Modifier to enforce restrictions on the frequency of calls
    modifier gatekeeping() {
        require(
            (lastCall[msg.sender] + 1 days) <= block.timestamp || (callCount[msg.sender] + 5) <= totalCount,
            "Function can only be called once per 24 hours, or 5 times within the 24-hour period by different users"
        );
        _;
    }

    // Function to burn tokens by swapping ETH for the token
    function burnXenCrypto() public gatekeeping {
        require(address(this).balance > 0, "No ETH available");

        // Pull player's name from game contract
        string[] memory names = playerNameRegistry.getPlayerNames(msg.sender);
        require(names.length > 0, "User must have at least 1 name registered");

        // Update the call count and last call timestamp for the user
        totalCount++;
        callCount[msg.sender] = totalCount;
        lastCall[msg.sender] = block.timestamp;
        
        // Transfer 25% of contract balance to the user
        uint256 amountETH = address(this).balance * 25 / 100;
        payable(msg.sender).transfer(amountETH);

        

        emit TokenBurned(msg.sender, amountETH, names[0], block.timestamp);
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

        // Pull player's name from the PlayerNameRegistry contract
        string[] memory names = playerNameRegistry.getPlayerNames(user);

        string memory playerName = names[0];

        totalBurned += amount;

        // Emit the TokenBurned event
        emit TokenBurned(user, amount, playerName, block.timestamp);
    }

    // Function to check if a user's burn operation was successful
    function wasBurnSuccessful(address user) external view returns (bool) {
        return burnSuccessful[user];
    }
}
