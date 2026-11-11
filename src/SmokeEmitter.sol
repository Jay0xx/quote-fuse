// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

contract SmokeEmitter {
    event Smoke(bytes32 indexed runId);

    function emitSmoke(bytes32 runId) external {
        require(runId != bytes32(0), "zero run ID");
        emit Smoke(runId);
    }
}
