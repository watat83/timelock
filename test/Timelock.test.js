
let Timelock = artifacts.require('./Timelock');
let TimelockFactory = artifacts.require('./TimelockFactory');
let ethToDeposit = web3.utils.toWei("0.05", "ether");
let bob;
let alice;
let timelockContract;
let timelockFactoryContract;
let timestamp;
let depositReceipt;
let depositId;
let deposit;


function getABIEntry(_contractArtifact, _parameterType, _parameterName){
    const abi = _contractArtifact.abi;
    const filtered = abi.filter((interface) => interface.type == _parameterType && interface.name == _parameterName)
    return filtered[0];
}

contract('Timelock', async function(accounts) {

    before("Deploy Contracts", async function() {
        bob = accounts[0];
        alice = accounts[1];
        timelockContract = await Timelock.deployed();
        timelockFactoryContract = await TimelockFactory.deployed();

        timestamp = Date.parse("Sun Nov 27 2022 10:00:50 GMT-0800 (Pacific Standard Time)") / 1000
    });

    it('Initializes the contract with the correct values', async function() {
        assert.equal(await timelockContract.description(), "Family Timelock Funds", 'The Timelock description was not set')
        assert.notEqual(await timelockContract.owner(), 0x0, 'The Owner of the smart contract was set')
        assert.notEqual(await timelockContract.address, 0x0, 'The smart contract address was set')
        assert.equal(await timelockContract.owner(), bob, 'The smart contract address was not set properly')
    });

    it('Funds Smart Contract Account', async function(){
        try {
            await web3.eth.sendTransaction({
                from: (bob),
                to:  (timelockContract.address),
                value:  (await web3.utils.toWei("5", "ether")),
            })
            assert.equal(await web3.eth.getBalance(timelockContract.address), await web3.utils.toWei("5", "ether"), "Contract Not funded properly")
            
        } catch (error) {
            console.log(error)
        }
    })

    it('Ensures the timestamp is in the future', async function() {
        try {
            
            let receipt = await timelockContract.depositFunds.call("Tuition Fees 2022", alice, ethToDeposit, Date.parse("2022-05-14") / 1000, {from:bob, value:ethToDeposit})
            assert.notEqual(receipt, true);
        } catch (error) {
            assert(error.message.indexOf('revert') >= 0, 'Timestamp is in the past. Should be in the future');
            return true;
        }
    })

    it('Deposits funds', async function() {

        depositReceipt = await timelockContract.depositFunds("Tuition Fees 2022", alice, ethToDeposit, (timestamp), {from:bob, value:ethToDeposit})
        depositId = await timelockContract.getDepositTxId("Tuition Fees 2022", bob,alice, ethToDeposit, (timestamp),{from:bob})
        res = (await timelockContract.getOneDeposit(depositId, {from:bob}))
        assert(res[0].amount > 0, "The deposit was not successful");
        
    })

    it('Ensures that the deposit was broadcasted to the network', async function() {
        
        let events = depositReceipt.logs.filter((log) => log.event == "DepositedFundsEvent");
        if (events.length > 0) {
            assert.equal(events[0].args._from, bob)
            assert.equal(events[0].args._to, alice)
            assert.equal(Number(events[0].args._amount), ethToDeposit)
            assert.equal(Number(events[0].args._timestamp), timestamp)
        } else{
            assert(false)
        }
    })

    it('Ensures that Deposit is updated properly', async function() {
        
        try {
            let receipt = await timelockContract.updateDeposit(depositId, "New Description", alice, await web3.utils.toWei("0.01", "ether"), (timestamp),{from:bob})
            let events = receipt.logs.filter((log) => log.event == "UpdatedDepositEvent");

            
            if (events.length > 0) {
                assert.equal(events[0].args._from, bob)
                assert.equal(events[0].args._to, alice)
                assert.equal((events[0].args._description), "New Description")
                assert.equal(Number(events[0].args._amount), +web3.utils.toWei("0.01", "ether"))
                assert.equal((events[0].args._timestamp), timestamp)
                assert.equal((events[0].event), "UpdatedDepositEvent")
            } else{
                assert(false)
            }

            
        } catch (error) {
            console.log(error)
        }
    })

    it('Queues a Withdrawal transaction after the deposit', async function() {
        depositId = await timelockContract.getDepositTxId("New Description", bob,alice, await web3.utils.toWei("0.01", "ether"), (timestamp),{from:bob})
        const abiEntry = await getABIEntry(TimelockFactory, "function", "transferFunds")
        // console.log(abiEntry)
        try {
            const txId = await timelockContract.getTxId(
                timelockFactoryContract.address, // Target Smart Contract to call
                 depositId, // The deposit Id (which contains all information about a deposit)
                 abiEntry.name + "(bytes32)", // The function to execute from the _target contract
                //   [], // Data to pass as argument to the function
                  {from:bob} 
            )
            let receipt = await timelockContract.queue(timelockFactoryContract.address, depositId, abiEntry.name + "(bytes32)", {from:bob})
                // console.log(receipt)
            assert.equal(receipt.logs[0].event, "QueuedEvent", "The QueuedEvent was not fired")
            assert.equal(Number(receipt.logs[0].args._amount), await web3.utils.toWei("0.01", "ether"), "The amount is incorrect")
            assert.equal(await timelockContract.isQueued(txId), true, "Transaction was not properly queued")

        } catch (error) {
            console.log(error)
        }

    })

    it('Cancels an already queued transaction', async function() {
        const bobBalance = +await web3.utils.fromWei(await web3.eth.getBalance(bob));
        const abiEntry = await getABIEntry(TimelockFactory, "function", "transferFunds")
        const txId = await timelockContract.getTxId(
            timelockFactoryContract.address, // Target Smart Contract to Execute
             depositId, // The deposit Id (which contains all information about a deposit)
             abiEntry.name + "(bytes32)", // The function to run from the _target contract
              {from:bob} 
        )
        let res1 = await timelockContract.getOneDeposit(depositId, {from:bob});
        await timelockContract.cancel(txId, {from:bob})
         let res2 = await timelockContract.getOneDeposit(depositId, {from:bob});

        assert.equal(res2[0].amount, 0, "Transaction was not properly removed from the user's Deposits")
        assert.equal(await timelockContract.isQueued(txId), false, "Transaction was not properly cancelled")
        assert.equal(
            Number(await web3.utils.fromWei(await web3.eth.getBalance(bob))).toFixed(3), 
            (bobBalance + Number(await web3.utils.fromWei(res1[0].amount))).toFixed(3), 
            "Bob was not properly reimbursed"
        )
    })

})