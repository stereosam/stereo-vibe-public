# memory/ — what the agent reads before it starts guessing

An agent does not remember the last session. It remembers a file. This folder is that file,
split into four, because the four have different lifetimes.

| file | lifetime | rule |
|---|---|---|
| `infra_status.md` | changes when the machine changes | written by the installer from live detection, then maintained by hand |
| `PROJECT_status.md` | current truth | **overwritten in place**; a line that stopped being true gets replaced, not appended to |
| `PROJECT_backlog.md` | tasks in flight | Active → Changelog; nothing is deleted |
| `PROJECT_history.md` | the record | **append only**; never edited retroactively |

Keeping status and history in one file is the mistake this layout exists to prevent: the
file either fills up with stale dated sections, or loses the record of how things got here.

## Naming

With one project per folder, the `PROJECT_` prefix can stay. With several, rename them
`<project>_status.md`, `<project>_backlog.md`, `<project>_history.md` and give each project
a number. Task ids then read `13-4` — project 13, task 4 — and the agent can jump straight
to the right file and the right row without searching.

## infra_status.md is generated, then owned by you

The installer writes it once, from the checks it had just run: OS and build, what is
installed and at which version, which agent is signed in, which endpoints were reachable.
It never overwrites it afterwards — a second run leaves `infra_status.new.md` beside it, so
you can compare and merge by hand.

Everything that comes later — accounts, deploy targets, panels, what is paid for and until
when — is yours to add. The rule that makes it work: something new appeared, write it here
the same day. Memory that is out of date is worse than no memory at all.
