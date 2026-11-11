// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {SmokeEmitter} from "../src/SmokeEmitter.sol";
import {SmokeSubscriber} from "../src/SmokeSubscriber.sol";
import {SmokeReceiver} from "../src/SmokeReceiver.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

interface Vm {
    function etch(address target, bytes calldata code) external;
    function prank(address sender) external;
    function expectRevert() external;
}

contract MockSystem {
    uint256 public subscriptionCount;
    uint256 public callbackCount;
    uint256 public subscribedChain;
    address public subscribedEmitter;
    uint256 public subscribedTopic;
    uint256 public callbackChain;
    address public callbackRecipient;
    uint64 public callbackGas;
    bytes public callbackPayload;

    function subscribe(uint256 chain_, address emitter_, uint256 topic_, uint256, uint256, uint256) external {
        ++subscriptionCount;
        subscribedChain = chain_;
        subscribedEmitter = emitter_;
        subscribedTopic = topic_;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        ++callbackCount;
        callbackChain = config_.chainId;
        callbackRecipient = config_.recipient;
        callbackGas = config_.gasLimit;
        callbackPayload = config_.payload;
    }
}

contract SmokeTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address private constant PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    bytes32 private constant RUN_ID = keccak256("quote-fuse-smoke-test");

    MockSystem private system;
    SmokeEmitter private emitter;
    SmokeSubscriber private subscriber;
    SmokeReceiver private receiver;

    function setUp() public {
        MockSystem implementation = new MockSystem();
        vm.etch(SYSTEM, address(implementation).code);
        system = MockSystem(SYSTEM);
        emitter = new SmokeEmitter();
        subscriber = new SmokeSubscriber(address(emitter));
        receiver = new SmokeReceiver(IPayable(payable(PROXY)), address(subscriber));
        subscriber.setReceiver(address(receiver));
    }

    function _log(bytes32 runId) private view returns (IReactive.LogRecord memory log_) {
        log_.chainId = 1301;
        log_.contractAddress = address(emitter);
        log_.topic0 = uint256(keccak256("Smoke(bytes32)"));
        log_.topic1 = uint256(runId);
        log_.opCode = 2;
    }

    function testValidCallbackAndSubscription() public {
        require(system.subscriptionCount() == 1, "subscription count");
        require(system.subscribedChain() == 1301, "origin chain");
        require(system.subscribedEmitter() == address(emitter), "emitter");
        require(system.subscribedTopic() == uint256(keccak256("Smoke(bytes32)")), "topic");

        vm.prank(SYSTEM);
        subscriber.react(_log(RUN_ID));
        require(system.callbackCount() == 1, "callback count");
        require(system.callbackChain() == 84532, "destination chain");
        require(system.callbackRecipient() == address(receiver), "recipient");
        require(system.callbackGas() == 300_000, "gas budget");
        require(keccak256(system.callbackPayload()) == keccak256(abi.encodeWithSignature("onSmoke(address,bytes32)", address(0), RUN_ID)), "payload");

        vm.prank(PROXY);
        receiver.onSmoke(address(subscriber), RUN_ID);
        require(receiver.counter() == 1 && receiver.processed(RUN_ID), "receiver state");
    }

    function testDirectCallBypassesProxyReverts() public {
        vm.expectRevert();
        receiver.onSmoke(address(subscriber), RUN_ID);
        require(receiver.counter() == 0, "counter changed");
    }

    function testUnapprovedReactiveSenderReverts() public {
        vm.expectRevert();
        vm.prank(PROXY);
        receiver.onSmoke(address(0xBEEF), RUN_ID);
        require(receiver.counter() == 0, "counter changed");
    }

    function testDuplicateRunIdReverts() public {
        vm.prank(PROXY);
        receiver.onSmoke(address(subscriber), RUN_ID);
        vm.expectRevert();
        vm.prank(PROXY);
        receiver.onSmoke(address(subscriber), RUN_ID);
        require(receiver.counter() == 1, "counter doubled");
    }

    function testWrongSourceLogsIgnored() public {
        IReactive.LogRecord memory log_ = _log(RUN_ID);
        log_.chainId = 84532;
        vm.prank(SYSTEM);
        subscriber.react(log_);
        log_ = _log(RUN_ID);
        log_.contractAddress = address(0xBEEF);
        vm.prank(SYSTEM);
        subscriber.react(log_);
        log_ = _log(RUN_ID);
        log_.topic0 = 1;
        vm.prank(SYSTEM);
        subscriber.react(log_);
        log_ = _log(RUN_ID);
        log_.opCode = 1;
        vm.prank(SYSTEM);
        subscriber.react(log_);
        require(system.callbackCount() == 0, "unexpected callback");
    }

    function testUnauthenticatedReactRevertsAndDuplicateIsIgnored() public {
        vm.expectRevert();
        subscriber.react(_log(RUN_ID));
        vm.prank(SYSTEM);
        subscriber.react(_log(RUN_ID));
        vm.prank(SYSTEM);
        subscriber.react(_log(RUN_ID));
        require(system.callbackCount() == 1, "duplicate request");
    }

    function testCanConfigureCrossChainReceiverWithoutLocalCode() public {
        SmokeSubscriber fresh = new SmokeSubscriber(address(emitter));
        address destinationOnly = address(0x1234);
        require(destinationOnly.code.length == 0, "test address has local code");
        fresh.setReceiver(destinationOnly);
        require(fresh.receiver() == destinationOnly, "cross-chain receiver not set");
    }
}
