// const  Web3  = require('web3');
// let web3 = new Web3(Web3.givenProvider || 'http://localhost:9545')

require('@openzeppelin/test-helpers/configure')({ environment: 'web3', provider: web3.currentProvider});
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');

let Timelock = artifacts.require('./Timelock');
let TimelockFactory = artifacts.require('./TimelockFactory');
let ethToDeposit = web3.utils.toWei("1", "ether");
let creator;
let bob;
let alice;
let timelockContract;
let timelockFactoryContract;
let timestamp;
let depositId;
let deposit;
let timelockedWallets;
let timelockedWalletInstance;


function getABIEntry(_contractArtifact, _parameterType, _parameterName){
    const abi = _contractArtifact.abi;
    const filtered = abi.filter((interface) => interface.type == _parameterType && interface.name == _parameterName)
    return filtered[0];
}

async function addDays(date, days) {
    var result = new Date(date);
    result.setDate(result.getDate() + days);
    return Date.parse(result);
}


contract('Timelock Factory', async (accounts, network, deployer) => {

    before("Deploy Contracts", async function() {
        web3Accounts = await web3.eth.getAccounts()
        creator = accounts[0] || web3Accounts[0];
        bob = accounts[1] || web3Accounts[1];
        alice = accounts[9] || web3Accounts[9];
        
        timelockContract = await Timelock.deployed();
        timelockFactoryContract = await TimelockFactory.deployed();
        timestamp = Date.parse("Sun Nov 27 2022 10:00:50 GMT-0800 (Pacific Standard Time)") / 1000
        
    });

    it('Initializes the contract with the correct values', async function() {
        assert.equal(await timelockFactoryContract.owner(), creator, 'Contract not owned by Timelock')
        assert.notEqual(await timelockFactoryContract.address, 0x0, 'The smart contract address was set')
    });

    it('Creates a new Timelocked Wallet Instance', async function() {
        await timelockFactoryContract.newTimeLockedWallet("Bob's Family Funds", {
            from: bob, 
            // gasPrice: '20000000000', // default gas price in wei, 20 gwei in this case,
            // transactionConfirmationBlocks: 3,
            // gasLimit: 500000
        })
        timelockedWallets = await timelockFactoryContract.getWallets({from:bob});

        timelockedWalletInstance = await new web3.eth.Contract(timelockContract.abi, timelockedWallets[0]);
        assert.equal(await timelockedWalletInstance.methods.owner().call(), bob, "The owner of the timelocked instance was not set properly")
        assert.equal(await timelockedWalletInstance.methods.description().call(), "Bob's Family Funds", "The description was not set properly")
    })
    it('Funds Smart Contracts Accounts', async function(){
 
        try {
            
            const receipt = await web3.eth.sendTransaction({
                from: String(accounts[7]),
                to:  String(timelockedWallets[0]),
                value:  String(await web3.utils.toWei("50", "ether")),
            })          
            assert.equal(await web3.eth.getBalance(timelockedWallets[0]), await web3.utils.toWei("50", "ether"), "Timelocked Wallet Not funded properly");
        } catch (error) {
            console.log(error)
        }
    })

    it('Deposits funds', async function() {
        try {
            await timelockedWalletInstance.methods.depositFunds("Tuition Fees 2022", alice, ethToDeposit, (timestamp)).send({from:bob, value:ethToDeposit, gas:"2100000"})
            
            depositId = await timelockedWalletInstance.methods.getDepositTxId("Tuition Fees 2022", bob,alice, ethToDeposit, (timestamp)).call({from:bob})
            const res = await (timelockedWalletInstance.methods.getOneDeposit(depositId)).call({from:bob})

            deposit = res[0]

            assert.equal(deposit.description, "Tuition Fees 2022", "Description was not properly set on the Deposit")
            assert.equal(deposit.from, bob, "The sender was not properly set on the Deposit")
            assert.equal(deposit.to, alice, "The receiver was not properly set on the Deposit")
        } catch (error) {
            console.log(error)
        }
    })

    it('Queues a Withdrawal transaction after the deposit', async function() {
        const abiEntry = await getABIEntry(TimelockFactory, "function", "transferFunds")

        try {
            const txId = await timelockedWalletInstance.methods.getTxId(
                timelockFactoryContract.address, // Target Smart Contract to Execute
                 depositId, // The deposit Id (which contains all information about a deposit)
                 abiEntry.name + "(bytes32)", // The function to run from the _target contract                   
            ).call({from:bob})

            const receipt = await timelockedWalletInstance.methods.queue(await timelockFactoryContract.address, depositId, abiEntry.name + "(bytes32)").send({from: bob, gas:"2100000"});
            
            assert.equal(receipt.events.QueuedEvent.event, "QueuedEvent", "The QueuedEvent was not fired")
            assert.equal(Number(receipt.events.QueuedEvent.returnValues._amount), ethToDeposit, "The amount is incorrect")
            assert.equal(await timelockedWalletInstance.methods.isQueued(txId).call({from:bob}), true, "Transaction was not properly queued")
            
        } catch (error) {
            console.log(error)
        }
        
    })
    it('Advances the time to execute the future transaction', async function(){
        const res = await timelockedWalletInstance.methods.getOneDeposit(depositId).call({from:bob});
        let currentBlock = await web3.eth.getBlock('latest');
        let blockTimestamp = currentBlock.timestamp;

        assert(res[0].timestamp > blockTimestamp, "TimestampNotPassedError")
        
        // Set a Future date. In this case, 1 days after the timestamp
        const futureDate = (await addDays(Date.parse(new Date(timestamp*1000)), 1))

        // Go Back to the Future (1 days after the timestamp)
        await time.increaseTo(futureDate/1000);

        currentBlock = await web3.eth.getBlock('latest');
        blockTimestamp = currentBlock.timestamp;

        // Ensure GRACE_PERIOD for executing the function has not expired yet: 
        // block.timestamp < deposit.timestamp + GRACE_PERIOD
        assert(
            res[0].timestamp + await timelockContract.GRACE_PERIOD() > blockTimestamp, 
            "TimestampExpiredError"
        )
    })

    it('Executes the Queued Transaction', async function() {
               
        const abiEntry = await getABIEntry(TimelockFactory, "function", "transferFunds")

        const userBalanceBeforeExecution = await web3.utils.fromWei(await web3.eth.getBalance(alice))
        const calculated = Number(await web3.utils.fromWei((ethToDeposit))) + Number(userBalanceBeforeExecution)
        try {
            // Execute the transaction
            const receiptExec = await timelockedWalletInstance.methods.execute(
                await timelockFactoryContract.address, 
                depositId, 
                abiEntry.name + "(bytes32)",
                
            ).send({from: bob, gas:"2100000"})
            
            assert.equal(Number(await web3.utils.fromWei(await web3.eth.getBalance(alice))).toFixed(3), calculated.toFixed(3), "The transfer of funds was not successful")
            
        } catch (error) {
            console.log(error)
        }
    })
    
    it('Updates the Claimed field of the Deposit to TRUE', async function(){
        await timelockedWalletInstance.methods.claim(depositId).send({from:bob, gas:"2100000"});
        const oneDeposit = await timelockedWalletInstance.methods.getOneDeposit(depositId).call({from:bob});
        const depositIdToDepositMapping = await timelockedWalletInstance.methods.depositIdToDeposit(depositId).call({from:bob});

        assert.equal(oneDeposit[0].claimed, true, "The Deposit was not updated successfully")
        assert.equal(depositIdToDepositMapping.claimed, true, "The depositIdToDepositMapping was not updated successfully")
    })

})
