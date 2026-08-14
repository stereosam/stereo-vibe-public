# -*- coding: utf-8 -*-
"""Заводит новый проект в памяти. Запуск на VPS.
  ssh <user>@<your-server> "python3 /path/to/memory/new_project.py --name <name> [--desc '..'] [--dir '..'] [--number N] [--dry-run]"

Что делает (атомарно, идемпотентно):
  1. Источник карты номеров — блок «## Маппинг проектов → директории» в MEMORY.md.
     Свободный номер = младший, которого нет в карте (ретро/слитые тоже числятся занятыми).
  2. Создаёт <name>_status.md (frontmatter + 4 раздела) и <name>_backlog.md (таблица).
     Если любой из файлов УЖЕ есть — СТОП, ничего не трогает (правило «не перезатирать без чтения»).
  3. Дописывает ОДНУ строку в маппинг MEMORY.md.
  4. Строка в session_log.md.
  --dry-run: только показать план (номер + что создаст), без записи.

Пишем ТОЛЬКО тут, на VPS. Синк раздаёт вниз сам. Новых файлов-реестров не плодим —
источник один (MEMORY.md), CLAUDE.md/go.md/new.md на него лишь ссылаются.
"""
import sys, io, os, re, argparse
from datetime import datetime, timedelta, timezone

BASE = os.path.dirname(os.path.abspath(__file__))
MAP_HEADER = "## Маппинг проектов → директории"


def _p(name):
    return os.path.join(BASE, name)


def _read(name):
    fp = _p(name)
    return io.open(fp, encoding="utf-8").read() if os.path.exists(fp) else ""


def _write(name, s):
    fp = _p(name)
    tmp = fp + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(s)
    os.replace(tmp, fp)


def _nsk_date():
    return (datetime.now(timezone.utc) + timedelta(hours=7)).strftime("%Y-%m-%d")


def _map_bounds(memory):
    """Границы блока маппинга: (start_idx, end_idx) по строкам."""
    lines = memory.split("\n")
    start = None
    for i, l in enumerate(lines):
        if l.strip() == MAP_HEADER:
            start = i
            break
    if start is None:
        raise SystemExit("[FAIL] в MEMORY.md не найден блок '%s'" % MAP_HEADER)
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("## "):
            end = j
            break
    return lines, start, end


def _taken_numbers(lines, start, end):
    """Все номера из тела маппинга: ловим 'N=' и 'N ретро/слитые'."""
    body = "\n".join(lines[start + 1:end])
    return set(int(n) for n in re.findall(r"(\d+)=", body))


def _free_number(taken):
    n = 1
    while n in taken:
        n += 1
    return n


def _names_in_map(lines, start, end):
    body = "\n".join(lines[start + 1:end])
    return set(m.lower() for m in re.findall(r"\d+=([A-Za-z0-9_]+)", body))


STATUS_TMPL = """---
name: {name}
description: Проект {n} — {desc}
type: project
---

# {name} — ТЕКУЩАЯ ПРАВДА

## Что за проект
{about}

## Где артефакты
- Папка: {dir}

## Как устроено (стек / пути / конфиги)
- TODO

## Грабли
- (пока нет)
"""

BACKLOG_TMPL = """# Backlog — {name} (проект {n})
{desc}. Детали — в {name}_status.md.

## Активные
| # | Задача | Заметки |
|---|---|---|
| {n}-1 | Определить MVP и первые шаги |  |

## Changelog (DONE)
| # | Задача | Заметки |
|---|---|---|
| {n}-2 | ✅ DONE {date} — Оформлен как проект {n} командой /new |  |
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="snake_case имя проекта")
    ap.add_argument("--desc", default="", help="одна строка описания")
    ap.add_argument("--dir", default="", help="папка артефактов (опц.)")
    ap.add_argument("--number", type=int, default=0, help="номер вручную (иначе младший свободный)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    name = a.name.strip()
    if not re.fullmatch(r"[a-z0-9_]+", name):
        raise SystemExit("[FAIL] имя '%s' — только строчные латиница/цифры/подчёркивание" % name)

    desc = a.desc.strip() or "TODO: заполнить описание"
    date = _nsk_date()

    memory = _read("MEMORY.md")
    lines, start, end = _map_bounds(memory)
    taken = _taken_numbers(lines, start, end)
    names = _names_in_map(lines, start, end)

    # --- проверки перед созданием ---
    status_f = name + "_status.md"
    backlog_f = name + "_backlog.md"
    problems = []
    if name in names:
        problems.append("имя '%s' уже есть в маппинге MEMORY.md" % name)
    if os.path.exists(_p(status_f)):
        problems.append("%s уже существует" % status_f)
    if os.path.exists(_p(backlog_f)):
        problems.append("%s уже существует" % backlog_f)
    if a.number and a.number in taken:
        problems.append("номер %d уже занят в маппинге" % a.number)
    if problems:
        raise SystemExit("[FAIL] не создаю (правило «не перезатирать»):\n  - " + "\n  - ".join(problems))

    n = a.number or _free_number(taken)

    dir_txt = a.dir.strip() or "TODO (серверный проект — папки на ПК может не быть)"
    about = desc if desc != "TODO: заполнить описание" else "TODO: заполнить"

    plan = (
        "[PLAN]\n"
        "  номер:   %d\n"
        "  имя:     %s\n"
        "  описание: %s\n"
        "  файлы:   %s , %s\n"
        "  маппинг: строка '%d=%s' в MEMORY.md\n"
        "  session_log: + строка за %s"
        % (n, name, desc, status_f, backlog_f, n, name, date)
    )
    if a.dry_run:
        print(plan)
        print("[DRY-RUN] ничего не записано.")
        return

    # --- запись файлов ---
    _write(status_f, STATUS_TMPL.format(name=name, n=n, desc=desc, about=about, dir=dir_txt))
    _write(backlog_f, BACKLOG_TMPL.format(name=name, n=n, desc=desc, date=date))

    # --- маппинг: новая строка в конце блока ---
    entry = "%d=%s (%s)" % (n, name, desc)
    new_lines = lines[:end] + [entry] + lines[end:]
    _write("MEMORY.md", "\n".join(new_lines))

    # --- session_log ---
    sl = _read("session_log.md")
    log_line = "| %s | %s | Заведён проект %d командой /new (%s, %s) |" % (date, name, n, status_f, backlog_f)
    if log_line not in sl:
        sl = sl.rstrip("\n") + "\n" + log_line + "\n"
        _write("session_log.md", sl)

    print(plan)
    print("[OK] проект %d '%s' заведён." % (n, name))
    print("     created: %s , %s" % (status_f, backlog_f))
    print("     mapping: +'%s' в MEMORY.md" % entry)


if __name__ == "__main__":
    main()
