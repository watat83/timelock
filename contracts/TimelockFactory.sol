// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Timelock.sol";

contract TimelockFactory {
    // Timelock Smart Contract variable
    Timelock timelock;
    // Owner of the factory contract
    address public owner;

    // Mapping which stores all the wallets created by an account (account => wallet[])
    mapping(address => address[]) wallets;

    // Modifiers
    // Ensures that only the timelock contract can access a specific resource
    modifier onlyTimelock() {
        require(
            msg.sender == address(timelock),
            "Only Timelock can access this resource"
        );
        _;
    }

    // Events
    // Broadcast a event whenever a new Timelocked Contract is deployed and instantiated
    // @param _wallet which is the wallet newly created
    // @param _owner which is the account that created the wallet
    // @param _description which is a brief description of the wallet
    // @param _createdAt which is timestamp when the wallet was created
    event WalletCreatedEvent(
        address indexed _wallet,
        address indexed _owner,
        string _description,
        uint256 _createdAt
    );

    constructor(address payable _timelockContractAddress) {
        // initialize the timelock contract variable
        timelock = Timelock(_timelockContractAddress);
        // Set the owner of the timelock factory
        owner = msg.sender;
    }

    // Returns an array of wallets created by the account calling the function
    // @return _wallets
    function getWallets() public view returns (address[] memory _wallets) {
        return wallets[msg.sender];
    }

    // Returns an address of newly created wallet by the account calling the function
    // @param _description which is a description of the newly created wallet
    // @return wallet
    function newTimeLockedWallet(string memory _description)
        public
        returns (address wallet)
    {
        // Create new instance of the Timelock contract and return the address
        wallet = address(new Timelock(_description, msg.sender));

        // Store the wallet inside the wallets mapping for the current account
        wallets[msg.sender].push(wallet);

        // Emit an event
        emit WalletCreatedEvent(
            wallet,
            msg.sender,
            _description,
            block.timestamp
        );

        // Return the newly created wallet
        return wallet;
    }

    // Transfer funds to the recipient of the deposit. This can only be called by the timelock contract
    // @param _txId id of the transaction of be executed
    function transferFunds(bytes32 _txId) external payable onlyTimelock {
        (, , , address to, uint256 amount, , ) = timelock.queued(_txId);
        (bool sent, ) = payable(to).call{value: amount}("");
        require(sent, "Failed to send Ether");
    }
}
