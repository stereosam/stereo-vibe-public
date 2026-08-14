#!/bin/bash
# Лаунчер для macOS: снимает флаг «скачано из интернета», выдаёт права
# и запускает проверщик. Двойной клик в Finder — и всё.
# (zip не сохраняет +x при распаковке — поэтому права выдаём тут сами.)
DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$DIR/core/check-work-tools-macos.command"
# снять карантин Gatekeeper (иначе «неопознанный разработчик») + права
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null
chmod +x "$CORE" "$0" 2>/dev/null
exec bash "$CORE" "$@"
