// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

contract SmokeSubscriber is AbstractReactive {
    uint256 public constant ORIGIN_CHAIN_ID = 1301;
    uint256 public constant DESTINATION_CHAIN_ID = 84532;
    uint64 public constant CALLBACK_GAS_LIMIT = 300_000;
    uint256 public constant SMOKE_TOPIC = uint256(keccak256("Smoke(bytes32)"));

    address public immutable owner;
    address public immutable emitter;
    address public receiver;
    mapping(bytes32 => bool) public requested;

    event ReceiverConfigured(address indexed receiver);
    event SmokeMatched(bytes32 indexed runId);

    error NotOwner();
    error ReceiverAlreadyConfigured();
    error InvalidReceiver();
    error ReceiverNotConfigured();

    constructor(address emitter_) {
        if (emitter_ == address(0)) revert InvalidReceiver();
        owner = msg.sender;
        emitter = emitter_;
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, emitter_, SMOKE_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function setReceiver(address receiver_) external {
        if (msg.sender != owner) revert NotOwner();
        if (receiver != address(0)) revert ReceiverAlreadyConfigured();
        // The receiver is deployed on Base, so its address has no code on Lasna.
        if (receiver_ == address(0)) revert InvalidReceiver();
        receiver = receiver_;
        emit ReceiverConfigured(receiver_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID || log_.contractAddress != emitter ||
            log_.topic0 != SMOKE_TOPIC || log_.opCode != 2 || log_.data.length != 0) return;
        bytes32 runId = bytes32(log_.topic1);
        if (runId == bytes32(0) || requested[runId]) return;
        address target = receiver;
        if (target == address(0)) revert ReceiverNotConfigured();

        requested[runId] = true;
        emit SmokeMatched(runId);
        SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
            chainId: DESTINATION_CHAIN_ID,
            recipient: target,
            gasLimit: CALLBACK_GAS_LIMIT,
            payload: abi.encodeWithSignature("onSmoke(address,bytes32)", address(0), runId)
        }));
    }
}
