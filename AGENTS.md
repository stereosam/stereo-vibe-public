# AGENTS.md

Things that are not visible from the code.

- **`windows/` and `macos/` are build output.** They are byte-for-byte the contents of the
  published StereoVibe Lite zips. The build script (kept with the private workshop kit)
  normalizes encodings, copies `templates/` into each package and refuses to build if a
  check fails. Treat a hand edit here as a patch to be carried back, not as the source.
- **Two implementations, no shared core.** `windows/_не трогать/check-work-tools.ps1` and
  `macos/_не трогать/check-work-tools.sh` are hand-kept at feature parity. A change to one
  is incomplete until it is made in the other.
- **Encodings are load-bearing.** `.cmd` launchers are ASCII + CRLF: `cmd.exe` parses them
  in the OEM codepage, and one Cyrillic character breaks the launcher with an
  unrelated-looking error. The Windows `.ps1` is UTF-8 **with BOM** + CRLF, or Windows
  PowerShell 5.1 reads it as ANSI. The macOS script is UTF-8 without BOM + LF, starts with
  `#!/bin/bash`. `.gitattributes` stores both package folders as-is — do not "fix" it.
- **Windows PowerShell 5.1, not 7.** Appx cmdlets used for the desktop-app checks fail
  under PowerShell 7; the launcher forces 5.1 by full path.
- **macOS still ships bash 3.2.** No associative arrays, no `${var^^}`, no `mapfile`, no
  `case` inside `$( … )`.
- **No download-and-execute.** No `irm | iex`, no `curl | bash` of our own, no encoded
  commands that fetch code. The one download path is WinGet repair, and it installs only
  after a valid Microsoft signature check. Antivirus engines flag the other patterns as
  malware.
- **Network contact is fixed and documented.** A version check (one field read, nothing
  executed) and an anonymous summary built from a fixed whitelist of fields, switched off
  with `-NoReport` / `--no-report`. Do not add endpoints, and never put free text, paths,
  user or machine names into the summary.
- **Every external call has a time limit.** winget/npm/brew run in background jobs with a
  timeout and a visible bar; a program's own `--version` is limited to 30 s and a timeout
  means "did not answer", never "missing".
- **A check may never abort the run.** Wrap it, record a row, continue. The report having
  every line is a feature, not a formality.
- **Memory files are never overwritten, and carry no identity.** An existing file is left
  alone; a fresh `infra_status` goes next to it as `.new.md`. No machine name, user name or
  IP in it; paths start with `~`.
- **The full run really installs software and really elevates (Windows).** Do not test it
  on a machine you care about — the check-only mode exercises the same detection paths.
- **There are no tests.** Verification is a manual check-only run on Windows and on macOS.
  The risky areas are the sign-in detectors (they depend on file layouts owned by three
  other vendors) and WinGet repair.
