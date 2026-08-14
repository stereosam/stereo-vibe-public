# -*- coding: utf-8 -*-
"""Помощник сохранения памяти. Запуск на VPS, спека JSON по stdin:
  ssh <user>@<your-server> "python3 /path/to/memory/save_memory.py" < spec.json
Спека: {
  "date": "2026-06-21",                                  # опц.; иначе текущая дата NSK
  "last_saved": "2026-06-21" или "**Last saved: ...**",       # голую дату ОБЕРНЁТ сам; заменяет сущ. маркер
  "session_log": "| 2026-06-21 | проект | ~$ | ... |",   # +строка (идемпотентно) + месяц-сплит; no-op сейвы НЕ пишутся
  "grabli": ["текст без номера", ...],                   # +grabli.md, дедуп(норм.хэш) + СКВОЗНАЯ перенумерация 1..N
  "backlog": [                                            # операции с backlog_*.md (имя можно без .md — допишется)
     {"file":"backlog_x","id":"1-26","action":"done","note":"кратко что сделали"},
     {"file":"backlog_x","action":"add","title":"заголовок","note":"описание"},  # id опц. для add → авто max+1
     {"file":"backlog_x","id":"1-31","action":"add","done":true,"title":"...","note":"..."}  # add+done -> сразу в Changelog
  ],
  "sections": [{"file":"project_x_status","marker":"UPDATE 2026-..","text":"## UPDATE ..\\n.."}]
}
Всё идемпотентно + атомарная запись. grabli — пустой список [] = только перенумеровать/починить дубли.
Имя файла без расширения .md нормализуется автоматически (защита от файлов-сирот).
В конце — read-back: показывает фактически записанные Last saved / session_log tail / backlog-строки.
"""
import sys, io, os, json, re
from datetime import datetime, timedelta, timezone

BASE = os.path.dirname(os.path.abspath(__file__))


def _md(name):
    """Нормализация имени .md-файла: дописать расширение, если забыли. Без этого
    'backlog_x' читался как несуществующий -> done молча мимо, add плодил файл-сироту."""
    name = (name or "").strip()
    if name and not name.endswith(".md"):
        name += ".md"
    return name


def _read(p):
    fp = os.path.join(BASE, p)
    return io.open(fp, encoding="utf-8").read() if os.path.exists(fp) else ""


def _exists(p):
    return os.path.exists(os.path.join(BASE, p))


def _write(p, s):
    fp = os.path.join(BASE, p)
    tmp = fp + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(s)
    os.replace(tmp, fp)


def _nsk_date():
    return (datetime.now(timezone.utc) + timedelta(hours=7)).strftime("%Y-%m-%d")


def _norm(t):
    """Нормализованный ключ для дедупа: только буквы/цифры, нижний регистр."""
    return re.sub(r"[^0-9a-zа-яё]+", "", t.lower())


def _is_noop_log(sl, spec):
    """True, если строка session_log — пустой/no-op сейв (не логируем, чтоб не сорить).
    Критерий: явные фразы пустоты, ИЛИ стоимость ~$0 без единой правки в спеке."""
    if re.search(r"ничего не сделан|пуст(ый|ая|ой)\s+старт|^\s*\|\s*[—-]\s*\|", sl, re.I):
        return True
    has_work = bool(spec.get("backlog") or spec.get("sections") or spec.get("grabli"))
    if re.search(r"~?\$0(?![.\d])", sl) and not has_work:
        return True
    return False


def main():
    spec = json.load(sys.stdin)
    log = []
    date = spec.get("date") or _nsk_date()

    # 1. Last saved → MEMORY.md
    ls = spec.get("last_saved")
    if ls:
        ls = ls.strip()
        # Толерантность: голую дату оборачиваем в маркер (иначе строка без маркера
        # не найдётся при след. сейве → дублируется хвостом дат).
        if not ls.startswith("**Last saved:"):
            ls = "**Last saved: " + ls + "**"
        s = _read("MEMORY.md")
        lines = s.split("\n")
        done = False
        for i, l in enumerate(lines):
            if l.startswith("**Last saved:"):
                lines[i] = ls
                done = True
                break
        if not done:
            lines.append(ls)
        _write("MEMORY.md", "\n".join(lines))
        log.append("Last saved " + ("обновлён" if done else "добавлен"))

    # 2. session_log.md (+ месяц-сплит прошлых месяцев) + ВАЛИДАЦИЯ + no-op гард
    sl = spec.get("session_log")
    if sl:
        # Толерантность: достраиваем краевые '|' (принимаем 'дата | проект | текст').
        sl = sl.strip()
        if sl and not sl.startswith("|"):
            sl = "| " + sl
        if sl and not sl.endswith("|"):
            sl = sl + " |"
        if sl.count("|") < 4:
            log.append("session_log ОТКЛОНЁН (<3 столбцов даже после нормализации): " + sl[:50])
        elif _is_noop_log(sl, spec):
            log.append("session_log no-op (пропуск, не сорим логом): " + sl[:50])
        else:
            s = _read("session_log.md")
            if sl.strip() and sl.strip() not in s:
                s = s.rstrip() + "\n" + sl + "\n"
                log.append("session_log +строка")
            else:
                log.append("session_log дубль (пропуск)")
            m = re.search(r"\|\s*(\d{4})-(\d{2})-\d{2}", sl)
            if m:
                cur = m.group(1) + "-" + m.group(2)
                keep, moved = [], {}
                for ln in s.split("\n"):
                    mm = re.match(r"\|\s*(\d{4})-(\d{2})-\d{2}", ln)
                    if mm:
                        ym = mm.group(1) + "-" + mm.group(2)
                        if ym < cur:
                            moved.setdefault(ym, []).append(ln)
                            continue
                    keep.append(ln)
                if moved:
                    for ym, rows in sorted(moved.items()):
                        ap = "session_log_" + ym + ".md"
                        _write(ap, (_read(ap).rstrip() + "\n" + "\n".join(rows) + "\n").lstrip("\n"))
                    s = "\n".join(keep)
                    log.append("месяц-сплит session_log: " + ", ".join(sorted(moved)))
            _write("session_log.md", s)

    # 3. grabli.md — дедуп по норм.хэшу + СКВОЗНАЯ перенумерация 1..N (чинит дубли)
    if "grabli" in spec:
        gr = spec.get("grabli") or []
        s = _read("grabli.md")
        lines = s.split("\n")
        first = next((i for i, l in enumerate(lines) if re.match(r"^\d+\.\s", l)), len(lines))
        preamble = "\n".join(lines[:first]).rstrip()
        entries, cur = [], None
        for l in lines[first:]:
            if re.match(r"^\d+\.\s", l):
                if cur is not None:
                    entries.append(cur.rstrip())
                cur = re.sub(r"^\d+\.\s", "", l)
            elif cur is not None:
                cur += "\n" + l
        if cur is not None:
            entries.append(cur.rstrip())
        # 2026-08-01: грабли разнесены по темам (grabli_<тема>.md + grabli_archive.md).
        # grabli.md = индекс + ВХОДЯЩИЕ. Дедуп — по всем файлам; нумерация — продолжение
        # глобального максимума (историч. номера в тем-файлах не трогаем).
        import glob as _glob
        base = 0
        theme_keys = set()
        for tf in _glob.glob(os.path.join(BASE, "grabli_*.md")):
            t = io.open(tf, encoding="utf-8").read()
            cur2 = None
            for tl in t.split("\n"):
                if re.match(r"^\d+\.\s", tl):
                    base = max(base, int(re.match(r"^(\d+)\.", tl).group(1)))
                    if cur2 is not None:
                        theme_keys.add(_norm(cur2))
                    cur2 = re.sub(r"^\d+\.\s", "", tl)
                elif cur2 is not None:
                    cur2 += "\n" + tl
            if cur2 is not None:
                theme_keys.add(_norm(cur2))
        seen = {_norm(e) for e in entries} | theme_keys
        added = []
        for g in gr:
            g = (g or "").strip()
            if not g or _norm(g) in seen:
                continue
            entries.append(g)
            seen.add(_norm(g))
            added.append(len(entries))
        body = "\n".join("{0}. {1}".format(i, e) for i, e in enumerate(entries, base + 1))
        out = (preamble + "\n\n" + body).strip() + "\n"
        if s.strip() != out.strip():
            # бэкап НЕ рядом с оригиналом (правило гигиены 2026-08-01)
            bdir = "/path/to/backups/grabli_renumber"
            os.makedirs(bdir, exist_ok=True)
            io.open(os.path.join(bdir, "grabli.md." + date.replace("-", "")), "w", encoding="utf-8").write(s)
        _write("grabli.md", out)
        dup_fixed = "; входящих {0}, нумерация от {1}".format(len(entries), base + 1)
        log.append("grabli +{0}{1}".format(added if added else "0", dup_fixed))

    # 4. backlog_*.md — закрыть/добавить задачи (идемпотентно)
    STATUS = "🟡🟢🔴⚪🔄⭐❌"
    for b in spec.get("backlog") or []:
        f = _md(b.get("file")); bid = str(b.get("id", "")).strip(); act = b.get("action")
        # Толерантность: add без id -> авто max(id)+1 по префиксу файла.
        if act == "add" and not bid and f and _exists(f):
            _ids = re.findall(r"(?m)^\|\s*(\d+)-(\d+)\s*\|", _read(f))
            if _ids:
                _pref = _ids[0][0]
                _mx = max(int(n) for p, n in _ids if p == _pref)
                bid = "{0}-{1}".format(_pref, _mx + 1)
                log.append("backlog {0}: авто-id {1}".format(f, bid))
        if not f or not bid or act not in ("done", "add"):
            log.append("backlog ОТКЛОНЁН (file/id/action): " + json.dumps(b, ensure_ascii=False)[:60])
            continue
        if not _exists(f):
            if act == "done":
                log.append("{0} {1}: ФАЙЛА НЕТ -> done пропущен (проверь имя)".format(f, bid))
                continue
            log.append("ВНИМАНИЕ: {0} не существует — создаю новый под add".format(f))
        s = _read(f)
        note = (b.get("note") or "").strip()
        if act == "done":
            lines = s.split("\n")
            hit = False
            for i, l in enumerate(lines):
                if re.match(r"^\|\s*" + re.escape(bid) + r"\s*\|", l):
                    hit = True
                    if "✅ DONE" in l or "✅ ~~" in l:
                        log.append("{0} {1} уже DONE (пропуск)".format(f, bid))
                        break
                    l2 = re.sub(r"(\|\s*" + re.escape(bid) + r"\s*\|\s*)([" + STATUS + r"]\s*)?",
                                r"\1✅ ", l, count=1)
                    rs = l2.rstrip()
                    if rs.endswith("|"):
                        rs = rs[:-1].rstrip()
                    suffix = " **DONE {0}{1}** |".format(date, (": " + note) if note else "")
                    lines[i] = rs + suffix
                    _write(f, "\n".join(lines))
                    log.append("{0} {1} -> DONE".format(f, bid))
                    break
            if not hit:
                log.append("{0} {1} НЕ найдена в файле (пропуск)".format(f, bid))
        elif act == "add":
            if re.search(r"(?m)^\|\s*" + re.escape(bid) + r"\s*\|", s):
                log.append("{0} {1} уже есть (пропуск add)".format(f, bid))
                continue
            title = (b.get("title") or "").strip()
            if b.get("done"):
                row = "| {0} | ✅ DONE {1} — {2} | {3} |".format(bid, date, title, note)
                m = re.search(r"(?m)^##\s*Changelog[^\n]*\n", s)
                if m:
                    pos = m.end()
                    for hl in s[pos:].split("\n"):
                        if re.match(r"^\|\s*#\s*\|", hl) or re.match(r"^\|[\s:|-]+\|\s*$", hl):
                            pos += len(hl) + 1
                        else:
                            break
                    s = s[:pos] + row + "\n" + s[pos:]
                else:
                    s = s.rstrip() + "\n\n## Changelog (DONE)\n" + row + "\n"
                _write(f, s)
                log.append("{0} {1} +Changelog (done)".format(f, bid))
            else:
                row = "| {0} | {1} | {2} |".format(bid, title, note)
                anchor = "\n## Changelog"
                if anchor in s:
                    s = s.replace(anchor, "\n" + row + anchor, 1)
                else:
                    s = s.rstrip() + "\n" + row + "\n"
                _write(f, s)
                log.append("{0} {1} +добавлена".format(f, bid))

    # 5. sections → дописать в файл, если маркера нет
    for sec in spec.get("sections") or []:
        f, marker, text = _md(sec["file"]), sec["marker"], sec["text"]
        s = _read(f)
        if marker not in s:
            s = s.rstrip() + "\n\n" + text + "\n"
            _write(f, s)
            log.append(f + " +секция")
        else:
            log.append(f + " секция есть (пропуск)")

    print("OK")
    for x in log:
        print(" -", x)

    # 6. READ-BACK — показать что фактически легло (страховка от молчаливого мимо)
    print("--- read-back ---")
    ls2 = next((l for l in _read("MEMORY.md").split("\n") if l.startswith("**Last saved:")), "")
    if ls2:
        print("  Last saved:", ls2[:110])
    sl_lines = [l for l in _read("session_log.md").split("\n") if l.strip().startswith("| 20")]
    if sl_lines:
        print("  session_log tail:", sl_lines[-1][:110])
    for b in spec.get("backlog") or []:
        f = _md(b.get("file")); bid = str(b.get("id", "")).strip()
        if not f or not bid or not _exists(f):
            continue
        for l in _read(f).split("\n"):
            if re.match(r"^\|\s*" + re.escape(bid) + r"\s*\|", l):
                print("  {0} {1}: {2}".format(f, bid, l.strip()[:100]))
                break


if __name__ == "__main__":
    main()
