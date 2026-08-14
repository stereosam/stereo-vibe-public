# Offline installers (Windows)

Drop installers here and the kit will use them when the machine has no network, or when
WinGet is unavailable. This is what makes the kit usable from a USB stick in a room with
bad Wi-Fi — which is where it gets used most.

File names have to match these masks:

| tool | mask | where to get it |
|---|---|---|
| PowerShell | `PowerShell-*.msi` | https://github.com/PowerShell/PowerShell/releases (x64 msi) |
| App Installer (WinGet) | `*AppInstaller*.msixbundle` or `*DesktopAppInstaller*.msixbundle` | Microsoft.DesktopAppInstaller, from the Microsoft Store or GitHub |
| Git | `Git-*.exe` | https://git-scm.com/download/win (64-bit standalone) |
| Node.js LTS | `node-*.msi` | https://nodejs.org/en/download (Windows Installer .msi, LTS, x64) |

The agent CLIs (Codex, Claude Code, Gemini) install through npm and need the network
anyway — they also need an online sign-in, so there is no offline path for them.

If the machine has a working connection, leave this folder empty: everything comes from
WinGet. The binaries themselves are gitignored — this file is the only tracked thing here.
