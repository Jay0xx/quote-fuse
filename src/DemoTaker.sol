// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {QuoteSettlement} from "./QuoteSettlement.sol";

interface IApproveToken {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Testnet-only taker account controlled by the deployer.
contract DemoTaker {
    address public immutable owner;
    error Unauthorized();
    error ApprovalFailed();

    constructor() { owner = msg.sender; }

    function approveToken(address token, address spender, uint256 amount) external {
        if (msg.sender != owner) revert Unauthorized();
        if (!IApproveToken(token).approve(spender, amount)) revert ApprovalFailed();
    }

    function fill(QuoteSettlement settlement, QuoteSettlement.Quote calldata quote, bytes calldata signature) external {
        if (msg.sender != owner) revert Unauthorized();
        settlement.fill(quote, signature);
    }
}
