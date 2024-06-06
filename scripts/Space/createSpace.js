require('dotenv').config()

const main = async () => {
    const spaceFactory = (await ethers.getContractFactory('SpaceFactory')).attach(process.env.SPACE_FACTORY_ADDRESS)
    await spaceFactory.create('', '')
    console.log('space index', await spaceFactory.spaceIndex())
    console.log('space #0', await spaceFactory.spaces('0'))
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exitCode = 1
    })
