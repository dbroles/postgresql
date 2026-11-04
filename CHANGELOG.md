# Changelog

All notable changes to the "User Manager for PostgreSQL" project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - Upcoming

### Added
- **Role Categories & Custom Grouping**:
  - Local per-connection category storage in `SharedPreferences` scoped by `host:login:database` (`role_categories_<host>:<login>:<database>` and `savedRoleCategoryTemplates_<host>:<login>:<database>`), providing zero-setup compatibility with managed DBaaS platforms (AWS RDS, Google Cloud SQL, Azure, Neon, Supabase) without requiring PostgreSQL C-level superuser parameter privileges.
  - Extended category syntax (`name:order:color`) supporting custom order and hex color accent badges.
  - Collapsible category headers with role counts (`granted / total`) and persistent collapsed/expanded state.
  - Dedicated **Role Categories** tab in Settings with drag-to-reorder prioritization.
  - Category editor dialog supporting direct role assignment, real-time search across role names and descriptions, and bulk select/deselect.
  - Multi-Admin & Multi-Tenant Role Isolation: Scoped Settings category management and suggestions strictly to roles where the connected user has `ADMIN OPTION` (`grantable == true`).
- **Configurable Database Connection Parameter & Saved Connections**:
  - Added dedicated **Database** input in Connection Settings (defaulting to `postgres`), enabling seamless connections to DBaaS providers (Render, Railway, Neon, AWS RDS) that use custom database names.
  - Added **Saved Connections** chips in Connection Settings for one-tap switching between saved `username@host[:port]/database` profiles, with per-connection password storage in OS secure storage and single-click profile removal.
  - Enhanced the bottom connection status bar to display `username@host:<port>/database` (omitting `:<port>` when using the standard PostgreSQL port `5432`, as well as redundant `"Connected to"` and `"with ssl"` text) and automatically scroll as a continuous-loop ticker when long hostnames (such as AWS RDS endpoints) overflow the screen width.
- **User Duplication**:
  - Duplicate user action available from desktop AppBar and mobile details view.
  - Clones user configuration, attributes, and assigned role memberships (with grantable validation).
- **Password Generator & Onboarding Credentials**:
  - Cryptographically secure 16-character password generator (`casino` button).
  - "Copy Onboarding Credentials" button that generates a formatted credential summary and `postgresql://` connection URI ready to share with users.
  - Streamlined, always-visible password field in Create / Edit User dialogs.
- **Account Expiration Enhancements**:
  - "Expiring Soon" visual status indicators for accounts approaching their `VALID UNTIL` limit.
  - Single-row quick expiration date presets: **Expire Now**, **+30**, **+90**, and **+365**.
  - Platform-adaptive date picker (Material date picker on Desktop/Android/Linux, Cupertino wheel picker on iOS/macOS).
- **Granular Display Filters in Settings**:
  - Filter to hide ungrantable roles (`grantable = false`).
  - Filter to hide users where the connected user lacks admin options.
  - Independent visibility controls for Superusers and the Connected User.
- **Test Coverage**:
  - Expanded comprehensive automated test suite to 114 unit, widget, and live matrix integration tests covering PostgreSQL 16, 17, and 18.

### Changed
- Refined UI layout: strictly separating Users on the left (`rolcanlogin = true`) from Roles/Groups on the right (`rolcanlogin = false`).
- Compact single-row date presets in Create User dialog with horizontal scroll support.
- Shortened and cleaned up button labels and settings descriptions for improved mobile usability.
- Prepared and configured Android build metadata for Google Play Store publishing.

---

## [1.0.1] - 2026-10-27

### Added
- SignPath Windows code-signing integration for automated `.exe` installer signing.
- Automated macOS code-signing and Apple notarization in release workflow.

### Fixed
- GitHub Actions release workflow secret expressions.

---

## [1.0.0] - 2026-09-25

### Initial Release Milestones
- **Core PostgreSQL Architecture**:
  - PostgreSQL 16 & 17 support.
  - Database-first architecture with strict pushdown SQL queries for role catalog introspection.
  - Clean client-side model: Users on the left (`rolcanlogin = true`), Roles on the right (`rolcanlogin = false`).
  - Strict SQL injection prevention with identifier and literal escaping.
- **Authentication & Security**:
  - Mandatory SSL/TLS encryption support (`sslMode = require`) with live connection security status indicator.
  - Secure credential storage backed by OS-level keychains (Apple Keychain, Windows Credential Manager, Linux Secret Service / Keyring, Android KeyStore).
  - `CREATEROLE` permission model support (no `SUPERUSER` requirement for daily operation).
- **Role Attributes & Visualization**:
  - Visual attribute indicators for all 8 standard PostgreSQL role attributes (`SUPERUSER`, `INHERIT`, `CREATEROLE`, `CREATEDB`, `LOGIN`, `REPLICATION`, `BYPASSRLS`, `PASSWORD`).
  - Real-time grantor badges and multi-grantor tracking for external role memberships.
- **Role & User Management**:
  - Create, edit, and delete database users and roles.
  - Grant and revoke role memberships with `ADMIN OPTION` validation.
  - `VALID UNTIL` support for account expiration.
- **Multi-Platform Support & CI/CD**:
  - Desktop: macOS (Apple Silicon & Intel DMG), Windows (Inno Setup x64 Installer & MSIX for Microsoft Store), Linux (Debian `.deb` & tarball).
  - Mobile: iOS / iPadOS and Android.
  - Automated GitHub Actions release pipeline building cross-platform installers on git tag pushes.

