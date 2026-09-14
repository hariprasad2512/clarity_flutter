# Project Rules

This is a Dart / Flutter, Swift, C, C++, Kotlin, Shell Scripts, Documentation / Markdown project.

## Project Structure

<!-- TODO: Describe your project structure here -->
<!-- Example:
- `src/` - Application source code
- `tests/` - Test files
- `docs/` - Documentation
-->

## Code Standards

### Dart / Flutter

- Follow Effective Dart guidelines
- Use const constructors where possible
- Separate business logic from UI widgets

### Swift

- Follow Swift API design guidelines
- Use guard for early returns
- Prefer value types (structs) over reference types (classes)

### C

- Always check return values and handle errors
- Free allocated memory and avoid leaks
- Use header guards in all .h files

### C++

- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Follow the C++ Core Guidelines

### Kotlin

- Use data classes for DTOs
- Prefer val over var
- Use coroutines for async operations

### Shell Scripts

- Use set -euo pipefail at the start of scripts
- Quote all variable expansions
- Use functions for reusable logic

### Documentation / Markdown

- Use consistent heading levels
- Keep line length under 120 characters where practical
- Include code examples for technical documentation

## Commands

### Dart / Flutter

- **Build:** `flutter build`
- **Test:** `flutter test`
- **Lint:** `dart analyze`

### Swift

- **Build:** `swift build`
- **Test:** `swift test`
- **Lint:** `swiftlint`

### C

- **Build:** `make`
- **Test:** `make test`
- **Lint:** `cppcheck --enable=all .`

### C++

- **Build:** `cmake --build .`
- **Test:** `make test`
- **Lint:** `clang-tidy`

### Kotlin

- **Build:** `gradle build`
- **Test:** `gradle test`
- **Lint:** `gradle ktlintCheck`

### Shell Scripts

- **Test:** `bats test/`
- **Lint:** `shellcheck **/*.sh`

### Documentation / Markdown

- **Lint:** `markdownlint "**/*.md"`

## Custom Agents

The following custom subagents are available (invoke with `@agent-name`):

- **@backend-developer**: Server-side logic, APIs, and data processing
- **@mobile-developer**: Native and cross-platform mobile app development
- **@java-architect**: Java architecture, JVM tuning, and enterprise patterns
- **@kotlin-specialist**: Kotlin idioms, coroutines, and multiplatform development
- **@swift-expert**: Swift protocols, concurrency, and Apple platform APIs
- **@cpp-pro**: Modern C++ patterns, templates, and memory management
- **@spring-boot-engineer**: Spring Boot auto-config, DI, and reactive stack
- **@flutter-expert**: Flutter widgets, state management, and platform channels
- **@devops-engineer**: CI/CD pipelines, infrastructure, and deployment
- **@platform-engineer**: Internal developer platforms and self-service tooling
- **@sre-engineer**: Site reliability, monitoring, and incident response
- **@code-reviewer**: Code review with security and performance focus
- **@performance-engineer**: Performance profiling and optimization guidance
- **@cli-developer**: CLI tool design, argument parsing, and UX patterns
- **@dependency-manager**: Dependency updates, audit, and compatibility checks
- **@docs-writer**: Technical documentation and API reference writing
- **@git-workflow-manager**: Git workflow, branching strategy, and commit hygiene
- **@test-writer**: Test generation following project patterns
- **@embedded-systems**: Firmware, RTOS, and hardware interface programming
- **@game-developer**: Game engine integration, physics, and rendering pipelines
- **@mobile-app-developer**: Mobile UI/UX, app lifecycle, and platform guidelines
- **@technical-writer**: User guides, tutorials, and knowledge base articles

## Available Skills

The following skills are installed and will be loaded on demand:

- **git-release**: Release notes and version bumps
- **pr-review**: Structured PR review checklist
- **test-patterns**: Test generation following project conventions
- **deploy**: CI/CD pipeline and deployment setup
- **dependency-audit**: Audit dependencies for vulnerabilities and license issues
- **changelog-generate**: Changelog generation from commit history
- **ci-pipeline**: CI pipeline configuration and optimization
- **env-setup**: Development environment setup and onboarding

## Conventions

- Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
- Write meaningful commit messages that explain the "why"
- Keep PRs focused on a single concern
