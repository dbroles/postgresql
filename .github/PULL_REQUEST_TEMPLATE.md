## Description
Briefly describe the change, its purpose, and what problem it solves.

## Related Issue
Fixes #(issue number)

## Architecture & Database First
- [ ] Conforms to the "Database First" design rule: computation, filtering, and sorting are pushed down to PostgreSQL SQL queries rather than client-side Dart where applicable.
- [ ] No hardcoded passwords, credentials, or sensitive connection parameters.

## Checklist
- [ ] `flutter analyze` passes with 0 warnings or errors.
- [ ] `flutter test` passes with all tests succeeding.
- [ ] Added or updated automated unit/widget tests for changes.
