# STEREO VIBE

STEREO VIBE is a one-click starter kit that turns a bare Windows or macOS machine into a
working AI-coding setup. It checks and installs Git, Node and a coding-agent CLI (Claude
Code, Codex or Gemini), verifies you are logged in, then scaffolds the agent's memory:
a `CLAUDE.md` and a `memory/` folder pre-filled with what it just detected about the machine.

**Platforms:** Windows 10 (1809+) / 11 · macOS 13+
**Dependencies:** none. Two self-contained scripts — PowerShell and bash.
**Portable:** runs from a USB stick; every path inside is relative to the script.
**Note on language:** the console UX is Russian (the kit was built for a Russian-speaking
workshop). Identifiers, docs and commit messages are English. See "Reading the output" below.

---

## The problem

Every guide to agentic coding starts at "open your terminal and run the agent". The gap is
before that, and it is where people actually get stuck:

- the CLI is installed but not signed in — and an unauthenticated CLI looks exactly like a
  working one until it doesn't;
- Node is installed but not in this shell's `PATH`, so the check says "missing" and the
  person reinstalls what they already have;
- the package manager dies halfway through because the terminal is not elevated, and the
  only symptom is "it started installing and gave up";
- the endpoints the agent needs are blocked on this network, and the failure mode is a
  timeout ten minutes later, not an error;
- and once the agent finally runs, it knows nothing about the machine it runs on.

STEREO VIBE is one pass that closes all five and ends with a verdict:
**ENVIRONMENT READY** (exit code 0) or **NOT READY** with the exact list of what is left.

## What it does, in order

1. **System** — free disk space, OS version.
2. **Tools** — PowerShell, WinGet, Git, Node.js LTS (Homebrew, Git, Node on macOS).
3. **AI CLIs** — Claude Code, Codex and Gemini CLI, each on its own line. Any one of them
   is enough; missing the other two is not a blocker.
4. **Sign-in** — the check that actually matters: `codex login status`,
   `~/.claude/.credentials.json`, `~/.gemini/oauth_creds.json`, API keys in the environment.
5. **Desktop apps** — detected properly (on Windows the ChatGPT app ships as the Appx
   package `OpenAI.Codex`, which is *not* the `codex` CLI — a distinction that confuses
   people daily).
6. **Reachability** — a real HTTPS request to `api.anthropic.com`, `api.openai.com` and
   `generativelanguage.googleapis.com`, with retries. Any HTTP answer, including 401,
   counts as reachable; only a dropped connection counts as blocked.
7. **Live test** (opt-in) — an actual one-word prompt through the installed CLI. Proves
   login, network and quota in one shot. Off by default: it spends quota.
8. **Verdict** — every row is always printed, blockers are listed with the exact fix.
9. **Get to work** — signs you in if needed, creates the project folder, `git init`s it,
   writes the agent's memory (below), and launches the agent **in a separate window,
   unelevated**, leaving a `START-<agent>` shortcut in the project folder.

## The part I would read first: it installs memory, not just tools

Step 9 is the reason this repository exists.

The installer has just found out everything an agent normally has to guess in its first
session: the OS and build, what is installed and at which version, which agent you are
signed into, which endpoints are unreachable from here. Instead of dropping that into a
log, it writes it into the project:

```
~/stereo-vibe/
├─ CLAUDE.md              rules the agent reads before touching anything
├─ memory/
│  ├─ infra_status.md     filled in from the checks that just ran — not a placeholder
│  ├─ PROJECT_status.md   current truth about the project (overwritten in place)
│  ├─ PROJECT_backlog.md  tasks: Active + Changelog
│  └─ PROJECT_history.md  append-only log, never edited retroactively
├─ scratch/               drafts — so they never land in the project
└─ backup/                backups — so they never land next to the original
```

A generated `infra_status.md` looks like this, with real values:

```markdown
## Installed
| tool | version |
|---|---|
| Git | 2.55.0 |
| Node.js | 24.19.0 |

## AI agents
| CLI | installed | signed in |
|---|---|---|
| Claude Code | 2.1.228 | yes |
| Codex | 0.147.0 | no |
| Gemini CLI | not installed | — |

## Network reachability, measured at install time
| endpoint | reachable |
|---|---|
| api.anthropic.com | yes |
| generativelanguage.googleapis.com | no |
```

Three memory files rather than one, because they have three different lifetimes:
**status is overwritten, history only grows, backlog lives in between.** The shape matters
more than the content — the agent knows where to look before it has read anything.

Nothing is ever overwritten: an existing file is left alone, and a second run writes
`infra_status.new.md` next to the old one instead of clobbering your edits. The external IP
is deliberately not recorded — only whether each endpoint answered.

`templates/CLAUDE.md` is the rule set that ships with it — read before you touch, do not
breed files, drafts to `scratch/`, backups to `backup/`, and "think a tool is missing?
read `memory/infra_status.md` first, then ask". The Russian original is next to it as
`CLAUDE.ru.md`; the installer picks by system language, or by `-Lang en|ru` / `--lang en|ru`.

## Install

Nothing to build, nothing to configure, no keys.

**Windows**
```powershell
git clone https://github.com/stereosam/stereo-vibe-public
cd stereo-vibe-public

# safe first run: reports only, changes nothing on your machine
windows\core\run-check-report-only.cmd

# full run: installs what is missing, asks for elevation via UAC
windows\run-check-windows.cmd
```

**macOS**
```bash
git clone https://github.com/stereosam/stereo-vibe-public
cd stereo-vibe-public
chmod +x macos/START-macOS.command macos/core/check-work-tools-macos.command

bash macos/core/check-work-tools-macos.command --report-only   # safe first run
./macos/START-macOS.command                                    # full run
```

**Start with report-only.** The full run installs software: it self-elevates through UAC on
Windows, and it will run `winget install` / `brew install` / `npm install -g` for anything
missing. That is the point of the tool, but you should see the report before you let it.
On macOS it never uses `sudo` — Homebrew refuses to run as root and installs into the user
prefix anyway.

Flags: `-ReportOnly` / `--report-only`, `-LiveTest` / `--live-test`,
`-PreferredAI Codex|Claude|Gemini` / `--ai codex|claude|gemini`, `-Lang` / `--lang`.

## Reading the output

The console is Russian. The status tags are not, and they carry the meaning:

| tag | status | meaning |
|---|---|---|
| `[OK]` | READY | installed, and for an AI CLI, signed in |
| `[+]` | REPAIRED | installed or updated during this run |
| `[^]` | UPDATE | installed, newer version exists — not a blocker |
| `[!]` | LOGIN | installed but not signed in — **this is a blocker** |
| `[-]` | ABSENT | this AI CLI is missing, but another one works — not a blocker |
| `[X]` | MISSING / BLOCKED | missing, or an endpoint is unreachable — blocker |
| `[!!]` | ERROR | the check itself failed |
| `[-]` | N/A | does not apply on this OS |

The run ends with `ENVIRONMENT READY` (exit 0) or `NOT READY` (exit 1) plus the list of
blockers, and always writes `reports/log_<timestamp>.txt` and `reports/report_<timestamp>.json`
next to the script — or to the temp directory if the folder is read-only, which is what
happens when you run it from a locked USB stick.

## Design decisions worth stealing

Each of these is a bug that reached a real person before it became a rule.

- **Presence-first.** Installed is green. An available update is a note, not a blocker.
  Onboarding that fails on "you are one patch version behind" gets abandoned.
- **The update check is physically read-only.** `winget list --upgrade-available` cannot
  install anything even if it wanted to. Installation happens only in repair mode.
- **Every check is independent.** One failure adds a row; it never aborts the run. The
  report always has every line, which is what makes it useful to send to someone else.
- **Installed ≠ working.** The sign-in gate is the whole point: an unauthenticated CLI
  reports a version number happily.
- **"Installed but not on PATH" is its own answer.** Known executable locations are probed
  before declaring something missing, so nobody is sent to install what they already have.
- **De-escalation before launching the agent.** The kit runs elevated because package
  installs need it. Spawning the agent normally from an elevated process would hand it the
  same rights — and, worse, the OAuth browser opens in a different session without the
  user's cookies, so sign-in silently does nothing. The agent is therefore started through
  the file manager, which runs unelevated, and inherits *its* level.
- **Launchers stay ASCII-only.** `cmd.exe` parses `.cmd` files in the OEM codepage; a
  Cyrillic character in an `echo` or `REM` breaks parsing outright. All localized text
  lives in the `.ps1`.
- **Two sources for geo, retries for probes.** A single provider is a single point of
  failure: one timed-out lookup used to flip the verdict of the entire run.
- **One place writes state.** Detection used to print one thing and report another,
  because the network probe updated the screen but not the state variable.
- **Menu numbering is computed, never hardcoded.** An entry that was hidden because you
  were not signed in used to leave a number that did nothing — which reads as a broken app.
- **Memory is never overwritten.** The installer writes files the agent will read, and the
  same rule it gives the agent applies to itself: an existing file is somebody's edit.

## Telemetry

**Off.** The kit can POST a one-line verdict to an endpoint of your choice — that is how
the workshop version lets a mentor see who is stuck — but there is no default endpoint in
this repository. Pass `-ReportUrl https://your.server/...` (or `--report-url`, or set
`STEREO_REPORT_URL` on macOS) if you want it. With no URL, nothing leaves the machine and
no machine id is generated.

## Roadmap

- Sign the Windows launcher, or wrap it in a small signed executable, to stop the
  SmartScreen warning on a freshly downloaded `.cmd`.
- Check quota and billing, not just the fact of a sign-in.
- English console UX behind a switch (the checks are language-agnostic already).
- Optional editor checks (VS Code and extensions).
- One shared check definition instead of two hand-synced implementations.
- Write `infra_status` into a diff on every run, so an agent can see what changed on the
  machine since last time.

## Known limitations

- **The console output is Russian.** The status tags, exit codes and JSON report are not,
  and the table above maps them. Translating the UX is on the roadmap; doing it badly
  halfway would be worse than doing it not at all.
- **Two implementations, kept at parity by hand.** Windows is PowerShell, macOS is bash,
  and there is no shared core. Every behavioural change has to be made twice. This is the
  main structural debt.
- **No test suite.** Verification is a manual report-only run on a real machine. There is
  no way to unit-test "winget lies about this package" anyway, but the absence is real.
- **Repair mode installs software.** It self-elevates on Windows and runs package managers.
  Run report-only first, on any machine you care about.
- **The macOS launcher clears the quarantine attribute** (`xattr -dr com.apple.quarantine`)
  on its own folder, otherwise Gatekeeper blocks a double-clicked `.command` downloaded
  from the internet. That is deliberate and it is visible in the first ten lines of the
  file — read it before you run it.
- **Linux is not supported.**
- **Offline installers are not included.** The kit will install from a local folder when
  there is no network; the binaries are yours to drop in (see the READMEs under
  `*/core/installers/`).
- **The workshop version does more than this one.** Where AI providers are unreachable, it
  also walks the student through connecting a tunnel. That part is specific to a private
  service and is not published; what remains here is the diagnosis, which is the part that
  generalizes.

## License

MIT.
