# Privacy Policy for User Manager for PostgreSQL

**Last Updated:** September 11, 2026  
**Effective Date:** September 11, 2026

This Privacy Policy explains how **User Manager for PostgreSQL** ("the Application"), developed by Daniel van der Meulen ("we", "us", or "our"), handles your information.

We respect your privacy and are committed to protecting it. **User Manager for PostgreSQL does not collect, store, transmit, sell, or share any personal data with us or any third parties.**

---

## 1. Summary of Key Points

- **Zero Data Collection:** We do not collect, track, or monitor your personal data, usage analytics, or device identifiers.
- **Direct Database Communication:** The Application connects directly and exclusively to the PostgreSQL database server(s) that you configure. No traffic is routed through our servers or any third-party intermediaries.
- **Local Credential Storage:** Database passwords and connection details are stored locally on your device using OS-native encryption.
- **No Third-Party Analytics or Advertising:** The Application contains no third-party tracking libraries, analytics frameworks, advertising networks, or telemetry services.

---

## 2. Information Handled by the Application

### 2.1 Database Connection Configuration
To connect to your PostgreSQL database, the Application allows you to input:
- Hostname or IP address
- Port number
- Database name
- Username
- Password
- SSL / TLS preferences

This information is stored **locally on your device** solely to allow you to reconnect to your databases conveniently.

### 2.2 Security of Stored Credentials
- **Passwords:** Passwords are encrypted and saved exclusively within your operating system's native secure credential store:
  - **Windows:** Windows Credential Manager (via Data Protection API / DPAPI)
  - **macOS & iOS:** Apple Keychain
  - **Linux:** Secret Service API / `libsecret`
  - **Android:** Android KeyStore
- **Configuration metadata:** Non-sensitive settings (such as host, port, database name, and username) are stored locally using platform application preferences.
- Passwords and connection secrets are **never** logged, never written to plain-text files, and never transmitted over the internet to any party other than your target PostgreSQL server.

### 2.3 Database Data and Metadata
When managing roles, users, and privileges, the Application queries your PostgreSQL server for catalog metadata (such as roles, memberships, and role attributes). 
- All query results are processed entirely in memory on your local device.
- We have no access to your database content, schemas, roles, or query results.

---

## 3. Network Access and Data Transmission

The Application only communicates over the network with the specific PostgreSQL host and port configured by the user. 

- **Direct Connections:** Communication occurs directly between your client device and the target PostgreSQL server.
- **SSL / TLS:** The Application supports encrypted connections (SSL/TLS) to protect data in transit between your device and your database server.
- **No External Services:** The Application makes no external HTTP, API, telemetry, or diagnostic calls to the developer or any third party.

---

## 4. Third-Party Services and Tracking

The Application:
- Does **not** include any third-party software development kits (SDKs) for analytics (e.g., Google Analytics, Firebase, Sentry, Telemetry).
- Does **not** include advertising SDKs or display advertisements.
- Does **not** perform user profiling, cross-device tracking, or fingerprinting.

---

## 5. User Control and Data Deletion

You maintain complete control over your data:
- **Modifying or Deleting Connections:** You can edit or delete saved database connections and saved passwords at any time from within the Application.
- **Complete Removal:** Uninstalling the Application removes its locally stored preferences. Secure credentials stored in Windows Credential Manager or your OS keychain can also be cleared directly within the Application or through your operating system's credential management tool.

---

## 6. Children's Privacy

The Application is a developer and database administration tool intended for IT professionals, database administrators, and software developers. It does not knowingly collect or solicit any personal information from children under the age of 13 (or under 16 in the European Union).

---

## 7. Compliance with Global Regulations

- **General Data Protection Regulation (GDPR) / UK GDPR:** Because we do not collect, process, or store personal data on external servers, we do not act as a data controller or data processor for your personal information.
- **California Consumer Privacy Act (CCPA) / CPRA:** We do not collect or sell consumer personal information.
- **Microsoft Store Certification Policy:** This policy satisfies Section 10.5 (Privacy) of the Microsoft Store App Developer Agreement by disclosing all data handling practices.

---

## 8. Changes to This Privacy Policy

We may update this Privacy Policy from time to time, for example to reflect changes in our practices or for legal, operational, or regulatory reasons. Any revisions will be published in this repository with an updated "Last Updated" date.

---

## 9. Contact Us

If you have questions, concerns, or feedback regarding this Privacy Policy or the security of the Application, you can reach out via:

- **GitHub Issues:** [https://github.com/dbroles/postgresql/issues](https://github.com/dbroles/postgresql/issues)
- **Security Vulnerability Reporting:** [https://github.com/dbroles/postgresql/security/advisories/new](https://github.com/dbroles/postgresql/security/advisories/new)
- **Project Repository:** [https://github.com/dbroles/postgresql](https://github.com/dbroles/postgresql)
