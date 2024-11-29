// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

/// @title Merkle Tree Input File Generator Script
/// @notice Generates a JSON file for use as input for a Merkle tree with addresses and corresponding amounts.
/// @dev This script writes an output JSON file at the specified path, containing a structured format of addresses and
/// token amounts for whitelist purposes.
contract GenerateInput is Script {
    /// @notice Fixed amount to be associated with each address in the whitelist (25 Ether).
    uint256 private constant AMOUNT = 25 ether;

    /// @notice Path to save the generated JSON input file.
    string private constant INPUT_PATH = "/script/data/input.json";

    /// @notice Number of addresses in the whitelist.
    uint256 count;

    /// @dev Array to define data types used in the JSON output, containing "address" and "uint" as elements.
    string[] types = new string[](2);

    /// @dev Array of whitelisted addresses to be included in the output JSON.
    string[] whitelist = new string[](4);

    /// @dev Initializes data types and whitelist addresses, generates JSON data, and writes it to the specified file.
    function run() public {
        types[0] = "address";
        types[1] = "uint";
        whitelist[0] = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
        whitelist[1] = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
        whitelist[2] = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";
        whitelist[3] = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";
        count = whitelist.length;

        string memory input = _createJSON();

        // Write the generated JSON string to the specified file path
        vm.writeFile(string.concat(vm.projectRoot(), INPUT_PATH), input);

        console.log("DONE: The output is found at %s", INPUT_PATH);
    }

    /// @notice Creates a JSON string formatted with the address and amount data.
    /// @dev Constructs a JSON string with each address in the whitelist paired with the fixed AMOUNT value.
    /// @return A JSON-formatted string containing the whitelist addresses and associated amounts.
    function _createJSON() internal view returns (string memory) {
        string memory countString = vm.toString(count); // Convert count to string
        string memory amountString = vm.toString(AMOUNT); // Convert amount to string

        string memory json = string.concat('{ "types": ["address", "uint"], "count":', countString, ',"values": {');

        for (uint256 i = 0; i < whitelist.length; i++) {
            if (i == whitelist.length - 1) {
                // Append last entry without a trailing comma
                json = string.concat(
                    json,
                    '"',
                    vm.toString(i),
                    '"',
                    ': { "0":',
                    '"',
                    whitelist[i],
                    '"',
                    ', "1":',
                    '"',
                    amountString,
                    '"',
                    " }"
                );
            } else {
                // Append entry with a trailing comma
                json = string.concat(
                    json,
                    '"',
                    vm.toString(i),
                    '"',
                    ': { "0":',
                    '"',
                    whitelist[i],
                    '"',
                    ', "1":',
                    '"',
                    amountString,
                    '"',
                    " },"
                );
            }
        }

        json = string.concat(json, "} }");

        return json;
    }
}
