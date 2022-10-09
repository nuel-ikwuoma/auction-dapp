const {
  loadFixture,
  time,
} = require('@nomicfoundation/hardhat-network-helpers')
const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('', function () {
  async function deployAuctionRegistryAndDeedToken() {
    const AuctionRegistry = await ethers.getContractFactory('AuctionRegistry')
    const DeedRegistry = await ethers.getContractFactory('DeedRegistry')

    const auctionRegistry = await AuctionRegistry.deploy()
    const deedRegistry = await DeedRegistry.deploy(
      'Deed Token',
      'DTN',
      auctionRegistry.address,
    )
    await auctionRegistry.setDeedTokenContract(deedRegistry.address)
    return { auctionRegistry, deedRegistry }
  }

  it('should register auction with the correct id', async function () {
    const { auctionRegistry, deedRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )

    const [deployer] = await ethers.getSigners()

    const deedId = 0
    const deedURI = ''
    // mint a deed
    await deedRegistry.registerDeed(deedId, deedURI)
    await deedRegistry.transferFrom(
      deployer.address,
      auctionRegistry.address,
      deedId,
    )
    const auctionIdOwner = await auctionRegistry.getOwnerOfAuctionId(deedId)
    // deed owner should be owner of deed's Id in auction registry
    expect(auctionIdOwner).to.equal(deployer.address)
  })

  it('should be able to create a new auction if registered with auction registry', async function () {
    const { auctionRegistry, deedRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )
    const [deployer] = await ethers.getSigners()

    const deedId = 0
    const deedURI = ''
    // mint a deed
    await deedRegistry.registerDeed(deedId, deedURI)
    await deedRegistry.transferFrom(
      deployer.address,
      auctionRegistry.address,
      deedId,
    )

    const ONE_DAY_IN_SECS = 24 * 60 * 60

    const name = 'Test Auction'
    const metadata = ''
    const startPrice = ethers.utils.parseEther('1')
    const deadline = (await time.latest()) + ONE_DAY_IN_SECS

    await auctionRegistry.createAuction(
      name,
      metadata,
      startPrice,
      deadline,
      deedId,
    )

    const auctionIdx = 0
    const res = await auctionRegistry.getAuction(auctionIdx)
    expect(res._name).to.equal(name)
    expect(res._metadata).to.equal(metadata)
    expect(res._startPrice.toString()).to.equal(startPrice.toString())
    expect(res._blockDeadlineToBidOnAuction.toString()).to.equal(
      String(deadline),
    )
    expect(res._owner).to.equal(deployer.address)
  })
})
