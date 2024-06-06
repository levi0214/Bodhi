const main = async () => {
    const bodhiAddress = process.env.BODHI_ADDRESS

    const TradeHelper = await ethers.getContractFactory('BodhiTradeHelper')
    const tradeHelper = await TradeHelper.deploy(bodhiAddress)
    await tradeHelper.deployed()
    console.log('tradeHelper deployed to:', tradeHelper.address)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exitCode = 1
    })
