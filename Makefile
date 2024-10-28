VERSION = v0.0.3

#### Build ####
build: ## Build the binary
	@echo "--> Building development binary"
	@go build -ldflags="-X github.com/liftedinit/yaci/cmd/yaci.Version=$(VERSION)" -o bin/yaci ./main.go

.PHONY: build

#### Test ####
test: ## Run tests
	@echo "--> Running tests"
	@go test -v -short -race ./...

test-e2e: ## Run end-to-end tests
	@echo "--> Running end-to-end tests"
	@go test -v -race ./cmd/yaci/postgres_test.go

.PHONY: test test-e2e

#### Docker ####
docker-up:
	@echo "--> Running docker compose up --build --wait -d"
	@docker compose -f docker/yaci.yml up --build --wait -d

docker-down:
	@echo "--> Running docker compose down -v"
	@docker compose -f docker/yaci.yml down -v

.PHONY: docker-up docker-down

####  Linting  ####
golangci_lint_cmd=golangci-lint
golangci_version=v1.61.0

lint:
	@echo "--> Running linter"
	@go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(golangci_version)
	@$(golangci_lint_cmd) run ./... --timeout 15m

lint-fix:
	@echo "--> Running linter and fixing issues"
	@go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(golangci_version)
	@$(golangci_lint_cmd) run ./... --fix --timeout 15m

.PHONY: lint lint-fix

#### FORMAT ####
goimports_version=v0.26.0

format: ## Run formatter (goimports)
	@echo "--> Running goimports"
	@go install golang.org/x/tools/cmd/goimports@$(goimports_version)
	@find . -name '*.go' -exec goimports -w -local github.com/liftedinit/yaci {} \;

.PHONY: format

#### GOVULNCHECK ####
govulncheck_version=v1.1.3

govulncheck: ## Run govulncheck
	@echo "--> Running govulncheck"
	@go install golang.org/x/vuln/cmd/govulncheck@$(govulncheck_version)
	@govulncheck ./...

.PHONY: govulncheck
