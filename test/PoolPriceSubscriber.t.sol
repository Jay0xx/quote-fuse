// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {PoolPriceSubscriber} from "../src/PoolPriceSubscriber.sol";
import {ControlledPool, IPoolToken} from "../src/ControlledPool.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {QuoteSettlement} from "../src/QuoteSettlement.sol";
import {QuoteVersionReceiver} from "../src/QuoteVersionReceiver.sol";

interface VmPool {
    struct Log { bytes32[] topics; bytes data; address emitter; }
    function etch(address target, bytes calldata code) external;
    function prank(address sender) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8, bytes32, bytes32);
    function warp(uint256 time) external;
    function expectRevert(bytes calldata data) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract PriceMockSystem {
    uint256 public subscriptions;
    uint256 public subscribedChain;
    address public subscribedPool;
    uint256 public subscribedTopic;
    uint256 public callbacks;
    uint256 public destination;
    address public recipient;
    uint64 public gasLimit;
    bytes public payload;

    function subscribe(uint256 chainId, address pool, uint256 topic, uint256, uint256, uint256) external {
        ++subscriptions; subscribedChain = chainId; subscribedPool = pool; subscribedTopic = topic;
    }
    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory c) external {
        ++callbacks; destination = c.chainId; recipient = c.recipient; gasLimit = c.gasLimit; payload = c.payload;
    }
}

contract PriceProxyFixture {
    function deliver(QuoteVersionReceiver receiver, address sender, uint256 version) external {
        receiver.onVersion(sender, version);
    }
}

contract PoolPriceSubscriberTest {
    VmPool private constant vm = VmPool(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 private constant MAKER_KEY = 0x123456;
    PriceMockSystem private system;
    MockERC20 private token0;
    MockERC20 private token1;
    ControlledPool private pool;
    PoolPriceSubscriber private subscriber;
    QuoteSettlement private control;
    QuoteSettlement private protectedQuote;
    QuoteVersionReceiver private receiver;
    PriceProxyFixture private proxy;
    address private maker;
    address private taker = address(0xCAFE);

    function setUp() public {
        vm.warp(1_000_000);
        PriceMockSystem impl = new PriceMockSystem();
        vm.etch(SYSTEM, address(impl).code);
        system = PriceMockSystem(SYSTEM);
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        pool = new ControlledPool(IPoolToken(address(token0)), IPoolToken(address(token1)));
        token0.mint(address(this), 2_000 ether);
        token1.mint(address(this), 2_000 ether);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.seed(1_000 ether, 1_000 ether);
        subscriber = new PoolPriceSubscriber(address(pool), 1e18, 300);
        maker = vm.addr(MAKER_KEY);
        control = new QuoteSettlement(maker, address(token0), address(token1), false);
        protectedQuote = new QuoteSettlement(maker, address(token0), address(token1), true);
        proxy = new PriceProxyFixture();
        receiver = new QuoteVersionReceiver(IPayable(payable(address(proxy))), address(subscriber), protectedQuote);
        protectedQuote.setVersionReceiver(address(receiver));
        subscriber.setReceiver(address(receiver));
        token0.mint(maker, 300 ether);
        token1.mint(taker, 600 ether);
        vm.prank(maker); token0.approve(address(control), type(uint256).max);
        vm.prank(maker); token0.approve(address(protectedQuote), type(uint256).max);
        vm.prank(taker); token1.approve(address(control), type(uint256).max);
        vm.prank(taker); token1.approve(address(protectedQuote), type(uint256).max);
    }

    function logAt(uint256 blockNumber, uint256 index, uint256 r0, uint256 r1) private view returns (IReactive.LogRecord memory l) {
        l.chainId = 1301; l.contractAddress = address(pool); l.topic0 = subscriber.SYNC_TOPIC();
        l.opCode = 1; l.data = abi.encode(r0, r1); l.blockNumber = blockNumber; l.logIndex = index;
    }
    function deliverLog(IReactive.LogRecord memory l) private { vm.prank(SYSTEM); subscriber.react(l); }

    function testThresholdBoundaryBothDirectionsAndCumulative() public {
        deliverLog(logAt(1, 0, 1000, 1029)); // 2.9%: below
        require(system.callbacks() == 0, "below threshold");
        deliverLog(logAt(2, 0, 1000, 1030)); // exactly 3%
        require(system.callbacks() == 1 && subscriber.acceptedReference() == 103e16, "exact boundary");
        deliverLog(logAt(3, 0, 1000, 1060)); // 2.91% from accepted reference
        require(system.callbacks() == 1, "reference should not follow small move");
        deliverLog(logAt(4, 0, 1000, 1061)); // 3.01% accumulated
        require(system.callbacks() == 2 && subscriber.latestVersionRequested() == 2, "cumulative move");
        deliverLog(logAt(5, 0, 1000, 1029)); // >3% downward from 1061
        require(system.callbacks() == 3, "downward move");
    }

    function testInvalidDuplicateOlderAndWrongLogs() public {
        IReactive.LogRecord memory l = logAt(10, 2, 1000, 1040);
        l.chainId = 84532; deliverLog(l);
        l = logAt(10, 2, 1000, 1040); l.contractAddress = address(0xBEEF); deliverLog(l);
        l = logAt(10, 2, 1000, 1040); l.opCode = 2; deliverLog(l);
        l = logAt(10, 2, 0, 1000); deliverLog(l);
        l = logAt(10, 2, uint256(type(uint112).max) + 1, 1000); deliverLog(l);
        require(system.callbacks() == 0, "invalid log callback");
        l = logAt(10, 2, 1000, 1040); deliverLog(l);
        deliverLog(l); deliverLog(logAt(9, 3, 1000, 900)); deliverLog(logAt(10, 1, 1000, 900));
        require(system.callbacks() == 1 && subscriber.latestVersionRequested() == 1, "duplicate or older log");
    }

    function testRealPoolSwapToSettlementPath() public {
        require(system.subscriptions() == 1 && system.subscribedChain() == 1301 && system.subscribedPool() == address(pool), "subscription");
        QuoteSettlement.Quote memory c = quote(1, 0, 100 ether, 200 ether);
        QuoteSettlement.Quote memory p = quote(1, 0, 100 ether, 200 ether);
        bytes memory cs = sign(control, c); bytes memory ps = sign(protectedQuote, p);
        vm.recordLogs();
        pool.swapExact0For1(20 ether, 1);
        VmPool.Log[] memory logs = vm.getRecordedLogs();
        uint256 syncCount;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(pool) && logs[i].topics.length == 1 && logs[i].topics[0] == bytes32(subscriber.SYNC_TOPIC())) {
                ++syncCount;
                (uint112 r0, uint112 r1) = abi.decode(logs[i].data, (uint112, uint112));
                require(r0 == pool.reserve0() && r1 == pool.reserve1(), "event not pool state");
                IReactive.LogRecord memory l = logAt(1, i, r0, r1);
                l.data = logs[i].data;
                deliverLog(l);
            }
        }
        require(syncCount == 1 && system.callbacks() == 1, "one real swap callback");
        require(system.destination() == 84532 && system.recipient() == address(receiver) && system.gasLimit() == 300_000, "callback route");
        require(keccak256(system.payload()) == keccak256(abi.encodeWithSignature("onVersion(address,uint256)", address(0), 1)), "callback payload");
        require(protectedQuote.quoteVersion() == 0 && subscriber.latestVersionRequested() == 1, "requested and applied conflated");
        proxy.deliver(receiver, address(subscriber), 1);
        require(protectedQuote.quoteVersion() == 1, "not applied");
        vm.prank(taker); control.fill(c, cs);
        vm.expectRevert(abi.encodeWithSelector(QuoteSettlement.StaleQuoteVersion.selector, 0, 1));
        vm.prank(taker); protectedQuote.fill(p, ps);
        QuoteSettlement.Quote memory fresh = quote(2, 1, 100 ether, 190 ether);
        bytes memory freshSig = sign(protectedQuote, fresh);
        vm.prank(taker); protectedQuote.fill(fresh, freshSig);
        require(token0.balanceOf(taker) == 200 ether && token1.balanceOf(maker) == 390 ether, "final balances");
    }

    function quote(uint256 nonce, uint256 version, uint256 amount0, uint256 amount1) private view returns (QuoteSettlement.Quote memory q) {
        q = QuoteSettlement.Quote(maker, taker, address(token0), address(token1), amount0, amount1, block.timestamp + 1 hours, nonce, version);
    }
    function sign(QuoteSettlement settlement, QuoteSettlement.Quote memory q) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_KEY, settlement.hashQuote(q)); return abi.encodePacked(r, s, v);
    }
}
