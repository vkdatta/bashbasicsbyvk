<div align="center"><img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-black?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Python-3.8%2B-black?style=for-the-badge&logo=python&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Shell-Bash-black?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/License-MIT-black?style=for-the-badge&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Install-pip-black?style=for-the-badge&logo=pypi&logoColor=white&labelColor=%23272727&color=%23171717"/></div>bashbasicsbyvk

bashbasicsbyvk is a lightweight interactive file manager for your shell environment. It provides modern, simple alternatives to repetitive shell commands for managing files, organizing data, finding content, extracting information from websites, and more.

Installation

<details>
<summary><strong>Termux for Android</strong></summary><br>Prerequisites

Run:

pkg update -y
pkg upgrade -y
pkg install -y python git curl termux-api rclone

Install Python dependencies:

pip install numpy pandas requests beautifulsoup4 tqdm openpyxl

Storage

Enable Termux storage access:

termux-setup-storage

Grant the requested Android storage permission.

For sharing files with external apps, open:

nano ~/.termux/termux.properties

Add or uncomment:

allow-external-apps = true

Then completely restart Termux.

Rclone

Configure your Google Drive remote:

rclone config

Suggested configuration:

Step| Value
New remote| "n"
Name| "gdrive"
Storage| Google Drive
Client ID / Secret| Leave empty
Scope| "1"
Root folder ID| Leave empty
Advanced config| "n"
Auto config| "y"

Installation

pip install git+https://github.com/vkdatta/bashbasicsbyvk.git

Upgrade

pip install --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git

Deletion

pip uninstall bashbasicsbyvk

</details><details>
<summary><strong>Linux and Other Cloud Shells</strong></summary><br>Prerequisites

Ensure Python, pip, Git, and Rclone are installed.

For Debian/Ubuntu-based systems:

sudo apt update
sudo apt install -y python3 python3-pip python3-venv python3-dev git curl rclone

Storage

No additional setup is normally required.

Rclone

Configure your Google Drive remote:

rclone config

Suggested configuration:

Step| Value
New remote| "n"
Name| "gdrive"
Storage| Google Drive
Client ID / Secret| Leave empty
Scope| "1"
Root folder ID| Leave empty
Advanced config| "n"
Auto config| "y"

Installation

Without sudo:

pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

With sudo:

sudo pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Upgrade

Without sudo:

pip install --upgrade --force-reinstall --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

With sudo:

sudo pip install --upgrade --force-reinstall --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Deletion

Without sudo:

pip uninstall bashbasicsbyvk --break-system-packages

With sudo:

sudo pip uninstall bashbasicsbyvk --break-system-packages

</details><details>
<summary><strong>VMs</strong></summary><br>Prerequisites

For Debian/Ubuntu-based VMs:

sudo apt update
sudo apt install -y python3 python3-pip python3-venv python3-dev git curl rclone

Storage

No additional setup is normally required.

Rclone

Configure your Google Drive remote:

rclone config

Suggested configuration:

Step| Value
New remote| "n"
Name| "gdrive"
Storage| Google Drive
Client ID / Secret| Leave empty
Scope| "1"
Root folder ID| Leave empty
Advanced config| "n"
Auto config| "y"

Installation

Without sudo:

pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

With sudo:

sudo pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Upgrade

Without sudo:

pip install --upgrade --force-reinstall --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

With sudo:

sudo pip install --upgrade --force-reinstall --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Deletion

Without sudo:

pip uninstall bashbasicsbyvk --break-system-packages

With sudo:

sudo pip uninstall bashbasicsbyvk --break-system-packages

</details><details>
<summary><strong>All Others</strong></summary><br>Prerequisites

Ensure the following are available:

- Python 3.8+
- pip
- Git
- Bash

Installation

pip install git+https://github.com/vkdatta/bashbasicsbyvk.git

If your system restricts global Python package installation:

pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Or with sudo:

sudo pip install --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Upgrade

pip install --upgrade --force-reinstall git+https://github.com/vkdatta/bashbasicsbyvk.git

If required:

pip install --upgrade --force-reinstall --break-system-packages git+https://github.com/vkdatta/bashbasicsbyvk.git

Deletion

pip uninstall bashbasicsbyvk

</details>Commands

Command| Purpose
"o"| Interactive omni file manager
"xtract"| Extract HTML tables and hyperlinks from web pages

"o"

o

A single interactive file manager for common shell operations.

Supported operations include:

- Run
- Copy
- Erase
- Delete
- Overwrite
- Rename
- Move
- Batch create
- Batch delete
- Organise
- Find

"xtract"

xtract

Extracts HTML tables and hyperlinks from single or paginated URLs.

URL Patterns

Intent| Format| Example
Single page| Plain URL| "example.com/article/page.html"
Specific page| URL ending in a number| "example.com/article/100"
Page range| URL with "{N}"| "example.com/article/{100}"

"{100}" means pages 1 through 100.