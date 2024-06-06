require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  gasReporter: {
    currency: "USD",
    token: "MATIC",
    outputFile: "gas-report.txt",
    noColors: true,
    coinmarketcap: process.env.CMC_API_KEY,
    enabled: process.env.GAS ? true : false,
  },
  networks: {
    opSepolia: {
      url: `https://opt-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      // accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 11155420,
    },
    op: {
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      // accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 10,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "opSepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimism.etherscan.io",
        },
      },
    ],
  },
  sourcify: {
    enabled: false,
  },
};
