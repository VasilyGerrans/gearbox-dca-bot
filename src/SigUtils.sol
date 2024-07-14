// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Implemented as a contract to allow dynamic DOMAIN_SEPARATOR.
contract SigUtils {
    struct Permit {
        address payer;
        address creditAccount;
        address tokenIn;
        address tokenOut;
        uint256 deadline;
        bytes data;
    }

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address payer,address creditAccount,address tokenIn,address tokenOut,uint256 deadline,bytes data)"
        );
    bytes32 internal immutable DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("BOT")),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev Computes the hash of the fully encoded EIP-712 message for the domain, which can be used to
    ///      recover the signer.
    function getTypedDataHash(
        Permit memory permit
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    _getStructHash(permit)
                )
            );
    }

    /// @dev Recovers signer address from permit and signature.
    function _recoverAddress(
        Permit calldata permit,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        unchecked {
            return
                ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19\x01",
                            DOMAIN_SEPARATOR,
                            keccak256(
                                abi.encode(
                                    PERMIT_TYPEHASH,
                                    permit.payer,
                                    permit.creditAccount,
                                    permit.tokenIn,
                                    permit.tokenOut,
                                    permit.deadline,
                                    keccak256(permit.data)
                                )
                            )
                        )
                    ),
                    v,
                    r,
                    s
                );
        }
    }

    /// @dev Computes the hash of a permit
    function _getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.payer,
                    _permit.creditAccount,
                    _permit.tokenIn,
                    _permit.tokenOut,
                    _permit.deadline,
                    keccak256(_permit.data)
                )
            );
    }
}
