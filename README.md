<div align="center">

<img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-black?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=%23272727&color=%23171717&borderRadius=50"/>
<img src="https://img.shields.io/badge/Python-3.8%2B-black?style=for-the-badge&logo=python&logoColor=white&labelColor=%23272727&color=%23171717&borderRadius=50"/>
<img src="https://img.shields.io/badge/Shell-Bash-black?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=%23272727&color=%23171717&borderRadius=50"/>
<img src="https://img.shields.io/badge/License-MIT-black?style=for-the-badge&logoColor=white&labelColor=%23272727&color=%23171717&borderRadius=50"/>
<img src="https://img.shields.io/badge/Install-pip-black?style=for-the-badge&logo=pypi&logoColor=white&labelColor=%23272727&color=%23171717&borderRadius=50"/>

</div>

### bashbasicsbyvk

bashbasicsbyvk is a lightweight, open-source collection of Bash-Python scripts made to optimize workflows and file management in shell environments. It offers comprehensive, high-performance file management with run, copy, erase, delete, overwrite, rename, move, batch-create and batch-delete, organise, and find functions via a simple interactive call — letting you do anything without confusion. The integrated `xtract` function automates extraction of HTML tables and links from single and multi-page sites, streamlining data harvesting from catalogues, reports, and dashboards.

---

### Prerequisites

Run the following blocks in order:

```bash
pkg install termux-api
pkg install python -y
pkg install root-repo
pkg uninstall tur-repo -y
pkg update -y
pkg upgrade -y
pkg install tur-repo -y
pkg install clang libopenblas libffi libzmq build-essential -y
```
```bash
pkg update
pkg install clang make cmake pkg-config
pkg install python-dev
pkg install ninja
pkg install libandroid-spawn
pkg install libffi-dev
pkg install rclone
```
```bash
pip install numpy
```
```bash
pip install pandas
```
```bash
pkg install -y termux-api python git curl
```
```bash
pip install requests pandas beautifulsoup4 tqdm 
```
```bash
pip install openpyxl 
```

---

### Storage Setup

If you're in Termux, enable storage access in your environment using:

```bash
termux-setup-storage
```

Grant the requested storage permission when prompted by Android. This creates symlinks in `~/storage/` for shared directories like Downloads and ensures Termux can read from `/storage/emulated/0/`.

Allow external app access (required for sharing files to apps like Chrome):

```bash
nano ~/.termux/termux.properties
```

Locate or add the line:

```
allow-external-apps = true
```

Uncomment it if present by removing the `#`. Save and exit, then restart the Termux app completely — **Android Settings → Apps → Termux → Force Stop → Relaunch**. This enables the content provider (`com.termux.files`) to grant read access to URIs for external apps.

---

### Rclone Setup and Config

<details>
<summary><strong>Remote Shell (e.g. Google Cloud)</strong></summary>

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

</details>

<details>
<summary><strong>Local Shell</strong></summary>

<br/>

```bash
pkg install rclone
```

</details>

Configure a new Google Drive remote:

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

---

### Installation and Upgrade

```bash
pip install git+https://github.com/vkdatta/bashbasicsbyvk.git
```

This is a personal project — all changes go directly to `main`. No versioned releases. If a command behaves unexpectedly, force-reinstall to pull the latest state:

```bash
pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git
```
---
### Clone

```bash
git clone https://github.com/vkdatta/bashbasicsbyvk.git
```
---

### Commands

| Command | Purpose |
|---|---|
| `o` | Omni file manager — run, copy, erase, delete, overwrite, rename, move, batch-create, batch-delete, organise, find |
| `xtract` | Extract all HTML tables & hyperlinks from single or paginated URLs |

---

### `o` — Omni File Manager

```bash
o
```

A single interactive call to manage everything in your shell. No flags, no paths.

<details>
<summary><strong>Supported Operations</strong></summary>

<br/>

| Category | Operations |
|---|---|
| **Files** | Run, Copy, Erase, Delete, Overwrite, Rename, Move |
| **Batch** | Batch-create, Batch-delete |
| **Navigate** | Find, Organise |

</details>

---

### `xtract` — Web Scraper

```bash
xtract
```

Extracts **all** HTML tables and hyperlinks from one or more paginated web pages in a single invocation. Perfect for harvesting catalogues, reports, and dashboards spread across multiple pages.

<details>
<summary><strong>URL Patterns & Examples</strong></summary>

<br/>

| Intent | Format | Example |
|---|---|---|
| Single page | Plain URL | `example.com/article/p.html` |
| Specific page number | URL ending in page number | `example.com/article/100` |
| Page range (1 to N) | URL with `{N}` | `example.com/article/{100}` |

> **Note:** `{100}` means pages **1 through 100**. Curly braces signal a range — no braces means that exact page only.

</details>
