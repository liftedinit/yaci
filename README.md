# yaci

`yaci` is a command-line tool that connects to a gRPC server and extracts blockchain data.

Tested with Cosmos SDK v0.50.x.

## Use-case

Off-chain indexing of block & transaction data.

## Requirements

- Go 1.23.1
- Docker & Docker Compose (optional)

## Features

- Ability to extract block and transaction chain data to various output formats:
  - JSON
  - TSV
  - PostgreSQL
- Supports server reflection; no need to specify the proto file.
- (Nested) `Any` type are properly decoded.
- Live monitoring of the blockchain.
- Batch extraction of data.

## Installation

To install the `yaci` tool, you need to have Go installed on your system. Then, you can use the following command to install `yaci`:

```sh
go install github.com/liftedinit/yaci@latest
```

The `yaci` binary will be installed in the `$GOPATH/bin` directory.

## Usage
The basic usage of the yaci tool is as follows:
```shell
yaci [command] [address] [flags]
```

## Commands

- `extract` - Extracts blockchain data to various output format.
- `version` - Prints the version of the tool. 

## Global Flags

- `-l`, `--logLevel` - The log level (default: "info")'

## Extract Command

Extract blockchain data and output it in the specified format.

## Flags

The following flags are available for all `extract` subcommand:

- `-t`, `--block-time` - The time to wait between each block extraction (default: 2s)
- `-s`, `--start` - The starting block height to extract data from (default: 1)
- `-e`, `--stop` - The stopping block height to extract data from (default: 1)
- `-k`, `--insecure` - Skip TLS certificate verification (default: false)'
- `--live` - Continuously extract data from the blockchain (default: false)
- `-r`, `--max-retries` - The maximum number of retries to connect to the gRPC server (default: 3)
- `-c`, `--max-concurrency` - The maximum number of concurrent requests to the gRPC server (default: 100)

### Subcommands

- `json` - Extracts blockchain data to JSON files.
- `tsv` - Extracts blockchain data to TSV files.
- `postgres` - Extracts blockchain data to a PostgreSQL database.

### JSON Subcommand

Extract blockchain data and output it in JSON format.

#### Usage

```
Usage:
  yaci extract json [address] [flags]
```

#### Flags

- `-o`, `--out` - The output directory to store the extracted data (default: "out")

#### Example

```shell
yaci extract json localhost:9090 -k -s 1 -e 100 -o ./data
```

This command will connect to the gRPC server running on `localhost:9090`, extract data from block height `1` to `100`, and store the extracted data in the `data` directory.

### TSV Subcommand

Extract blockchain data and output it in TSV format.

#### Usage

```
Usage:
  yaci extract tsv [address] [flags]
```

#### Flags

- `-o`, `--out` - The output directory to store the extracted data (default: "tsv")

#### Example

```shell
yaci extract tsv localhost:9090 -k -s 1 -e 100
```

This command will connect to the gRPC server running on `localhost:9090`, extract data from block height `1` to `100`, and store the extracted data in the `tsv` directory in the `blocks.tsv` and `transactions.tsv` files.

### PostgreSQL Subcommand

Extract blockchain data and output it to a PostgreSQL database.

#### Usage

```
Usage:
  yaci extract postgres [address] [psql-connection-string] [flags]
```


#### Example

```shell
yaci extract postgres localhost:9090 postgres://postgres:foobar@localhost/postgres -s 106000 -k --live -t 5
```

This command will connect to the gRPC server running on `localhost:9090`, continuously extract data from block height `106000` and store the extracted data in the `postgres` database. New blocks and transactions will be inserted into the database every 5 seconds.

## Demo

To run the demo, you need to have Docker installed on your system. Then, you can run the following command:

```shell
# Build and start the e2e environment
docker compose up --wait --build
```

Wait for the e2e environment to start. Then, open a new browser tab and navigate to http://localhost:3000/blocks?order=id.desc to view the blocks and to http://localhost:3000/transactions to view the transactions.

Run

```shell
docker compose down -v
```

to stop the e2e environment.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
