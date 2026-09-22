APPLICATION OVERVIEW:
"User Manager for PostgreSQL" is a desktop administration client used to manage PostgreSQL (v14+) users, groups, and role privileges. It connects directly from the client machine to a user-specified PostgreSQL database.

WHAT TO EXPECT ON FIRST LAUNCH:
When the application starts, it attempts to connect to a local PostgreSQL instance (default localhost:5432). Because test machines do not have PostgreSQL running by default, the app will gracefully detect that the server is unreachable and automatically open the "Connection Settings" dialog. This is the expected and intended behavior.

PREREQUISITES TO TEST FULL CONNECTIVITY:
The application requires network access to a PostgreSQL server (version 14 or higher) with a role that has CREATEROLE permissions (the app intentionally restricts running directly as SUPERUSER for security best practices).

HOW TO TEST:

1. Testing Connection Error Handling (No database required):
   - Launch the app. Notice the app handles the unreachable local database gracefully and opens the "Connection Settings" screen.
   - Enter invalid credentials (e.g., host "192.0.2.1" or invalid password) and click "Save & Connect".
   - Verify that the app reports connection failures with a descriptive message without freezing or crashing.

2. Testing with a PostgreSQL Instance:
   - If you have an accessible PostgreSQL test server or local instance:
     * Host: [Insert your test host, or localhost]
     * Port: [5432]
     * Database: [postgres or test db]
     * Username: [role_admin_user]
     * Password: [password]
     * SSL Mode: [prefer / require / disable]
   - Click "Save & Connect".
   - Once connected:
     * The left panel displays database users (roles with LOGIN enabled).
     * Selecting a user displays their assigned role attributes (Superuser, Inherit, Create Role, etc.) and group memberships on the right panel.
     * Use the filter / view toggles (System roles, Ungrantable roles, etc.) to filter roles.
     * Click the settings gear icon in the app bar to modify connection settings or disconnect.

CREDENTIALS & SECURITY NOTES:
- Database passwords are saved locally using the Windows Data Protection API (DPAPI) via Windows Credential Manager.
- The app does not require any third-party online account, Microsoft login, registration, or subscription.
- No personal data or telemetry is sent to any external server.
