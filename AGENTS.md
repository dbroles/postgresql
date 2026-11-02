# Database First / Minimal Client Code
- Always favor database pushdown: anything that can be computed, filtered, transformed, or ordered directly in SQL should be done in PostgreSQL.
- Keep client-side Dart code minimal, avoiding redundant sorting or filtering logic.

# Terminology: Users vs Roles
- Objects on the left (`rolcanlogin = true`) are **Users**.
- Objects on the right (`rolcanlogin = false`) are **Roles**.

