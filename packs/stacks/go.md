# Go Stack

## Detection
- `go.mod` present

## Validation Commands
- Test: `go test ./...`
- Lint: `golangci-lint run`
- Build: `go build ./...`
- Vet: `go vet ./...`

## Patterns to Follow
- Standard Go project layout (cmd/, internal/, pkg/)
- Interfaces for dependency injection (accept interfaces, return structs)
- Error wrapping with `fmt.Errorf("...: %w", err)`
- Context propagation for cancellation and timeouts
- Table-driven tests
- Minimal dependencies — prefer stdlib

## Test Patterns
- `_test.go` files alongside source
- Table-driven tests with `t.Run()`
- `testify/assert` or stdlib `testing`
- `httptest` for HTTP handler tests
- Mock interfaces with generated mocks or manual implementations
