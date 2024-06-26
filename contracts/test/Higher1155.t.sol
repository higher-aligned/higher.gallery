// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Higher1155} from "src/Higher1155.sol";
import {IHigher1155, MintConfig} from "src/IHigher1155.sol";
import {IHigher1155Factory} from "src/IHigher1155Factory.sol";
import {MockERC1155TokenReceiver} from "test/MockERC1155TokenReceiver.sol";
import {MockHigherToken} from "test/MockHigherToken.sol";

contract Higher1155Test is Test {
    Higher1155 internal _higher1155;
    address internal _creator = makeAddr("creator");
    address internal _factory = makeAddr("factory");

    event Create(uint256 id);
    event Mint(uint256 indexed id, address minter, uint256 amount, string comment);
    event Upgraded(address indexed implementation);

    function setUp() external {
        _higher1155 = new Higher1155();
        vm.prank(_factory);
        _higher1155.initialize(_creator, "");
        vm.etch(_factory, hex"01");
    }

    function test_initialize(address creator, address factory, string calldata contractURI) external {
        vm.assume(creator != address(0));

        Higher1155 higher1155 = new Higher1155();

        vm.prank(factory);
        higher1155.initialize(creator, contractURI);

        assertEq(higher1155.owner(), creator);
        assertEq(higher1155.factory(), factory);
        assertEq(higher1155.contractURI(), contractURI);
    }

    function test_cannotInitializeTwice(address creator, string calldata contractURI) external {
        vm.assume(creator != address(0));

        Higher1155 higher1155 = new Higher1155();
        higher1155.initialize(creator, contractURI);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        higher1155.initialize(creator, contractURI);
    }

    function test_create(
        string calldata tokenURI,
        MintConfig calldata mintConfig,
        string calldata secondUri,
        MintConfig calldata secondMintConfig
    ) external {
        vm.expectEmit(address(_higher1155));
        emit Create(1);

        vm.prank(_creator);
        uint256 firstId = _higher1155.create(tokenURI, mintConfig);

        assertEq(firstId, 1);
        assertEq(_higher1155.uri(firstId), tokenURI);
        assertEq(_higher1155.mintConfig(firstId).price, mintConfig.price);

        // Create a second token to ensure that the id increments properly
        vm.expectEmit(address(_higher1155));
        emit Create(2);

        vm.prank(_creator);
        uint256 secondId = _higher1155.create(secondUri, secondMintConfig);

        assertEq(secondId, 2);
        assertEq(_higher1155.uri(secondId), secondUri);
        assertEq(_higher1155.mintConfig(secondId).price, secondMintConfig.price);
    }

    function test_createAsFactory(string calldata tokenURI, MintConfig calldata mintConfig) external {
        vm.expectEmit(address(_higher1155));
        emit Create(1);

        vm.prank(_factory);
        uint256 firstId = _higher1155.create(tokenURI, mintConfig);

        assertEq(firstId, 1);
        assertEq(_higher1155.uri(firstId), tokenURI);
        assertEq(_higher1155.mintConfig(firstId).price, mintConfig.price);
    }

    function test_cannotCreateAsUnauthorizedCreator(
        address unauthorizedCreator,
        string calldata tokenURI,
        MintConfig calldata mintConfig
    ) external {
        vm.assume(unauthorizedCreator != _creator && unauthorizedCreator != _factory);

        vm.expectRevert(abi.encodeWithSelector(IHigher1155.UnauthorizedCreator.selector, unauthorizedCreator));
        vm.prank(unauthorizedCreator);
        _higher1155.create(tokenURI, mintConfig);
    }

    struct MintParams {
        address minter;
        uint256 amount;
        string comment;
    }

    struct ERC20PermitParams {
        address owner;
        address spender;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function test_approveAndMint(
        string calldata tokenURI,
        MintConfig memory mintConfig,
        MintParams memory mintParams,
        ERC20PermitParams calldata permitParams
    ) external {
        vm.assume(mintParams.minter != address(_higher1155));

        mintConfig.price = bound(mintConfig.price, 0, 3.4028236692e38);
        mintParams.amount = bound(mintParams.amount, 0, 3.4028236692e38);
        mintConfig.maxSupply = bound(mintConfig.maxSupply, mintParams.amount, type(uint256).max);
        vm.warp(mintConfig.endTimestamp);

        MockHigherToken higherToken = new MockHigherToken();
        vm.mockCall(
            _factory, abi.encodeWithSelector(IHigher1155Factory.higherToken.selector), abi.encode(address(higherToken))
        );
        vm.mockCall(
            address(higherToken),
            abi.encodeWithSelector(
                IERC20Permit.permit.selector,
                permitParams.owner,
                permitParams.spender,
                permitParams.value,
                permitParams.deadline,
                permitParams.v,
                permitParams.r,
                permitParams.s
            ),
            abi.encode()
        );
        vm.mockCall(
            _factory,
            abi.encodeWithSelector(
                IHigher1155Factory.transferPayment.selector,
                mintParams.minter,
                _creator,
                mintParams.amount * mintConfig.price
            ),
            abi.encode()
        );

        setUpTokenReceiver(mintParams.minter);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectEmit(address(_higher1155));
        emit Mint(id, mintParams.minter, mintParams.amount, mintParams.comment);

        vm.prank(mintParams.minter);
        _higher1155.approveAndMint(
            permitParams.owner,
            permitParams.spender,
            permitParams.value,
            permitParams.deadline,
            permitParams.v,
            permitParams.r,
            permitParams.s,
            id,
            mintParams.amount,
            mintParams.comment
        );

        assertEq(_higher1155.balanceOf(mintParams.minter, id), mintParams.amount);
    }

    function test_mint(string calldata tokenURI, MintConfig memory mintConfig, MintParams memory mintParams) external {
        vm.assume(mintParams.minter != address(_higher1155));

        mintConfig.price = bound(mintConfig.price, 0, 3.4028236692e38);
        mintParams.amount = bound(mintParams.amount, 0, 3.4028236692e38);
        mintConfig.maxSupply = bound(mintConfig.maxSupply, mintParams.amount, type(uint256).max);
        vm.warp(mintConfig.endTimestamp);

        vm.mockCall(
            _factory,
            abi.encodeWithSelector(
                IHigher1155Factory.transferPayment.selector,
                mintParams.minter,
                _creator,
                mintParams.amount * mintConfig.price
            ),
            abi.encode()
        );

        setUpTokenReceiver(mintParams.minter);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectEmit(address(_higher1155));
        emit Mint(id, mintParams.minter, mintParams.amount, mintParams.comment);

        vm.prank(mintParams.minter);
        _higher1155.mint(id, mintParams.amount, mintParams.comment);

        assertEq(_higher1155.balanceOf(mintParams.minter, id), mintParams.amount);
    }

    function test_mintWithNoMaxSupply(
        string calldata tokenURI,
        MintConfig memory mintConfig,
        MintParams memory mintParams
    ) external {
        vm.assume(mintParams.minter != address(_higher1155));

        mintConfig.price = bound(mintConfig.price, 0, 3.4028236692e38);
        mintParams.amount = bound(mintParams.amount, 0, 3.4028236692e38);
        mintConfig.maxSupply = 0;
        vm.warp(mintConfig.endTimestamp);

        vm.mockCall(
            _factory,
            abi.encodeWithSelector(
                IHigher1155Factory.transferPayment.selector,
                mintParams.minter,
                _creator,
                mintParams.amount * mintConfig.price
            ),
            abi.encode()
        );

        setUpTokenReceiver(mintParams.minter);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectEmit(address(_higher1155));
        emit Mint(id, mintParams.minter, mintParams.amount, mintParams.comment);

        vm.prank(mintParams.minter);
        _higher1155.mint(id, mintParams.amount, mintParams.comment);

        assertEq(_higher1155.balanceOf(mintParams.minter, id), mintParams.amount);
    }

    function test_mintWithNoEndTimestamp(
        string calldata tokenURI,
        MintConfig memory mintConfig,
        MintParams memory mintParams,
        uint256 timestamp
    ) external {
        vm.assume(mintParams.minter != address(_higher1155));

        mintConfig.price = bound(mintConfig.price, 0, 3.4028236692e38);
        mintParams.amount = bound(mintParams.amount, 0, 3.4028236692e38);
        mintConfig.maxSupply = bound(mintConfig.maxSupply, mintParams.amount, type(uint256).max);
        mintConfig.endTimestamp = 0;
        vm.warp(timestamp);

        vm.mockCall(
            _factory,
            abi.encodeWithSelector(
                IHigher1155Factory.transferPayment.selector,
                mintParams.minter,
                _creator,
                mintParams.amount * mintConfig.price
            ),
            abi.encode()
        );

        setUpTokenReceiver(mintParams.minter);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectEmit(address(_higher1155));
        emit Mint(id, mintParams.minter, mintParams.amount, mintParams.comment);

        vm.prank(mintParams.minter);
        _higher1155.mint(id, mintParams.amount, mintParams.comment);

        assertEq(_higher1155.balanceOf(mintParams.minter, id), mintParams.amount);
    }

    function test_cannotMintMoreThanMaxSupply(
        string calldata tokenURI,
        MintConfig memory mintConfig,
        uint256 extra,
        string calldata comment
    ) external {
        vm.assume(extra > 0 && extra < type(uint256).max);

        mintConfig.maxSupply = bound(mintConfig.maxSupply, 1, type(uint256).max - extra);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHigher1155.MaxSupplyExceeded.selector, 0, mintConfig.maxSupply + extra, mintConfig.maxSupply
            )
        );
        _higher1155.mint(id, mintConfig.maxSupply + extra, comment);
    }

    function test_cannotMintAfterEndTimestamp(
        string calldata tokenURI,
        MintConfig memory mintConfig,
        uint256 amount,
        uint256 timedelta,
        string calldata comment
    ) external {
        vm.assume(timedelta > 0 && timedelta < type(uint256).max);

        mintConfig.maxSupply = bound(mintConfig.maxSupply, amount, type(uint256).max);
        mintConfig.endTimestamp = bound(mintConfig.endTimestamp, 1, type(uint256).max - timedelta);
        vm.warp(mintConfig.endTimestamp + timedelta);

        vm.prank(_creator);
        uint256 id = _higher1155.create(tokenURI, mintConfig);

        vm.expectRevert(
            abi.encodeWithSelector(IHigher1155.MintEnded.selector, block.timestamp, mintConfig.endTimestamp)
        );
        _higher1155.mint(id, amount, comment);
    }

    function test_upgrade(address owner, string calldata contractURI) external {
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(_higher1155), abi.encodeCall(IHigher1155.initialize, (owner, contractURI)));

        Higher1155 newImplementation = new Higher1155();

        vm.expectEmit(address(proxy));
        emit Upgraded(address(newImplementation));

        vm.prank(owner);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImplementation), "");
    }

    function test_cannotUpgradeAsNonOwner(address owner, address nonOwner, string calldata contractURI) external {
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(_higher1155), abi.encodeCall(IHigher1155.initialize, (owner, contractURI)));

        Higher1155 newImplementation = new Higher1155();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, (nonOwner)));
        vm.prank(nonOwner);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImplementation), "");
    }

    function setUpTokenReceiver(address tokenReceiver) internal {
        vm.assume(
            tokenReceiver > address(9) && tokenReceiver != 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
                && tokenReceiver != CONSOLE
        );

        vm.etch(tokenReceiver, type(MockERC1155TokenReceiver).runtimeCode);
    }
}
