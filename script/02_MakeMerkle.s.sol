// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Merkle } from "murky/src/Merkle.sol";
import { ScriptHelper } from "murky/script/common/ScriptHelper.sol";

/// @title MakeMerkle
/// @notice A script for generating Merkle proofs for referral rewards distribution.
/// @dev This script reads referral rewards data from an input JSON file, computes Merkle proofs for each entry, and
/// writes the output in a specified format.
/// The output JSON file includes Merkle proofs, root hash, and leaf nodes for each entry.
contract MakeMerkle is Script, ScriptHelper {
    using stdJson for string;

    // Instance of the Murky Merkle library for proof generation.
    Merkle private m = new Merkle();

    /// @dev Path to the input JSON file containing the referral rewards data.
    string private inputPath = "/script/data/input.json";
    /// @dev Path to the output JSON file where the generated proofs and root hash will be saved.
    string private outputPath = "/script/data/output.json";

    // Reads the referral data from the input file.
    string private elements = vm.readFile(string.concat(vm.projectRoot(), inputPath));

    // Retrieves the data types for the Merkle tree leaves from JSON (e.g., address and uint).
    string[] private types = elements.readStringArray(".types");

    // Number of referral reward entries in the JSON file.
    uint256 private count = elements.readUint(".count");
    // Array to store hashed leaves of the Merkle tree.
    bytes32[] private leafs = new bytes32[](count);

    // Array to store inputs for each leaf node.
    string[] private inputs = new string[](count);

    // Array to store generated JSON entries for each proof.
    string[] private outputs = new string[](count);

    // Consolidated output JSON string containing all proofs, root, and leaf nodes.
    string private output;

    /// @notice Constructs a JSON path to retrieve specific referral reward data from the input file.
    /// @param i Index of the referral entry.
    /// @param j Index of the data type (e.g., address or uint) in the entry.
    /// @return The JSON path to access the specific data in the input file.
    function getValuesByIndex(uint256 i, uint256 j) internal pure returns (string memory) {
        return string.concat(".values.", vm.toString(i), ".", vm.toString(j));
    }

    /// @notice Creates a JSON entry for a specific Merkle proof.
    /// @param _inputs Serialized input values (e.g., address and amount) for the Merkle leaf.
    /// @param _proof Serialized Merkle proof nodes.
    /// @param _root The Merkle root hash.
    /// @param _leaf The Merkle leaf node hash.
    /// @return result The JSON entry as a single string.
    function generateJsonEntries(string memory _inputs, string memory _proof, string memory _root, string memory _leaf)
        internal
        pure
        returns (string memory result)
    {
        result = string.concat(
            "{",
            "\"inputs\":",
            _inputs,
            ",",
            "\"proof\":",
            _proof,
            ",",
            "\"root\":\"",
            _root,
            "\",",
            "\"leaf\":\"",
            _leaf,
            "\"",
            "}"
        );
    }

    /// @notice Reads the input file, generates Merkle proofs for each referral reward, and writes the output file.
    /// @dev Uses the Murky library to compute Merkle proofs and builds the output JSON format.
    function run() public {
        console.log("Generating Merkle Proof for %s", inputPath);

        for (uint256 i = 0; i < count; ++i) {
            string[] memory input = new string[](types.length); // Input values as strings (e.g., address and amount).
            bytes32[] memory data = new bytes32[](types.length); // Input values as bytes32 for hashing.

            for (uint256 j = 0; j < types.length; ++j) {
                if (compareStrings(types[j], "address")) {
                    address value = elements.readAddress(getValuesByIndex(i, j));
                    data[j] = bytes32(uint256(uint160(value))); // Convert address to bytes32.
                    input[j] = vm.toString(value);
                } else if (compareStrings(types[j], "uint")) {
                    uint256 value = vm.parseUint(elements.readString(getValuesByIndex(i, j)));
                    data[j] = bytes32(value);
                    input[j] = vm.toString(value);
                }
            }

            // Compute the leaf node hash for the Merkle tree
            leafs[i] = keccak256(bytes.concat(keccak256(ltrim64(abi.encode(data)))));
            inputs[i] = stringArrayToString(input); // Store the inputs for JSON output.
        }

        for (uint256 i = 0; i < count; ++i) {
            // Generate proof and other necessary data for each leaf node.
            string memory proof = bytes32ArrayToString(m.getProof(leafs, i));
            string memory root = vm.toString(m.getRoot(leafs));
            string memory leaf = vm.toString(leafs[i]);
            string memory input = inputs[i];

            outputs[i] = generateJsonEntries(input, proof, root, leaf);
        }

        // Combine all JSON entries into a single output.
        output = stringArrayToArrayString(outputs);
        vm.writeFile(string.concat(vm.projectRoot(), outputPath), output);

        console.log("DONE: The output is found at %s", outputPath);
    }
}
