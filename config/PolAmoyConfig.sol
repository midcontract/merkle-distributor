// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Latest configuration of deployed contracts.
library PolAmoyConfig {
    uint256 public constant CHAIN_ID = 80002;

    // COMMON
    address public constant OWNER = 0x3eAb900aC1E0de25F465c63717cD1044fF69243C; // INITIAL OWNER/ADMIN
    address public constant MOCK_USDT = 0xD19AC10fE911d913Eb0B731925d3a69c80Bd6643;
    address public constant MOCK_DAI = 0xA0A8Ee7bF502EC4Eb5C670fE5c63092950dbB718;
}
