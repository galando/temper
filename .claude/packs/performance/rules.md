# Performance Pack

**Version:** 1.0.0
**Last Updated:** 2026-05-12

## Frontend Rules (WARN if violated)

- **Core Web Vitals**: Monitor LCP (< 2.5s), INP (< 200ms), CLS (< 0.1). Block if any metric exceeds 2x threshold without justification.
- **React memoization**: Wrap components that re-render without prop changes in `React.memo`. Use `useMemo` for expensive computations, `useCallback` for event handlers passed as props.
- **Bundle splitting**: Lazy-load routes with `React.lazy` + `Suspense`. Code-split on route boundaries. Block if single-chunk bundle exceeds 300KB gzipped without justification.
- **Image formats**: Use WebP or AVIF with `<picture>` fallback. Block JPEG/PNG for hero images or above-the-fold content without explicit size justification.
- **Lazy loading**: Use `loading="lazy"` on images below the fold. Use `IntersectionObserver` for component-level lazy rendering.
- **Render blocking**: Inline critical CSS, defer non-critical scripts. Block if render-blocking third-party scripts in `<head>` without `async`/`defer`.
- **Font loading**: Use `font-display: swap` or `optional`. Block if custom fonts block text rendering without fallback.

## Backend Rules (WARN if violated)

- **N+1 detection**: No database or API calls inside loops (`for`, `forEach`, `while`, `map`). Use batch queries with `WHERE id IN (...)` or `JOIN`. Block if loop body contains `db.query`, `Model.find`, `fetch`, `axios`, `http.request` without explicit batch/limit guard.
- **Pagination on unbounded queries**: All endpoints returning lists must accept `limit`/`offset` or `cursor` parameters. Enforce `LIMIT` clause at the database level. Block if `findAll()`, `SELECT *`, or unbounded list returned without pagination.
- **Cache TTL**: Cache expensive computations and frequently accessed data. Set explicit TTL. Warm caches on deploy for critical paths. Warn if cacheable endpoint has no cache headers or in-memory cache.
- **Query plan inspection**: For queries touching tables > 10K rows, verify `EXPLAIN` plan uses indexes. Block if full table scan on large tables without justification.
- **Connection pooling**: Use connection pools for database and HTTP clients. Block if creating new connections per request.
- **Async I/O**: No synchronous file I/O (`readFileSync`, `sync*` methods) in request handlers or event-loop contexts.
- **Race conditions**: Shared mutable state (counters, flags, caches) modified by concurrent requests must use atomic operations or synchronization. Block on non-atomic mutations in request handlers (`counter++`, `nextId++`, `state.value = ...` without mutex/lock/transaction). Warn on shared state without concurrency protection.

## Methodology Gate: Measure First

**BLOCK** on performance claims without baseline numbers.

Before making any performance optimization:
1. **Measure** the current state with a specific metric (ms, bytes, requests/sec)
2. **State** the target metric and where it comes from (SLA, user research, monitoring)
3. **Optimize** the smallest change that moves the metric
4. **Verify** the improvement with the same measurement

No "this should be faster" without a number. No "this is slow" without a baseline.

## Anti-Rationalizations

| Rationalization | Why It's Wrong |
|-----------------|----------------|
| "Premature optimization is the root of all evil" | Knuth said this about *micro-optimizations in hot paths*, not about N+1 queries or missing pagination. Fix structural problems early. |
| "The dataset is small right now" | Data grows. A query that works on 100 rows will kill production at 1M rows. Design for scale from day one. |
| "We can optimize later" | N+1 queries and missing pagination are architecture decisions, not optimizations. Fixing them later requires breaking API changes. |
| "It's fast on my machine" | Your machine has no latency, no contention, no cold caches. Measure in staging or production-like conditions. |
| "The user won't notice" | 100ms added per item in a list of 50 items = 5 seconds. Users notice 5 seconds. |
| "Caching will fix it" | Caching masks the problem, it doesn't fix it. Cache misses still hit the unoptimized path. Fix the query first. |
| "Bundle size doesn't matter" | Every KB matters on mobile networks. 300KB gzipped = 1.5s on 3G. Trim what you don't need. |
