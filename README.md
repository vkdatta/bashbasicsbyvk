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

Settings are grouped: **Display** (hidden files · sort order · file details · group by · big-folder limit · animation) · **Filters** (display filter · search filter) · **Colors** (background · text) · **Files & archives** (compress format · zip hidden) · **File API** (see below) · **System** (timezone · import nano settings) · **Reset all settings**. Type `=` and a word of a name to find a group (`=nuke`, `=sort`, `=snapshot`).

### Timezone

`s` → **Timezone** sets one timezone for the whole app: link expiry times in `api`, file times, logs, exported file names and the helper scripts (the background daemon follows it too). Times that show a clock time now carry the zone, e.g. `until 2026-10-10 02:20 IST`.

Every zone in the machine's tz database is listed with its abbreviation and current offset (`Asia/Kolkata  IST  UTC+05:30`). Type `=` and part of a name, abbreviation or offset to search: `=kolkata`, `=ist`, `=new york`, `=+05:30`. Pick **System default** to follow the computer's clock again. Stored machine stamps (`CREATED=…Z`, telemetry day) stay in UTC on purpose.


## File API services: price check, Backup, Saved Surf, Snapshots

All of these use the same encrypted pipeline as `up-` (packed as tar.gz, AES-256-GCM per 16 MiB chunk) and the same credit rules. Their settings live in `s` → **File API**: *Credits · Links (up-/c2c-) · Cloud Surf shares (ux-) · Backup · Saved Surf (save-) · Snapshots*.

### Price check before spending credits
Before `up-`, `ux-`, a backup, a save, and before extending an item, the packed size is priced by the server (nothing is charged yet):
- cost **1** credit and you have enough → it just goes;
- cost **above 1** → *"costs X credits — [c] continue · [r] reduce time · [i] increase time · [s] stop"*. Time is entered the way `e-N` in `api` takes it (`12h`, `2d`, `+1d`, `-6h`);
- **not enough credits** → *stop*, or *reduce time*: it suggests the longest time your credits cover (cost ≈ your balance). If even 1 hour is too dear, it says so and stops.

`s` → File API → **Credits** → *Don't ask* skips the price check entirely (the server still refuses when your balance is too low).

### Backup (`bk`, Home → Backup)
Every delete (`d`, the file menu's Delete, the fx delete functions) first copies what is about to go to the cloud, like `up-`, kept 30 days by default. You are asked for a name (Enter = none): the backup is called `DDMMYYYY HHMM NAME` or just `DDMMYYYY HHMM`. If a backup was wanted but fails or is stopped, you are asked whether to delete anyway. In **Backup**: `r-N` restores into the current folder (never overwrites), `a-N` renames, `e-N` extends/shortens, `x-N` nukes — the same controls as Links. Settings: *Backup before delete* (yes · no · ask every time, default **yes**) and *Default nuke time* (default 30 days).
Not backed up: symlinks (only the link is removed), Google Drive placeholders (they are empty), rule bundles of the `.r` rule book, and "move" operations (the data lives on at the destination). Each backup costs credits like any upload (at least 1).

### `save-` and Saved Surf (`sv`, Home → Saved Surf)
`save-1-3` or `save-2 as tax papers` works like `up-` but **no link is ever shown**. It is client-side encrypted exactly like `ux-` (dinons → FEK → a fresh key per item): the item key is wrapped with your FEK on your computer and the server stores only that wrapped key, which it has no way to open, so the backend operator cannot read it. The data and the wrapped key are only served to their owner, and the key is destroyed when the item expires or is nuked. Open it from any device with your e-mail + diseps + API key **and your dinons**. Named like backups.

### Snapshots (`snap-`, `sn`, Home → Snapshots)
`snap-1-3` puts files/folders on this computer's snapshot list. While `o` is running, a background process snapshots every path **that changed** every *interval* (`s` → File API → Snapshots: 1 minute … 30 days, default 1 hour; *Keep time* default 7 days; on/off). Rules:
- it only runs while `o` runs; reopen after 10 days with a 10-minute interval and you get **one** snapshot of that moment, not 1440;
- each path is first copied to a temporary folder (cheap on copy-on-write disks), and the archive is packed from the copy, so editing or deleting a 5 GB file mid-sync cannot corrupt it;
- the background process never prompts; when your credits are not enough a one-line notice shows in the main screen and snapshots pause;
- a snapshot is named `AS ON DDMMYYYY HHMM` and cannot be renamed.

**Home → Snapshots** lists every device that has a snapshot list (devices are told apart by the telemetry uuid), the paths on each, and their snapshots. You can view and restore snapshots of any device, nuke or extend them, and remove a path from another device's list (that device stops on its next sync). Paths and device names are stored encrypted.

**Telemetry:** the telemetry uuid is the device id for snapshots, so there is no switch to turn telemetry off any more, and the app never deletes or regenerates the uuid. Once you use Snapshots the uuid is tied, on the server, to your account.

### Any device, encrypted names, and who shared a link
Everything you hold is managed from **any device you log in on** (e-mail + diseps + API key + dinons): Links, Backup, Saved Surf, Snapshots, Cloud Surf. Only `up-` / `c2c-` links are end-to-end (the key lives only in the link). Everything else is client-side encrypted (CSE): dinons → FEK → keys.
- **Links tab:** each new `up-` link is also stored *encrypted* with a per-user label key, so `c-N` copies it again on any device. The server cannot open it. Older links are added a few per refresh. With `FILEAPI_BASHBASICS_STORE_KEYS=0` nothing is kept in the cloud.
- **Names** (up-, backup, save-, `a-N`) are sent as `e1.<ciphertext>`. Without your dinons a name is not sent at all. Size, expiry and timing stay readable to the server (billing/expiry need them); `ux-` names stay readable to the receivers.
- **Backups** are CSE and owner-only now (restore from any device). Older backups restore only on the computer that made them.
- **Who shared it:** every link page shows the uploader's mail and `d3` (codes 13, 24, 7 of the diseps) with a Copy button and a **Report abuse** link to `/help`. Nobody can look inside a link, so this is how pirated, adult, illegal or harmful sharing is curbed: reports go to the admin, who can restrict the link or suspend the account.
- **Admin** (`Authorization: Bearer $ADMIN_TOKEN`): `GET /admin/reports`, `POST /admin/restrict|unrestrict|suspend|unsuspend|dismiss`.
