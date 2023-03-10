// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import "../TestConstants.sol";
import "./NameRegistryConstants.sol";
import {NameRegistryHarness} from "../Utils.sol";

import {NameRegistry} from "../../src/NameRegistry.sol";
import {NameRegistryTestSuite} from "./NameRegistryTestSuite.sol";

/* solhint-disable state-visibility */
/* solhint-disable max-states-count */
/* solhint-disable avoid-low-level-calls */

contract NameRegistryTest is NameRegistryTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ChangeTrustedCaller(address indexed trustedCaller);
    event DisableTrustedOnly();
    event ChangeVault(address indexed vault);
    event ChangePool(address indexed pool);
    event ChangeFee(uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes16[] fnames = [bytes16("alice"), bytes16("bob"), bytes16("carol"), bytes16("dan")];

    uint256[] tokenIds = [ALICE_TOKEN_ID, BOB_TOKEN_ID, CAROL_TOKEN_ID, DAN_TOKEN_ID];

    /*//////////////////////////////////////////////////////////////
                           DEFAULT ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzGrantAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);
    }

    function testFuzzRevokeAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);

        vm.prank(defaultAdmin);
        nameRegistry.revokeRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);
    }

    function testFuzzCannotGrantAdminRoleUnlessDefaultAdmin(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.grantRole(ADMIN_ROLE, bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);
    }

    function testFuzzGrantDefaultAdminRole(address newDefaultAdmin) public {
        vm.assume(defaultAdmin != newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
    }

    function testFuzzCannotGrantDefaultAdminRoleUnlessDefaultAdmin(address newDefaultAdmin, address alice) public {
        _assumeClean(alice);
        vm.assume(alice != defaultAdmin);
        vm.assume(newDefaultAdmin != defaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);
    }

    function testFuzzRevokeDefaultAdminRole(address newDefaultAdmin) public {
        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);

        vm.prank(newDefaultAdmin);
        nameRegistry.revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), false);
        if (defaultAdmin != newDefaultAdmin) {
            assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
        }
    }

    function testFuzzCannotRevokeDefaultAdminRoleUnlessDefaultAdmin(address newDefaultAdmin, address alice) public {
        _assumeClean(alice);
        vm.assume(defaultAdmin != newDefaultAdmin);
        vm.assume(alice != defaultAdmin && alice != newDefaultAdmin);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
    }

    /*//////////////////////////////////////////////////////////////
                             MODERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzReclaimRegisteredNames(
        address[4] calldata users,
        address mod,
        address[4] calldata recoveryAddresses,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](13);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
            addresses[i + 8] = recoveryAddresses[i];
        }
        addresses[12] = mod;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewalTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recoveryAddresses[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }

        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        _assertBatchReclaimSuccess(users, destinations, renewalTs);
    }

    function testFuzzReclaimRegisteredNamesCloseToExpiryShouldExtend(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewalTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        // Fast forward to just before the renewals expire
        vm.warp(renewalTs - 1);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        _assertBatchReclaimSuccess(users, destinations, expectedExpiryTs);
    }

    function testFuzzReclaimExpiredNames(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        vm.warp(renewableTs);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        _assertBatchReclaimSuccess(users, destinations, expectedExpiryTs);
    }

    function testFuzzReclaimBiddableNames(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;
        _grant(MODERATOR_ROLE, ADMIN);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        vm.warp(biddableTs);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(ADMIN);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        _assertBatchReclaimSuccess(users, destinations, expectedExpiryTs);
    }

    function testFuzzReclaimResetsERC721Approvals(
        address[4] calldata users,
        address[4] calldata approveUsers,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](12);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = approveUsers[i];
            addresses[i + 8] = destinations[i];
        }
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        _grant(MODERATOR_ROLE, ADMIN);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            nameRegistry.approve(approveUsers[i], tokenIds[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }
        vm.prank(ADMIN);
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.getApproved(tokenIds[i]), address(0));
        }
    }

    function testFuzzReclaimWhenPaused(address[4] calldata users, address[4] calldata destinations) public {
        address[] memory addresses = new address[](8);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _grant(MODERATOR_ROLE, ADMIN);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }
        vm.prank(ADMIN);
        vm.expectRevert("Pausable: paused");
        nameRegistry.reclaim(reclaimActions);

        _assertBatchOwnership(users, tokenIds, renewableTs);
    }

    function testFuzzCannotReclaimIfRegistrable(address mod, address[4] calldata destinations) public {
        address[] memory addresses = new address[](5);
        for (uint256 i = 0; i < destinations.length; i++) {
            addresses[i] = destinations[i];
        }
        addresses[4] = mod;
        _assumeUniqueAndClean(addresses);
        _grant(MODERATOR_ROLE, mod);

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }

        vm.prank(mod);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.reclaim(reclaimActions);

        address[4] memory zeroAddresses = [address(0), address(0), address(0), address(0)];
        _assertBatchNoOwnership(destinations);
        _assertBatchRecoveryState(tokenIds, zeroAddresses, zeroAddresses, 0);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(nameRegistry.expiryTsOf(tokenIds[i]), 0);
            vm.expectRevert("ERC721: invalid token ID");
            assertEq(nameRegistry.ownerOf(tokenIds[i]), address(0));
        }
    }

    function testFuzzCannotReclaimUnlessModerator(
        address[4] calldata users,
        address[4] calldata destinations,
        address notModerator,
        address[4] calldata recoveryAddresses
    ) public {
        address[] memory addresses = new address[](13);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
            addresses[i + 8] = recoveryAddresses[i];
        }
        addresses[12] = notModerator;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 recoveryTs;
        for (uint256 i = 0; i < fnames.length; i++) {
            recoveryTs = _requestRecovery(users[i], tokenIds[i], recoveryAddresses[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }

        vm.prank(notModerator);
        vm.expectRevert(NameRegistry.NotModerator.selector);
        nameRegistry.reclaim(reclaimActions);

        _assertBatchNoOwnership(destinations);
        _assertBatchOwnership(users, tokenIds, renewableTs);
        _assertBatchRecoveryState(tokenIds, recoveryAddresses, recoveryAddresses, recoveryTs);
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeTrustedCaller(address alice) public {
        vm.assume(alice != nameRegistry.trustedCaller() && alice != address(0));

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice);
        nameRegistry.changeTrustedCaller(alice);

        assertEq(nameRegistry.trustedCaller(), alice);
    }

    function testFuzzCannotChangeTrustedCallerToZeroAddr(address alice) public {
        vm.assume(alice != nameRegistry.trustedCaller() && alice != address(0));
        address trustedCaller = nameRegistry.trustedCaller();

        vm.prank(ADMIN);
        vm.expectRevert(NameRegistry.InvalidAddress.selector);
        nameRegistry.changeTrustedCaller(address(0));

        assertEq(nameRegistry.trustedCaller(), trustedCaller);
    }

    function testFuzzCannotChangeTrustedCallerUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        address trustedCaller = nameRegistry.trustedCaller();
        vm.assume(bob != trustedCaller && bob != address(0));

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeTrustedCaller(bob);

        assertEq(nameRegistry.trustedCaller(), trustedCaller);
    }

    function testFuzzDisableTrustedCaller() public {
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();
        assertEq(nameRegistry.trustedOnly(), 0);
    }

    function testFuzzCannotDisableTrustedCallerUnlessAdmin(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.disableTrustedOnly();

        assertEq(nameRegistry.trustedOnly(), 1);
    }

    function testFuzzChangeVault(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        assertEq(nameRegistry.vault(), VAULT);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeVault(bob);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), bob);
    }

    function testFuzzCannotChangeVaultToZeroAddr(address alice) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), VAULT);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidAddress.selector);
        nameRegistry.changeVault(address(0));

        assertEq(nameRegistry.vault(), VAULT);
    }

    function testFuzzCannotChangeVaultUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        assertEq(nameRegistry.vault(), VAULT);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), VAULT);
    }

    function testFuzzChangePool(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        assertEq(nameRegistry.pool(), POOL);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangePool(bob);
        nameRegistry.changePool(bob);

        assertEq(nameRegistry.pool(), bob);
    }

    function testFuzzCannotChangePoolToZeroAddr(address alice) public {
        _assumeClean(alice);
        assertEq(nameRegistry.pool(), POOL);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidAddress.selector);
        nameRegistry.changePool(address(0));

        assertEq(nameRegistry.pool(), POOL);
    }

    function testFuzzCannotChangePoolUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        assertEq(nameRegistry.pool(), POOL);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changePool(bob);
    }

    /*//////////////////////////////////////////////////////////////
                             TREASURER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeFee(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);
        _grant(TREASURER_ROLE, alice);
        assertEq(nameRegistry.fee(), 0.01 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeFee(fee);
        nameRegistry.changeFee(fee);

        assertEq(nameRegistry.fee(), fee);
    }

    function testFuzzCannotChangeFeeUnlessTreasurer(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.changeFee(fee);
    }

    function testFuzzWithdrawFunds(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether - amount);
        assertEq(VAULT.balance, amount);
    }

    function testFuzzCannotWithdrawUnlessTreasurer(address alice, uint256 amount) public {
        _assumeClean(alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    function testFuzzCannotWithdrawInvalidAmount(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        amount = amount % AMOUNT_FUZZ_MAX;
        vm.deal(address(nameRegistry), amount);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.withdraw(amount + 1 wei);

        assertEq(address(nameRegistry).balance, amount);
        assertEq(VAULT.balance, 0);
    }

    function testFuzzCannotWithdrawToNonPayableAddress(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(ADMIN);
        nameRegistry.changeVault(address(this));

        vm.prank(alice);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    // Tests that cover pausing and its implications on other functions live alongside unit tests
    // for the functions

    function testFuzzCannotPauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.pause();
    }

    function testFuzzCannotUnpauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertBatchReclaimSuccess(
        address[4] calldata from,
        address[4] calldata to,
        uint256 expectedExpiryTs
    ) internal {
        for (uint256 i = 0; i < from.length; i++) {
            address[4] memory zeroAddresses = [address(0), address(0), address(0), address(0)];
            _assertBatchNoOwnership(from);
            _assertBatchOwnership(to, tokenIds, expectedExpiryTs);
            _assertBatchRecoveryState(tokenIds, zeroAddresses, zeroAddresses, 0);
        }
    }

    function _assertBatchNoOwnership(address[4] calldata addresses) internal {
        for (uint256 i = 0; i < addresses.length; i++) {
            assertEq(nameRegistry.balanceOf(addresses[i]), 0);
        }
    }

    function _assertBatchOwnership(
        address[4] calldata addresses,
        uint256[] memory fnameTokenIds,
        uint256 expiryTs
    ) internal {
        for (uint256 i = 0; i < addresses.length; i++) {
            assertEq(nameRegistry.balanceOf(addresses[i]), 1);
            assertEq(nameRegistry.expiryTsOf(fnameTokenIds[i]), expiryTs);
            assertEq(nameRegistry.ownerOf(fnameTokenIds[i]), addresses[i]);
        }
    }

    function _assertBatchRecoveryState(
        uint256[] memory fnameTokenIds,
        address[4] memory recovery,
        address[4] memory recoveryDestination,
        uint256 recoveryTs
    ) internal {
        for (uint256 i = 0; i < fnameTokenIds.length; i++) {
            assertEq(nameRegistry.recoveryOf(fnameTokenIds[i]), recovery[i]);
            assertEq(nameRegistry.recoveryTsOf(tokenIds[i]), recoveryTs);
            assertEq(nameRegistry.recoveryDestinationOf(tokenIds[i]), recoveryDestination[i]);
        }
    }
}