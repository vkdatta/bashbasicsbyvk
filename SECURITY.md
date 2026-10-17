# Security Policy

bashbasicsbyvk handles files that people care about, both locally and, for paid features, in transit through an encrypted relay. We take security reports seriously and treat the design of the system as part of the product.

This page is the stable summary. The detailed, current architecture is maintained in the **Security Architecture** document in the [documentation folder](https://drive.google.com/drive/folders/1SpbH4qV1FpwUem5gw-Fv-chuuaFdXefr).

---

## Reporting a vulnerability

**Report privately to [vkd.codes@gmail.com](mailto:vkd.codes@gmail.com).** Please do not open a public issue, pull request or discussion for a security problem.

Include:

- A clear description and the impact you believe it has
- Steps to reproduce, or a proof of concept
- Affected version (`pip show bashbasicsbyvk`, or the tag/commit from `-u`) and platform
- Whether you want to be credited, and under what name

What to expect:

- Acknowledgement in good faith as soon as we can, and updates until the issue is resolved.
- A fix and, where users are affected, a note in the release.
- Credit to reporters who want it.
- This is an independently run project, so please be patient with response times. Complete reports are handled fastest.

### Rules of engagement

- Test only against **your own account and data**.
- Do not access, modify or delete other users' data, and do not degrade the service (no denial-of-service, no volumetric testing, no spam).
- Give us reasonable time to fix the issue before public disclosure.
- Do not post keys, DISEPs, DINONs, links or credentials anywhere public, including in reports sent to public channels.

We do not currently offer a monetary bounty.

---

## Supported versions

| Channel | Security fixes |
|---|---|
| Latest **Stable** release | Yes |
| **Tags (beta)** | Best effort, may change without notice |
| Older releases | Upgrade with `-u` |
| **Infinity Stones** tools (`i`) | Development stage, no security guarantee |

---

## Scope

**In scope**

- The local tool (shell and Python scripts, the `o` command, the `bvk-ls` helper)
- The client side of FileAPI: encryption, key handling, `up-`, `do-`, `c2c-`, `ux-`, `-auth`, backup, snapshot, save
- The hosted FileAPI service and web viewer: authentication, authorisation, link handling, credit accounting
- Insecure defaults, key or credential leakage, path traversal, command injection, unsafe temporary files, privilege issues, flaws in the sharing handshake (RBAM)

**Out of scope**

- Vulnerabilities in third-party tools the software calls (Bash, Python, Node.js, curl, rclone, gcloud, git, gh and others); report those upstream
- Content on third-party services such as Google Drive or GitHub
- Attacks that require an already-compromised device, shell or user account
- Social engineering of the maintainer or users
- Findings that apply only to Infinity Stones when they behave as documented, for example a tool that modifies files by design
- Missing best-practice headers or similar findings with no demonstrable impact

To report **unlawful content** shared through a relay link, email the link's random identifier (the part after the site address, not the part after `#`) with your reasons and contact details.

---

## Security model

### What is protected

| Layer | Design |
|---|---|
| **Client-side encryption** | Files and a manifest of names and folders are encrypted on your device before upload. A fresh random 256-bit key is generated per transfer. |
| **Cipher** | AES-256-GCM. Each piece is cryptographically bound to its role and position, so tampered, swapped or substituted pieces fail to decrypt. |
| **Transport** | HTTPS, TLS 1.2 or higher. |
| **Link sharing (`up-`)** | The key travels in the URL fragment (`#k=`). Fragments are not sent to servers in HTTP requests. Whoever holds the full link can decrypt that one upload. |
| **Direct sharing (`ux-`, RBAM)** | Client-side encryption with a per-share File Encryption Key (FEK) protected by sender-issued DINONs. No public link. Access is approved by the receiver and revocable by the sender. |
| **Streaming** | Archives are streamed through pack, encrypt and upload, so the unencrypted archive does not touch disk. |
| **Account identity** | An email address alone does not identify or open an account. Accounts are distinguished by DISEPs (27 random identifiers), which limits enumeration, brute force and email-based takeover. API keys are stored server-side only as one-way SHA-256 hashes. |
| **Local secrets** | Keys live in an environment variable loaded from a mode-600 file, never on a command line (shell history) and never in Git. |
| **Rotation** | `-auth` regenerates keys. Old keys stop working immediately. |
| **Metadata minimisation** | Telemetry is limited to a random ID, a country code and a date. No IP address, file name, path or command is stored in telemetry records. |
| **Expiry** | Every relay transfer is deleted automatically at its expiry time. Incomplete uploads are cleaned up automatically. |

### The secrets, and who may hold them

| Secret | Purpose | Share it? |
|---|---|---|
| API key | Authenticates you to FileAPI | **Never** |
| DISEPs (27) | Account identifiers | Only with the maintainer when you need account help |
| Special DISEPs (3) | Identify you to someone you approve for RBAM sharing | Yes, to people you know, for the handshake only |
| DINONs (29) | Protect FEKs for `ux-` shares | Sender to each approved receiver only |
| FEK | Encrypts one `ux-` share | **Never**; exists unwrapped only in memory |
| Link key (`#k=`) | Decrypts one `up-` upload | Yes, deliberately; treat the whole link as a password |

### What we can and cannot see

- **We cannot read** file contents, file names or folder structure of relay transfers, because we do not hold the keys.
- **We can see** account email and key hash, credit ledger entries, random link IDs, file counts, stored sizes and expiry times, and short-term network request data needed to run and protect the service.
- Full detail: Privacy Policy and GDPR Notice in the documentation folder.

---

## Limitations, stated plainly

- No software can guarantee absolute security. The protections above depend on correct implementation, key confidentiality, and the security of your own devices.
- End-to-end encryption protects content in transit and at rest on the relay. It does **not** protect a file after a recipient has downloaded it. Revoking access cannot reach a copy already downloaded; this is true of every sharing system.
- Anyone who obtains a complete `up-` link (including from clipboard history, chat logs or screenshots) can open that transfer until it expires or is deleted.
- Backups cover only deletions made through the built-in delete command, not deletions made by other commands, other applications or direct filesystem operations. They are not a substitute for independent backups.
- A compromised device, shell, terminal logger or clipboard manager can expose keys and files regardless of the transfer design.

---

## Hardening checklist for users

1. Keep the latest **Stable** release; use `-u` to upgrade.
2. Never paste your API key, DISEPs, DINONs or full links into chats, tickets or public issues. If one leaks, run `-auth` to rotate and email the maintainer if you need help.
3. Do not run `o` as root or with `sudo` unless you must.
4. Use short expiry times for sensitive links and delete links you no longer need from `api`.
5. Share Special DISEPs and approve RBAM requests only with people you know. Review shares periodically and remove users you no longer need.
6. Review bulk operations (delete by date or extension, find and replace in contents, organise, CSV rename, move) before confirming. Local operations have no recycle bin.
7. Only run UDF scripts and imported function zips you trust; they execute with your permissions.
8. Treat `kl` as a force-kill of every process you own.
9. Avoid Infinity Stones on sensitive data or production systems. They are in development.
10. Cloud Shell transfer modes disable SSH host-key checking; use them on networks you trust.

---

## Dependencies

The software bundles third-party tools and may call or install them (for example Python, Node.js, curl, rclone, gcloud, OpenSSH, git, gh, watchdog, openpyxl, pandas, requests, Beautiful Soup, pyright). They are governed by their own licences and security processes. See **Licence and Third-Party Notices**.

---

## Disclosure and credit

We prefer coordinated disclosure: report privately, allow time for a fix, then publish. Reporters are credited in release notes on request.

*Last reviewed: 2026-10-17. The Drive documentation is the authoritative, current source; if this page and a Drive document differ, the Drive document prevails.*
