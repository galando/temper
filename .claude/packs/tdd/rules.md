# TDD Pack

**Version:** 1.0.0
**Last Updated:** 2025-03-09

## Mandatory Rules (BLOCK if violated)
- Every new function/method must have a corresponding test
- Tests must be written BEFORE implementation (RED → GREEN → REFACTOR)
- Test names must describe the scenario being tested

## Quality Rules (WARN if violated)
- Tests should follow Given-When-Then structure
- Each test should verify one behavior
- Tests should be independent (no shared state between tests)
- Tests should be fast (unit tests < 100ms each)
- Mock external dependencies (APIs, databases, file system)

## Conventions (SUGGEST improvements)
- Use descriptive test names: `methodName_scenario_expectedResult`
- Group related tests in describe/context blocks
- Use test fixtures for complex setup

## TDD Workflow

### RED Phase: Write Failing Test

```
1. Determine what to test:
   - Read the task's expected behavior
   - Identify the public method/endpoint being added or changed
   - Identify edge cases from the spec

2. Find the right test file:
   - If modifying existing code → find its existing test file
   - If creating new code → create test file following project naming:
     - Java: src/test/java/{same-package}/{ClassName}Test.java
     - React: {ComponentName}.test.tsx (same directory or __tests__/)
     - Python: tests/test_{module_name}.py or {module}_test.py
     - Go: {file}_test.go (same package)

3. Write the test:
   - Use Given-When-Then structure
   - Test the happy path AND at least one error case
   - Mock external dependencies

4. Run the test → it MUST FAIL (RED)
   - If test passes unexpectedly: investigate before proceeding
```

### GREEN Phase: Implement

```
1. Write the MINIMAL code needed to pass the test
2. Follow patterns from adjacent code (see build.md pattern matching)
3. Do NOT add extra features or utilities
4. Run test → must PASS (GREEN)
```

### REFACTOR Phase: Clean Up

```
ONLY refactor when ALL of these are true:
- All tests are GREEN
- The improvement is obvious and low-risk
- It directly relates to the current task

After refactoring: run ALL tests again → must still pass
```

## When intent.md Exists (Scenario-Driven TDD)

When `/temper:plan` generates an intent.md with Gherkin scenarios, the TDD cycle becomes scenario-driven:

| TDD Phase | Without intent.md | With intent.md |
|-----------|-------------------|----------------|
| **What to test** | Read task spec, identify public methods | Read Gherkin scenario from intent.md |
| **RED** | Write test for expected behavior | Write test mapped to scenario name |
| **GREEN** | Minimal implementation | Minimal implementation |
| **REFACTOR** | Clean up if safe | Clean up if safe |

The RED-GREEN-REFACTOR cycle is the same. The input changes:
- Test names reference the scenario name
- Given block becomes test setup
- When block becomes action under test
- Then block becomes assertions
- Scenario coverage gate enforces all scenarios have passing tests

Intent.md scenarios drive WHAT to test. TDD pack enforces HOW (discipline, conventions, structure).

## Concrete TDD Examples

### Spring Boot Example

```
TASK: "Add endpoint GET /api/bookings/{id} that returns booking details"

TEST (RED):
  @Test
  void shouldReturnBookingById() {
      // Given
      Booking booking = new Booking(1L, "user@test.com", LocalDate.now());
      when(bookingService.findById(1L)).thenReturn(Optional.of(booking));

      // When
      var response = mockMvc.perform(get("/api/bookings/1"))
          .andReturn().getResponse();

      // Then
      assertThat(response.getStatus()).isEqualTo(200);
      assertThat(response.getContentAsString()).contains("user@test.com");
  }

  @Test
  void shouldReturn404WhenBookingNotFound() {
      // Given
      when(bookingService.findById(999L)).thenReturn(Optional.empty());

      // When/Then
      mockMvc.perform(get("/api/bookings/999"))
          .andExpect(status().isNotFound());
  }

RUN: ./mvnw test -pl booking-service → FAILS (controller doesn't exist yet) ✓
```

### React/TypeScript Example

```
TASK: "Add BookingCard component that displays booking summary"

TEST (RED):
  describe('BookingCard', () => {
    it('renders booking details', () => {
      const booking = {
        id: '1',
        guest: 'Jane Doe',
        checkIn: '2026-03-15',
        status: 'confirmed'
      };

      render(<BookingCard booking={booking} />);

      expect(screen.getByText('Jane Doe')).toBeInTheDocument();
      expect(screen.getByText('Mar 15, 2026')).toBeInTheDocument();
      expect(screen.getByText('Confirmed')).toBeInTheDocument();
    });

    it('calls onCancel when cancel button clicked', async () => {
      const onCancel = vi.fn();
      render(<BookingCard booking={mockBooking} onCancel={onCancel} />);

      await userEvent.click(screen.getByRole('button', { name: /cancel/i }));
      expect(onCancel).toHaveBeenCalledWith('1');
    });
  });

RUN: npm test -- BookingCard → FAILS (component doesn't exist yet) ✓
```

### Node/Express Example

```
TASK: "Add POST /api/users endpoint that creates a user"

TEST (RED):
  describe('POST /api/users', () => {
    it('creates a new user and returns 201', async () => {
      // Given
      const newUser = { email: 'test@example.com', name: 'Test User' };

      // When
      const response = await request(app)
        .post('/api/users')
        .send(newUser);

      // Then
      expect(response.status).toBe(201);
      expect(response.body).toMatchObject({
        id: expect.any(String),
        email: newUser.email,
        name: newUser.name
      });
    });

    it('returns 400 when email is missing', async () => {
      const response = await request(app)
        .post('/api/users')
        .send({ name: 'Test User' });

      expect(response.status).toBe(400);
      expect(response.body.error).toContain('email');
    });
  });

RUN: npm test -- users.test.js → FAILS (route doesn't exist yet) ✓
```

## Test File Location by Stack

| Stack | Test Location | Naming Convention |
|-------|---------------|-------------------|
| Spring Boot | `src/test/java/{package}/` | `{Class}Test.java` |
| React/TS | Same dir or `__tests__/` | `{Component}.test.tsx` |
| Node/Jest | Same dir or `__tests__/` | `{module}.test.js` |
| Python/pytest | `tests/` | `test_{module}.py` |
| Go | Same package | `{file}_test.go` |
| Rust | Same dir or `tests/` | `#[test]` in source |
