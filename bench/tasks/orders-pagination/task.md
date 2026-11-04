`GET /orders` returns every order at once, which is too slow for big shops. Add cursor pagination:

- A `limit` query parameter: default 20, at most 100. A limit that is not a whole number from 1 to 100 gets status 400 with a body `{"error": "..."}`.
- Orders come newest first by `created_at`, ties broken by `id`, highest first. The order is the same on every page.
- The response body is `{"items": [...], "next_cursor": ...}`. `next_cursor` is a string, or null on the last page.
- A `cursor` query parameter takes the `next_cursor` of the previous page. A cursor the server did not issue (malformed or tampered) gets status 400.
- An order created after the first page was fetched must not make a later page repeat or skip any order that existed when the first page was fetched.
