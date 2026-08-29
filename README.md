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
| `xtract` | Extract all HTML tables & hyperlinks from single or paginated URLs |

---

### Installation

<details>
<summary><strong>Termux for Android</strong></summary>

<br/>

#### Prerequisites

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

#### Storage

Enable storage access:

```bash
termux-setup-storage
```

Grant the permission when prompted. Then allow external app access:

```bash
nano ~/.termux/termux.properties
```

Add or uncomment the following line:

```
allow-external-apps = true
```

Save, exit, then fully restart Termux: **Android Settings → Apps → Termux → Force Stop → Relaunch**.

#### Rclone

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

#### Install

```bash
pip install git+https://github.com/vkdatta/bashbasicsbyvk.git
```

#### Upgrade

```bash
pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git
```

#### Uninstall

```bash
pip uninstall bashbasicsbyvk
```

</details>

---

<details>
<summary><strong>Linux and Other Cloud Shells</strong></summary>

<br/>

#### Rclone

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

#### Install

```bash
pip install git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

#### Upgrade

```bash
pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

#### Uninstall

```bash
pip uninstall bashbasicsbyvk
```

</details>

---

<details>
<summary><strong>VMs</strong></summary>

<br/>

#### Prerequisites

```bash
sudo apt update && sudo apt install python3 python3-pip python3-venv python3-dev -y
```

#### Rclone

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

#### Install

```bash
sudo pip install git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

#### Upgrade

```bash
sudo pip install -vvv --progress-bar on --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git --break-system-packages
```

#### Uninstall

```bash
sudo pip uninstall bashbasicsbyvk
```

</details>
