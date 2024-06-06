const main = async () => {
    const Bodhi = await ethers.getContractFactory('Bodhi')
    const bodhi = await Bodhi.deploy()
    await bodhi.deployed()
    console.log('Bodhi deployed to:', bodhi.address)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exitCode = 1
    })
