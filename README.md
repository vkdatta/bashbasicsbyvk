<div align="center">

<img src="https://storage.googleapis.com/vkimages/bashbasicsbyvk/favicon.png" width="50" height="50" />
    
# bashbasicsbyvk

**Advanced terminal file manager**

Browse, select, move, copy, delete, find, rename, bookmark, favourite, organise, filter, compress, map and share files from one interactive command, `o`.

<img src="https://img.shields.io/badge/Platform-Linux%20%7C%20WSL%20%7C%20Termux%20%7C%20Docker%20%7C%20macOS%20%7C%20CloudShell-black?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Python-3.8%2B-black?style=for-the-badge&logo=python&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Shell-Bash-black?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/License-MIT-black?style=for-the-badge&labelColor=%23272727&color=%23171717"/>
<img src="https://img.shields.io/badge/Encryption-AES--256--GCM-black?style=for-the-badge&labelColor=%23272727&color=%23171717"/>

[Documentation and Pricing](https://bashbasicsbyvk.pages.dev/) ·
[Security Policy](SECURITY.md) ·
[Report a Bug](https://github.com/vkdatta/bashbasicsbyvk/issues) ·
[llms.txt](llms.txt)

</div>

---

## Overview

Bash Basics By Vk, styled as `bashbasicsbyvk` is an advanced terminal file manager for Linux, WSL, Termux (Android), Docker, macOS and cloud shells.

It has two parts:

1. **A free, fully offline, file manager.** To browse, select, move, copy, delete, find, rename, bookmark, favourite, organise, filter, compress, map.

2. **An optional paid FileAPI service.** To share, transfer, and back up files on a just-in-time basis with seamless speed, robust security, and comprehensive safeguards. Also provides efficient link management.

(Visit  [documentation](https://bashbasicsbyvk.pages.dev/))

---

## Why it exists

* Difficulty tracking and managing files across directories.
* Inefficient execution of bulk file operations.
* Repeatedly filtering and locating required files.
* Complicated file transfers between devices and locations.
* Slow file transfers resulting in unnecessary time consumption.
* Having to memorize commands or repeatedly refer to AI for assistance.
* Difficulty tracking files created, modified, or managed by AI agents.
* Increased cognitive load from relying on multiple tools for different operations.
* Permanent file loss due to accidental deletion and lack of recovery options.
* Difficulty maintaining control over files transferred to or stored on external servers.
* Difficulty understanding the current state of files, directories, processes, and ongoing operations.
* Repeatedly executing the same sequences of commands for routine tasks.
* Inability to easily reverse operations or restore previous states.
* Constantly switching between multiple file managers for different activities.
* Difficulty understanding and resolving file ownership and permission issues.
* Difficulty identifying and managing duplicate files scattered across directories.
* Difficulty identifying large files, unnecessary data, and storage consumption.
* Lack of a unified interface for managing files, transfers, backups, snapshots, and remote storage.
* AI-human workflow gap, where AI agents execute commands and manipulate files faster than humans can inspect, understand, and verify their actions.

---

## Free: Local File Manager

- **Navigate:** Directories, breadcrumbs, bookmarks, recents, favourites, filters, admin-defined and user-defined functions, Google Drive, Cloudflare Pages and Workers, Cloud Shell, and GitHub repositories.
- **Act:** Run, view, edit, copy contents, delete, erase contents, overwrite, rename, share, go to path, get info, lock, unlock, archive, unarchive, extract simple syntax trees, organise, map, find and replace, and more.
- **Keymap:** Explore available key bindings, supporting your favourite `Ctrl` and `Shift` shortcuts, as well as mouse navigation.
- **Stage:** Stage files and folders for bulk actions, including shortcut, copy, move, delete, archive, get info, lock, and more.
- **Select with expressions:** Select items by extension, size, date, name, duplicates, empty items, or CSV lists.
- **Display rules:** Show only what matters in a given folder. For example, `.d.ext py` displays only Python files. Save your rules as reusable presets.
- **Organise:** Organise items by year, month, date, extension, or alphabetically — with the ability to undo changes.
- **Compress:** Pack and unpack multiple items using ZIP, TAR, TAR.GZ, TAR.XZ, TAR.BZ2, 7Z, TAR.ZST, TAR.LZ4, and `.skill` formats.
- **Cheat codes:** To list every app specific command accepted by the current prompt for quick reference.
- **Functions:** Use built-in operations, workflows or create your own reusable scripts. Functions can be exported and imported.
- **Find & Replace:** Choose from six modes to find or find and replace text in filenames, file contents, or both.
- **Native Speed:** Never compromise on speed. bashbasicsbyvk is as fast as you expect it to be 🚅. It uses language-specific compiled engines, such as C for file operations and Go for fileapi network transfers, making this multi-language project exceptionally well-equipped to address language-specific challenges and leverage their respective strengths. It also includes fallback engines, so even if an engine fails due to device-specific issues, a fallback engine, primarily written in shell, ensures the operation can still work.

---

## Paid: FileAPI (end-to-end encrypted transfer, backup, AI help)

The FileAPI services are metered with affordable credits.

- **Transfer Files:** Transfer files between multiple shell locations at exceptionally high, tested speeds. Automatically delete transferred files after a specified period or remove them manually.
- **Share Files:** Share files with team members so they can download them without leaving the terminal, provided they also use this service.
- **Copy:** Copy the contents of multiple files in a headless environment, making it easy to paste them into any AI bot or prompt.
- **Backup & Snapshots:** Enable automatic backups and snapshots to protect against errors during destructive file operations.
- **AI Commands:** Describe advanced operations to AI in plain language, and let it translate your instructions into executable commands.

Pricing is pay-as-you-go. Read [Pricing](https://bashbasicsbyvk.pages.dev/sessions/pricing)

 ---

## Security

Since this is a local file manager, no data leaves your machine while using our app in general from us, except when you choose paid FileAPI services. Files are end to end encrypted, or client side encrypted based on type action, and the account is protected with Diseps and Dinons. Your local keys for this app are kept in a mode-600 environment file, for safety. No ads, no cookies, no sale of data. Only anonymous telemetry is collected for analytics. 

Read the [Security Policy](SECURITY.md) for the full model, limits and responsible disclosure.

---

## Installation

```bash
curl -fsSL https://bashbasicsbyvk.pages.dev/bashbasicsbyvk_install.sh -o bashbasicsbyvk_install.sh && bash bashbasicsbyvk_install.sh
```

---

## Use with care

File-management tools can permanently delete data. Review operations before confirming, and keep independent backups. Some tools are in active development, and may cause unexpected behaviours. Please go through the risk section before using the tool. 

---

## Documentation

**[Live Documentation](https://bashbasicsbyvk.pages.dev/)**

## Contact and support

Maintainer: Vk Datta. **vkd.codes@gmail.com**. 

## License

Source code: [MIT](LICENSE) © 2026 Vk Datta. 

The FileAPI service and web viewer are governed by the Terms and Conditions and Privacy Policy. 

"bashbasicsbyvk" is a project name; please do not present modified builds as endorsed. Independent of and not endorsed by Google, GitHub, Cloudflare or any other third party named in the docs.

<sub>Keywords: terminal file manager, bash file manager, TUI file manager, Termux file manager, command line file manager, encrypted file sharing CLI, end-to-end encrypted file transfer, send files between servers, share files from terminal, safe delete with backup, batch rename, find and replace in files, organise files by date, duplicate file finder, Linux, WSL, Docker, Cloud Shell.</sub>