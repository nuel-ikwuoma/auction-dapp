const hre = require('hardhat')

async function main() {
  const DeedToken = await hre.ethers.getContractFactory('DeedRegistry')
  const AuctionRegistry = await hre.ethers.getContractFactory('AuctionRegistry')

  const auctionRegistry = await AuctionRegistry.deploy()
  const deedToken = await DeedToken.deploy(
    'Deed Token',
    'DTN',
    auctionRegistry.address,
  )

  console.log(`Deployed AuctionRegistry at address ${auctionRegistry.address}`)
  console.log(`Deployed DeedToken at address ${deedToken.address}`)

  // write deployment address to JSON file

  //initialize AuctionRegistry
  await auctionRegistry.setDeedTokenContract(deedToken.address)
}

main()
  .then(() => {
    console.log('Deployment Successful!')
    process.exitCode = 0
  })
  .catch((err) => {
    console.error(err)
    process.exitCode = 1
  })
