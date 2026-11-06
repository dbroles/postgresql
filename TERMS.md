# Terms of Service for User Manager for PostgreSQL

**Last Updated:** November 6, 2026  
**Effective Date:** September 11, 2026

These Terms of Service ("Terms") govern your use of **User Manager for PostgreSQL** ("the Application"), developed by Daniel van der Meulen ("we", "us", or "our"). By downloading, installing, or using the Application, you agree to be bound by these Terms.

---

## 1. Overview of the Application

**User Manager for PostgreSQL** is a client-side database administration utility that connects directly from your device to PostgreSQL database servers that you configure, allowing you to view and manage PostgreSQL users, roles, attributes, and role memberships.

- **Free & Open Source:** The Application is provided free of charge under the PostgreSQL / BSD-style open-source license (see [LICENSE](LICENSE)).
- **No Account Required:** We do not operate any backend servers, user accounts, or subscription services.

---

## 2. License to Use

Subject to these Terms and the [LICENSE](LICENSE) included with the source code, you are granted a non-exclusive, worldwide, royalty-free license to use, copy, modify, and distribute the Application and its documentation for personal, educational, or commercial purposes.

---

## 3. User Responsibilities and Database Administration Risks

Because the Application executes administrative SQL and Data Definition Language (DDL) statements—including `CREATE ROLE`, `ALTER ROLE`, `DROP ROLE`, `GRANT`, `REVOKE`, and `COMMENT ON ROLE`—directly against the PostgreSQL server(s) you connect to, you acknowledge and agree that:

1. **Authorized Access Only:** You will only connect the Application to PostgreSQL servers and databases that you own or are explicitly authorized to administer.
2. **Responsibility for Administrative Actions:** You are solely responsible for all commands executed, users created or deleted, passwords changed, and privileges granted or revoked through the Application.
3. **Principle of Least Privilege:** In accordance with PostgreSQL security best practices, the Application is designed to operate using a dedicated Role Admin account (`CREATEROLE` without `SUPERUSER`) rather than a PostgreSQL `SUPERUSER` account. You are responsible for properly configuring your database roles, Row-Level Security (RLS) policies, and object-level grants.
4. **Device & Network Security:** You are responsible for maintaining the security of your device, operating system credential store, and network connection (including selecting an appropriate SSL/TLS mode such as `require` when connecting over untrusted networks).
5. **Backups:** You are solely responsible for maintaining adequate backups of your PostgreSQL cluster and catalog state before performing administrative changes.

---

## 4. Privacy and Data Handling

The Application does not collect, transmit, or store any personal data, telemetry, or database credentials on any external server operated by us or any third party. All database connections occur directly between your device and your configured PostgreSQL server.

For complete details on how credentials and local preferences are handled, please review our [Privacy Policy (PRIVACY.md)](PRIVACY.md).

---

## 5. Disclaimer of Warranties ("AS IS")

THE APPLICATION AND ITS DOCUMENTATION ARE PROVIDED ON AN **"AS IS"** AND **"AS AVAILABLE"** BASIS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE AUTHORS AND COPYRIGHT HOLDERS SPECIFICALLY DISCLAIM ALL WARRANTIES, INCLUDING, WITHOUT LIMITATION, IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APPLICATION WILL BE ERROR-FREE, UNINTERRUPTED, OR COMPATIBLE WITH EVERY POSTGRESQL CONFIGURATION OR CLOUD PROVIDER.

---

## 6. Limitation of Liability

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE TO ANY PARTY FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, LOSS OF DATA, CORRUPTION OF DATABASE CATALOGS, UNAUTHORIZED ACCESS RESULTING FROM MISCONFIGURED ROLES OR PRIVILEGES, LOST PROFITS, OR BUSINESS INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE OF OR INABILITY TO USE THE APPLICATION, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## 7. Updates and Maintenance

The authors and copyright holders have no obligation to provide maintenance, technical support, updates, enhancements, or modifications for the Application. We may release updates via application stores (Google Play Store, Apple App Store, Mac App Store, Microsoft Store) or GitHub Releases at our sole discretion.

---

## 8. Governing Law

These Terms shall be governed by and construed in accordance with the laws of the Netherlands, without regard to its conflict of law provisions. If any provision of these Terms is held to be invalid or unenforceable, the remaining provisions will remain in full force and effect.

---

## 9. Changes to These Terms

We may update these Terms from time to time to reflect changes in the Application or legal requirements. Updated Terms will be published in the project repository with a revised "Last Updated" date.

---

## 10. Contact Us

If you have questions regarding these Terms of Service, you can reach out via:

- **GitHub Issues:** [https://github.com/dbroles/postgresql/issues](https://github.com/dbroles/postgresql/issues)
- **Security Vulnerability Reporting:** [https://github.com/dbroles/postgresql/security/advisories/new](https://github.com/dbroles/postgresql/security/advisories/new)
- **Project Repository:** [https://github.com/dbroles/postgresql](https://github.com/dbroles/postgresql)

