// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this challenge. Also return variable names need to be specified exactly may be referenced (It may be helpful to cross reference with front-end code function calls).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    IERC20 token; //instantiates the imported contract
    // track total liqudity
    uint256 public totalLiquidity;
    //track individual liquidity
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address swapper, uint256 ethInput, uint256 tokenOutput);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address liquidityProvider, uint256 tokensInput, uint256 ethInput, uint256 liquidityMinted);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
        address liquidityRemover, uint256 tokensOutput, uint256 ethOutput, uint256 liquidityWithdrawn
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written).
     *            Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        //check if already has liquidity
        require(totalLiquidity == 0, "DEX:init - already has liquidity");
        // set liquidity equal to contract balance
        totalLiquidity = address(this).balance;
        // set liquidity mapping as sender/total liquidity
        liquidity[msg.sender] = totalLiquidity;
        // transfer user tokens to dex
        require(token.transferFrom(msg.sender, address(this), tokens));
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90)
     *      Price section for an understanding of the DEX's pricing model and for a price function to add to your contract.
     *      You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     *         Constranct product formula -> x * y = k where x and y are the reserves
     *         dy = (y * 997) * dx / (x + 997 * dx)
     */
    function price(uint256 dx, uint256 x, uint256 y) public pure returns (uint256 yOutput) {
        // amount of tokens to exchange, add 0.03 fee for DEX
        uint256 xInputwithFee = dx * 997;
        // 1000000000
        uint256 inputReserve = xInputwithFee * y;
        // increasing the precision
        // (1000000 * 1000) + 1000000000
        uint256 outputReserve = (x * 1000) + xInputwithFee;
        // (1000000 * 1000) + 1000000000
        uint256 dy = inputReserve / outputReserve;
        return dy;
    }

    /**
     * @notice returns liquidity for a user.
     * NOTE: this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * NOTE: if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     * NOTE: if you will be submitting the challenge make sure to implement this function as it is used in the tests.
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "you should send some eth");
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 eth_reserve = address(this).balance - msg.value;
        uint256 tokenOutput = price(msg.value, eth_reserve, token_reserve);
        require(token.transfer(msg.sender, tokenOutput));
        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        return tokenOutput;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokens) public returns (uint256 ethOutput) {
        require(tokens > 0, "you should send some tokens");
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 ethOutput = price(tokens, token_reserve, address(this).balance);
        (bool sent,) = msg.sender.call{value: ethOutput}("");
        require(sent, "tokenToEth: revert in transferring eth to you!");
        require(token.transferFrom(msg.sender, address(this), tokens));
        emit TokenToEthSwap(msg.sender, tokens, ethOutput);
        return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call.
     *          That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        require(msg.value > 0, "you should send some eth");
        // current eth reserve
        uint256 ethReserve = address(this).balance - msg.value;

        // $BAL reserve
        uint256 token_reserve = token.balanceOf(address(this));
        // $BAL amount
        uint256 tokenDeposit = msg.value * token_reserve / ethReserve + 1;
        uint256 liquidityMinted = msg.value * totalLiquidity / ethReserve;

        liquidity[msg.sender] = liquidity[msg.sender] + liquidityMinted;
        totalLiquidity = totalLiquidity + liquidityMinted;
        require(token.transferFrom(msg.sender, address(this), tokenDeposit));
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return tokensDeposited;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 eth_amount, uint256 token_amount) {
        // token reserve
        uint256 tokenReserve = token.balanceOf(address(this));

        // calculate eth amount to get out
        uint256 ethWithdrawn = amount * address(this).balance / totalLiquidity;

        // calculate the tokens amount to get out
        uint256 tokenWithdrawn = amount * tokenReserve / totalLiquidity;

        // removing liquidity from user total
        liquidity[msg.sender] = liquidity[msg.sender] - ethWithdrawn;

        // removing liquidity from total
        totalLiquidity = totalLiquidity - ethWithdrawn;

        // transfer out user eth amount
        (bool sent,) = msg.sender.call{value: ethWithdrawn}("");
        require(sent, "tokenToEth: revert in transferring eth to you!");
        // transfer out user token amount
        require(token.transfer(msg.sender, tokenWithdrawn));
        emit LiquidityRemoved(msg.sender, amount, ethWithdrawn, tokenWithdrawn);
        return (ethWithdrawn, tokenWithdrawn);
    }
}
