Работа с Fleet Board (дашборд парка). Аргумент: $ARGUMENTS

# Fleet Board — карта и как добавлять плитки

**Где:** `<home>\fleet_board\` (домашний ПК <workstation>, ВНЕ синка YandexDisk).
ПРАВИЛО: читать файл ПОЛНОСТЬЮ перед правкой; делать бэкап `*.bak.<ts>_<что>`.

## Архитектура
- **Окно-виджет:** `run_widget.py` (pywebview/WebView2) грузит `widget.html` (GridStack). Запуск: `pythonw run_widget.py` (Python312, НЕ venv). Иконка `Fleet Widget.lnk`. Один экземпляр — mutex `FleetWidgetSingleton`.
- **Данные (2 сборщика, пишут рядом, виджет читает через инжект `<script>` — обход file:// CORS):**
  - `status_collector.py` (30с, автозапуск `FleetCollector.vbs`) → `status.json` + `status.js` (`window.__STATUS__`). Сервисы ПК + **ОДИН ssh к VPS** (`vps_all()`: сервисы/диск/аптайм/туннели/ошибки/**скачивания disk-sync**) + Я.Диск-квота + диск C + корзина.
  - `hw_sampler.py` (3с, `FleetHW.vbs`) → `hw.js` (`window.__HW__`): CPU/RAM (psutil) + GPU/темпа/VRAM (nvidia-smi) + сеть + VPN.
- **Раскладка:** `layout.json` (позиции). Нет записи для плитки → autoPosition (свободное место); ручной drag → persist в layout.json.
- **Автозапуск (Startup .vbs):** FleetWidget + FleetCollector + FleetHW.

## РЕЦЕПТ: добавить плитку «X»
1. **Данные** в `status_collector.py`:
   - VPS-метрика → дописать `echo "KEY $(...)"` в `cmd` внутри `vps_all()` (там уже DISK/UP/TUN/ERR/DL*); добавить ветку парсинга `elif p[0]=="KEY":` → `res[...]`; в `res` init добавить ключ; в финальный `data={...}` добавить `"x": v.get("x")`.
   - ПК-метрика → отдельная функция + положить в `data`.
   - Кавычки в ssh-cmd: строки Python одинарные `'...'`, bash-двойные `"..."` внутри литералом (в т.ч. вложенные `"..."`/`$(...)` в `$()` — bash ок). СНАЧАЛА протестировать команду живым `ssh <user>@<your-server> '...'`, потом вшивать.
2. **widget.html** — 4 точки:
   - `buildTiles()`: `add('x',w,h);addHideCtx('x');` (w,h ×2 внутри add — сетка 12 кол.).
   - `draw()` (в `if(d){...}`): `if(d.x)set('x',valTile('',big,sub,'Лейбл'));` — данные из `d.x`. `valTile(ic,big,sub,lbl)` — ic игнор; иконка эмодзи в big/lbl или `icon('name')+...`.
   - `TILE_GROUPS`: добавить `'x'` в группу (для меню ➕).
   - `TILE_NAMES`: `x:'Имя плитки'` (подпись).
3. **layout.json** (опц.): позиция, иначе autoPosition + перетащить.
4. **Применить:**
   - `cd <home>\fleet_board && python status_collector.py` (обновит status.js данными). Проверить: `python -c "import json,io;print(json.load(io.open(r'<home>\fleet_board\status.json',encoding='utf-8')).get('x'))"`.
   - **Перезапустить виджет** (он кэширует widget.html): убить `pythonw run_widget.py` + ВСЕ `msedgewebview2` (иначе зомби лочат .wvdata), затем `Start-Process pythonw run_widget.py -WorkingDirectory <home>\fleet_board`.

## Источники данных (шпаргалка)
- VPS-метрики: один ssh в `vps_all()`.
- Скачивания disk-sync: nginx VPS `/var/log/nginx/disksync.access.log*` (у disksync СВОЙ лог!) — `grep StereoDiskSync_Setup.exe`; 200=полные, уник IP=скачавшие. Сейчас плитка `disksync` (DLUNIQ/DLTOTAL/DLTODAY).
- Метрика/визиты/цели: токен «Claude Metrika» в `reference_api_integrations.md`, счётчик 109706407, `curl -H "Authorization: OAuth <t>" https://api-metrika.yandex.net/stat/v1/data?ids=109706407&...`. Цели: 566797911 download.

## СЛОТЫ — быстрый способ добавить виджет (предпочтительно)
Владелец сам создаёт пустой слот и ставит куда хочет, Claude вписывает только содержимое по ID.
1. Владелец: ➕ «новая плитка» → тип **«Слот (пустой — под виджет)»** → создаётся `custom:c<ts>`, показывает свой `🆔 c<ts>`.
2. Перетаскивает куда надо (позиция сохраняется в layout.json+customs.json сама).
3. ПКМ по слоту → **«📋 Копировать ID»** (тост покажет `ID: c<ts>`) → шлёт ID Claude.
4. Claude: в `widget.html` дописывает привязку —
   `SLOT_RENDER['c<ts>'] = (d,h)=> valTile('', d.<нужное>, '<sub>', '<Лейбл>');`
   (d=window.__STATUS__, h=window.__HW__). Перезапустить виджет (см. ниже). Контент сам обновляется в `draw()`.
Плюс: позицию владеет юзер, раскладку не ломает; Claude трогает ТОЛЬКО одну строку SLOT_RENDER.

## Durable: раскладка НЕ должна разъезжаться
- `add()` плитки БЕЗ записи в layout.json кладёт СТРОГО в конец (`_nextY`), НЕ через `autoPosition` (он компактил грид и расталкивал соседей → разъезд на старте). Поэтому забытая координата больше не ломает раскладку.
- Всё равно: для ПОСТОЯННОЙ плитки лучше дать координату в layout.json (или через слот).

## Перезапуск виджета (применить правки widget.html)
PowerShell, РАЗДЕЛЬНО (не в одном вызове со Start-Sleep):
1. `Get-CimInstance Win32_Process | ? {$_.CommandLine -match 'run_widget\.py'} | % {Stop-Process -Id $_.ProcessId -Force}`
2. `taskkill /F /IM msedgewebview2.exe /T` (убить webview-зомби, иначе лочат .wvdata)
3. `Start-Process pythonw.exe -ArgumentList run_widget.py -WorkingDirectory <home>\fleet_board`
Проверка: `run_widget` процессов >0, `werr*.txt` пустые (иначе JS-ошибка → откатить из *.bak).

## Грабли
- BOM в `*.vbs` ломает автозапуск (800A0408) — сохранять без BOM.
- mutex одиночки → чтобы reload подхватил новый код, СТАРЫЙ виджет убить (просто запуск только сфокусит существующий).
- msedgewebview2-зомби лочат `.wvdata` — убивать при рестарте.
- `status.json` pretty-JSON (indent=2) → grep многострочный; данные смотреть через python json.
- collector печатает короткий self-summary; полные данные — в status.json.
