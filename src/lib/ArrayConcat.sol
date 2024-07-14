// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library ArrayConcat { 
    function concat( 
        address[] memory array1,
        address[] memory array2
    ) internal pure returns (address[] memory array3) {
        array3 = new address[](array1.length + array2.length);

        for (uint256 i = 0; i < array1.length; i++) {
            array3[i] = array1[i];
        }

        for (uint256 i = 0; i < array2.length; i++) {
            array3[array1.length + i] = array2[i];
        }
    }
}