# VRF NFT Drawing

This contract allows an escrowed NFT to be fairly drawn in a raffle format backed by a Chainlink VRF contract.

## Contract Background

This contract has 2 safeguards: 
1. If no user claims the winning NFT the contest can be re-drawn
2. If desired, after a specific time window the NFT can be withdrawn by the owner. While this function is recommended it is not required in cases of a fully trustless raffle. However, issues with chainlink VRF not returning entropy could result in a frozen NFT. This is up to the raffle submitter to decide.

## User Flow

1. Create drawing
   1. Deploying drawing via factory, set nft information, timelock information, chainlink coordinator
   2. Start off drawing connected to a "raffle ticket" NFT (easy to do with any editioned 721 such as ZORA drops contracts)

2. Users in drawing can check if they've won and claim their nft
   1. If no user claims the nft within a TIME_CLAIM_PERIOD
      1. The admin can re-roll for another user
      2. [note]: this functionality can be disabled
   2. If the admin ADMIN_RECOVERY_PERIOD elapses
      1. The admin can withdraw the nft and repeat the process, etc. 
      2. [note]: this functionality can be disabled

## Getting started

1. Install forge/foundry: See https://book.getfoundry.sh/getting-started/installation
2. Setup git submodules: `git submodules init && git submodules update`
3. Run tests: `forge test`
4. Run tests w/ gas reports: `forge test --gas-report`
5. Run Deploy Script: `forge script ./script/SetupContractsScript.s.sol` (recommended to also verify with `forge script --verify`)

## Dependencies:

1. https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/
  a. Utilized for

2. https://github.com/smartcontractkit/chainlink/
  a. Chainlink smartcontractkit: 

## Deployments
1. Görli
   1. Factory: 0x71877Aa4ABbad79e0C93477020A41ff7e06AA746
2. Mainnet
   1. None yet, awaiting audit.