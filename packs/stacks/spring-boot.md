# Spring Boot Stack

## Detection
- `pom.xml` with spring-boot-starter dependency
- OR `build.gradle` with spring-boot plugin

## Validation Commands
- Compile: `./mvnw compile` or `./gradlew compileJava`
- Test: `./mvnw test` or `./gradlew test`
- Integration: `./mvnw verify -DskipUnitTests` or `./gradlew integrationTest`
- Coverage: `./mvnw jacoco:report` or `./gradlew jacocoTestReport`
- Build: `./mvnw package` or `./gradlew build`
- Lint: `./mvnw checkstyle:check` or `./gradlew checkstyleMain`
- Security: `./mvnw dependency-check:check` or `./gradlew dependencyCheckAnalyze`

## Patterns to Follow
- Use Spring Data JDBC (NOT JPA/Hibernate) unless project already uses JPA
- Constructor injection with `@RequiredArgsConstructor` (Lombok)
- DTOs for API responses — never expose entities directly
- Structured logging with SLF4J + Logback
- Use `@Transactional` for operations spanning multiple repository calls
- Use `Optional<T>` for nullable query results
- Repository interfaces extend `Repository<T, ID>` or `CrudRepository`

## Test Patterns
- JUnit 5 + Mockito for unit tests
- `@SpringBootTest` + Testcontainers for integration tests
- Test class per service/controller
- Given-When-Then structure in test methods
