# infra_status — this machine

> Written by the STEREO VIBE installer on {{DATE}}, from the checks it had just run.
> A starting point, not the truth forever: when something changes, edit it here.
> The agent reads this file before it starts guessing about the environment.

## Machine
- OS: {{OS_NAME}} {{OS_BUILD}}
- Host: {{HOSTNAME}}
- Free space on the system drive: {{DISK_FREE}}
- Projects live in: {{PROJECT_DIR}}
- Installer logs and JSON reports: {{REPORT_DIR}}

## Installed
| tool | version |
|---|---|
| Git | {{GIT_VERSION}} |
| Node.js | {{NODE_VERSION}} |
| {{PKG_MANAGER}} | {{PKG_VERSION}} |
| {{SHELL_NAME}} | {{SHELL_VERSION}} |

## AI agents
| CLI | installed | signed in |
|---|---|---|
| Claude Code | {{CLAUDE_INSTALLED}} | {{CLAUDE_LOGGED_IN}} |
| Codex | {{CODEX_INSTALLED}} | {{CODEX_LOGGED_IN}} |
| Gemini CLI | {{GEMINI_INSTALLED}} | {{GEMINI_LOGGED_IN}} |

Installed is not the same as usable: a CLI that is not signed in reports a version number
just as happily as one that works.

## Network reachability, measured at install time
| endpoint | reachable |
|---|---|
| api.anthropic.com | {{EP_ANTHROPIC}} |
| api.openai.com | {{EP_OPENAI}} |
| generativelanguage.googleapis.com | {{EP_GOOGLE}} |

Not re-measured since. If a call fails with a timeout rather than an error, check this
before blaming the code.

## Accounts and services
<!-- Fill in as you go, one line each: where the site is hosted, which bot, which panel,
     where the keys live, what is paid for and until when. -->

## Anything else worth knowing
<!-- Machine quirks: a corporate policy that blocks installs, a disk that fills up weekly,
     a second account. Whatever you had to explain to the agent twice. -->
