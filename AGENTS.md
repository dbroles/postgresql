# Database First / Minimal Client Code
- Always favor database pushdown: anything that can be computed, filtered, transformed, or ordered directly in SQL should be done in PostgreSQL.
- Keep client-side Dart code minimal, avoiding redundant sorting or filtering logic.
