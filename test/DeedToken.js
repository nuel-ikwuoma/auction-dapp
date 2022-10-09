const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers')
const { expect } = require('chai')
const { ethers } = require('hardhat')

const hre = require('hardhat')

describe('', function () {
  // fixture to setup deployments for both `AuctionRegistry` and `DeedRegistry`
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

  // deploy with correct name and symbol
  it('should deploy deed token with correct name and symbol', async function () {
    const tokenName = 'Deed Token'
    const tokenSymbol = 'DTN'
    const { deedRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )
    // name and symbol should be set correctly
    expect(await deedRegistry.name()).to.equal(tokenName)
    expect(await deedRegistry.symbol()).to.equal(tokenSymbol)
  })

  it('should return correct address for auction registry', async function () {
    const { deedRegistry, auctionRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )
    // auction registry address should be set correctly
    expect(await deedRegistry.getAuctionRegistry()).to.equal(
      auctionRegistry.address,
    )
  })

  it('should register deed token to the correct address', async function () {
    const { deedRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )
    const deedId = 0
    const deedURI = ''
    await deedRegistry.registerDeed(deedId, deedURI)
    const [deployer] = await ethers.getSigners()
    // should mint token to correct address
    expect(await deedRegistry.ownerOf(deedId)).to.equal(deployer.address)
  })
})
