<div align="center">

# bashbasicsbyvk

**Interactive terminal file manager with FileAPI services**

Browse, select, move, rename, search and organise files from one interactive command, `o`. Send files between servers, containers and teammates without leaving the shell.

<img src="https://img.shields.io/badge/Platform-Linux%20%7C%20WSL%20%7C%20Termux-black?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Python-3.8%2B-black?style=for-the-badge&logo=python&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Shell-Bash-black?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/License-MIT-black?style=for-the-badge&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Encryption-AES--256--GCM-black?style=for-the-badge&labelColor=%23272727&color=%23171717"/>

[Documentation and Pricing](https://drive.google.com/drive/folders/1SpbH4qV1FpwUem5gw-Fv-chuuaFdXefr) ·
[Security Policy](SECURITY.md) ·
[Report a Bug](https://github.com/vkdatta/bashbasicsbyvk/issues) ·
[llms.txt](llms.txt)

</div>

---

## Overview

`bashbasicsbyvk` is a terminal file manager for Linux, WSL, Termux (Android), Docker, macOS and cloud shells, with MIT-licensed source. 

It has two parts:

1. **A free, fully offline, open-source file manager.** Navigate with numbers instead of paths, select with a query language, stage copy/move/shortcut operations, bookmark, batch-edit, organise and compress. No account, no network. (Visit  [documentation](https://drive.google.com/drive/folders/1SpbH4qV1FpwUem5gw-Fv-chuuaFdXefr))
2. **An optional paid hosted service (FileAPI), not part of the open-source licence.** Files are encrypted on your device before they leave it. Share by link, share directly with another user, back up before every delete, and snapshot important files. Credit-based pricing starts at **US$1**.

---

## Why it exists

| Problem in the terminal                                              | What bashbasicsbyvk does                                                                    |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Long paths and `ls`/`cd`/`mv` chains for routine work                | Number-based navigation, breadcrumb jumps, bookmarks, recents and favourites                |
| Selecting "all PNGs under 3 MB from last month"                      | One expression: `.s.ext png & .s.size <3mb & .s.time last30d`                               |
| Moving files between your laptop, a VPS, a container and Cloud Shell | `up-` uploads an encrypted, expiring link; `do-` pulls it down on the other side            |
| Sending a file to a colleague without pasting links around           | `ux-` shares directly between users, with revocable access, directly from terminal          |
| Deleting the wrong thing                                             | Paid backup keeps a recoverable encrypted copy of anything removed with the built-in delete |
| Beginners who do not want to memorise Linux commands                 | Everything is a menu; power users keep the grammar                                          |

---

## Free: the local file manager

- **Navigate:** directories, breadcrumb jumps, bookmarks, recents, per-folder favourites, name filter, index mode for very large folders.
- **Act:** run, view, edit (nano), copy contents to clipboard, delete, erase, overwrite from clipboard, rename, share.
- **Stage:** `c-` copy, `m-` move, `s-` shortcut, `b-` bookmark, applied with `d-` at the destination. Persistent buffers (`c--`, `m--`) for repeated use.
- **Select with expressions:** by extension, size, date, name, duplicates, empty items, CSV lists. Combine with `&`, `|`, `!` and grouping.
- **Display rules:** show only what you care about in a given folder (`.d.ext py`), saved as presets.
- **Batch:** create or delete many files and folders, find and replace in names and contents, CSV-driven rename, delete by date or extension.
- **Organise:** by year, month, date, extension or alphabet, and undo it.
- **Compress:** `z-` and `uz-` for zip and unzip of multiple items.
- **Project maps:** `p-` generates a text map of any path.
- **Functions (`fx`):** built-in CSV-driven operations plus your own scripts, exportable and importable.
- **Transfer (`t`):** local copy/move, and Google Drive or Cloud Shell through your own `rclone` / `gcloud` login.
- **Interface:** sort, group (Settings → Group by: year → month → date → ext, drawn as a tree of headers; grouped natively by the C helper), file details, colours, timezone, instant pop / carpet draws (no animation delay), settings that reset cleanly.
- **Native speed:** a C helper (`bvk-ls`) lists large folders quickly; `health` tells you exactly what is active on your machine.

<details>
<summary><strong>Selection and filter examples</strong></summary>

```text
.s.ext png,jpg & .s.size <3mb           small images
.s.dup -r                               duplicate files in all subfolders
.s.empty & .s.d -r                      empty folders, deep
.s.time last30d                         modified in the last 30 days
.s.csv                                  names listed in a CSV file
( .s.ext png | .s.ext py ) & !.s.sw a   grouping and negation
.d.ext py                               display only Python files here
```

Full grammar and every command are in the [documentation](https://drive.google.com/drive/folders/1SpbH4qV1FpwUem5gw-Fv-chuuaFdXefr).

</details>

---

## Paid: FileAPI (end-to-end encrypted transfer, backup, AI help)

The local tool is free. The hosted services are metered with simple credits. Receivers never pay.

| Feature | Command | What you get |
|---|---|---|
| **Encrypted link sharing** | `up-` / `do-` | Files are packed, encrypted on your device and uploaded. You get a link; the decryption key lives only in the link. Recipients do not need the tool. Expiry is yours to set, and links can be extended, shortened or deleted in bulk from `api`. |
| **Text to clipboard anywhere** | `c2c-` | Merge selected text files into one encrypted paste you can open on another machine. |
| **RBAM direct sharing** | `ux-` | Share user-to-user with client-side encryption and no public link. Sender controls and can revoke access at any level. |
| **Backup before delete** | internal delete | Paid users get an encrypted backup taken before each delete, recoverable for a limited window. |
| **Snapshots** | startup / schedule | Selected files upload automatically as part of your routine. |
| **Save to Cloud Surf** | Save | Same pipeline as upload, delivered to your own cloud arena instead of a shared link. |
| **AI Command Help** | `.ai` | Ask how to do something and get command-specific guidance. |

Pricing is pay-as-you-go: US$1 buys credits, and cost scales with data size and how long it stays alive. Small text and files up to 5 MB are priced at about one credit per month of retention. See **Pricing** in the documentation for current rates and examples.

**To get started:** email **vkd.codes@gmail.com** for API access, then run `-auth` inside `o`.

---

## Security at a glance

- Encryption happens **on your device**. The service stores ciphertext it has no key for.
- Per-transfer random 256-bit key, AES-256-GCM, TLS in transit.
- Account identity is not your email address. It is an email plus 27 random identifiers (DISEPs); API keys are stored server-side only as hashes.
- Keys are kept in a mode-600 environment file, never on a command line, never in Git. `-auth` rotates them and the old ones stop working immediately.

- No ads, no cookies, no tracking, no sale of data.

Read the [Security Policy](SECURITY.md) for the full model, limits and responsible disclosure.

---

## Installation

<details>
<summary><strong>Termux for Android</strong></summary>

<br/>

<details>
<summary>Prerequisites</summary>

<br/>

```bash
pkg install termux-api
pkg install python -y
pkg install root-repo
pkg uninstall tur-repo -y
pkg update -y && pkg upgrade -y
pkg install tur-repo -y
pkg install clang libopenblas libffi libzmq build-essential -y
```

```bash
pkg install clang make cmake pkg-config python-dev ninja libandroid-spawn libffi-dev rclone
```

```bash
pip install numpy pandas requests beautifulsoup4 tqdm openpyxl
```

</details>

<details>
<summary>Storage</summary>

<br/>

Enable storage access:

```bash
termux-setup-storage
```

Grant the permission when prompted. Then allow external app access:

```bash
nano ~/.termux/termux.properties
```

Add or uncomment:

```
allow-external-apps = true
```

Save, exit, then fully restart Termux: **Android Settings → Apps → Termux → Force Stop → Relaunch**.

</details>

<details>
<summary>Rclone</summary>

<br/>

```bash
pkg install rclone
rclone config
```

| Step | Prompt | Value |
|---|---|---|
| 1 | New remote? | `n` |
| 2 | Name | `gdrive` |
| 3 | Storage type | Google Drive |
| 4 | Client ID / Secret | *(leave empty)* |
| 5 | Scope | `1` — Full access |
| 6 | Root folder ID | *(leave empty)* |
| 7 | Advanced config? | `n` |
| 8 | Auto config? | `y` |

</details>

<details>
<summary>Install</summary>

<br/>

```bash
pip install git+https://github.com/vkdatta/bashbasicsbyvk.git
```

</details>

<details>
<summary>Upgrade</summary>

<br/>

```bash
pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git
```

</details>

<details>
<summary>Uninstall</summary>

<br/>

```bash
pip uninstall bashbasicsbyvk
```

</details>

</details>

---

<details>
<summary><strong>Linux and Other Cloud Shells</strong></summary>

<br/>

<details>
<summary>Prerequisites</summary>

<br/>

```bash
export PATH="$HOME/.local/bin:$PATH"
```

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

</details>

<details>
<summary>Rclone</summary>

<br/>

```bash
cd ~
curl -LO https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip -j rclone-current-linux-amd64.zip "*/rclone" -d ~/bin/
chmod 755 ~/bin/rclone
rm rclone-current-linux-amd64.zip
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
fi
```

```bash
rclone config
```

| Step | Prompt | Value |
|---|---|---|
| 1 | New remote? | `n` |
| 2 | Name | `gdrive` |
| 3 | Storage type | Google Drive |
| 4 | Client ID / Secret | *(leave empty)* |
| 5 | Scope | `1` — Full access |
| 6 | Root folder ID | *(leave empty)* |
| 7 | Advanced config? | `n` |
| 8 | Auto config? | `y` |

</details>

<details>
<summary>Install</summary>

<br/>

```bash
pip install git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

.then

```bash
export PATH="$HOME/.local/bin:$PATH"
```

.then

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

</details>

<details>
<summary>Upgrade</summary>

<br/>

```bash
pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

</details>

<details>
<summary>Uninstall</summary>

<br/>

```bash
pip uninstall bashbasicsbyvk
```

</details>

</details>

---

<details>
<summary><strong>VMs</strong></summary>

<br/>

<details>
<summary>Prerequisites</summary>

<br/>

```bash
sudo apt update && sudo apt install python3 python3-pip python3-venv python3-dev -y
```

</details>

<details>
<summary>Rclone</summary>

<br/>

```bash
cd ~
curl -LO https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip -j rclone-current-linux-amd64.zip "*/rclone" -d ~/bin/
chmod 755 ~/bin/rclone
rm rclone-current-linux-amd64.zip
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
fi
```

```bash
rclone config
```

| Step | Prompt | Value |
|---|---|---|
| 1 | New remote? | `n` |
| 2 | Name | `gdrive` |
| 3 | Storage type | Google Drive |
| 4 | Client ID / Secret | *(leave empty)* |
| 5 | Scope | `1` — Full access |
| 6 | Root folder ID | *(leave empty)* |
| 7 | Advanced config? | `n` |
| 8 | Auto config? | `y` |

</details>

<details>
<summary>Install</summary>

<br/>

```bash
sudo pip install git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

</details>

<details>
<summary>Upgrade</summary>

<br/>

```bash
sudo pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

</details>

<details>
<summary>Uninstall</summary>

<br/>

```bash
sudo pip uninstall bashbasicsbyvk
```

</details>

</details>

---

## Use with care

File-management tools can permanently delete data and there is no recycle bin for local operations. Review bulk operations before confirming, and keep independent backups. `kl` force-ends every process owned by your user. The **Infinity Stones** menu (`i`: web table extraction, JavaScript and Python audit, Git Push, SQL generation, LocalHost) is in development and should be used only on data you can afford to lose.

---

## Documentation

Always current, maintained in one place: **[Drive documentation folder](https://drive.google.com/drive/folders/1SpbH4qV1FpwUem5gw-Fv-chuuaFdXefr)**

About · Commands · Pricing · Security Architecture · Privacy Policy · Terms and Conditions · GDPR Notice · Legal Notice · Licence and Third-Party Notices · Contact

In the app, `-h` opens the same link.

## Contact and support

Maintainer: Vk Datta. API access, bugs and anything private: **vkd.codes@gmail.com**. Public, non-sensitive issues and suggestions: [GitHub Issues](https://github.com/vkdatta/bashbasicsbyvk/issues). Never post keys, DISEPs, DINONs or links in public.

## License

Source code: [MIT](LICENSE) © 2026 Vk Datta. The hosted FileAPI service and web viewer are governed by the Terms and Conditions and Privacy Policy. "bashbasicsbyvk" is a project name; please do not present modified builds as endorsed. Independent of and not endorsed by Google, GitHub, Cloudflare or any other third party named in the docs.

<sub>Keywords: terminal file manager, bash file manager, TUI file manager, Termux file manager, command line file manager, encrypted file sharing CLI, end-to-end encrypted file transfer, send files between servers, share files from terminal, safe delete with backup, batch rename, find and replace in files, organise files by date, duplicate file finder, Linux, WSL, Docker, Cloud Shell.</sub>
