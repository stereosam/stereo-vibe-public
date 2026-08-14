Создать новый Telegram-бот через work_bot (Bot Management API). Без ручного BotFather.

Аргумент $ARGUMENTS = `<Имя бота> | <username>` (username ОБЯЗАН кончаться на `bot`).
Пример: `/newbot Stereo Disk Sync | stereo_disk_bot`
Если аргумент не передан — спроси имя и username.

## Что уже готово (не пересоздавать)
- Менеджер: **@stereo_work_bot** (id 8628356043), `can_manage_bots=true`. Токен в `/path/to/bots/<assistant-bot>/.env` (`TELEGRAM_TOKEN`), владелец — `OWNER_CHAT_ID`.
- Движок: `/path/to/bots/<assistant-bot>/tools/newbot.py` (делает весь флоу).

## Шаги выполнения
1. Запусти движок В ФОНЕ (он сам стопает work-bot на время поллинга и потом рестартит):
   ```
   ssh <user>@<your-server> '/path/to/bots/<assistant-bot>/venv/bin/python /path/to/bots/<assistant-bot>/tools/newbot.py --name "<Имя>" --username <username>'
   ```
   Запускать через `run_in_background: true` (поллинг до 5 мин).
2. Сразу скажи пользователю: **«В Telegram от @stereo_work_bot пришла ссылка — нажми её и подтверди создание бота»**. Без его тапа бот не создастся.
3. Дождись завершения фонового процесса. Успех = строка `[OK] бот @<username> создан. Токен сохранён -> /path/to/bots/<assistant-bot>/managed/<username>.token`.
4. Если `[FAIL]` — смотри причину в выводе:
   - «ссылку не нажали» → попроси нажать, перезапусти движок.
   - «поле не совпало» (RAW managed_bot keys) → структура апдейта отличается; поправь извлечение токена/параметр `getManagedBotToken` в движке по показанным ключам.

## Безопасность (КРИТИЧНО)
- Токен нового бота — СЕКРЕТ. Он лежит в `/path/to/bots/<assistant-bot>/managed/<username>.token` (chmod 600). В синканутую память (`claude_memory`) НЕ писать. В вывод stdout токен не печатать.
- work-bot во время поллинга недоступен ~до 5 мин (нужен эксклюзивный getUpdates) — это норма, движок его сам поднимает в `finally`.

## Рецепт под капотом (на случай отладки)
Bot API Bot Management: deep-link `https://t.me/newbot/<manager>/<suggested>?name=<name>` → владелец подтверждает → прилетает `update.managed_bot` (ManagedBotUpdated, поля user+bot) + сервисный ManagedBotCreated → токен забирается методом **`getManagedBotToken`** (параметр — id нового бота).

## После создания
- Подключить обработчик нового бота (отдельный сервис или в составе платформы) — это уже не часть /newbot.
- Предложить занести бота в backlog/инфра-память (через /save).

## ⚠️ ОБЯЗАТЕЛЬНО: чек-лист логирования переписок
Перед запуском бота пройти чек-лист из `claude_memory/reference_chat_logging_standard.md`
(раздел «ЧЕК-ЛИСТ при создании нового бота»). Коротко — решить по каждому пункту:
1. Логируем переписку вообще? (да = канон chat-archive; нет = приватный бот, не пишем вовсе)
2. Скачивать файлы? (`DOWNLOAD_MEDIA`, +Я.Диск-дубль?) — дефолт нет, только file_id.
3. Транскрибировать голос? (`TRANSCRIBE_VOICE`) — дефолт да (нужен whisper_client.py + GPU-туннель).
4. Приватность: есть посторонние/клиенты — что НЕ писать.
5. Privacy mode в группах (админ / setprivacy Disable), если нужны все сообщения.
Правило: **либо пишем строго по канону, либо не пишем вовсе** — кустарных форматов не плодить.
