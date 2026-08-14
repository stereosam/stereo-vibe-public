# -*- coding: utf-8 -*-
"""Read-only дайджест для сборки spec.json перед сохранением.
  ssh <user>@<your-server> "python3 /path/to/memory/save_prep.py [проект]"
Ничего НЕ пишет. Показывает: Last saved, хвост session_log, номера grabli,
и Активные задачи бэклога(ов) — чтобы не забыть закрыть/не продублировать id.
"""
import sys, io, os, re, glob

BASE = os.path.dirname(os.path.abspath(__file__))


def read(p):
    fp = os.path.join(BASE, p)
    return io.open(fp, encoding="utf-8").read() if os.path.exists(fp) else ""


def pick(*names):
    """Первое существующее имя из вариантов (пилот новой схемы имён 2026-08-01)."""
    import os as _os
    for n in names:
        if _os.path.exists(_os.path.join(BASE, n)):
            return n
    return names[0]


def active_tasks(fname):
    """Строки раздела «Активные» (id + кратко)."""
    s = read(fname)
    out, on = [], False
    for l in s.split("\n"):
        if re.match(r"^##\s*Активные", l):
            on = True; continue
        if re.match(r"^##\s", l):
            on = False
        if on and re.match(r"^\|\s*[\w-]+\s*\|", l) and "| #" not in l and "---" not in l:
            c = [x.strip() for x in l.split("|")]
            if len(c) >= 3:
                out.append((c[1], c[2][:70]))
    return out


def main():
    arg = sys.argv[1].strip() if len(sys.argv) > 1 else None

    print("===== SAVE-PREP (read-only) =====")
    ls = next((l for l in read("MEMORY.md").split("\n") if l.startswith("**Last saved:")), "")
    print("\n[Last saved]\n  " + (ls[:160] if ls else "—"))

    print("\n[session_log — последние 5]")
    sl = [l for l in read("session_log.md").split("\n") if l.strip().startswith("| 20")]
    for l in sl[-5:]:
        print("  " + l[:130])

    g = read("grabli.md")
    nums = [int(m.group(1)) for m in re.finditer(r"(?m)^(\d+)\.\s", g)]
    print("\n[grabli] всего: {0}, последний номер: {1}".format(len(nums), max(nums) if nums else 0))

    print()
    print("[гигиена — размеры сверх порога]")
    checks = [("grabli.md", 50), ("session_log.md", 60)]
    if arg:
        checks.append((pick(arg + "_status.md", "project_" + arg + "_status.md"), 30))
    else:
        _st = set(glob.glob(os.path.join(BASE, "project_*_status.md")) +
                  glob.glob(os.path.join(BASE, "*_status.md")))
        checks += sorted((os.path.basename(p), 30) for p in _st)
    fat = False
    for f, lim in checks:
        fp = os.path.join(BASE, f)
        if os.path.exists(fp) and os.path.getsize(fp) > lim * 1024:
            print("  !! {0}: {1} КБ (порог {2}) — предложить отжимку/разнос".format(
                f, os.path.getsize(fp) // 1024, lim))
            fat = True
    if not fat:
        print("  ok")

    files = [pick(arg + "_backlog.md", "backlog_" + arg + ".md")] if arg else sorted(
        os.path.basename(p) for p in set(
            glob.glob(os.path.join(BASE, "backlog_*.md")) +
            glob.glob(os.path.join(BASE, "*_backlog.md"))))
    print("\n[backlog — Активные задачи]")
    for f in files:
        tasks = active_tasks(f)
        if not tasks and not os.path.exists(os.path.join(BASE, f)):
            print("  {0}: НЕТ ФАЙЛА".format(f)); continue
        print("  --- {0} ({1} активных) ---".format(f, len(tasks)))
        for tid, desc in tasks:
            print("    {0} | {1}".format(tid, desc))

    print("\nДальше: собрать spec.json (last_saved/session_log/grabli/backlog/sections) "
          "и: ssh ... save_memory.py < spec.json")


if __name__ == "__main__":
    main()
