# foundry-template

this repository is for foundry setup

## To get started with foundry:

### Installation

- Install foundry for **Linux/Mac**: `curl -L https://foundry.paradigm.xyz | bash` -> `foundryup`;
- More about installation on Windows or Docker see [here](https://book.getfoundry.sh/getting-started/installation)

### Project setup

- To use this project, run:

```sh
  $ forge install
```

- If you need to create new project, run:

```sh
    $ forge-init
```

> By default, `forge-init` will also initialize a **new git repository**, install some submodules and create an **initial commit message**. If you do not want this behavior, pass `--no-git`

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to local:

```sh
$ forge script script/{ContractName}.s.sol --broadcast --fork-url http://localhost:8545
```

> For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
> [BIP39 mnemonic](https://iancoleman.io/bip39/).

> For instructions on how to deploy to a testnet or mainnet, check out the
> [Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ pnpm lint
```

### Test

Run the tests:

```sh
$ forge test
```

> To run tests on fork, add `----fork-url <your_rpc_url>`. More details [here](https://book.getfoundry.sh/forge/fork-testing)
