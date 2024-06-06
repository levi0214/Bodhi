const main = async () => {
    const SpaceFactory = await ethers.getContractFactory('SpaceFactory')
    const sf = await SpaceFactory.deploy()
    await sf.deployed()
    console.log('SpaceFactory deployed to:', sf.address)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exitCode = 1
    })
