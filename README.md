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


## Settings (`s`)

Same feel as the main menu — no numbers to type:

| Key | Does |
|---|---|
| `↑` `↓` | move |
| `space` / `enter` | switch a `[x]` on/off, pick an option, or open a sub-screen |
| `←` `→` | (Group by) move a level earlier/later in the chain |
| `u` | back one level (sub-screen → Settings → main menu) |
| `q` | close Settings completely and return to the main menu |

Screens: Show hidden files · Sort order · File details · Group by · Display filter · Search filter · Compress format · Animation · Big-folder limit · Background color · Text color · Import nano settings · Reset all settings.
