# AGENTS.md

Things that are not visible from the code.

- **Two implementations, no shared core.** `windows/core/check-work-tools.ps1` and
  `macos/core/check-work-tools-macos.command` are hand-kept at feature parity. A change to
  one is incomplete until it is made in the other.
- **`.cmd` launchers must stay ASCII-only.** `cmd.exe` parses them in the OEM codepage;
  one Cyrillic character in an `echo` or `REM` breaks the launcher with an unrelated-looking
  error. All localized text belongs in the `.ps1`. The same applies to the shim files the
  script generates at runtime.
- **macOS still ships bash 3.2.** No associative arrays, no `${var^^}`, no `mapfile`. The
  memory templating uses `${var//pattern/replacement}` for exactly this reason.
- **Never add a default telemetry endpoint.** `-ReportUrl` / `--report-url` /
  `STEREO_REPORT_URL` are empty on purpose; empty means nothing is sent and no machine id
  is generated.
- **A check may never abort the run.** Wrap it, record a row, continue. The report having
  every line is a feature, not a formality.
- **Memory files are never overwritten.** The installer writes into a folder a human edits.
  An existing file is left alone; a fresh `infra_status` goes next to it as `.new.md`.
- **Repair mode really installs software and really elevates.** Do not test it on a machine
  you care about — `-ReportOnly` / `--report-only` exercise the same code paths.
- **There are no tests.** Verification is a manual report-only run on Windows and on macOS.
  The risky areas are the login detectors (they depend on file layouts owned by three other
  vendors) and the elevation dance around launching the agent.
