# CLAUDE.md — project rules

You are working in a vibe-coding project. Answer plainly, without filler. The person you
help may be new to this — explain in plain words.

## START OF A CONVERSATION
- Run `hostname` and `date` — know which machine you are on and what day it is.
- Never guess the date. Take it from `date`.

## READ BEFORE YOU TOUCH
- Before changing or deleting a file, read it in full, in this session.
- Did not read it — do not touch it. Overwrite and delete are irreversible: there is no
  getting it back.
- Unsure whether this is the right file, or whether you may touch it at all — stop and ask
  instead of guessing.

## DO NOT BREED FILES
- Everything lives inside the project. Before creating a new file, look for an existing one
  on the same topic and write there.
- No suitable project for the task — start a new one, or add it as a section to an existing
  one. Do not drop the file somewhere random.
- Files go in their own project folder. Not on the desktop, not in random places.
- One file per topic: one long file with sections beats ten short ones.
- Drafts and anything temporary go to `scratch/`, not into the project.
- Backups go to `backup/`, never next to the original.

## THE MACHINE: what exists and where to look → memory/infra_status.md
Your environment is described in `memory/infra_status.md`. Look there for:
- the machine: OS, where projects live, what is installed (editor, git, Node, agent CLIs);
- access: which AI CLIs are signed in, where the credentials live, what is paid for;
- network: which AI endpoints this machine can actually reach;
- services: where sites and bots are deployed, where the dashboards and logins are.
- Think a tool or an access is missing → read `memory/infra_status.md` FIRST, then ask.
- Something new appeared (a program, a key, an account, a service) → write it there right
  away. Not written down means the next conversation will not know about it.

## THE PROJECT: what is true and what is left → memory/
- `memory/PROJECT_status.md` — current truth: what this project is, how it works, where
  things live, what is broken. Overwritten in place as reality changes.
- `memory/PROJECT_backlog.md` — tasks: Active, and a Changelog of what is done.
- `memory/PROJECT_history.md` — append-only log. One event, one line. Never rewritten.

Three files rather than one because they have three different lifetimes. Read status and
backlog before starting work; add to history when something actually changed.
