// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {QuoteSettlement} from "./QuoteSettlement.sol";

contract QuoteVersionReceiver is AbstractCallback {
    QuoteSettlement public immutable settlement;

    constructor(IPayable proxy_, address reactive_, QuoteSettlement settlement_)
        AbstractCallback(proxy_, reactive_)
    {
        settlement = settlement_;
    }

    function onVersion(address reactive_, uint256 newVersion)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        settlement.advanceVersion(newVersion);
    }
}
