// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Types } from "../libraries/Types.sol";
import { IValidatorManager } from "../L1/interfaces/IValidatorManager.sol";
import { Colosseum } from "../L1/Colosseum.sol";
import { L2OutputOracle } from "../L1/L2OutputOracle.sol";
import { ValidatorPool } from "../L1/ValidatorPool.sol";
import { ZKVerifier } from "../L1/ZKVerifier.sol";
import { Hashing } from "../libraries/Hashing.sol";
import { Proxy } from "../universal/Proxy.sol";
import { ColosseumTestData } from "./testdata/ColosseumTestData.sol";
import { Colosseum_Initializer } from "./CommonTest.t.sol";
import { MockL2OutputOracle } from "./ValidatorManager.t.sol";

contract MockColosseum is Colosseum {
    constructor(
        L2OutputOracle _l2Oracle,
        ZKVerifier _zkVerifier,
        uint256 _submissionInterval,
        uint256 _creationPeriodSeconds,
        uint256 _bisectionTimeout,
        uint256 _provingTimeout,
        bytes32 _dummyHash,
        uint256 _maxTxs,
        uint256[] memory _segmentsLengths,
        address _securityCouncil,
        address _zkMerkleTrie
    )
        Colosseum(
            _l2Oracle,
            _zkVerifier,
            _submissionInterval,
            _creationPeriodSeconds,
            _bisectionTimeout,
            _provingTimeout,
            _dummyHash,
            _maxTxs,
            _segmentsLengths,
            _securityCouncil,
            _zkMerkleTrie
        )
    {}

    function getChallenge(
        uint256 _outputIndex,
        address _challenger
    ) external view returns (Types.Challenge memory) {
        return challenges[_outputIndex][_challenger];
    }

    function isAbleToBisect(
        uint256 _outputIndex,
        address _challenger
    ) external view returns (bool) {
        return _isAbleToBisect(challenges[_outputIndex][_challenger]);
    }

    function hashPublicInput(
        Types.PublicInputProof calldata _proof
    ) external view returns (bytes32) {
        return _hashPublicInput(_proof.srcOutputRootProof.stateRoot, _proof.publicInput);
    }
}

// Test the implementations of the Colosseum
contract ColosseumTest is Colosseum_Initializer {
    MockColosseum mockColosseum;
    uint256 internal targetOutputIndex;
    mapping(address => bool) internal isChallenger;

    event ReadyToProve(uint256 indexed outputIndex, address indexed challenger);

    function nextSender(Types.Challenge memory _challenge) internal pure returns (address) {
        return _challenge.turn % 2 == 0 ? _challenge.challenger : _challenge.asserter;
    }

    function setUp() public virtual override {
        super.setUp();

        MockColosseum mockColosseumImpl = new MockColosseum(
            oracle,
            zkVerifier,
            submissionInterval,
            creationPeriodSeconds,
            bisectionTimeout,
            provingTimeout,
            DUMMY_HASH,
            MAX_TXS,
            segmentsLengths,
            address(securityCouncil),
            address(zkMerkleTrie)
        );
        vm.prank(multisig);
        Proxy(payable(address(colosseum))).upgradeTo(address(mockColosseumImpl));
        mockColosseum = MockColosseum(address(colosseum));

        vm.prank(trusted);
        pool.deposit{ value: trusted.balance }();
        vm.prank(asserter);
        pool.deposit{ value: asserter.balance }();

        // Submit genesis output
        uint256 nextBlockNumber = oracle.nextBlockNumber();
        // Roll to after the block number we'll submit
        warpToSubmitTime();
        vm.prank(pool.nextValidator());
        oracle.submitL2Output(bytes32(nextBlockNumber), nextBlockNumber, 0, 0);

        // Submit invalid output
        nextBlockNumber = oracle.nextBlockNumber();
        warpToSubmitTime();
        vm.prank(pool.nextValidator());
        oracle.submitL2Output(keccak256(abi.encode()), nextBlockNumber, 0, 0);

        vm.prank(challenger);
        pool.deposit{ value: challenger.balance }();
        isChallenger[challenger] = true;

        targetOutputIndex = oracle.latestOutputIndex();
    }

    function _getOutputRoot(address _sender, uint256 _blockNumber) private view returns (bytes32) {
        uint256 targetBlockNumber = ColosseumTestData.INVALID_BLOCK_NUMBER;
        if (_blockNumber == targetBlockNumber - 1) {
            return ColosseumTestData.PREV_OUTPUT_ROOT;
        }

        if (isChallenger[_sender]) {
            if (_blockNumber == targetBlockNumber) {
                return ColosseumTestData.TARGET_OUTPUT_ROOT;
            }
        } else if (_blockNumber >= targetBlockNumber) {
            return keccak256(abi.encode(_blockNumber));
        }

        return bytes32(_blockNumber);
    }

    function _newSegments(
        address _sender,
        uint8 _turn,
        uint256 _segStart,
        uint256 _segSize
    ) private view returns (bytes32[] memory) {
        uint256 segLen = colosseum.segmentsLengths(_turn - 1);

        bytes32[] memory arr = new bytes32[](segLen);

        for (uint256 i = 0; i < segLen; i++) {
            uint256 n = _segStart + i * (_segSize / (segLen - 1));
            arr[i] = _getOutputRoot(_sender, n);
        }

        return arr;
    }

    function _detectFault(
        Types.Challenge memory _challenge,
        address _sender
    ) private view returns (uint256) {
        if (_sender == _challenge.challenger && _sender != nextSender(_challenge)) {
            return 0;
        }

        uint256 segLen = colosseum.segmentsLengths(_challenge.turn - 1);
        uint256 start = _challenge.segStart;
        uint256 degree = _challenge.segSize / (segLen - 1);
        uint256 current = start + degree;

        for (uint256 i = 1; i < segLen; i++) {
            bytes32 output = _getOutputRoot(_sender, current);

            if (_challenge.segments[i] != output) {
                return i - 1;
            }

            current += degree;
        }

        revert("failed to select");
    }

    function _newChallenger(string memory name) private returns (address) {
        address newAddr = makeAddr(name);

        vm.deal(newAddr, 10 ether);
        vm.prank(newAddr);
        pool.deposit{ value: newAddr.balance }();
        isChallenger[newAddr] = true;

        return newAddr;
    }

    function _createChallenge(uint256 _outputIndex, address _challenger) private {
        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(_outputIndex);
        uint256 end = targetOutput.l2BlockNumber;
        uint256 start = end - oracle.SUBMISSION_INTERVAL();

        assertTrue(
            _getOutputRoot(targetOutput.submitter, end) != targetOutput.outputRoot,
            "not an invalid output"
        );

        bytes32[] memory segments = _newSegments(_challenger, 1, start, end - start);

        vm.prank(_challenger);
        colosseum.createChallenge(_outputIndex, bytes32(0), 0, segments);

        Types.Challenge memory challenge = mockColosseum.getChallenge(_outputIndex, _challenger);

        assertEq(challenge.asserter, targetOutput.submitter);
        assertEq(challenge.challenger, _challenger);
        assertEq(challenge.timeoutAt, block.timestamp + colosseum.BISECTION_TIMEOUT());
        assertEq(challenge.segments.length, colosseum.segmentsLengths(0));
        assertEq(challenge.segStart, start);
        assertEq(challenge.segSize, end - start);
        assertEq(challenge.turn, 1);
    }

    function _bisect(uint256 _outputIndex, address _challenger, address _sender) private {
        Types.Challenge memory challenge = mockColosseum.getChallenge(_outputIndex, _challenger);

        uint256 position = _detectFault(challenge, _sender);
        uint256 segSize = challenge.segSize / (colosseum.segmentsLengths(challenge.turn - 1) - 1);
        uint256 segStart = challenge.segStart + position * segSize;

        bytes32[] memory segments = _newSegments(_sender, challenge.turn + 1, segStart, segSize);

        vm.prank(_sender);
        // check that ReadyToProve event was emitted on the last bisection.
        if (challenge.turn + 1 == segmentsLengths.length) {
            vm.expectEmit(true, true, false, false);
            emit ReadyToProve(_outputIndex, _challenger);
        }
        colosseum.bisect(_outputIndex, challenge.challenger, position, segments);

        Types.Challenge memory newChallenge = mockColosseum.getChallenge(_outputIndex, _challenger);
        assertEq(newChallenge.turn, challenge.turn + 1);
        assertEq(newChallenge.segments.length, segments.length);
        assertEq(newChallenge.segStart, segStart);
        assertEq(newChallenge.segSize, segSize);
    }

    function _proveFault(
        uint256 _outputIndex,
        address _challenger
    ) private returns (bytes32 publicInputHash) {
        // get previous snapshot
        Types.CheckpointOutput memory prevOutput = oracle.getL2Output(_outputIndex);

        Types.Challenge memory challenge = mockColosseum.getChallenge(_outputIndex, _challenger);

        uint256 position = _detectFault(challenge, challenge.challenger);
        publicInputHash = _doProveFault(challenge.challenger, _outputIndex, position);

        assertEq(
            uint256(colosseum.getStatus(_outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.NONE)
        );

        Types.CheckpointOutput memory newOutput = oracle.getL2Output(_outputIndex);

        assertEq(newOutput.submitter, _challenger);
        assertEq(newOutput.outputRoot, bytes32(0));
        assertEq(prevOutput.timestamp, newOutput.timestamp);
        assertEq(prevOutput.l2BlockNumber, newOutput.l2BlockNumber);
    }

    function _doProveFault(
        address _challenger,
        uint256 _outputIndex,
        uint256 _position
    ) private returns (bytes32) {
        (
            Types.OutputRootProof memory srcOutputRootProof,
            Types.OutputRootProof memory dstOutputRootProof
        ) = ColosseumTestData.outputRootProof();
        Types.PublicInput memory publicInput = ColosseumTestData.publicInput();
        Types.BlockHeaderRLP memory rlps = ColosseumTestData.blockHeaderRLP();

        ColosseumTestData.ProofPair memory pp = ColosseumTestData.proofAndPair();

        (ColosseumTestData.Account memory account, bytes[] memory merkleProof) = ColosseumTestData
            .merkleProof();

        Types.PublicInputProof memory proof = Types.PublicInputProof({
            srcOutputRootProof: srcOutputRootProof,
            dstOutputRootProof: dstOutputRootProof,
            publicInput: publicInput,
            rlps: rlps,
            l2ToL1MessagePasserBalance: bytes32(account.balance),
            l2ToL1MessagePasserCodeHash: account.codeHash,
            merkleProof: merkleProof
        });

        vm.prank(_challenger);
        colosseum.proveFault(_outputIndex, _position, proof, pp.proof, pp.pair);

        return mockColosseum.hashPublicInput(proof);
    }

    function _dismissChallenge(uint256 txId) private {
        // confirm transaction without check condition
        vm.prank(guardian1);
        securityCouncil.confirmTransaction(txId);

        vm.prank(guardian2);
        securityCouncil.confirmTransaction(txId);
    }

    function test_constructor_succeeds() external {
        assertEq(address(colosseum.L2_ORACLE()), address(oracle), "oracle address not matched");
        assertEq(
            address(colosseum.ZK_VERIFIER()),
            address(zkVerifier),
            "zk verifier address not matched"
        );
        assertEq(colosseum.CREATION_PERIOD_SECONDS(), creationPeriodSeconds);
        assertEq(colosseum.BISECTION_TIMEOUT(), bisectionTimeout);
        assertEq(colosseum.PROVING_TIMEOUT(), provingTimeout);
        assertEq(colosseum.L2_ORACLE_SUBMISSION_INTERVAL(), submissionInterval);
        assertEq(colosseum.DUMMY_HASH(), DUMMY_HASH);
        assertEq(colosseum.MAX_TXS(), MAX_TXS);
        assertEq(colosseum.SECURITY_COUNCIL(), address(securityCouncil));
        assertEq(colosseum.ZK_MERKLE_TRIE(), address(zkMerkleTrie));
    }

    function test_initialize_succeeds() external {
        assertEq(colosseum.segmentsLengths(0), segmentsLengths[0]);
        assertEq(colosseum.segmentsLengths(1), segmentsLengths[1]);
        assertEq(colosseum.segmentsLengths(2), segmentsLengths[2]);
        assertEq(colosseum.segmentsLengths(3), segmentsLengths[3]);
    }

    function test_createChallenge_succeeds() external {
        _createChallenge(targetOutputIndex, challenger);
    }

    function test_createChallenge_otherChallenger_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);

        address otherChallenger = makeAddr("other challenger");

        vm.deal(otherChallenger, 1 ether);
        vm.prank(otherChallenger);
        pool.deposit{ value: requiredBondAmount }();

        _createChallenge(outputIndex, otherChallenger);

        // ensure that both challenges are enabled.
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );
        assertEq(
            uint256(colosseum.getStatus(outputIndex, otherChallenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );
    }

    function test_createChallenge_genesisOutput_reverts() external {
        uint256 segLen = colosseum.segmentsLengths(0);

        vm.prank(challenger);
        vm.expectRevert(Colosseum.NotAllowedGenesisOutput.selector);
        colosseum.createChallenge(0, bytes32(0), 0, new bytes32[](segLen));
    }

    function test_createChallenge_asAsserter_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(outputIndex);
        uint256 segLen = colosseum.segmentsLengths(0);

        vm.prank(targetOutput.submitter);
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, new bytes32[](segLen));
    }

    function test_createChallenge_existedChallenge_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );

        uint256 segLen = colosseum.segmentsLengths(0);
        vm.prank(challenger);
        vm.expectRevert(Colosseum.ImproperChallengeStatus.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, new bytes32[](segLen));
    }

    function test_createChallenge_withBadSegments_reverts() external {
        uint256 latestBlockNumber = oracle.latestBlockNumber();
        uint256 outputIndex = oracle.getL2OutputIndexAfter(latestBlockNumber);
        uint256 segLen = colosseum.segmentsLengths(0);

        vm.startPrank(challenger);

        // invalid segments length
        vm.expectRevert(Colosseum.InvalidSegmentsLength.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, new bytes32[](segLen + 1));

        bytes32[] memory segments = new bytes32[](segLen);

        // invalid output root of the first segment
        for (uint256 i = 0; i < segments.length; i++) {
            segments[i] = keccak256(abi.encodePacked("wrong hash", i));
        }
        segments[segLen - 1] = oracle.getL2Output(outputIndex).outputRoot;
        vm.expectRevert(Colosseum.FirstSegmentMismatched.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, segments);

        // invalid output root of the last segment
        for (uint256 i = 0; i < segments.length; i++) {
            segments[i] = keccak256(abi.encodePacked("wrong hash", i));
        }
        segments[0] = oracle.getL2Output(outputIndex - 1).outputRoot;
        segments[segLen - 1] = oracle.getL2Output(outputIndex).outputRoot;
        vm.expectRevert(Colosseum.LastSegmentMatched.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, segments);

        vm.stopPrank();
    }

    function test_createChallenge_notSubmittedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        uint256 segLen = colosseum.segmentsLengths(0);

        vm.prank(challenger);
        vm.expectRevert();
        colosseum.createChallenge(outputIndex + 1, bytes32(0), 0, new bytes32[](segLen));
    }

    function test_createChallenge_afterChallengeProven_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        test_proveFault_succeeds();

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.NONE)
        );

        uint256 segLen = colosseum.segmentsLengths(0);

        vm.prank(challenger);
        vm.expectRevert(Colosseum.OutputAlreadyDeleted.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, new bytes32[](segLen));
    }

    function test_createChallenge_afterChallengerTimedOut_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);

        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        _bisect(outputIndex, challenge.challenger, challenge.asserter);
        challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
        vm.warp(challenge.timeoutAt + 1);

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.CHALLENGER_TIMEOUT)
        );

        // the asserter calls the challengerTimeout() to close the timed out challenge.
        vm.prank(challenge.asserter);
        colosseum.challengerTimeout(outputIndex, challenge.challenger);

        _createChallenge(outputIndex, challenge.challenger);
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );
    }

    function test_createChallenge_afterDismissed_succeeds() external {
        uint256 outputIndex = targetOutputIndex;

        test_dismissChallenge_succeeds();

        _createChallenge(outputIndex, challenger);
    }

    function test_createChallenge_afterCreationPeriod_reverts() external {
        uint256 outputIndex = targetOutputIndex;

        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);
        // warp to creation deadline
        vm.warp(output.timestamp + colosseum.CREATION_PERIOD_SECONDS() + 1);

        bytes32[] memory segments = new bytes32[](0);
        vm.prank(challenger);
        vm.expectRevert(Colosseum.CreationPeriodPassed.selector);
        colosseum.createChallenge(outputIndex, bytes32(0), 0, segments);
    }

    function test_createChallenge_wrongFork_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        uint256 segLen = colosseum.segmentsLengths(0);

        vm.prank(challenger);
        vm.expectRevert(Colosseum.L1Reorged.selector);
        colosseum.createChallenge(
            outputIndex,
            bytes32(uint256(0x01)),
            block.number - 1,
            new bytes32[](segLen)
        );
    }

    function test_bisect_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        _bisect(outputIndex, challenge.challenger, challenge.asserter);
    }

    function test_bisect_finalizedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );

        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(outputIndex);
        vm.warp(targetOutput.timestamp + oracle.FINALIZATION_PERIOD_SECONDS() + 1);

        uint256 segLen = colosseum.segmentsLengths(challenge.turn);

        vm.prank(challenge.asserter);
        vm.expectRevert(Colosseum.OutputAlreadyFinalized.selector);
        colosseum.bisect(outputIndex, challenge.challenger, 0, new bytes32[](segLen));
    }

    function test_bisect_withBadSegments_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        uint256 position = _detectFault(challenge, challenge.asserter);
        uint256 segSize = challenge.segSize / (colosseum.segmentsLengths(challenge.turn - 1) - 1);
        uint256 segStart = challenge.segStart + position * segSize;

        bytes32[] memory segments = _newSegments(
            challenge.asserter,
            challenge.turn + 1,
            segStart,
            segSize
        );

        vm.startPrank(challenge.asserter);

        // invalid output of the first segment
        bytes32 firstSegment = segments[0];
        segments[0] = keccak256(abi.encodePacked("wrong hash", uint256(0)));
        vm.expectRevert(Colosseum.FirstSegmentMismatched.selector);
        colosseum.bisect(outputIndex, challenge.challenger, position, segments);

        // invalid output of the last segment
        segments[0] = firstSegment;
        segments[segments.length - 1] = challenge.segments[position + 1];
        vm.expectRevert(Colosseum.LastSegmentMatched.selector);
        colosseum.bisect(outputIndex, challenge.challenger, position, segments);

        vm.stopPrank();
    }

    function test_bisect_ifNotYourTurn_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        uint256 segLen = colosseum.segmentsLengths(challenge.turn);

        vm.prank(challenge.challenger);
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.bisect(outputIndex, challenge.challenger, 0, new bytes32[](segLen));
    }

    function test_bisect_whenAsserterTimedOut_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        uint256 segLen = colosseum.segmentsLengths(challenge.turn);

        vm.warp(challenge.timeoutAt + 1);
        vm.prank(challenge.asserter);
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.bisect(outputIndex, challenge.challenger, 0, new bytes32[](segLen));

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TIMEOUT)
        );
    }

    function test_bisect_whenChallengerTimedOut_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        _bisect(outputIndex, challenge.challenger, challenge.asserter);

        // update challenge
        challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);

        uint256 segLen = colosseum.segmentsLengths(challenge.turn);

        vm.warp(challenge.timeoutAt + 1);
        vm.prank(challenge.challenger);
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.bisect(outputIndex, challenge.challenger, 0, new bytes32[](segLen));

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.CHALLENGER_TIMEOUT)
        );
    }

    function test_bisect_cancelChallenge_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, otherChallenger);
        // Make it the challenger turn
        _bisect(outputIndex, otherChallenger, challenge.asserter);

        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        uint256 prevDeposit = pool.balanceOf(otherChallenger);
        uint256 pendingBond = pool.getPendingBond(outputIndex, otherChallenger);

        vm.prank(otherChallenger);
        colosseum.bisect(outputIndex, otherChallenger, 0, new bytes32[](0));

        // Ensure that the challenge has been deleted.
        assertEq(
            uint256(colosseum.getStatus(outputIndex, otherChallenger)),
            uint256(Colosseum.ChallengeStatus.NONE)
        );
        // Ensure that the pending bond has been refunded.
        vm.expectRevert("ValidatorPool: the pending bond does not exist");
        pool.getPendingBond(outputIndex, otherChallenger);
        assertEq(pool.balanceOf(otherChallenger), prevDeposit + pendingBond);
    }

    function test_bisect_cancelChallenge_senderNotChallenger_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, otherChallenger);
        // Make it the challenger turn
        _bisect(outputIndex, otherChallenger, challenge.asserter);

        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        vm.prank(challenger);
        vm.expectRevert(Colosseum.OnlyChallengerCanCancel.selector);
        colosseum.bisect(outputIndex, otherChallenger, 0, new bytes32[](0));
    }

    function test_proveFault_succeeds() public returns (bytes32 publicInputHash) {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(outputIndex);

        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.READY_TO_PROVE)
        );

        publicInputHash = _proveFault(outputIndex, challenge.challenger);

        (, bytes32 outputRoot, , ) = colosseum.deletedOutputs(outputIndex);
        assertEq(outputRoot, targetOutput.outputRoot);
        assertTrue(colosseum.verifiedPublicInputs(publicInputHash));
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.NONE)
        );
    }

    function test_proveFault_finalizedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenger)),
            uint256(Colosseum.ChallengeStatus.READY_TO_PROVE)
        );

        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(outputIndex);
        vm.warp(targetOutput.timestamp + oracle.FINALIZATION_PERIOD_SECONDS() + 1);

        vm.expectRevert(Colosseum.OutputAlreadyFinalized.selector);
        _doProveFault(challenger, outputIndex, 0);
    }

    // TODO(pangssu): Testing is impossible in the current state. It must be fixed without fail.
    // function test_proveFault_whenAsserterTimedOut_succeeds() external {
    //     uint256 outputIndex = targetOutputIndex;
    //
    //     _createChallenge(outputIndex, challenger);
    //
    //     Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);
    //
    //     assertEq(nextSender(challenge), challenge.asserter);
    //
    //     vm.warp(challenge.timeoutAt + 1);
    //     // check the asserter timeout
    //     assertEq(
    //         uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
    //         uint256(Colosseum.ChallengeStatus.ASSERTER_TIMEOUT)
    //     );
    //
    //     _proveFault(outputIndex, challenge.challenger);
    // }

    function test_proveFault_cancelChallenge_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, otherChallenger);
        while (mockColosseum.isAbleToBisect(outputIndex, otherChallenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, otherChallenger);
            _bisect(outputIndex, otherChallenger, nextSender(challenge));
        }

        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        uint256 prevDeposit = pool.balanceOf(otherChallenger);
        uint256 pendingBond = pool.getPendingBond(outputIndex, otherChallenger);
        Types.PublicInputProof memory _emptyProof;

        vm.prank(otherChallenger);
        colosseum.proveFault(outputIndex, 0, _emptyProof, new uint256[](0), new uint256[](0));

        // Ensure that the challenge has been deleted.
        assertEq(
            uint256(colosseum.getStatus(outputIndex, otherChallenger)),
            uint256(Colosseum.ChallengeStatus.NONE)
        );
        // Ensure that the pending bond has been refunded.
        vm.expectRevert("ValidatorPool: the pending bond does not exist");
        pool.getPendingBond(outputIndex, otherChallenger);
        assertEq(pool.balanceOf(otherChallenger), prevDeposit + pendingBond);
    }

    function test_dismissChallenge_succeeds() public {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);

        bytes32 publicInputHash = test_proveFault_succeeds();
        Types.CheckpointOutput memory newOutput = oracle.getL2Output(outputIndex);

        vm.prank(address(securityCouncil));
        colosseum.dismissChallenge(
            outputIndex,
            newOutput.submitter,
            output.submitter,
            output.outputRoot,
            publicInputHash
        );

        (, bytes32 outputRoot, , ) = colosseum.deletedOutputs(outputIndex);
        assertEq(outputRoot, bytes32(0));
        assertFalse(colosseum.verifiedPublicInputs(publicInputHash));
    }

    function test_dismissChallenge_notSecurityCouncil_reverts() external {
        test_proveFault_succeeds();

        vm.prank(makeAddr("not_security_council"));
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.dismissChallenge(0, address(0), address(0), bytes32(0), bytes32(0));
    }

    function test_dismissChallenge_outputNotDeleted_reverts() external {
        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.OutputNotDeleted.selector);
        colosseum.dismissChallenge(
            targetOutputIndex,
            address(0),
            address(0),
            bytes32(0),
            bytes32(0)
        );
    }

    function test_dismissChallenge_finalizedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(outputIndex);
        vm.warp(targetOutput.timestamp + oracle.FINALIZATION_PERIOD_SECONDS() + 1);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.OutputAlreadyFinalized.selector);
        colosseum.dismissChallenge(0, address(0), address(0), bytes32(0), bytes32(0));
    }

    function test_dismissChallenge_invalidOutputGiven_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);

        bytes32 publicInputHash = test_proveFault_succeeds();
        Types.CheckpointOutput memory newOutput = oracle.getL2Output(outputIndex);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.InvalidOutputGiven.selector);
        colosseum.dismissChallenge(
            outputIndex,
            newOutput.submitter,
            output.submitter,
            bytes32(0),
            publicInputHash
        );
    }

    function test_dismissChallenge_invalidAddressGiven_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);

        bytes32 publicInputHash = test_proveFault_succeeds();
        Types.CheckpointOutput memory newOutput = oracle.getL2Output(outputIndex);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.InvalidAddressGiven.selector);
        colosseum.dismissChallenge(
            outputIndex,
            address(0),
            output.submitter,
            output.outputRoot,
            publicInputHash
        );

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.InvalidAddressGiven.selector);
        colosseum.dismissChallenge(
            outputIndex,
            newOutput.submitter,
            address(0),
            output.outputRoot,
            publicInputHash
        );
    }

    function test_dismissChallenge_invalidPublicInput_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);

        test_proveFault_succeeds();
        Types.CheckpointOutput memory newOutput = oracle.getL2Output(outputIndex);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.InvalidPublicInput.selector);
        colosseum.dismissChallenge(
            outputIndex,
            newOutput.submitter,
            output.submitter,
            output.outputRoot,
            bytes32(0)
        );
    }

    function test_challengerTimeout_succeeds() public {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        _bisect(outputIndex, challenge.challenger, challenge.asserter);

        challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
        vm.warp(challenge.timeoutAt + 1);
        // check the challenger timeout
        assertEq(nextSender(challenge), challenge.challenger);
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.CHALLENGER_TIMEOUT)
        );

        vm.prank(challenge.asserter);
        colosseum.challengerTimeout(outputIndex, challenge.challenger);
    }

    function test_challengerNotCloseWhenAsserterTimeout_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        _createChallenge(outputIndex, challenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        assertEq(nextSender(challenge), challenge.asserter);

        vm.warp(challenge.timeoutAt + 1);
        // check the asserter timeout
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TIMEOUT)
        );
        // then challenger do not anything

        vm.warp(challenge.timeoutAt + colosseum.PROVING_TIMEOUT() + 1);
        // check the challenger timeout
        assertEq(
            uint256(colosseum.getStatus(outputIndex, challenge.challenger)),
            uint256(Colosseum.ChallengeStatus.CHALLENGER_TIMEOUT)
        );
    }

    function test_cancelChallenge_succeeds() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);

        assertEq(
            uint256(colosseum.getStatus(outputIndex, otherChallenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );

        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        assertEq(
            uint256(colosseum.getStatus(outputIndex, otherChallenger)),
            uint256(Colosseum.ChallengeStatus.ASSERTER_TURN)
        );

        uint256 prevDeposit = pool.balanceOf(otherChallenger);
        uint256 pendingBond = pool.getPendingBond(outputIndex, otherChallenger);

        vm.prank(otherChallenger);
        colosseum.cancelChallenge(outputIndex);

        // Ensure that the pending bond has been refunded.
        vm.expectRevert("ValidatorPool: the pending bond does not exist");
        pool.getPendingBond(outputIndex, otherChallenger);
        assertEq(pool.balanceOf(otherChallenger), prevDeposit + pendingBond);
    }

    function test_cancelChallenge_noChallenge_reverts() external {
        vm.expectRevert(Colosseum.CannotCancelChallenge.selector);
        colosseum.cancelChallenge(0);
    }

    function test_cancelChallenge_outputNotDeleted_reverts() external {
        uint256 outputIndex = targetOutputIndex;

        _createChallenge(outputIndex, challenger);

        vm.prank(challenger);
        vm.expectRevert(Colosseum.CannotCancelChallenge.selector);
        colosseum.cancelChallenge(outputIndex);
    }

    function test_cancelChallenge_senderNotChallenger_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);

        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        vm.prank(challenger);
        vm.expectRevert(Colosseum.OnlyChallengerCanCancel.selector);
        colosseum.cancelChallenge(outputIndex);
    }

    function test_cancelChallenge_whenChallengerTimedOut_reverts() external {
        uint256 outputIndex = targetOutputIndex;
        address otherChallenger = _newChallenger("other challenger");

        _createChallenge(outputIndex, otherChallenger);
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, otherChallenger);
        _bisect(outputIndex, otherChallenger, challenge.asserter);

        vm.warp(challenge.timeoutAt + 1);
        // The output root of the target output index was replaced by another challenge.
        test_proveFault_succeeds();

        vm.prank(otherChallenger);
        vm.expectRevert(Colosseum.ImproperChallengeStatusToCancel.selector);
        colosseum.cancelChallenge(outputIndex);
    }

    function test_forceDeleteOutput_succeeds() external {
        uint256 outputIndex = targetOutputIndex;

        _createChallenge(outputIndex, challenger);

        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        vm.prank(address(securityCouncil));
        colosseum.forceDeleteOutput(outputIndex);
    }

    function test_forceDeleteOutput_notSecurityCouncil_reverts() external {
        uint256 outputIndex = targetOutputIndex;

        vm.prank(address(1));
        vm.expectRevert(Colosseum.NotAllowedCaller.selector);
        colosseum.forceDeleteOutput(outputIndex);
    }

    function test_forceDeleteOutput_finalizedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;

        _createChallenge(outputIndex, challenger);

        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        vm.warp(oracle.finalizedAt(outputIndex) + 1);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.OutputAlreadyFinalized.selector);
        colosseum.forceDeleteOutput(outputIndex);
    }

    function test_forceDeleteOutput_alreadyDeletedOutput_reverts() external {
        uint256 outputIndex = targetOutputIndex;

        _createChallenge(outputIndex, challenger);

        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, challenger);

        while (mockColosseum.isAbleToBisect(outputIndex, challenge.challenger)) {
            challenge = mockColosseum.getChallenge(outputIndex, challenge.challenger);
            _bisect(outputIndex, challenge.challenger, nextSender(challenge));
        }

        vm.prank(address(securityCouncil));
        colosseum.forceDeleteOutput(outputIndex);

        vm.prank(address(securityCouncil));
        vm.expectRevert(Colosseum.OutputAlreadyDeleted.selector);
        colosseum.forceDeleteOutput(outputIndex);
    }

    function test_isInCreationPeriod_succeeds() external {
        uint256 outputIndex = targetOutputIndex;

        assertEq(colosseum.isInCreationPeriod(outputIndex), true);

        Types.CheckpointOutput memory output = oracle.getL2Output(outputIndex);
        vm.warp(output.timestamp + colosseum.CREATION_PERIOD_SECONDS() + 1);

        assertEq(colosseum.isInCreationPeriod(outputIndex), false);
    }
}

contract Colosseum_ValidatorSystemUpgrade_Test is Colosseum_Initializer {
    MockColosseum mockColosseum;
    MockL2OutputOracle mockOracle;
    uint256 internal targetOutputIndex;

    function setUp() public override {
        super.setUp();

        MockColosseum mockColosseumImpl = new MockColosseum(
            oracle,
            zkVerifier,
            submissionInterval,
            creationPeriodSeconds,
            bisectionTimeout,
            provingTimeout,
            DUMMY_HASH,
            MAX_TXS,
            segmentsLengths,
            address(securityCouncil),
            address(zkMerkleTrie)
        );
        vm.prank(multisig);
        Proxy(payable(address(colosseum))).upgradeTo(address(mockColosseumImpl));
        mockColosseum = MockColosseum(address(colosseum));

        address oracleAddress = address(oracle);
        MockL2OutputOracle mockOracleImpl = new MockL2OutputOracle(
            pool,
            valMgr,
            address(colosseum),
            submissionInterval,
            l2BlockTime,
            startingBlockNumber,
            startingTimestamp,
            finalizationPeriodSeconds
        );
        vm.prank(multisig);
        Proxy(payable(oracleAddress)).upgradeTo(address(mockOracleImpl));
        mockOracle = MockL2OutputOracle(oracleAddress);

        // Deploy ValidatorPool with new argument
        terminateOutputIndex = 0;
        poolImpl = new ValidatorPool({
            _l2OutputOracle: oracle,
            _portal: mockPortal,
            _securityCouncil: guardian,
            _trustedValidator: trusted,
            _requiredBondAmount: requiredBondAmount,
            _maxUnbond: maxUnbond,
            _roundDuration: roundDuration,
            _terminateOutputIndex: terminateOutputIndex
        });
        vm.prank(multisig);
        Proxy(payable(address(pool))).upgradeTo(address(poolImpl));

        // Submit outputs until ValidatorPool is terminated
        vm.prank(trusted);
        pool.deposit{ value: trusted.balance }();
        for (uint256 i; i <= terminateOutputIndex; i++) {
            _submitL2OutputV1();
        }

        // Only trusted validator can submit the first output with ValidatorManager
        _registerValidator(trusted, minActivateAmount);

        // Submit invalid output as asserter
        uint256 nextBlockNumber = oracle.nextBlockNumber();
        warpToSubmitTime();
        vm.prank(valMgr.nextValidator());
        oracle.submitL2Output(keccak256(abi.encode()), nextBlockNumber, 0, 0);

        // To create challenge, challenger also registers validator
        _registerValidator(challenger, minActivateAmount);

        targetOutputIndex = oracle.latestOutputIndex();
    }

    function _nextSender(Types.Challenge memory challenge) private pure returns (address) {
        return challenge.turn % 2 == 0 ? challenge.challenger : challenge.asserter;
    }

    function _getOutputRoot(address sender, uint256 blockNumber) private view returns (bytes32) {
        uint256 targetBlockNumber = ColosseumTestData.INVALID_BLOCK_NUMBER;
        if (blockNumber == targetBlockNumber - 1) {
            return ColosseumTestData.PREV_OUTPUT_ROOT;
        }

        // If asserter, wrong output after targetBlockNumber
        if (sender == trusted) {
            if (blockNumber < targetBlockNumber - 1) {
                return keccak256(abi.encode(blockNumber));
            } else {
                return keccak256(abi.encode());
            }
        }

        // If challenger, correct output always
        if (blockNumber == targetBlockNumber) {
            return ColosseumTestData.TARGET_OUTPUT_ROOT;
        } else {
            return keccak256(abi.encode(blockNumber));
        }
    }

    function _newSegments(
        address sender,
        uint8 turn,
        uint256 segStart,
        uint256 segSize
    ) private view returns (bytes32[] memory) {
        uint256 segLen = colosseum.segmentsLengths(turn - 1);

        bytes32[] memory arr = new bytes32[](segLen);

        for (uint256 i = 0; i < segLen; i++) {
            uint256 n = segStart + i * (segSize / (segLen - 1));
            arr[i] = _getOutputRoot(sender, n);
        }

        return arr;
    }

    function _getFirstSegments() private view returns (bytes32[] memory) {
        Types.CheckpointOutput memory targetOutput = oracle.getL2Output(targetOutputIndex);
        uint256 end = targetOutput.l2BlockNumber;
        uint256 start = end - oracle.SUBMISSION_INTERVAL();

        bytes32[] memory segments = _newSegments(challenger, 1, start, end - start);

        return segments;
    }

    function _bisect(uint256 outputIndex, address _challenger, address sender) private {
        Types.Challenge memory challenge = mockColosseum.getChallenge(outputIndex, _challenger);

        uint256 position = _detectFault(challenge, sender);
        uint256 segSize = challenge.segSize / (colosseum.segmentsLengths(challenge.turn - 1) - 1);
        uint256 segStart = challenge.segStart + position * segSize;

        bytes32[] memory segments = _newSegments(sender, challenge.turn + 1, segStart, segSize);

        vm.prank(sender);
        colosseum.bisect(outputIndex, challenge.challenger, position, segments);
    }

    function _detectFault(
        Types.Challenge memory challenge,
        address sender
    ) private view returns (uint256) {
        if (sender == challenge.challenger && sender != _nextSender(challenge)) {
            return 0;
        }

        uint256 segLen = colosseum.segmentsLengths(challenge.turn - 1);
        uint256 start = challenge.segStart;
        uint256 degree = challenge.segSize / (segLen - 1);
        uint256 current = start + degree;

        for (uint256 i = 1; i < segLen; i++) {
            bytes32 output = _getOutputRoot(sender, current);

            if (challenge.segments[i] != output) {
                return i - 1;
            }

            current += degree;
        }

        revert("failed to select faulty position");
    }

    function _getProof()
        private
        pure
        returns (ColosseumTestData.ProofPair memory, Types.PublicInputProof memory)
    {
        (
            Types.OutputRootProof memory srcOutputRootProof,
            Types.OutputRootProof memory dstOutputRootProof
        ) = ColosseumTestData.outputRootProof();
        Types.PublicInput memory publicInput = ColosseumTestData.publicInput();
        Types.BlockHeaderRLP memory rlps = ColosseumTestData.blockHeaderRLP();
        ColosseumTestData.ProofPair memory pp = ColosseumTestData.proofAndPair();
        (ColosseumTestData.Account memory account, bytes[] memory merkleProof) = ColosseumTestData
            .merkleProof();

        Types.PublicInputProof memory proof = Types.PublicInputProof({
            srcOutputRootProof: srcOutputRootProof,
            dstOutputRootProof: dstOutputRootProof,
            publicInput: publicInput,
            rlps: rlps,
            l2ToL1MessagePasserBalance: bytes32(account.balance),
            l2ToL1MessagePasserCodeHash: account.codeHash,
            merkleProof: merkleProof
        });

        return (pp, proof);
    }

    function test_createChallenge_callValidatorManager_succeeds() public {
        bytes32[] memory segments = _getFirstSegments();

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(IValidatorManager.isActive.selector, challenger)
        );
        vm.prank(challenger);
        colosseum.createChallenge(targetOutputIndex, bytes32(0), 0, segments);

        assertEq(assetMgr.totalValidatorKroBonded(challenger), bondAmount);
    }

    function test_createChallenge_notSatisfyCondition_reverts() external {
        bytes32[] memory segments = _getFirstSegments();

        vm.expectRevert(IValidatorManager.ImproperValidatorStatus.selector);
        vm.prank(makeAddr("other challenger"));
        colosseum.createChallenge(targetOutputIndex, bytes32(0), 0, segments);
    }

    function test_proveFault_callValidatorManager_succeeds()
        public
        returns (bytes32 publicInputHash)
    {
        test_createChallenge_callValidatorManager_succeeds();

        Types.Challenge memory challenge = mockColosseum.getChallenge(
            targetOutputIndex,
            challenger
        );
        uint128 beforeAsserterKro = assetMgr.totalValidatorKro(challenge.asserter);

        while (mockColosseum.isAbleToBisect(targetOutputIndex, challenger)) {
            _bisect(targetOutputIndex, challenger, _nextSender(challenge));
            challenge = mockColosseum.getChallenge(targetOutputIndex, challenger);
        }

        (ColosseumTestData.ProofPair memory pp, Types.PublicInputProof memory proof) = _getProof();

        uint256 position = _detectFault(challenge, challenge.challenger);

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(
                IValidatorManager.slash.selector,
                targetOutputIndex,
                challenger,
                challenge.asserter
            )
        );
        vm.prank(challenger);
        colosseum.proveFault(targetOutputIndex, position, proof, pp.proof, pp.pair);

        publicInputHash = mockColosseum.hashPublicInput(proof);

        assertEq(assetMgr.totalValidatorKro(challenge.asserter), beforeAsserterKro - bondAmount);
        assertEq(assetMgr.totalValidatorKro(challenger), minActivateAmount);
    }

    function test_dismissChallenge_callValidatorManager_succeeds() external {
        Types.CheckpointOutput memory output = oracle.getL2Output(targetOutputIndex);
        uint128 beforeAsserterKro = assetMgr.totalValidatorKro(output.submitter);

        bytes32 publicInputHash = test_proveFault_callValidatorManager_succeeds();

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(
                IValidatorManager.revertSlash.selector,
                targetOutputIndex,
                output.submitter
            )
        );
        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(
                IValidatorManager.slash.selector,
                targetOutputIndex,
                output.submitter,
                challenger
            )
        );
        vm.prank(address(securityCouncil));
        colosseum.dismissChallenge(
            targetOutputIndex,
            challenger,
            output.submitter,
            output.outputRoot,
            publicInputHash
        );

        assertEq(assetMgr.totalValidatorKro(output.submitter), beforeAsserterKro);
        assertEq(assetMgr.totalValidatorKro(challenger), minActivateAmount - bondAmount);

        // check if original output submitter gets output reward + challenge reward
        uint128 tax = (bondAmount * assetMgr.TAX_NUMERATOR()) / assetMgr.TAX_DENOMINATOR();
        uint128 challengeReward = bondAmount - tax;

        mockOracle.mockSetNextFinalizeOutputIndex(terminateOutputIndex + 1);
        vm.warp(oracle.finalizedAt(targetOutputIndex));
        _submitL2OutputV2(false);

        assertEq(
            assetMgr.reflectiveWeight(output.submitter),
            minActivateAmount + baseReward + challengeReward
        );
    }

    function test_forceDeleteOutput_callValidatorManager_succeeds() external {
        test_createChallenge_callValidatorManager_succeeds();

        Types.Challenge memory challenge = mockColosseum.getChallenge(
            targetOutputIndex,
            challenger
        );
        uint128 beforeAsserterKro = assetMgr.totalValidatorKro(challenge.asserter);

        while (mockColosseum.isAbleToBisect(targetOutputIndex, challenger)) {
            _bisect(targetOutputIndex, challenger, _nextSender(challenge));
            challenge = mockColosseum.getChallenge(targetOutputIndex, challenger);
        }

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(
                IValidatorManager.slash.selector,
                targetOutputIndex,
                securityCouncil,
                challenge.asserter
            )
        );
        vm.prank(address(securityCouncil));
        colosseum.forceDeleteOutput(targetOutputIndex);

        assertEq(assetMgr.totalValidatorKro(challenge.asserter), beforeAsserterKro - bondAmount);
        assertEq(assetMgr.totalValidatorKro(challenger), minActivateAmount);
    }

    function test_cancelChallenge_callValidatorManager_succeeds() external {
        address otherChallenger = asserter;
        _registerValidator(asserter, minActivateAmount);

        bytes32[] memory segments = _getFirstSegments();
        vm.prank(otherChallenger);
        colosseum.createChallenge(targetOutputIndex, bytes32(0), 0, segments);

        test_proveFault_callValidatorManager_succeeds();

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(IValidatorManager.unbondValidatorKro.selector, otherChallenger)
        );
        vm.prank(otherChallenger);
        colosseum.cancelChallenge(targetOutputIndex);

        assertEq(assetMgr.totalValidatorKroBonded(otherChallenger), 0);
    }

    function test_challengerTimeout_callValidatorManager_succeeds() external {
        test_createChallenge_callValidatorManager_succeeds();

        Types.Challenge memory challenge = mockColosseum.getChallenge(
            targetOutputIndex,
            challenger
        );
        _bisect(targetOutputIndex, challenger, challenge.asserter);

        challenge = mockColosseum.getChallenge(targetOutputIndex, challenger);
        vm.warp(challenge.timeoutAt + 1);

        // check the challenger timeout
        assertEq(_nextSender(challenge), challenger);
        assertTrue(
            colosseum.getStatus(targetOutputIndex, challenger) ==
                Colosseum.ChallengeStatus.CHALLENGER_TIMEOUT
        );

        vm.expectCall(
            address(valMgr),
            abi.encodeWithSelector(
                IValidatorManager.slash.selector,
                targetOutputIndex,
                challenge.asserter,
                challenger
            )
        );
        vm.prank(challenge.asserter);
        colosseum.challengerTimeout(targetOutputIndex, challenger);

        assertEq(assetMgr.totalValidatorKro(challenger), minActivateAmount - bondAmount);
    }
}
