# Contributing to User Manager for PostgreSQL

Thank you for your interest in contributing to **User Manager for PostgreSQL**!

## Core Architecture Principles

Before opening a pull request, please keep our core design philosophy in mind:

### Database First / Minimal Client Code
- **Favor Database Pushdown**: Anything that can be computed, filtered, transformed, or ordered directly in SQL should be done on the PostgreSQL server.
- **Minimal Client-side Logic**: Keep Flutter/Dart widgets and services clean, avoiding redundant client-side sorting or filtering logic when PostgreSQL can return it directly.

## Development Setup

1. **Prerequisites**:
   - Flutter SDK (stable channel, 3.29+)
   - Dart SDK (^3.10)
   - PostgreSQL (version 14 or higher for local testing)

2. **Clone and Install**:
   ```bash
   git clone git@github.com:dbroles/postgresql.git
   cd postgresql
   flutter pub get
   ```

3. **Running the App**:
   ```bash
   # Run on your desktop platform
   flutter run -d macos
   # or
   flutter run -d linux
   # or
   flutter run -d windows
   ```

## Testing & Quality Assurance

Before submitting changes, ensure all analysis and automated tests pass:

```bash
flutter analyze
flutter test
```

Please add unit or widget tests for any new features or bug fixes.

## Pull Requests

1. Fork the repository and create your branch from `master`.
2. Ensure your code conforms to `analysis_options.yaml`.
3. Follow the pull request template and link any relevant issues.
