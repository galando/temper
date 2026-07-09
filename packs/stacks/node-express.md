# Node.js + Express Stack

## Detection
- `package.json` with `express` dependency

## Validation Commands
- Build: `npm run build` (if TypeScript: `tsc`)
- Test: `npm test`
- Lint: `npm run lint`
- Type check: `npx tsc --noEmit` (if tsconfig.json exists)

## Patterns to Follow
- Async/await for all async operations (no callback chains)
- Express Router for route grouping
- Middleware for cross-cutting concerns (auth, logging, error handling)
- Central error handler middleware
- Input validation with Joi/Zod/class-validator
- Environment variables via dotenv or similar
- Structured JSON logging

## Test Patterns
- Jest or Vitest for unit tests
- Supertest for integration/API tests
- Mock external services
- Database: use test database or in-memory store
