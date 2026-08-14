Выполни workflow **"сохранись"** из MEMORY.md (раздел «сохранись / save» — единственный источник шагов; здесь НЕ дублируем детали формата).

ЧТЕНИЕ (без SSH): прочитай актуальный блок из ЛОКАЛЬНОГО зеркала — файл `<home>\YandexDisk\CLAUDE\claude_memory\MEMORY.md`, раздел между строкой «**"сохранись"» и «Ждать команды». Текущее содержимое статус-файлов/session_log/grabli тоже читай из зеркала `claude_memory/` (мгновенно). Если зеркала нет — фолбэк по SSH.

ШАГ 0 (перед сборкой спеки): `ssh <user>@<your-server> "python3 /path/to/memory/save_prep.py [проект]"` — read-only дайджест: Last saved, хвост session_log, max № grabli, Активные backlog (чтобы не забыть закрыть и не продублировать id).

ЗАПИСЬ — ОДНИМ заходом через помощник (не bespoke-скрипт, не несколько SSH): собери spec.json (поля: last_saved, session_log, grabli, **backlog**, sections — полный формат в docstring `save_memory.py` и MEMORY workflow) и:
`ssh <user>@<your-server> "python3 /path/to/memory/save_memory.py" < spec.json`
Помощник идемпотентен/атомарен: авто-месяц-сплит session_log, сквозная нумерация grabli, закрытие/добавление backlog. ТОЛЕРАНТЕН к формату (20.07): last_saved можно голой датой (обернёт в **Last saved: ..** сам), session_log без краевых | (достроит), backlog action add без id (авто max+1) — форматных отказов нет. Грабли — в grabli.md (НЕ в CLAUDE.md).
