const {
  loadFixture,
  time,
} = require('@nomicfoundation/hardhat-network-helpers')
const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('Auction Registry', function () {
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

  it('should be able to create, bid and finalize a registered auction', async function () {
    const { auctionRegistry, deedRegistry } = await loadFixture(
      deployAuctionRegistryAndDeedToken,
    )
    const [
      deployer,
      bidderOne,
      bidderTwo,
      bidderThree,
    ] = await ethers.getSigners()

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
    const bidAmount = ethers.utils.parseEther('1.2')

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

    // `bidderOne` should be able to bid on auction
    await auctionRegistry
      .connect(bidderOne)
      .bidOnAuction(deedId, { value: bidAmount })
    const bids = await auctionRegistry.getBidsOnAuction(deedId)
    expect(bids.length).to.equal(1)

    // expect bid of a lesser amount to fail
    await expect(
      auctionRegistry
        .connect(bidderTwo)
        .bidOnAuction(deedId, { value: startPrice }),
    ).to.be.revertedWithCustomError(
      auctionRegistry,
      'AuctionRegistry__InvalidBidAmount',
    )
    // owner should not be able to bid on auction
    await expect(
      auctionRegistry.bidOnAuction(deedId),
    ).to.be.revertedWithCustomError(
      auctionRegistry,
      'AuctionRegistry__OwnerOfAuction',
    )
    // expect a bid past auction deadline to fail
    await time.increaseTo(deadline + 1)
    await expect(
      auctionRegistry.connect(bidderThree).bidOnAuction(deedId, {
        value: ethers.utils.parseEther('2'),
      }),
    ).to.be.revertedWithCustomError(
      auctionRegistry,
      'AuctionRegistry__DeadlineExpired',
    )
    // expect `anyone` to be able to finalize auction past deadline
    // and ether balance of `owner` should change by `lastBidAmount`
    await expect(
      auctionRegistry.connect(bidderThree).finalizeAuction(deedId),
    ).changeEtherBalance(deployer, bidAmount)

    // send auction to `last bidder`
    const newDeedOwner = await deedRegistry.ownerOf(deedId)
    await expect(newDeedOwner).to.equal(bidderOne.address)
  })
})
