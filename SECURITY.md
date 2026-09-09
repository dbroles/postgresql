# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Considerations

**User Manager for PostgreSQL** interacts directly with database credentials, user accounts, and role privileges:
- Passwords are encrypted and stored exclusively within OS-native secure keychains (Apple Keychain, Windows Credential Manager, Linux Secret Service, Android KeyStore) via `flutter_secure_storage`.
- Passwords are never logged or stored in plain text configuration files.
- SSL/TLS connections can be enforced via connection settings.

## Reporting a Vulnerability

If you discover a potential security vulnerability in this project:

1. **Do not disclose the vulnerability publicly** in issues, discussions, or pull requests.
2. Please report the vulnerability privately via **[GitHub Private Vulnerability Reporting](https://github.com/dbroles/postgresql/security/advisories/new)** on the repository.
3. Include details of the vulnerability, steps to reproduce, and potential impact.

We will acknowledge receipt of your report within 48 hours and work with you on a fix and disclosure timeline.
