# React + TypeScript Stack

## Detection
- `package.json` with `react` dependency
- `tsconfig.json` present

## Validation Commands
- Build: `npm run build` (reads from package.json scripts)
- Test: `npm test` (reads from package.json scripts)
- Lint: `npm run lint` (if exists in scripts)
- Type check: `npx tsc --noEmit`

## Patterns to Follow
- Functional components with hooks (no class components)
- TypeScript interfaces for all props and state
- TailwindCSS utility classes for styling (if Tailwind detected)
- Custom hooks for shared logic (`use{Name}`)
- Context API for global state, `useState` for local state
- Error boundaries for graceful error handling
- Lazy loading for route-level code splitting

## Test Patterns
- Vitest or Jest + React Testing Library
- Test user behavior, not implementation details
- `render()` → `screen.getByRole()` → `userEvent.click()` → assert
- Mock API calls with MSW or vi.mock/jest.mock
