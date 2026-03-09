# Security Pack

**Version:** 1.0.0
**Last Updated:** 2025-03-09

## Mandatory Rules (BLOCK if violated)
- Never concatenate user input into SQL queries — use parameterized queries
- Never render unsanitized user input in HTML — use framework escaping
- Never hardcode secrets, API keys, or passwords in source code
- Never log sensitive data (passwords, tokens, PII)
- Never expose stack traces to end users

## Quality Rules (WARN if violated)
- Validate all input at system boundaries (type, format, length, range)
- Use HTTPS for all external API calls
- Set appropriate CORS headers
- Use strong password hashing (bcrypt/scrypt/Argon2)
- Set token expiration (max 1 hour for access tokens)
- Apply rate limiting to authentication endpoints

## Architectural Constraints (BLOCK if violated)
- Authentication/authorization checks required on all non-public endpoints
- Sensitive data must be encrypted at rest
- External API calls must go through authenticated gateway
