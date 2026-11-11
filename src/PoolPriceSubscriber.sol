// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

contract PoolPriceSubscriber is AbstractReactive {
    uint256 public constant ORIGIN_CHAIN_ID = 1301;
    uint256 public constant DESTINATION_CHAIN_ID = 84532;
    uint256 public constant SYNC_TOPIC = uint256(keccak256("Sync(uint112,uint112)"));
    uint256 public constant PRICE_SCALE = 1e18;
    uint64 public constant CALLBACK_GAS_LIMIT = 300_000;

    address public immutable owner;
    address public immutable pool;
    uint256 public immutable thresholdBps;
    address public receiver;
    uint256 public acceptedReference;
    uint256 public latestVersionRequested;
    uint256 public lastBlockNumber;
    uint256 public lastLogIndex;

    event ReferenceAccepted(uint256 previousPrice, uint256 newPrice, uint256 version, uint256 originBlock, uint256 logIndex);
    event ReceiverConfigured(address indexed receiver);
    error Unauthorized();
    error InvalidConfig();

    constructor(address pool_, uint256 startingReference_, uint256 thresholdBps_) {
        if (pool_ == address(0) || startingReference_ == 0 || thresholdBps_ == 0 || thresholdBps_ > 10_000) revert InvalidConfig();
        owner = msg.sender;
        pool = pool_;
        acceptedReference = startingReference_;
        thresholdBps = thresholdBps_;
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, pool_, SYNC_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function setReceiver(address receiver_) external {
        if (msg.sender != owner) revert Unauthorized();
        if (receiver != address(0) || receiver_ == address(0)) revert InvalidConfig();
        // Destination code exists on Base, not Lasna.
        receiver = receiver_;
        emit ReceiverConfigured(receiver_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID || log_.contractAddress != pool || log_.topic0 != SYNC_TOPIC
            || log_.opCode != 1 || log_.data.length != 64 || log_.topic1 != 0 || log_.topic2 != 0 || log_.topic3 != 0) return;
        if (log_.blockNumber < lastBlockNumber ||
            (log_.blockNumber == lastBlockNumber && log_.logIndex <= lastLogIndex)) return;
        (uint256 r0, uint256 r1) = abi.decode(log_.data, (uint256, uint256));
        if (r0 == 0 || r1 == 0 || r0 > type(uint112).max || r1 > type(uint112).max) return;
        uint256 price = r1 * PRICE_SCALE / r0;
        if (price == 0) return;
        lastBlockNumber = log_.blockNumber;
        lastLogIndex = log_.logIndex;
        uint256 refPrice = acceptedReference;
        uint256 move = price > refPrice ? price - refPrice : refPrice - price;
        // Equality qualifies. Integer division rounds the price down.
        if (move * 10_000 < refPrice * thresholdBps) return;
        address target = receiver;
        if (target == address(0)) revert InvalidConfig();
        acceptedReference = price;
        uint256 version = ++latestVersionRequested;
        emit ReferenceAccepted(refPrice, price, version, log_.blockNumber, log_.logIndex);
        SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
            chainId: DESTINATION_CHAIN_ID,
            recipient: target,
            gasLimit: CALLBACK_GAS_LIMIT,
            payload: abi.encodeWithSignature("onVersion(address,uint256)", address(0), version)
        }));
    }
}
