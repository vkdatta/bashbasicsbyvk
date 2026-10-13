<div align="center">

<img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-black?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Python-3.8%2B-black?style=for-the-badge&logo=python&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Shell-Bash-black?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/License-MIT-black?style=for-the-badge&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Install-pip-black?style=for-the-badge&logo=pypi&logoColor=white&labelColor=%23272727&color=%23171717"/>

</div>

### bashbasicsbyvk

**bashbasicsbyvk** is a lightweight file manager for your shell environment. From running, copying, renaming, and moving files to organising, indexing, and scraping web data — it's designed to make shell life simpler.

---

### Commands

| Command | Purpose |
|---|---|
| `o` | Omni file manager — run, copy, erase, delete, overwrite, rename, move, batch-create, batch-delete, organise, find |

---

### `o` — Omni File Manager

```bash
o
```

A single interactive call to manage everything in your shell. No flags, no paths.

<details>
<summary>Supported Operations</summary>

<br/>

| Category | Operations |
|---|---|
| **Files** | Run, Copy, Erase, Delete, Overwrite, Rename, Move |
| **Batch** | Batch-create, Batch-delete |
| **Navigate** | Find, Organise |

</details>

---

### Installation

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


## Google Drive (`fx` → `google_drive_fx` → `open google drive`)

Opens a Google Drive as the main screen, with every native command working on it.

1. Make a Drive profile once: `rclone config` → `n` → name → *Google Drive* (several profiles = several accounts).
2. `fx` → `google_drive_fx` → `open google drive` lists your rclone profiles (`n` creates one). Pick a number.
3. Your Drive appears like a folder (header `☁️ work:/Docs`), folders first like drive.google.com. Browse with numbers and `u`.
   `c  d  r  c-  m-  s-  d-  z-  uz-  t  f  up-  ux-` and the rest behave as in any folder; changes are pushed to Drive right after.

| Command | Meaning |
|---|---|
| `gd` | Drive menu: status, quota, commands |
| `gdx` | leave Google Drive (back to where you were) |
| `rf` / `gd.rf` | list this Drive folder again from Google |
| `gd.scan` | list the whole Drive below here (folder item counts become real) |
| `gd.clean` | free disk: downloaded, unchanged files become placeholders again |
| `gd.push`, `gd.sw` | push pending changes now, switch profile |

**How it works.** A profile is mirrored into `~/.bashbasicsbyvk/gdrive/<profile>/tree/`: folders are real folders, files are
free placeholders (sparse, right size and date). Content is downloaded the moment something reads it (open, copy out, zip, upload
link, `rclone` transfer); copying inside the Drive is a server-side copy. Create, delete (to the Drive **trash**), rename, move
(a real server-side move), edit and zip are pushed back afterwards. Over 100 removals at once asks first; a copy of a
not-downloaded file is never uploaded as zeros.

**Per-profile state.** Each profile has its own settings, buffers, selection and rules, favourites, locks, bookmarks, shortcut
registry, search index and link keys in `~/.bashbasicsbyvk/gdrive/<profile>/`. They are swapped in when the Drive opens and
back when you leave. `d-` inside a Drive offers to apply buffers you staged outside it. Upgrades, UDF scripts and the recents daemon stay global.

**Notes.** Folders you have not opened yet show no item count until listed (`gd.scan`). Google Docs/Sheets appear as their
exported files and are read-only. Content search (`f`) only sees downloaded files. Extra rclone flags per profile go in
`~/.bashbasicsbyvk/gdrive/<profile>/rclone.flags` (e.g. `--drive-shared-with-me`). Environment: `BVK_GD_TTL` (list cache seconds, 120),
`BVK_GD_CONFIRM_MB` (ask before downloading more, 200), `BVK_GD_MAX_DELETE` (100), `BVK_GD_PERMANENT=1` (skip the Drive trash).

## Upgrade (`-u`) and `health`

`-u` opens the upgrade loop (arrow keys `←/→` switch tabs):

- **📦 Stable** — published GitHub releases, newest first
- **🧪 Tags (beta)** — every git tag, newest first (`✓ stable` = also a release)

Type a number to install that exact version (it asks first), `i-N` to read its description,
`m` for the latest `main`, `rf` to refresh, `u` to leave. `★ installed` marks the last version
installed from this menu.

`health` explains why the file list is loaded by Python (`[loaded by py]`) instead of the native
C helper `bvk-ls`: it checks the CPU/OS match, the binary's ELF header, exec permission, noexec
mounts and a real run, then exercises every `bvk-ls` sub-command. The report is also saved to
`~/.bashbasicsbyvk/health.log`.

## Settings (`s`)

Same feel as the main menu — no numbers to type:

| Key | Does |
|---|---|
| `↑` `↓` | move |
| `space` / `enter` | switch a `[x]` on/off, pick an option, or open a sub-screen |
| `←` `→` | (Group by) move a level earlier/later in the chain |
| `u` | back one level (sub-screen → Settings → main menu) |
| `q` | close Settings completely and return to the main menu |

Screens: Show hidden files · Sort order · File details · Group by · Display filter · Search filter · Compress format · Timezone · Animation · Big-folder limit · Background color · Text color · Import nano settings · Reset all settings.

### Timezone

`s` → **Timezone** sets one timezone for the whole app: link expiry times in `api`, file times, logs, exported file names and the helper scripts (the background daemon follows it too). Times that show a clock time now carry the zone, e.g. `until 2026-10-10 02:20 IST`.

Every zone in the machine's tz database is listed with its abbreviation and current offset (`Asia/Kolkata  IST  UTC+05:30`). Type `=` and part of a name, abbreviation or offset to search: `=kolkata`, `=ist`, `=new york`, `=+05:30`. Pick **System default** to follow the computer's clock again. Stored machine stamps (`CREATED=…Z`, telemetry day) stay in UTC on purpose.
