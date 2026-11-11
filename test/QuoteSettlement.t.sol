// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {QuoteSettlement} from "../src/QuoteSettlement.sol";
import {QuoteVersionReceiver} from "../src/QuoteVersionReceiver.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {DemoTaker} from "../src/DemoTaker.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

interface VmQuote {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8, bytes32, bytes32);
    function prank(address sender) external;
    function warp(uint256 time) external;
    function chainId(uint256 newChainId) external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata data) external;
}

contract LocalProxy {
    function deliver(QuoteVersionReceiver receiver, address reactive, uint256 version) external {
        receiver.onVersion(reactive, version);
    }
}

contract QuoteSettlementTest {
    VmQuote private constant vm = VmQuote(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MAKER_KEY = 0xA11CE;
    address private maker;
    address private taker;
    address private reactive = address(0xBEEF);
    MockERC20 private makerToken;
    MockERC20 private takerToken;
    QuoteSettlement private control;
    QuoteSettlement private protectedQuote;
    QuoteVersionReceiver private receiver;
    LocalProxy private proxy;

    function setUp() public {
        vm.warp(1_000_000);
        maker = vm.addr(MAKER_KEY);
        taker = address(0xCAFE);
        makerToken = new MockERC20("Maker Token", "MAK");
        takerToken = new MockERC20("Taker Token", "TAK");
        control = new QuoteSettlement(maker, address(makerToken), address(takerToken), false);
        protectedQuote = new QuoteSettlement(maker, address(makerToken), address(takerToken), true);
        proxy = new LocalProxy();
        receiver = new QuoteVersionReceiver(IPayable(payable(address(proxy))), reactive, protectedQuote);
        protectedQuote.setVersionReceiver(address(receiver));
        makerToken.mint(maker, 1_000 ether);
        takerToken.mint(taker, 2_000 ether);
        vm.prank(maker);
        makerToken.approve(address(control), type(uint256).max);
        vm.prank(maker);
        makerToken.approve(address(protectedQuote), type(uint256).max);
        vm.prank(taker);
        takerToken.approve(address(control), type(uint256).max);
        vm.prank(taker);
        takerToken.approve(address(protectedQuote), type(uint256).max);
    }

    function quote(uint256 nonce, uint256 version) private view returns (QuoteSettlement.Quote memory q) {
        q = QuoteSettlement.Quote({maker: maker, taker: taker, makerToken: address(makerToken), takerToken: address(takerToken), makerAmount: 100 ether, takerAmount: 200 ether, expiry: block.timestamp + 1 hours, nonce: nonce, version: version});
    }

    function sign(QuoteSettlement settlement, QuoteSettlement.Quote memory q) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_KEY, settlement.hashQuote(q));
        return abi.encodePacked(r, s, v);
    }

    function testSideBySideVersionInvalidation() public {
        QuoteSettlement.Quote memory c = quote(1, 0);
        QuoteSettlement.Quote memory p = quote(1, 0);
        bytes memory cSig = sign(control, c);
        bytes memory pSig = sign(protectedQuote, p);
        require(control.hashQuote(c) != protectedQuote.hashQuote(p), "domain not bound to contract");
        proxy.deliver(receiver, reactive, 1);
        require(protectedQuote.quoteVersion() == 1, "version not advanced");

        vm.prank(taker);
        control.fill(c, cSig);
        require(makerToken.balanceOf(taker) == 100 ether, "control maker token");
        require(takerToken.balanceOf(maker) == 200 ether, "control taker token");
        uint256 makerA = makerToken.balanceOf(maker);
        uint256 takerA = makerToken.balanceOf(taker);
        uint256 makerB = takerToken.balanceOf(maker);
        uint256 takerB = takerToken.balanceOf(taker);

        vm.expectRevert(abi.encodeWithSelector(QuoteSettlement.StaleQuoteVersion.selector, 0, 1));
        vm.prank(taker);
        protectedQuote.fill(p, pSig);
        require(!protectedQuote.nonceUsed(1), "stale nonce consumed");
        require(makerToken.balanceOf(maker) == makerA && makerToken.balanceOf(taker) == takerA, "stale maker token moved");
        require(takerToken.balanceOf(maker) == makerB && takerToken.balanceOf(taker) == takerB, "stale taker token moved");

        QuoteSettlement.Quote memory fresh = quote(2, 1);
        bytes memory freshSig = sign(protectedQuote, fresh);
        vm.prank(taker);
        protectedQuote.fill(fresh, freshSig);
        require(makerToken.balanceOf(taker) == takerA + 100 ether, "fresh maker token");
        require(takerToken.balanceOf(maker) == makerB + 200 ether, "fresh taker token");
        require(protectedQuote.nonceUsed(2), "fresh nonce unused");
    }

    function testProtectedQuoteFillsBeforeAdvance() public {
        QuoteSettlement.Quote memory q = quote(7, 0);
        bytes memory sig = sign(protectedQuote, q);
        vm.prank(taker);
        protectedQuote.fill(q, sig);
        require(makerToken.balanceOf(taker) == 100 ether, "maker leg missing");
        require(takerToken.balanceOf(maker) == 200 ether, "taker leg missing");
    }

    function testDeployerOwnedTakerContractFills() public {
        DemoTaker demoTaker = new DemoTaker();
        takerToken.mint(address(demoTaker), 200 ether);
        demoTaker.approveToken(address(takerToken), address(control), 200 ether);
        QuoteSettlement.Quote memory q = quote(8, 0);
        q.taker = address(demoTaker);
        bytes memory sig = sign(control, q);
        demoTaker.fill(control, q, sig);
        require(makerToken.balanceOf(address(demoTaker)) == 100 ether, "taker received no maker tokens");
        require(takerToken.balanceOf(maker) == 200 ether, "maker received no taker tokens");
    }

    function testExpiryAndNonceReuse() public {
        QuoteSettlement.Quote memory q = quote(3, 0);
        bytes memory sig = sign(control, q);
        vm.warp(q.expiry);
        vm.expectRevert(QuoteSettlement.ExpiredQuote.selector);
        vm.prank(taker);
        control.fill(q, sig);
        vm.warp(q.expiry - 1);
        vm.prank(taker);
        control.fill(q, sig);
        vm.expectRevert(QuoteSettlement.NonceUsed.selector);
        vm.prank(taker);
        control.fill(q, sig);
    }

    function testTamperedTermsWrongTakerAndWrongDomain() public {
        QuoteSettlement.Quote memory q = quote(4, 0);
        bytes memory sig = sign(control, q);
        vm.expectRevert(QuoteSettlement.WrongTaker.selector);
        control.fill(q, sig);
        q.takerAmount += 1;
        vm.expectRevert(QuoteSettlement.InvalidSignature.selector);
        vm.prank(taker);
        control.fill(q, sig);
        q.takerAmount -= 1;
        vm.expectRevert(QuoteSettlement.InvalidSignature.selector);
        vm.prank(taker);
        protectedQuote.fill(q, sig);
        q.makerToken = address(takerToken);
        vm.expectRevert(QuoteSettlement.InvalidPair.selector);
        vm.prank(taker);
        control.fill(q, sig);
    }

    function testSignatureBoundToChainId() public {
        QuoteSettlement.Quote memory q = quote(6, 0);
        bytes memory sig = sign(control, q);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(QuoteSettlement.InvalidSignature.selector);
        vm.prank(taker);
        control.fill(q, sig);
    }

    function testTokenTransferFailuresAreAtomic() public {
        QuoteSettlement.Quote memory q = quote(5, 0);
        bytes memory sig = sign(control, q);
        takerToken.setFailTransfers(true);
        vm.expectRevert(QuoteSettlement.TokenTransferFailed.selector);
        vm.prank(taker);
        control.fill(q, sig);
        require(!control.nonceUsed(5) && makerToken.balanceOf(taker) == 0, "first transfer failure changed state");
        takerToken.setFailTransfers(false);
        makerToken.setFailTransfers(true);
        vm.expectRevert(QuoteSettlement.TokenTransferFailed.selector);
        vm.prank(taker);
        control.fill(q, sig);
        require(!control.nonceUsed(5) && takerToken.balanceOf(maker) == 0, "second transfer failure changed state");
    }

    function testCallbackAuthenticationAndMonotonicUpdates() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NotAuthorized(address,address)")), address(this), address(proxy)));
        receiver.onVersion(reactive, 2);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("CallbackNotAuthorized(address,address)")), address(0xBAD), reactive));
        proxy.deliver(receiver, address(0xBAD), 2);
        vm.expectRevert(QuoteSettlement.Unauthorized.selector);
        protectedQuote.advanceVersion(2);
        proxy.deliver(receiver, reactive, 2);
        proxy.deliver(receiver, reactive, 2);
        proxy.deliver(receiver, reactive, 1);
        require(protectedQuote.quoteVersion() == 2, "version decreased or duplicated");
    }
}
