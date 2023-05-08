//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { Faucet } from "../universal/faucet/Faucet.sol";
import { AdminFaucetAuthModule } from "../universal/faucet/authmodules/AdminFaucetAuthModule.sol";
import { FaucetHelper } from "../testing/helpers/FaucetHelper.sol";

contract Faucet_Initializer is Test {
    event Drip(
        string indexed authModule,
        bytes indexed userId,
        uint256 amount,
        address indexed recipient
    );
    address internal faucetContractAdmin;
    address internal faucetAuthAdmin;
    address internal nonAdmin;
    address internal fundsReceiver;
    uint256 internal faucetAuthAdminKey;
    uint256 internal nonAdminKey;
    uint256 internal startingTimestamp = 1000;

    Faucet faucet;
    AdminFaucetAuthModule optimistNftFam;
    AdminFaucetAuthModule githubFam;

    FaucetHelper faucetHelper;

    function setUp() public {
        vm.warp(startingTimestamp);
        faucetContractAdmin = makeAddr("faucetContractAdmin");
        fundsReceiver = makeAddr("fundsReceiver");

        faucetAuthAdminKey = 0xB0B0B0B0;
        faucetAuthAdmin = vm.addr(faucetAuthAdminKey);

        nonAdminKey = 0xC0C0C0C0;
        nonAdmin = vm.addr(nonAdminKey);

        _initializeContracts();
    }

    /**
     * @notice Instantiates a Faucet.
     */
    function _initializeContracts() internal {
        faucet = new Faucet(faucetContractAdmin);

        // Fill faucet with ether.
        vm.deal(address(faucet), 10 ether);

        optimistNftFam = new AdminFaucetAuthModule(faucetAuthAdmin);
        optimistNftFam.initialize("OptimistNftFam");
        githubFam = new AdminFaucetAuthModule(faucetAuthAdmin);
        githubFam.initialize("GithubFam");

        faucetHelper = new FaucetHelper();
    }

    function _enableFaucetAuthModules() internal {
        vm.prank(faucetContractAdmin);
        faucet.configure(
            optimistNftFam,
            Faucet.ModuleConfig("OptimistNftModule", true, 1 days, 1 ether)
        );
        vm.prank(faucetContractAdmin);
        faucet.configure(githubFam, Faucet.ModuleConfig("GithubModule", true, 1 days, .05 ether));
    }

    /**
     * @notice Get signature as a bytes blob.
     *
     */
    function _getSignature(uint256 _signingPrivateKey, bytes32 _digest)
        internal
        pure
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signingPrivateKey, _digest);

        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    /**
     * @notice Signs a proof with the given private key and returns the signature using
     *         the given EIP712 domain separator. This assumes that the issuer's address is the
     *         corresponding public key to _issuerPrivateKey.
     */
    function issueProofWithEIP712Domain(
        uint256 _issuerPrivateKey,
        bytes memory _eip712Name,
        bytes memory _contractVersion,
        uint256 _eip712Chainid,
        address _eip712VerifyingContract,
        address recipient,
        bytes memory id,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        AdminFaucetAuthModule.Proof memory proof = AdminFaucetAuthModule.Proof(
            recipient,
            nonce,
            id
        );
        return
            _getSignature(
                _issuerPrivateKey,
                faucetHelper.getDigestWithEIP712Domain(
                    proof,
                    _eip712Name,
                    _contractVersion,
                    _eip712Chainid,
                    _eip712VerifyingContract
                )
            );
    }
}

contract FaucetTest is Faucet_Initializer {
    function test_initialize() external {
        assertEq(faucet.ADMIN(), faucetContractAdmin);
    }

    function test_authAdmin_drip_succeeds() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("OptimistNftFam"),
            bytes(optimistNftFam.version()),
            block.chainid,
            address(optimistNftFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        vm.prank(nonAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(optimistNftFam, abi.encodePacked(fundsReceiver), signature)
        );
    }

    function test_nonAdmin_drip_fails() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            nonAdminKey,
            bytes("OptimistNftFam"),
            bytes(optimistNftFam.version()),
            block.chainid,
            address(optimistNftFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        vm.prank(nonAdmin);
        vm.expectRevert("Faucet: drip parameters could not be verified by security module");
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(optimistNftFam, abi.encodePacked(fundsReceiver), signature)
        );
    }

    function test_drip_optimistNft_sendsCorrectAmount() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("OptimistNftFam"),
            bytes(optimistNftFam.version()),
            block.chainid,
            address(optimistNftFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        uint256 recipientBalanceBefore = address(fundsReceiver).balance;
        vm.prank(nonAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(optimistNftFam, abi.encodePacked(fundsReceiver), signature)
        );
        uint256 recipientBalanceAfter = address(fundsReceiver).balance;
        assertEq(
            recipientBalanceAfter - recipientBalanceBefore,
            1 ether,
            "expect increase of 1 ether"
        );
    }

    function test_drip_github_sendsCorrectAmount() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        uint256 recipientBalanceBefore = address(fundsReceiver).balance;
        vm.prank(nonAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );
        uint256 recipientBalanceAfter = address(fundsReceiver).balance;
        assertEq(
            recipientBalanceAfter - recipientBalanceBefore,
            .05 ether,
            "expect increase of .05 ether"
        );
    }

    function test_drip_emitsEvent() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        vm.expectEmit(true, true, true, true, address(faucet));
        emit Drip("GithubModule", abi.encodePacked(fundsReceiver), .05 ether, fundsReceiver);

        vm.prank(nonAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );
    }

    function test_drip_disabledModule_reverts() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        vm.startPrank(faucetContractAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );

        faucet.configure(githubFam, Faucet.ModuleConfig("GithubModule", false, 1 days, .05 ether));

        vm.expectRevert("Faucet: provided auth module is not supported by this faucet");
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );
        vm.stopPrank();
    }

    function test_drip_preventsReplayAttacks() external {
        _enableFaucetAuthModules();
        bytes32 nonce = faucetHelper.consumeNonce();
        bytes memory signature = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce
        );

        vm.startPrank(faucetContractAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );

        vm.expectRevert("Faucet: nonce has already been used");
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature)
        );
        vm.stopPrank();
    }

    function test_drip_beforeTimeout_reverts() external {
        _enableFaucetAuthModules();
        bytes32 nonce0 = faucetHelper.consumeNonce();
        bytes memory signature0 = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce0
        );

        vm.startPrank(faucetContractAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce0),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature0)
        );

        bytes32 nonce1 = faucetHelper.consumeNonce();
        bytes memory signature1 = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce1
        );

        vm.expectRevert("Faucet: auth cannot be used yet because timeout has not elapsed");
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce1),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature1)
        );
        vm.stopPrank();
    }

    function test_drip_afterTimeout_succeeds() external {
        _enableFaucetAuthModules();
        bytes32 nonce0 = faucetHelper.consumeNonce();
        bytes memory signature0 = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce0
        );

        vm.startPrank(faucetContractAdmin);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce0),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature0)
        );

        bytes32 nonce1 = faucetHelper.consumeNonce();
        bytes memory signature1 = issueProofWithEIP712Domain(
            faucetAuthAdminKey,
            bytes("GithubFam"),
            bytes(githubFam.version()),
            block.chainid,
            address(githubFam),
            fundsReceiver,
            abi.encodePacked(fundsReceiver),
            nonce1
        );

        vm.warp(startingTimestamp + 1 days + 1 seconds);
        faucet.drip(
            Faucet.DripParameters(payable(fundsReceiver), nonce1),
            Faucet.AuthParameters(githubFam, abi.encodePacked(fundsReceiver), signature1)
        );
        vm.stopPrank();
    }
}