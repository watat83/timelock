const Timelock =  artifacts.require("Timelock");
const TimelockFactory =  artifacts.require("TimelockFactory");


module.exports = async function (deployer, network, accounts) {

    // Pass initial supply as argument of the deployer.
    await deployer.deploy(Timelock, "Family Timelock Funds", accounts[0]); 

    await deployer.deploy(TimelockFactory, await Timelock.address);

};