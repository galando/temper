# FastAPI Stack

## Detection
- `pyproject.toml` or `requirements.txt` with `fastapi` dependency

## Validation Commands
- Test: `pytest`
- Lint: `ruff check .` or `flake8`
- Type check: `mypy .`
- Format: `ruff format --check .` or `black --check .`
- Build: `python -m build` (if pyproject.toml has build config)

## Patterns to Follow
- Pydantic models for request/response validation
- Dependency injection via `Depends()`
- Async route handlers for I/O-bound operations
- SQLAlchemy or SQLModel for database access
- Alembic for database migrations
- Structured logging with `structlog` or `logging`

## Test Patterns
- Pytest + httpx AsyncClient for API tests
- Fixtures for database setup/teardown
- Factory Boy or manual fixtures for test data
- Mock external APIs with `respx` or `unittest.mock`
