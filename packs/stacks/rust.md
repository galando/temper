# Rust Stack

## Detection
- `Cargo.toml` present

## Validation Commands
- Test: `cargo test`
- Lint: `cargo clippy`
- Build: `cargo build`
- Format: `cargo fmt --check`
- Audit: `cargo audit`

## Patterns to Follow
- Standard Cargo project layout (the `src`, `tests` and `examples` folders)
- Use `Result<T, E>` for error handling
- Prefer `?` operator for error propagation
- Use `Arc<Mutex<T>>` for shared state when needed
- Leverage the borrow checker — avoid unnecessary clones
- Use serde for serialization/deserialization

## Test Patterns
- `#[test]` attributes in source or in the `tests` folder
- `#[cfg(test)]` modules for unit tests
- Use `assert!`, `assert_eq!`, `assert_ne!` macros
- Property-based testing with `proptest` or `quickcheck`
- Mock traits with `mockall` or manual implementations
