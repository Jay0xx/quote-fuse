// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

contract SmokeReceiver is AbstractCallback {
    uint256 public counter;
    mapping(bytes32 => bool) public processed;

    event SmokeReceived(bytes32 indexed runId, uint256 counter);
    error DuplicateRunId(bytes32 runId);
    error ZeroRunId();

    constructor(IPayable proxy_, address subscriber_) AbstractCallback(proxy_, subscriber_) {}

    function onSmoke(address reactive_, bytes32 runId)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (runId == bytes32(0)) revert ZeroRunId();
        if (processed[runId]) revert DuplicateRunId(runId);
        processed[runId] = true;
        unchecked { ++counter; }
        emit SmokeReceived(runId, counter);
    }
}
