# Bodhi

Official repository for Bodhi contracts, including core protocol, peripheral contracts, and applications.

Bodhi is a protocol for content incentivization. It turns any [Arweave](https://arweave.org) ID into a speculative asset, just like a mini company. When more people buy its shares, the price goes up. [Learn more](#learn-more-about-bodhi).

## Contracts

Bodhi is deployed on [Optimism](https://www.optimism.io/) (an Ethereum layer 2). 

The entire protocol consists of just 100 lines of code, enabling you to understand it within 10 minutes. If you are interested in building on Bodhi, you can explore the application code, which is also straightforward and consists of only 60 lines of code.

### Core

**Bodhi.sol**

- **Contract Address**: [0x2ad82a4e39bac43a54ddfe6f94980aaf0d1409ef](https://optimistic.etherscan.io/address/0x2ad82a4e39bac43a54ddfe6f94980aaf0d1409ef#code)
- **Description**: This is the main contract, with 100 lines of code.

### Peripheral

**BodhiTradeHelper.sol**

- **Contract Address**: [0x59301bb28884b477dec0f238c60650b60a691eb9](https://optimistic.etherscan.io/address/0x59301bb28884b477dec0f238c60650b60a691eb9#code)
- **Description**: A stateless peripheral contract used to assist with trade functionalities, like slippage control.

### Applications

**SpaceFactory.sol / Space.sol**

- **Contract Address**: [0xa14d19387c83b56343fc2e7a8707986af6a74d08](https://optimistic.etherscan.io/address/0xa14d19387c83b56343fc2e7a8707986af6a74d08#code)
- **Description**: The first application on Bodhi, permissionless discussion groups (like Reddit), with 60 lines of code.

## Deploy in Local Environment (for developers)

To use the contracts in your local environment, follow these steps:

### Requirements

Ensure you have [Node.js](https://nodejs.org/) and [Hardhat](https://hardhat.org/) installed.

### Running a Local Node

```bash
npx hardhat node
```

### Deployments

**Deploy Bodhi Protocol**

```bash
npx hardhat run scripts/deploy.js --network localhost
```

**Deploy Peripheral Contract: Trade Helper**

```bash
npx hardhat run scripts/peripheral/deployTradeHelper.js --network localhost
```

**Deploy Application: Bodhi Space Factory**

```bash
npx hardhat run scripts/Space/deploy.js --network localhost
```

## Notice

This repository is migrated from the original repository. It omits unrelated code and all tests. We plan to migrate from Hardhat to Foundry in the future to enhance our development workflows.

## Learn More About Bodhi

[Bodhi: An Experiment to Solve Content Incentivization and Public Goods Funding Problem](https://bodhi.wtf/0)

[The First App on Bodhi](https://bodhi.wtf/14160)

[Understanding Bodhi (in Chinese)](https://bodhi.wtf/space/0/14464)

