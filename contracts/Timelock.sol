// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

error NoDepositFoundError(bytes32 depositId);
error NotValidTimeStampError(uint256 timestamp);
error AlreadyQueuedError(bytes32 txId);
error TimestampNotInRangeError(uint256 blockTimestamp, uint256 timestamp);
error NotQueuedError(bytes32 txId);
error TimestampNotPassedError(uint256 blockTimestmap, uint256 timestamp);
error TimestampExpiredError(uint256 blockTimestamp, uint256 expiresAt);
error TxFailedError();
error NotOwner(string msg);

contract Timelock {
    // Owner of the timelock contract
    address public owner;
    // A description of the timelocked wallet (e.g. Bob's Timelocked Family Wallet)
    string public description;

    // Ensures that only the owner of the Smart contract can access a resource (e.g. function calls, etc.)
    modifier onlyOwner() {
        require(owner == msg.sender, "Only Owner can execute this function");
        _;
    }

    // Ensures that only the timestamp passed meets the requirements (e.g. The timelock period has to be in the future)
    // @param _timestamp
    // @returns a boolean value
    modifier isValidTimestamp(uint256 _timestamp) {
        require(
            validTimestamp(_timestamp),
            "The timelock period has to be in the future"
        );
        _;
    }

    // Constant Variables
    // @param MIN_DELAY deposit.timestamp > block.timestamp + MIN_DELAY
    // @param MAX_DELAY deposit.timestamp , block.timestamp + MAX_DELAY
    // @param MAX_DELAY deposit.timestamp , block.timestamp + MAX_DELAY
    uint256 public constant MIN_DELAY = 10; // 10 s
    uint256 public constant MAX_DELAY = 172800; // 2 days = 172800 = 86400s * 2
    uint256 public constant GRACE_PERIOD = 432000; // 5 days = 432000 = 86400s * 5

    // Deposits struct/mapping
    struct Deposit {
        bytes32 depositId;
        string description;
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }

    // Maps an address to a list of Deposits
    mapping(address => Deposit[]) public deposits;

    // Maps a depositId to a Deposit
    mapping(bytes32 => Deposit) public depositIdToDeposit;

    // Maps a txId to a Deposit (tx id => queued)
    mapping(bytes32 => Deposit) public queued;

    // Events
    // Emits an event whenever a deposit occurs
    // @param _from which is the depositor
    // @param _to which is the receiver of the funds
    // @param _amount which is the amount to be transfered
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    event DepositedFundsEvent(
        address indexed _from,
        address indexed _to,
        uint256 _amount,
        uint256 _timestamp
    );
    // Emits an event whenever a deposit is updated
    // @param _description which is the description of the Deposit to update
    // @param _from which is the depositor
    // @param _to which is the receiver of the funds
    // @param _amount which is the amount to be transfered
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    event UpdatedDepositEvent(
        string _description,
        address indexed _from,
        address indexed _to,
        uint256 _amount,
        uint256 _timestamp
    );

    // Emits an event whenever a deposit is queued for withdrawal/transfer
    // @param _txId which is the id of the transaction to be queued (different from the depositId)
    // @param _target which is the target contract that will execute the transfer with the _func function
    // @param _to which is the receiver of the funds
    // @param _amount which is the amount to be transfered
    // @param _func which is the function on the target contract to be called that will execute the transfer
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    event QueuedEvent(
        bytes32 indexed _txId,
        address indexed _target,
        address indexed _to,
        uint256 _amount,
        string _func,
        uint256 _timestamp
    );
    // Emits an event whenever a queued transaction is executed (transferFunds() function call)
    // @param _txId which is the id of the transaction that was executed (different from the depositId)
    // @param _target which is the target contract that executed the transfer
    // @param _to which is the receiver of the funds
    // @param _amount which is the amount to be transfered
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    event ExecutedTxEvent(
        bytes32 indexed _txId,
        address indexed _target,
        address indexed _to,
        uint256 _amount,
        uint256 _timestamp
    );

    // Emits an event whenever a queued transaction is canceled
    // @param _txId which is the id of the transaction to be cancelled (different from the depositId)
    event CanceledTxEvent(bytes32 indexed txId);

    // Emits an event whenever a Deposit has been claimed by the receiver
    // @param _depositId
    event ClaimedDepositEvent(bytes32 indexed depositId);

    constructor(string memory _description, address _owner) {
        description = _description;
        owner = _owner;
    }

    // Enables contract to receive funds
    receive() external payable {}

    // Returns a computed version the Keccak-256 hash of the inputs
    // @param _description:
    // @param _from:
    // @param _to:
    // @param _amount:
    // @param _timestamp:
    // @returns a bytes32 representing the DepositId
    function getDepositTxId(
        string memory _description,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _timestamp
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(_description, _from, _to, _amount, _timestamp)
            );
    }

    // Evaluates if the timestamp is greater than the current time/block
    // @param _timestamp
    // @returns a boolean value
    function validTimestamp(uint256 _timestamp) internal view returns (bool) {
        return (block.timestamp) < _timestamp;
    }

    // Returns an array of all deposits made by the user calling the function
    // @return Deposit[] memory
    function getDeposits() public view returns (Deposit[] memory) {
        return deposits[msg.sender];
    }

    // Returns a specific deposit by depositId for the account calling the function, along with the index of the deposit in the array
    // @param _depositTxId which is the id that uniquely identifies the Deposit
    // @return deposit which is the deposit associated with the _depositTxId
    // @return index which is the index of the deposit in the array

    function getOneDeposit(bytes32 _depositTxId)
        public
        view
        returns (Deposit memory deposit, uint256 index)
    {
        for (uint256 i = 0; i < deposits[msg.sender].length; i++) {
            if (deposits[msg.sender][i].depositId == _depositTxId)
                return (deposits[msg.sender][i], i);
        }
    }

    // Deposits funds in the timelock contract for future withdrawal
    // @param _description which is a description of the Deposit itself
    // @param _to which is the receiver of the funds
    // @param _amount which is the amount to be transfered
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    function depositFunds(
        string memory _description,
        address _to,
        uint256 _amount,
        uint256 _timestamp
    ) public payable isValidTimestamp(_timestamp) {
        require(msg.sender.balance > _amount, "Balance is low. Add more funds");

        (bool sent, ) = payable(address(this)).call{value: _amount}("");
        require(sent, "Failed to send Ether");

        bytes32 depositId = getDepositTxId(
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp
        );

        deposits[msg.sender].push(
            Deposit(
                depositId,
                _description,
                msg.sender,
                _to,
                _amount,
                _timestamp,
                false
            )
        );

        // Update depositId => Deposit Mapping
        depositIdToDeposit[depositId] = Deposit(
            depositId,
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp,
            false
        );
        emit DepositedFundsEvent(msg.sender, _to, _amount, _timestamp);
    }

    // Returns a specific deposit by a _user and _depositTxId, along with the index of the deposit in the array
    // @param _user which is the account that initiated the Deposit
    // @param _depositTxId which is the id that uniquely identifies the Deposit
    // @return deposit which is the deposit associated with the _depositTxId
    // @return index which is the index of the deposit in the array
    function fetchDeposit(address _user, bytes32 _depositTxId)
        internal
        view
        returns (Deposit memory deposit, uint256 index)
    {
        // Deposit[] memory deposits[_user] = deposits[_user];
        for (uint256 i = 0; i < deposits[_user].length; i++) {
            if (deposits[_user][i].depositId == _depositTxId)
                return (deposits[_user][i], i);
        }
    }

    // Reimburses a user in case they decided to update their deposit with a smaller amount.
    // They get reimbursed the difference
    // @param _user
    // @param _amount
    function reimburseUser(address _user, uint256 _amount) internal {
        (bool sent, ) = payable(_user).call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    // Updates a specific deposit by _depositId
    // @param _depositId which is the id that uniquely identifies the Deposit
    // @param _description which is a description of the Deposit being updated
    // @param _to which is the account receiving the funds
    // @param _amount which is the amount to be transferred
    // @param _timestamp which is the time when the receiver can withdraw the funds (Also a wait period)
    function updateDeposit(
        bytes32 _depositId,
        string memory _description,
        address _to,
        uint256 _amount,
        uint256 _timestamp
    ) public payable isValidTimestamp(_timestamp) {
        (Deposit memory deposit, uint256 index) = getOneDeposit(_depositId);
        bytes32 depositId = getDepositTxId(
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp
        );
        require(_amount > 0, "AmountLowError");
        require(deposit.amount > 0, "NoDepositFoundError");

        if (_amount > deposit.amount) {
            // Ensure there is enough funds in the user account
            require(
                msg.sender.balance > (_amount - deposit.amount),
                "Balance low. Topup your account"
            );

            (bool sent, ) = payable(address(this)).call{
                value: _amount - deposit.amount
            }("");
            require(sent, "Failed to send Ether");
        } else if (_amount < deposit.amount) {
            reimburseUser(msg.sender, deposit.amount - _amount);
        }

        deposits[msg.sender][index] = Deposit(
            getDepositTxId(_description, msg.sender, _to, _amount, _timestamp),
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp,
            false
        );
        // Update depositId => Deposit Mapping
        require(
            depositIdToDeposit[deposit.depositId].amount > 0,
            "There is no deposit associated with this id"
        );

        // Delete old entry in the mapping
        delete depositIdToDeposit[deposit.depositId];

        // Update the mapping with new entry
        depositIdToDeposit[depositId] = Deposit(
            depositId,
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp,
            false
        );
        emit UpdatedDepositEvent(
            _description,
            msg.sender,
            _to,
            _amount,
            _timestamp
        );
    }

    // Removes a specific deposit from the deposits mapping
    // @param _depositor
    // @param _index
    function removeDepositByIndex(address _depositor, uint256 _index) internal {
        if (_index >= deposits[_depositor].length) return;

        deposits[_depositor][_index] = deposits[_depositor][
            deposits[_depositor].length - 1
        ];
        deposits[_depositor].pop();
    }

    // Returns a computed version the Keccak-256 hash of the inputs
    // @param _target:
    // @param depositId:
    // @param _func:
    // @returns a bytes32 representing the Transaction Id
    function getTxId(
        address _target, // Target Smart Contract to Execute
        bytes32 depositId, // The deposit Id (which contains all information about a deposit)
        string calldata _func // The function to run from the _target contract
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_target, depositId, _func));
    }

    // Evaluates if a specific transaction has been queued by its _txId
    // @param _txId
    // @returns a boolean value
    function isQueued(bytes32 _txId) public view returns (bool _isQueued) {
        if (queued[_txId].to != address(0)) return true;
    }

    // Cancels a queued transaction by it transaction id or _txId. Only callable by the owner of the contract
    // @param _txId which is the id of the queued transaction to cancel
    function cancel(bytes32 _txId) external onlyOwner {
        require(isQueued(_txId) == true, "NotQueuedError");
        // require(queued[_txId].amount > 0, "NotQueuedError");
        Deposit memory deposit = queued[_txId];
        (, uint256 index) = getOneDeposit(deposit.depositId);
        removeDepositByIndex(deposit.from, index);

        // Reimburse the depositor
        (bool ok, ) = (deposit.from).call{value: deposit.amount}("");
        require(ok, "Reimbursement Error");

        // Clear the memory
        delete queued[_txId];
        delete deposit;
        delete index;

        // Emit the event
        emit CanceledTxEvent(_txId);
    }

    // Queues a specific transaction for execution
    // @param _target which is the timelock factory contract that will call the _func function
    // @param _depositId which is the id that uniquely identifies the Deposit
    // @param _func which is the function to call from the target contract that will execute the transfer of funds
    function queue(
        address _target, // Target Smart Contract to Execute
        bytes32 _depositId, // The deposit Id (which contains all information about a deposit)
        string calldata _func // The function to run from the _target contract // returns (
    ) external onlyOwner {
        Deposit memory deposit = depositIdToDeposit[_depositId];
        bytes32 txId = getTxId(_target, _depositId, _func);

        // Ensure that the deposit has not been queued yet
        require(isQueued(txId) == false, "AlreadyQueuedError");

        // ---|---------------|---------------------------|-------
        //  block       block + MIN_DELAY           block + MAX_DELAY

        // Ensure the timestamp is within the allowed range
        require(
            deposit.timestamp > block.timestamp + MIN_DELAY &&
                deposit.timestamp < block.timestamp + MAX_DELAY,
            "TimestampNotInRangeError"
        );

        // Queue the deposit for execution by txId
        queued[txId] = deposit;

        // Emit an event
        emit QueuedEvent(
            txId,
            _target,
            deposit.to,
            deposit.amount,
            _func,
            deposit.timestamp
        );

        // Free Memory space
        delete deposit;
        delete txId;
    }

    // Executes an already queued transaction
    // @param _target which is the timelock factory contract that will call the _func function
    // @param _depositId which is the id that uniquely identifies the Deposit
    // @param _func which is the function to call from the target contract that will execute the transfer of funds
    function execute(
        address _target,
        bytes32 _depositId,
        string calldata _func
    ) external payable onlyOwner returns (bytes memory) {
        bytes32 txId = getTxId(_target, _depositId, _func);

        Deposit memory deposit = queued[txId];

        // Ensure the transaction is queued
        require(queued[txId].amount > 0, "NotQueuedError");
        // ----|-------------------|-------
        //  timestamp    timestamp + grace period

        // Ensure the delay has passed or been reached
        require(
            queued[txId].timestamp < block.timestamp,
            "TimestampNotPassedError"
        );

        // Ensure the grace period has not expired yet
        require(
            block.timestamp < queued[txId].timestamp + GRACE_PERIOD,
            "TimestampExpiredError"
        );

        // prepare data
        bytes memory data;
        data = abi.encodePacked(bytes4(keccak256(bytes(_func))), txId);

        // call target
        (bool ok, bytes memory res) = (deposit.to).call{value: deposit.amount}(
            data
        );
        require(ok, "TxFailedError");

        // Emit an event
        emit ExecutedTxEvent(
            txId,
            _target,
            deposit.to,
            deposit.amount,
            deposit.timestamp
        );

        // Free memory space
        delete queued[txId];
        delete deposit;
        delete data;

        // Return the receipt of the transaction/transfer
        return res;
    }

    // Claims funds from an already executed transaction. This will update the claimed field of an already executed Deposit/transaction
    // @param _depositId which is the id that uniquely identifies the Deposit
    function claim(bytes32 _depositId) public onlyOwner {
        (Deposit memory oneDeposit, uint256 index) = getOneDeposit(_depositId);

        // Ensure that the deposit has not been claimed yet
        require(
            oneDeposit.claimed == false &&
                depositIdToDeposit[_depositId].claimed == false,
            "This deposit has been claimed already"
        );

        // Update the claim field on the deposits mapping
        deposits[oneDeposit.from][index] = Deposit(
            _depositId,
            oneDeposit.description,
            oneDeposit.from,
            oneDeposit.to,
            oneDeposit.amount,
            oneDeposit.timestamp,
            true
        );
        // Update the claim field on the depositIdToDeposit mapping
        depositIdToDeposit[_depositId].claimed = true;

        // Free memory space
        delete oneDeposit;

        // Emit an event
        emit ClaimedDepositEvent(_depositId);
    }
}
