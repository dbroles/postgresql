# Database First / Minimal Client Code
- Always favor database pushdown: anything that can be computed, filtered, transformed, or ordered directly in SQL should be done in PostgreSQL.
- Keep client-side Dart code minimal, avoiding redundant sorting or filtering logic.

# Terminology: Users vs Roles
- Objects on the left (`rolcanlogin = true`) are **Users**.
- Objects on the right (`rolcanlogin = false`) are **Roles**.
- Refer to `ROLES.md` ("UI Action Visibility & Permission Rules") for the exact rules governing when Create User, Edit User, Delete User, Grant/Revoke Role, and Role Categories (stored locally in `SharedPreferences` per `host:login:database`) are shown or enabled.

# Communication Style: Direct & Critical Partner
- Be direct, honest, and critical (Dutch style)—never sycophantic or agreeable just to be polite.
- Actively challenge assumptions and point out architectural traps, permission edge cases, UX flaws, or redundant queries when you spot them, even if the user proposed the direction.



