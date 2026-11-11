// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

contract QuoteSettlement {
    struct Quote {
        address maker;
        address taker;
        address makerToken;
        address takerToken;
        uint256 makerAmount;
        uint256 takerAmount;
        uint256 expiry;
        uint256 nonce;
        uint256 version;
    }

    bytes32 public constant QUOTE_TYPEHASH = keccak256("Quote(address maker,address taker,address makerToken,address takerToken,uint256 makerAmount,uint256 takerAmount,uint256 expiry,uint256 nonce,uint256 version)");
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("Quote Fuse");
    bytes32 private constant VERSION_HASH = keccak256("1");
    uint256 private constant SECP256K1_HALF_N = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    address public immutable maker;
    address public immutable makerToken;
    address public immutable takerToken;
    address public immutable owner;
    bool public immutable protectedMode;
    address public versionReceiver;
    uint256 public quoteVersion;
    mapping(uint256 => bool) public nonceUsed;
    uint256 private locked = 1;

    event QuoteFilled(bytes32 indexed quoteHash, uint256 indexed nonce, address indexed taker, uint256 version);
    event VersionAdvanced(uint256 previousVersion, uint256 newVersion);
    event VersionReceiverConfigured(address indexed receiver);

    error InvalidPair();
    error InvalidMaker();
    error WrongTaker();
    error ExpiredQuote();
    error NonceUsed();
    error StaleQuoteVersion(uint256 signedVersion, uint256 currentVersion);
    error InvalidSignature();
    error InvalidAmount();
    error TokenTransferFailed();
    error Unauthorized();
    error ReceiverAlreadySet();
    error ReentrantCall();

    constructor(address maker_, address makerToken_, address takerToken_, bool protectedMode_) {
        if (maker_ == address(0)) revert InvalidMaker();
        if (makerToken_ == address(0) || takerToken_ == address(0) || makerToken_ == takerToken_ ||
            makerToken_.code.length == 0 || takerToken_.code.length == 0) revert InvalidPair();
        maker = maker_;
        makerToken = makerToken_;
        takerToken = takerToken_;
        owner = msg.sender;
        protectedMode = protectedMode_;
    }

    function setVersionReceiver(address receiver_) external {
        if (msg.sender != owner) revert Unauthorized();
        if (!protectedMode || versionReceiver != address(0)) revert ReceiverAlreadySet();
        if (receiver_ == address(0) || receiver_.code.length == 0) revert Unauthorized();
        versionReceiver = receiver_;
        emit VersionReceiverConfigured(receiver_);
    }

    function advanceVersion(uint256 newVersion) external {
        if (!protectedMode || msg.sender != versionReceiver) revert Unauthorized();
        uint256 old = quoteVersion;
        if (newVersion <= old) return;
        quoteVersion = newVersion;
        emit VersionAdvanced(old, newVersion);
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function hashQuote(Quote calldata q) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(QUOTE_TYPEHASH, q.maker, q.taker, q.makerToken, q.takerToken, q.makerAmount, q.takerAmount, q.expiry, q.nonce, q.version));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    function fill(Quote calldata q, bytes calldata signature) external {
        if (locked != 1) revert ReentrantCall();
        locked = 2;
        if (q.maker != maker) revert InvalidMaker();
        if (msg.sender != q.taker) revert WrongTaker();
        if (q.makerToken != makerToken || q.takerToken != takerToken) revert InvalidPair();
        if (q.makerAmount == 0 || q.takerAmount == 0) revert InvalidAmount();
        if (block.timestamp >= q.expiry) revert ExpiredQuote();
        if (protectedMode && q.version != quoteVersion) revert StaleQuoteVersion(q.version, quoteVersion);
        if (nonceUsed[q.nonce]) revert NonceUsed();
        bytes32 digest = hashQuote(q);
        if (_recover(digest, signature) != maker) revert InvalidSignature();
        nonceUsed[q.nonce] = true;
        _transferFrom(q.takerToken, q.taker, maker, q.takerAmount);
        _transferFrom(q.makerToken, maker, q.taker, q.makerAmount);
        emit QuoteFilled(digest, q.nonce, q.taker, q.version);
        locked = 1;
    }

    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28 || uint256(s) > SECP256K1_HALF_N || r == bytes32(0) || s == bytes32(0)) revert InvalidSignature();
        return ecrecover(digest, v, r, s);
    }

    function _transferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        if (!ok || (data.length != 0 && (data.length != 32 || !abi.decode(data, (bool))))) revert TokenTransferFailed();
    }
}
