#!/bin/bash
# ==========================================================================
#  STEREO Vibe Lite — стартовый пакет вайбкодера для macOS.
#
#  Проверяет систему и ставит через Homebrew то, что нужно для вайбкодинга:
#  Git, Node.js, Python, Telegram, ИИ-агентов.
#  Проверяет, открываются ли ИИ-сервисы из этой сети (ничего не настраивает).
#
#  Связь с сервером пакета (адреса — константами ниже):
#   1) при запуске читаем номер свежей версии (version-mac.json, только поле
#      version) и, если он новее, печатаем строку со ссылкой на бота. Ничего
#      не скачиваем и не выполняем;
#   2) обезличенная сводка после проверки (версии программ и статусы, без
#      имени пользователя/компьютера, путей и ключей). Отключается --no-report.
#  Лог и JSON-отчёт остаются только на этом компьютере.
#
#  Совместимость: штатный /bin/bash 3.2 и BSD-утилиты macOS. Поэтому нет
#  ассоциативных массивов, mapfile, смены регистра через ${x,,} и GNU-ключей;
#  таймауты — своя функция run_timeout (команды timeout на macOS нет).
#
#  Флаги: --check          только проверка: ничего не ставим и не спрашиваем
#         --no-report      не отправлять обезличенную сводку
#         --apps 1,2       пункты меню ИИ без вопроса
#         --report-dir D   куда писать лог и JSON
#         --project-dir D  завести папку проекта с памятью агента в D без вопроса
#                          (по умолчанию пакет спрашивает про ~/stereo-vibe)
# ==========================================================================

# ---- Флаги ------------------------------------------------------------------
REPORT_ONLY=0; NO_REPORT=0; PREFERRED_APPS=''; REPORT_DIR=''; PROJECT_DIR_ARG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--report-only) REPORT_ONLY=1 ;;
    --no-report)           NO_REPORT=1 ;;
    --apps)                shift; PREFERRED_APPS="${1:-}" ;;
    --report-dir)          shift; REPORT_DIR="${1:-}" ;;
    --project-dir)         shift; PROJECT_DIR_ARG="${1:-}" ;;
  esac
  [ $# -gt 0 ] && shift
done
INSTALL_MISSING=1
[ "$REPORT_ONLY" -eq 1 ] && INSTALL_MISSING=0

# Длина строк (рамки, колонки) считается в символах только в UTF-8-локали.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;;
  *) export LC_ALL=en_US.UTF-8 ;;
esac
export HOMEBREW_NO_ENV_HINTS=1

# ---- Адреса сервера пакета, бот и ссылка на практикум -----------------------
VERSION_URL='https://stereosam.ru/vibe-lite/version-mac.json'
SUMMARY_URL='https://stereosam.ru/vibe-lite/report'
BOT_UPDATE_URL='https://t.me/stereo_practicum_bot?start=vibe_update'
PRACTICUM_URL='https://stereosam.ru/ai?utm_source=kit_lite_mac&utm_medium=app&utm_campaign=stereovibe'

SECONDS=0

# Версия пакета живёт в version.txt рядом со скриптом (показывается и уходит в сводку).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_VERSION='0.0.0'
if [ -f "$SCRIPT_DIR/version.txt" ]; then
  pv="$(tr -d ' \r\n\t' < "$SCRIPT_DIR/version.txt" 2>/dev/null)"
  if printf '%s' "$pv" | grep -qE '^[0-9]+(\.[0-9]+){1,3}$'; then PKG_VERSION="$pv"; fi
fi

# ---- Локальные данные: лог, JSON-отчёт, id установки -----------------------
# Не в папке пакета: в распакованном архиве должны лежать только лаунчер и
# служебная папка, а сам архив можно скачать и распаковать заново.
DATA_DIR="$HOME/Library/Application Support/STEREO-Vibe-Lite"
[ -n "$REPORT_DIR" ] || REPORT_DIR="$DATA_DIR/logs"
if ! mkdir -p "$REPORT_DIR" 2>/dev/null || ! ( : > "$REPORT_DIR/.wtest" ) 2>/dev/null; then
  REPORT_DIR="${TMPDIR:-/tmp}/stereo_vibe_lite_logs"
  mkdir -p "$REPORT_DIR" 2>/dev/null
fi
rm -f "$REPORT_DIR/.wtest" 2>/dev/null
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_PATH="$REPORT_DIR/log_$STAMP.txt"
JSON_PATH="$REPORT_DIR/report_$STAMP.json"
SUMMARY_PATH="$REPORT_DIR/summary_$STAMP.json"
( : > "$LOG_PATH" ) 2>/dev/null || LOG_PATH=/dev/null

# ---- Интерфейс --------------------------------------------------------------
if [ -t 1 ]; then
  C_CY=$'\033[36m'; C_YE=$'\033[33m'; C_GR=$'\033[32m'; C_RD=$'\033[31m'
  C_GY=$'\033[90m'; C_MG=$'\033[35m'; C_0=$'\033[0m'
else
  C_CY=''; C_YE=''; C_GR=''; C_RD=''; C_GY=''; C_MG=''; C_0=''
fi
BAR_ON=0

log() { printf '%s\n' "$*" >> "$LOG_PATH" 2>/dev/null; }
rep() { local s='' i=0; while [ "$i" -lt "$2" ]; do s="$s$1"; i=$((i + 1)); done; printf '%s' "$s"; }
pad() { local s="$1" n; n=$(( $2 - ${#s} )); [ "$n" -gt 0 ] && s="$s$(rep ' ' "$n")"; printf '%s' "$s"; }
center() {
  local t="$1" w="$2" p l
  p=$(( w - ${#t} )); [ "$p" -lt 0 ] && p=0
  l=$(( p / 2 ))
  printf '%s%s%s' "$(rep ' ' "$l")" "$t" "$(rep ' ' $(( p - l )))"
}
# Полоска прогресса и строка «проверяю…» живут только на экране: в лог не идут
# и стираются перед следующей строкой, иначе вывод слипается.
clear_bar() {
  if [ "$BAR_ON" -eq 1 ] && [ -t 1 ]; then printf '\r%s\r' "$(rep ' ' 78)"; fi
  BAR_ON=0
}
say() { local c="$1"; shift; clear_bar; printf '%s%s%s\n' "$c" "$*" "$C_0"; log "$*"; }
step() { if [ -t 1 ]; then printf '\r%s' "$(pad "      проверяю: $1..." 78)"; BAR_ON=1; fi; }
is_interactive() { [ -t 0 ]; }

# Вопрос человеку — крупной рамкой: среди серых служебных строк он иначе теряется.
ask_box() {
  local w=50 l
  for l in "$@"; do [ $(( ${#l} + 6 )) -gt "$w" ] && w=$(( ${#l} + 6 )); done
  say '' ''
  say "$C_MG" "  ╔$(rep '═' "$w")╗"
  say "$C_MG" "  ║$(rep ' ' "$w")║"
  for l in "$@"; do say "$C_MG" "  ║$(center "$l" "$w")║"; done
  say "$C_MG" "  ║$(rep ' ' "$w")║"
  say "$C_MG" "  ╚$(rep '═' "$w")╝"
}
# Ответ кладётся в ASK_ANSWER (read внутри $(...) не работает с терминалом).
read_ask() {
  ask_box "$@"
  ASK_ANSWER=''
  read -r -p '   твой ответ (цифра): ' ASK_ANSWER
  log "   ответ: «$ASK_ANSWER»"
}
answer_is_1() { local a="${ASK_ANSWER// /}"; [ "${a:0:1}" = '1' ]; }

big_box() { # заголовок подзаголовок цвет
  local t="$1" s="$2" c="$3" w=46
  [ $(( ${#t} + 8 )) -gt "$w" ] && w=$(( ${#t} + 8 ))
  [ $(( ${#s} + 8 )) -gt "$w" ] && w=$(( ${#s} + 8 ))
  say '' ''
  say "$c" "  ╔$(rep '═' "$w")╗"
  say "$c" "  ║$(rep ' ' "$w")║"
  say "$c" "  ║$(center "$t" "$w")║"
  [ -n "$s" ] && say "$c" "  ║$(center "$s" "$w")║"
  say "$c" "  ║$(rep ' ' "$w")║"
  say "$c" "  ╚$(rep '═' "$w")╝"
  say '' ''
}

write_banner() {
  [ -t 1 ] && printf '\033]0;STEREO Vibe Lite\007'
  say '' ''
  say "$C_CY" '  ███████ ████████ ███████ ██████  ███████  ██████'
  say "$C_CY" '  ██         ██    ██      ██   ██  ██      ██    ██'
  say "$C_CY" '  ███████    ██    █████   ██████   █████   ██    ██'
  say "$C_CY" '       ██    ██    ██      ██   ██  ██      ██    ██'
  say "$C_CY" '  ███████    ██    ███████ ██   ██  ███████  ██████  ·AI'
  say '' ''
  say "$C_YE" '  ─────  STEREO Vibe Lite · стартовый пакет вайбкодера · macOS  ─────'
  say "$C_GY" "  версия пакета: $PKG_VERSION"
  say '' ''
  if [ "$REPORT_ONLY" -eq 1 ]; then
    say "$C_GY" '  Режим: только проверка — ничего не ставлю.'
  else
    say '' '  Что сейчас будет:'
    say '' '   1. Проверю систему: место на диске и версию macOS.'
    say '' '   2. Проверю инструменты и поставлю недостающие через Homebrew.'
    say '' '   3. Предложу выбрать ИИ-агента (Codex, Claude Code, Gemini).'
    say '' '   4. Проверю, открываются ли ИИ-сервисы из твоей сети.'
    say "$C_GY" '  Окно не закрывай до надписи «Нажми ENTER». Установка может идти несколько минут.'
  fi
  say "$C_GY" '  Пакет не подписан в Apple, поэтому macOS при первом запуске его не открывает.'
  say "$C_GY" '  Как открыть: правый клик → «Открыть» (macOS 14 и старше) или «Системные настройки →'
  say "$C_GY" '  Конфиденциальность и безопасность → Открыть всё равно» (macOS 15 и новее).'
  if [ "$NO_REPORT" -eq 0 ]; then
    say "$C_GY" '  После проверки отправим обезличенную сводку (версии программ, без личных данных) — чтобы улучшать пакет'
  fi
  say '' ''
}
wait_end() {
  is_interactive || return 0
  say "$C_GY" '  ─────────────────────────────────────────────'
  say "$C_MG" '  ►►►   Нажми  ENTER,  чтобы  закончить   ◄◄◄'
  read -r _
}

# ---- Результаты -------------------------------------------------------------
# Параллельные массивы (в bash 3.2 нет ассоциативных). KEY/CODE — для
# обезличенной сводки: имя пункта из фиксированного набора и короткий код
# причины. Свободный текст (пути, сообщения ошибок) в сводку не идёт.
R_N=0
add_result() { # категория имя статус версия действие подробности ключ код
  R_CAT[$R_N]="$1"; R_NAME[$R_N]="$2"; R_ST[$R_N]="$3"; R_VER[$R_N]="${4:--}"
  R_ACT[$R_N]="${5:--}"; R_DET[$R_N]="${6:-}"; R_KEY[$R_N]="${7:-}"; R_CODE[$R_N]="${8:-}"
  R_N=$(( R_N + 1 ))
  local mark col line
  case "$3" in
    READY)    mark='ОК';         col="$C_GR" ;;
    FRESH) mark='ПОСТАВЛЕНО'; col="$C_GR" ;;
    LOGIN)    mark='НУЖЕН ВХОД'; col="$C_YE" ;;
    WARN)     mark='ВНИМАНИЕ';   col="$C_YE" ;;
    ABSENT)   mark='нет';        col="$C_GY" ;;
    MISSING)  mark='НЕТ';        col="$C_RD" ;;
    BLOCKED)  mark='ЗАКРЫТ';     col="$C_RD" ;;
    ERROR)    mark='ОШИБКА';     col="$C_RD" ;;
    *)        mark="$3";         col='' ;;
  esac
  line="      $mark · $2"
  if [ -n "${4:-}" ] && [ "$4" != '-' ]; then line="$line $4"; fi
  if [ "$3" != 'READY' ] && [ -n "${5:-}" ] && [ "$5" != '-' ]; then line="$line — $5"; fi
  say "$col" "$line"
  if [ -n "${6:-}" ]; then log "        подробности: $6"; fi
}

# ---- Низкоуровневые помощники -----------------------------------------------
# Command Line Tools от Apple. Без них /usr/bin/git и /usr/bin/python3 — заглушки:
# запуск такой заглушки не работает, а выводит окно «установить инструменты».
# Поэтому заглушки мы даже не запускаем, пока инструментов нет.
clt_ok() { xcode-select -p >/dev/null 2>&1; }
real_cmd() { # команда -> путь к рабочей команде или пусто
  local p
  p="$(command -v "$1" 2>/dev/null)"
  [ -n "$p" ] || return 1
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    /usr/bin/git|/usr/bin/python3|/usr/bin/pip3) clt_ok || return 1 ;;
  esac
  printf '%s' "$p"
}
# Программа может СТОЯТЬ, но не попасть в PATH этого окна (поставили и не
# открыли новый Терминал). Честнее сказать «стоит, но не в PATH», чем «НЕТ».
find_outside_path() {
  local c
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}
get_version() { # путь -> номер версии или пусто
  "$1" --version 2>&1 < /dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.-]+)?' | head -n 1
}
app_path() { # имя приложения -> путь к .app или пусто
  local a
  for a in "/Applications/$1.app" "$HOME/Applications/$1.app"; do
    [ -d "$a" ] && { printf '%s' "$a"; return 0; }
  done
  return 1
}
app_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null |
    grep -oE '^[0-9]+(\.[0-9]+){0,3}' | head -n 1
}
kill_tree() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
  kill -9 "$1" 2>/dev/null
}
# Любая установка ходит в сеть и на плохом канале может не вернуться вовсе.
# Поэтому каждая долгая команда идёт в фоне с лимитом времени и живой полоской.
# stdin закрыт: вопрос от программы в фоне некому показать.
# Возврат: код команды, 124 = не уложилась. Хвост вывода — в RUN_OUT, весь — в лог.
run_timeout() { # секунды подпись команда...
  local secs="$1" label="$2"; shift 2
  local out el=0 bars=24 fill pid rc
  out="$(mktemp "${TMPDIR:-/tmp}/stereo_vibe.XXXXXX" 2>/dev/null)" || out="${TMPDIR:-/tmp}/stereo_vibe_$$.out"
  [ -n "$label" ] && say "$C_GY" "      $label — до $secs сек"
  "$@" > "$out" 2>&1 < /dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$el" -ge "$secs" ]; then
      kill_tree "$pid"; wait "$pid" 2>/dev/null
      RUN_OUT="$(tail -n 20 "$out" 2>/dev/null)"
      { echo "---- $* (не уложилось в $secs сек)"; cat "$out"; } >> "$LOG_PATH" 2>/dev/null
      rm -f "$out"
      [ -n "$label" ] && say "$C_YE" "      $label — не ответило за $secs сек, иду дальше"
      return 124
    fi
    if [ -n "$label" ] && [ -t 1 ]; then
      fill=$(( bars * el / secs ))
      printf '\r%s' "$(pad "      $label  [$(rep '#' "$fill")$(rep '.' $(( bars - fill )))] ${el}s" 78)"
      BAR_ON=1
    fi
    sleep 1; el=$(( el + 1 ))
  done
  wait "$pid"; rc=$?
  clear_bar
  RUN_OUT="$(tail -n 20 "$out" 2>/dev/null)"
  { echo "---- $* (код $rc)"; cat "$out"; } >> "$LOG_PATH" 2>/dev/null
  rm -f "$out"
  return "$rc"
}
last_lines() { printf '%s' "$RUN_OUT" | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' '|' | sed 's/|$//; s/|/ | /g'; }

# ---- HTTP ---------------------------------------------------------------------
# Результат в PROBE_CODE (0 = ответа нет), PROBE_BODY (начало тела) и
# PROBE_CHALLENGE (1 = сайт проверяет браузер). Системный прокси curl не берёт —
# как и консольные агенты, так что проверка видит сеть их глазами.
http_probe() { # url секунды
  local b h
  b="$(mktemp "${TMPDIR:-/tmp}/stereo_vibe.XXXXXX" 2>/dev/null)" || b="${TMPDIR:-/tmp}/stereo_vibe_b$$"
  h="$(mktemp "${TMPDIR:-/tmp}/stereo_vibe.XXXXXX" 2>/dev/null)" || h="${TMPDIR:-/tmp}/stereo_vibe_h$$"
  PROBE_CODE="$(curl -sSL --max-time "$2" -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) stereo-vibe-lite' \
                  -o "$b" -D "$h" -w '%{http_code}' "$1" 2>/dev/null)"
  case "$PROBE_CODE" in
    [1-9][0-9][0-9]) ;;
    *) PROBE_CODE=0 ;;
  esac
  PROBE_BODY="$(head -c 4000 "$b" 2>/dev/null | tr -d '\000')"
  PROBE_CHALLENGE=0
  grep -qiE '^cf-mitigated:.*challenge' "$h" 2>/dev/null && PROBE_CHALLENGE=1
  rm -f "$b" "$h"
}

# ---- Уведомление о новой версии -----------------------------------------------
# Только уведомление: читаем из version-mac.json одно поле version и сравниваем
# со своим. Ничего не скачиваем и не выполняем. Любая ошибка — молча дальше.
ver_part() { printf '%s' "$1" | cut -d. -f"$2"; }
version_gt() { # $1 новее $2?
  local i=1 x y
  while [ "$i" -le 4 ]; do
    x="$(ver_part "$1" "$i")"; y="$(ver_part "$2" "$i")"
    x=$(( 10#${x:-0} )); y=$(( 10#${y:-0} ))
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
    i=$(( i + 1 ))
  done
  return 1
}
check_new_version() {
  local body fresh
  body="$(curl -fsS --max-time 5 "$VERSION_URL" 2>/dev/null | head -c 2000)"
  [ -n "$body" ] || return 0
  fresh="$(printf '%s' "$body" | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+){1,3}"' | head -n 1 |
           grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -n 1)"
  [ -n "$fresh" ] || return 0
  if version_gt "$fresh" "$PKG_VERSION"; then
    say '' ''
    say "$C_MG" "  ►►► Вышла новая версия StereoVibe $fresh — возьми свежий архив в боте: $BOT_UPDATE_URL"
    say '' ''
  fi
  return 0
}

# ---- Обезличенная сводка ------------------------------------------------------
# id установки — случайный, создаётся один раз и хранится локально. К человеку,
# компьютеру и учётной записи не привязан.
get_install_id() {
  local f="$DATA_DIR/install_id.txt" v
  if [ -f "$f" ]; then
    v="$(tr -d ' \r\n' < "$f" 2>/dev/null)"
    if printf '%s' "$v" | grep -qE '^[0-9a-f]{32}$'; then printf '%s' "$v"; return 0; fi
  fi
  v="$(uuidgen 2>/dev/null | tr -d '-' | tr 'ABCDEF' 'abcdef')"
  if ! printf '%s' "$v" | grep -qE '^[0-9a-f]{32}$'; then
    v="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  mkdir -p "$DATA_DIR" 2>/dev/null && printf '%s\n' "$v" > "$f" 2>/dev/null
  printf '%s' "$v"
}
# В сводку уходят только версии из цифр и латиницы — никакого свободного текста.
protect_version() {
  if [ -n "$1" ] && [ "$1" != '-' ] && printf '%s' "$1" | grep -qE '^[0-9A-Za-z .()+-]{1,40}$'; then printf '%s' "$1"; fi
}
map_status() {
  case "$1" in
    READY) echo ok ;; FRESH) echo installed ;; ERROR|MISSING|BLOCKED) echo error ;;
    WARN) echo warn ;; ABSENT) echo absent ;; LOGIN) echo login ;; *) echo unknown ;;
  esac
}
json_bool() { if [ "$1" = 1 ]; then printf 'true'; else printf 'false'; fi; }
new_summary() {
  local i=0 tools='' id='' mode='install' verdict='tools_ready' mv arch
  while [ "$i" -lt "$R_N" ]; do
    if [ -n "${R_KEY[$i]}" ]; then
      [ -n "$tools" ] && tools="$tools,"
      tools="$tools{\"tool\":\"${R_KEY[$i]}\",\"status\":\"$(map_status "${R_ST[$i]}")\",\"version\":\"$(protect_version "${R_VER[$i]}")\",\"code\":\"${R_CODE[$i]}\"}"
    fi
    i=$(( i + 1 ))
  done
  [ "$NO_REPORT" -eq 1 ] || id="$(get_install_id)"
  [ "$REPORT_ONLY" -eq 1 ] && mode='check'
  [ "$TOOL_BLOCKERS" -gt 0 ] && verdict='not_ready'
  mv=''; printf '%s' "$MAC_VER" | grep -qE '^[0-9]+(\.[0-9]+){0,2}$' && mv="$MAC_VER"
  case "$MAC_ARCH" in arm64|x86_64) arch="$MAC_ARCH" ;; *) arch='' ;; esac
  printf '{"schema":1,"package_version":"%s","install_id":"%s","os":"mac","mode":"%s","windows":null,"mac":{"version":"%s","arch":"%s"},"admin":%s,"tools":[%s],"ai_access":%s,"ai_services":{"openai":%s,"anthropic":%s,"gemini":%s},"verdict":"%s","duration_sec":%d}' \
    "$PKG_VERSION" "$id" "$mode" "$mv" "$arch" "$(json_bool "$IS_ADMIN")" "$tools" "$(json_bool "$AI_ACCESS")" \
    "$(json_bool "$AI_OK_openai")" "$(json_bool "$AI_OK_anthropic")" "$(json_bool "$AI_OK_gemini")" "$verdict" "$SECONDS"
}
send_summary() {
  local json code
  json="$(new_summary)"
  # Копия того, что отправляется (или отправилось бы), лежит рядом с логом.
  printf '%s\n' "$json" > "$SUMMARY_PATH" 2>/dev/null
  [ "$NO_REPORT" -eq 1 ] && return 0
  code="$(curl -sS --max-time 8 -o /dev/null -w '%{http_code}' -X POST \
            -H 'Content-Type: application/json; charset=utf-8' --data-binary "$json" "$SUMMARY_URL" 2>/dev/null)"
  # Ошибка отправки молчит: на работу пакета она не влияет.
  case "$code" in 2[0-9][0-9]) say "$C_GY" '  Обезличенная сводка отправлена. Спасибо!' ;; esac
  return 0
}
json_esc() { printf '%s' "$1" | tr '\t\r\n' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
write_local_report() {
  local i=0
  {
    printf '['
    while [ "$i" -lt "$R_N" ]; do
      [ "$i" -gt 0 ] && printf ','
      printf '\n {"Category":"%s","Component":"%s","Status":"%s","Version":"%s","Action":"%s","Details":"%s"}' \
        "${R_CAT[$i]}" "${R_NAME[$i]}" "${R_ST[$i]}" "$(json_esc "${R_VER[$i]}")" \
        "$(json_esc "${R_ACT[$i]}")" "$(json_esc "${R_DET[$i]}")"
      i=$(( i + 1 ))
    done
    printf '\n]\n'
  } > "$JSON_PATH" 2>/dev/null
}

# ---- Homebrew -------------------------------------------------------------------
# На Apple Silicon brew живёт в /opt/homebrew, и этой папки нет в PATH, пока её
# не добавят в профиль оболочки. Поэтому ищем и в PATH, и по известным путям.
BREW=''; BREW_IN_PATH=0; BREW_OK=0
find_brew() {
  local b
  b="$(command -v brew 2>/dev/null)"
  if [ -n "$b" ]; then BREW="$b"; BREW_IN_PATH=1; return 0; fi
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then BREW="$b"; BREW_IN_PATH=0; return 0; fi
  done
  return 1
}
# Пути Homebrew — в это окно (чтобы сразу видеть поставленное).
brew_env() {
  [ -n "$BREW" ] || return 1
  eval "$("$BREW" shellenv 2>/dev/null)"
  hash -r
}
# И в новые окна Терминала: ровно та строка, которую советует сам установщик
# Homebrew. Нужна только для /opt/homebrew (Apple Silicon); /usr/local/bin и так в PATH.
ensure_brew_profile() {
  [ "$BREW" = '/opt/homebrew/bin/brew' ] || return 0
  local prof shown
  # shown — только для показа человеку, тильда в нём не должна раскрываться.
  # shellcheck disable=SC2088
  case "${SHELL##*/}" in
    zsh)  prof="$HOME/.zprofile";     shown='~/.zprofile' ;;
    bash) prof="$HOME/.bash_profile"; shown='~/.bash_profile' ;;
    *)    return 1 ;;
  esac
  if [ -f "$prof" ] && grep -q 'brew shellenv' "$prof" 2>/dev/null; then return 0; fi
  # shellcheck disable=SC2016
  { echo ''; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"'; } >> "$prof" 2>/dev/null || return 1
  say "$C_GY" "      Homebrew добавлен в PATH новых окон Терминала: строка в $shown (так советует сам установщик Homebrew)."
  return 0
}
brew_version() { "$BREW" --version 2>/dev/null < /dev/null | head -n 1 | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -n 1; }
brew_install() { # подпись аргументы-для-brew-install...
  local label="$1"; shift
  run_timeout 600 "$label" "$BREW" install "$@"
}
check_brew() {
  local rc
  step 'Homebrew'
  if find_brew; then
    BREW_OK=1
    if [ "$BREW_IN_PATH" -eq 1 ]; then
      add_result "$CAT1" 'Homebrew' READY "$(brew_version)" 'стоит' '' brew
      return
    fi
    brew_env
    if [ "$INSTALL_MISSING" -eq 1 ] && ensure_brew_profile; then
      add_result "$CAT1" 'Homebrew' READY "$(brew_version)" 'стоит' '' brew
    else
      add_result "$CAT1" 'Homebrew' WARN "$(brew_version)" "стоит ($BREW), но не виден в PATH — добавь в ~/.zprofile строку: eval \"\$($BREW shellenv)\"" '' brew not_in_path
    fi
    return
  fi
  if [ "$INSTALL_MISSING" -eq 0 ]; then
    add_result "$CAT1" 'Homebrew' MISSING '-' 'не установлен. Поставить: https://brew.sh' '' brew not_installed; return
  fi
  if [ "$IS_ADMIN" -ne 1 ]; then
    add_result "$CAT1" 'Homebrew' MISSING '-' 'не установлен, а ставится он только из учётной записи администратора Mac — войди под администратором и запусти пакет ещё раз' '' brew no_admin; return
  fi
  if ! is_interactive; then
    add_result "$CAT1" 'Homebrew' MISSING '-' 'не установлен. Поставить: https://brew.sh' '' brew not_installed; return
  fi
  say '' ''
  say "$C_YE" '  Homebrew — менеджер программ для Mac: через него пакет ставит Git, Node.js,'
  say "$C_YE" '  Python и ИИ-агентов. Его ещё нет.'
  say "$C_GY" '  Поставлю официальным установщиком с https://brew.sh. Он попросит пароль от Mac'
  say "$C_GY" '  (при вводе символы не видны — это нормально) и нажать Enter. Если на Mac нет'
  say "$C_GY" '  «инструментов командной строки» Apple, установщик поставит и их: это 5–15 минут.'
  read_ask 'ПОСТАВИТЬ HOMEBREW?' '1 — поставить   ·   2 — не надо'
  if ! answer_is_1; then
    add_result "$CAT1" 'Homebrew' MISSING '-' 'не ставили — без него программы придётся ставить вручную' '' brew declined; return
  fi
  say "$C_GY" '  ── установщик Homebrew ──'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  rc=$?
  log "  установщик Homebrew: код $rc"
  if find_brew; then
    BREW_OK=1
    brew_env
    ensure_brew_profile
    say "$C_GY" '  Строку для PATH, о которой пишет установщик, я уже добавил — делать это руками не нужно.'
    add_result "$CAT1" 'Homebrew' FRESH "$(brew_version)" 'установлен' '' brew
  else
    add_result "$CAT1" 'Homebrew' MISSING '-' 'не встал — поставь вручную: https://brew.sh' "код выхода установщика $rc" brew brew_failed
  fi
}

# ---- Инструменты ------------------------------------------------------------------
# Проверка: стоит — ОК; нет — ставим через Homebrew (в режиме установки).
# Homebrew нет или он не смог — понятное сообщение, где взять вручную.
check_formula() { # имя команда формула ссылка ключ [запасные пути через пробел]
  local name="$1" exe="$2" formula="$3" url="$4" key="$5" fb="${6:-}" p rc why
  step "$name"
  p="$(real_cmd "$exe")"
  if [ -n "$p" ]; then add_result "$CAT1" "$name" READY "$(get_version "$p")" 'стоит' '' "$key"; return; fi
  if [ -n "$fb" ]; then
    # shellcheck disable=SC2086
    if p="$(find_outside_path $fb)"; then
      add_result "$CAT1" "$name" WARN "$(get_version "$p")" 'стоит, но не виден в PATH — закрой окно Терминала и запусти пакет заново' "$p" "$key" not_in_path
      return
    fi
  fi
  if [ "$INSTALL_MISSING" -eq 0 ]; then
    add_result "$CAT1" "$name" MISSING '-' "не установлен. Поставить: brew install $formula" '' "$key" not_installed; return
  fi
  if [ "$BREW_OK" -ne 1 ]; then
    add_result "$CAT1" "$name" MISSING '-' "не установлен, а Homebrew нет — поставь вручную: $url" '' "$key" no_brew; return
  fi
  brew_install "устанавливаю $name" "$formula"; rc=$?
  hash -r
  p="$(real_cmd "$exe")"
  if [ -n "$p" ]; then add_result "$CAT1" "$name" FRESH "$(get_version "$p")" 'установлено через Homebrew' '' "$key"; return; fi
  why="$(last_lines)"; [ "$rc" -eq 124 ] && why='нет ответа 600 сек (проверь интернет)'
  add_result "$CAT1" "$name" MISSING '-' "Homebrew не смог поставить — поставь вручную: $url" "$why" "$key" brew_failed
}

telegram_app() {
  app_path 'Telegram' || app_path 'Telegram Desktop'
}
check_telegram() {
  local name='Telegram' rc why
  step "$name"
  if telegram_app >/dev/null; then add_result "$CAT1" "$name" READY '-' 'стоит' '' telegram; return; fi
  if [ "$INSTALL_MISSING" -eq 0 ] || ! is_interactive; then
    add_result "$CAT1" "$name" ABSENT '-' 'не установлен (нужен для работы с Telegram-ботами)' '' telegram not_installed; return
  fi
  # Спрашиваем: ставить мессенджер на чужой компьютер молча нельзя.
  read_ask 'ПОСТАВИТЬ TELEGRAM?' '1 — поставить (пригодится для своих Telegram-ботов)   ·   2 — не надо'
  if ! answer_is_1; then add_result "$CAT1" "$name" ABSENT '-' 'не ставили — по желанию' '' telegram declined; return; fi
  if [ "$BREW_OK" -ne 1 ]; then add_result "$CAT1" "$name" MISSING '-' 'Homebrew нет — скачай с https://macos.telegram.org' '' telegram no_brew; return; fi
  brew_install 'устанавливаю Telegram' --cask telegram; rc=$?
  if telegram_app >/dev/null; then add_result "$CAT1" "$name" FRESH '-' 'установлено через Homebrew' '' telegram; return; fi
  why="$(last_lines)"; [ "$rc" -eq 124 ] && why='нет ответа 600 сек (проверь интернет)'
  add_result "$CAT1" "$name" MISSING '-' 'не встал — скачай с https://macos.telegram.org' "$why" telegram brew_failed
}

# ---- ИИ-приложения и агенты --------------------------------------------------------
CODEX_PATHS="$HOME/.local/bin/codex /opt/homebrew/bin/codex /usr/local/bin/codex"
CLAUDE_PATHS="$HOME/.local/bin/claude $HOME/.claude/local/claude /opt/homebrew/bin/claude /usr/local/bin/claude"
SELECTED=' '
FAIL_codex=''; FAIL_claude=''; FAIL_gemini=''; FAIL_chatgptweb=''; FAIL_geminiweb=''
INSTALL_ERR=''
is_selected() { case "$SELECTED" in *" $1 "*) return 0 ;; esac; return 1; }
add_selected() { is_selected "$1" || SELECTED="$SELECTED$1 "; }
set_fail() {
  case "$1" in
    codex) FAIL_codex="$2" ;; claude) FAIL_claude="$2" ;; gemini) FAIL_gemini="$2" ;;
    chatgptweb) FAIL_chatgptweb="$2" ;; geminiweb) FAIL_geminiweb="$2" ;;
  esac
}
get_fail() {
  case "$1" in
    codex) printf '%s' "$FAIL_codex" ;; claude) printf '%s' "$FAIL_claude" ;; gemini) printf '%s' "$FAIL_gemini" ;;
    chatgptweb) printf '%s' "$FAIL_chatgptweb" ;; geminiweb) printf '%s' "$FAIL_geminiweb" ;;
  esac
}

install_codex_cli() {
  if real_cmd codex >/dev/null; then say "$C_GY" '    Codex CLI уже установлен.'; return 0; fi
  if [ "$BREW_OK" -ne 1 ]; then INSTALL_ERR='Homebrew нет. Если Node.js стоит — в новом окне Терминала выполни: npm install -g @openai/codex'; return 1; fi
  brew_install 'ставлю Codex CLI' --cask codex
  hash -r
  if real_cmd codex >/dev/null; then say "$C_GR" '    Codex CLI установлен.'; return 0; fi
  INSTALL_ERR="Homebrew не смог поставить Codex CLI ($(last_lines)). Запасной путь — в новом окне Терминала: npm install -g @openai/codex"
  return 1
}
install_claude_cli() {
  if real_cmd claude >/dev/null; then say "$C_GY" '    Claude Code CLI уже установлен.'; return 0; fi
  if [ "$BREW_OK" -ne 1 ]; then INSTALL_ERR='Homebrew нет. Инструкция по ручной установке: https://docs.anthropic.com/en/docs/claude-code/setup'; return 1; fi
  brew_install 'ставлю Claude Code CLI' --cask claude-code
  hash -r
  if real_cmd claude >/dev/null; then
    say "$C_GR" '    Claude Code CLI установлен.'
    say "$C_GY" '    Учти: Claude Code работает с подпиской Pro/Max, на бесплатном аккаунте — нет.'
    return 0
  fi
  INSTALL_ERR="Homebrew не смог поставить Claude Code ($(last_lines)). Инструкция: https://docs.anthropic.com/en/docs/claude-code/setup"
  return 1
}
install_gemini_cli() {
  if real_cmd gemini >/dev/null; then say "$C_GY" '    Gemini CLI уже установлен.'; return 0; fi
  hash -r
  if real_cmd npm >/dev/null; then
    run_timeout 300 'ставлю Gemini CLI (npm)' npm install -g @google/gemini-cli
    hash -r
  fi
  # npm не справился (например, Node.js поставлен не через Homebrew и npm нужны
  # права администратора) — тот же Gemini CLI есть и в Homebrew.
  if ! real_cmd gemini >/dev/null && [ "$BREW_OK" -eq 1 ]; then
    brew_install 'ставлю Gemini CLI (Homebrew)' gemini-cli
    hash -r
  fi
  if real_cmd gemini >/dev/null; then say "$C_GR" '    Gemini CLI установлен.'; return 0; fi
  if ! real_cmd npm >/dev/null && [ "$BREW_OK" -ne 1 ]; then INSTALL_ERR='нужен Node.js — он ставится в этом же пакете; запусти пакет ещё раз'; return 1; fi
  INSTALL_ERR='не встал — в новом окне Терминала выполни: npm install -g @google/gemini-cli'
  return 1
}
# Веб-версия как приложение: маленькое приложение в ~/Applications, которое
# открывает сайт в браузере по умолчанию. Видно в Launchpad и в поиске Spotlight.
# Собирается штатным osacompile прямо на этом Mac, поэтому Gatekeeper его не держит.
webapp_path() { printf '%s' "$HOME/Applications/$1 (веб).app"; }
install_webapp() { # имя адрес
  local app
  app="$(webapp_path "$1")"
  if [ -d "$app" ]; then say "$C_GY" "    «$1 (веб)» уже есть в «Программах»."; return 0; fi
  mkdir -p "$HOME/Applications" 2>/dev/null
  if osacompile -o "$app" -e "open location \"$2\"" >/dev/null 2>&1 && [ -d "$app" ]; then
    say "$C_GR" "    Приложение «$1 (веб)» добавлено в «Программы» (папка ~/Applications, есть в Launchpad и Spotlight)."
    return 0
  fi
  INSTALL_ERR="не получилось сделать приложение-ярлык. Открой $2 в Safari и выбери «Файл → Добавить в Dock»"
  return 1
}
install_chatgpt_web() {
  say "$C_GY" '    Делаю приложение-ярлык веб-версии https://chatgpt.com — вход и подписка там те же.'
  say "$C_GY" '    Для работы с кодом есть Codex CLI (пункт 1).'
  install_webapp 'ChatGPT' 'https://chatgpt.com'
}

select_and_install_ai() {
  local answer w words has0=0 has9=0 app names='' rc
  [ "$INSTALL_MISSING" -eq 1 ] || return 0
  if ! is_interactive && [ -z "$PREFERRED_APPS" ]; then return 0; fi
  say '' ''
  say "$C_CY" '  ── ВЫБОР ИИ-ИНСТРУМЕНТОВ ─────────────────────'
  say "$C_CY" '   АГЕНТЫ (правят файлы и запускают код — это и есть вайбкодинг):'
  say "$C_YE" '   [1] Codex CLI — агент OpenAI (нужна подписка ChatGPT Plus)'
  say "$C_YE" '   [2] Claude Code CLI — агент Anthropic (нужна подписка Pro/Max)'
  say "$C_YE" '   [3] Gemini CLI — агент Google'
  say "$C_CY" '   ПРИЛОЖЕНИЯ (окно с чатом):'
  say "$C_YE" '   [4] ChatGPT — веб-версия как приложение'
  say "$C_YE" '   [5] Gemini — веб-версия как приложение'
  say "$C_GY" '   Можно несколько: 1,4   ·   [9] всё сразу   ·   [0] пропустить'
  answer="$PREFERRED_APPS"
  if [ -z "$answer" ]; then
    read_ask 'ЧТО УСТАНОВИТЬ?' 'номера через запятую: 1,4   ·   9 — всё сразу   ·   0 — пропустить'
    answer="$ASK_ANSWER"
  fi
  words="$(printf '%s' "$answer" | tr ',;' '  ')"
  set -f
  for w in $words; do
    [ "$w" = '0' ] && has0=1
    [ "$w" = '9' ] && has9=1
  done
  if [ "$has0" -eq 1 ] || [ -z "$(printf '%s' "$words" | tr -d ' \t')" ]; then
    set +f
    say "$C_GY" "   ответ: «$answer» → ничего не ставим"
    return 0
  fi
  if [ "$has9" -eq 1 ]; then
    SELECTED=' codex claude gemini chatgptweb geminiweb '
  else
    for w in $words; do
      case "$w" in
        1) add_selected codex ;;
        2) add_selected claude ;;
        3) add_selected gemini ;;
        4) add_selected chatgptweb ;;
        5) add_selected geminiweb ;;
        *) say "$C_YE" "   Неизвестный вариант: $w" ;;
      esac
    done
  fi
  set +f
  for app in codex claude gemini chatgptweb geminiweb; do
    is_selected "$app" || continue
    case "$app" in
      codex) names="$names Codex CLI," ;; claude) names="$names Claude Code CLI," ;; gemini) names="$names Gemini CLI," ;;
      chatgptweb) names="$names ChatGPT (веб)," ;; geminiweb) names="$names Gemini (веб)," ;;
    esac
  done
  say "$C_GY" "   ответ: «$answer» → выбрано:${names%,}"
  for app in codex claude gemini chatgptweb geminiweb; do
    is_selected "$app" || continue
    INSTALL_ERR=''
    case "$app" in
      codex)      install_codex_cli ;;
      claude)     install_claude_cli ;;
      gemini)     install_gemini_cli ;;
      chatgptweb) install_chatgpt_web ;;
      geminiweb)  install_webapp 'Gemini' 'https://gemini.google.com' ;;
    esac
    rc=$?
    if [ "$rc" -ne 0 ]; then
      set_fail "$app" "$INSTALL_ERR"
      say "$C_YE" "    Не удалось: $INSTALL_ERR"
    fi
  done
}
# «Не выбрано» (серое, не проблема) или «выбрано, но не встало» (жёлтое, с причиной).
add_not_installed() { # категория имя приложение-из-меню пояснение ключ
  if is_selected "$3"; then
    add_result "$1" "$2" WARN '-' 'выбран, но не установился' "$(get_fail "$3")" "$5" install_failed
  else
    add_result "$1" "$2" ABSENT '-' "$4" '' "$5" not_selected
  fi
}
test_runtime() { # имя ключ запасные-пути команда аргументы...
  local name="$1" key="$2" fb="$3" exe="$4" p out rc
  shift 4
  step "$name · запуск"
  p="$(real_cmd "$exe")"
  # shellcheck disable=SC2086
  [ -z "$p" ] && [ -n "$fb" ] && p="$(find_outside_path $fb)"
  if [ -z "$p" ]; then add_result "$CAT1" "$name · запуск" MISSING '-' 'команда не найдена' '' "$key" not_found; return; fi
  out="$("$p" "$@" 2>&1 < /dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then add_result "$CAT1" "$name · запуск" READY '-' 'работает' '' "$key"
  else add_result "$CAT1" "$name · запуск" ERROR '-' "код выхода $rc" "$(printf '%s' "$out" | head -c 300)" "$key" run_failed; fi
}
# Вход в агентов проверяем по локальным файлам, ничего никуда не отправляя.
# 0 = вход выполнен, 1 = нет.
codex_login() {
  local p rc
  p="$(real_cmd codex)" || return 1
  run_timeout 15 '' "$p" login status; rc=$?
  if printf '%s' "$RUN_OUT" | grep -qiE 'not logged in|logged out|no credentials'; then return 1; fi
  [ "$rc" -eq 0 ] && return 0
  [ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]
}
# На macOS Claude Code хранит вход в Связке ключей, а не в файле. Проверяем
# только наличие записи (без чтения секрета — macOS ничего не спрашивает).
claude_login() {
  [ -n "${ANTHROPIC_API_KEY:-}" ] && return 0
  [ -s "$HOME/.claude/.credentials.json" ] && return 0
  security find-generic-password -s 'Claude Code-credentials' >/dev/null 2>&1 && return 0
  grep -q '"oauthAccount"' "$HOME/.claude.json" 2>/dev/null
}
gemini_login() {
  { [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; } && return 0
  [ -s "$HOME/.gemini/oauth_creds.json" ]
}

format_status_line() { # индекс
  local i="$1" icon label col
  case "${R_ST[$i]}" in
    READY)    icon='[OK] '; label='ГОТОВ  '; col="$C_GR" ;;
    FRESH) icon='[+]  '; label='ПОСТАВЛ'; col="$C_GR" ;;
    LOGIN)    icon='[!]  '; label='ВОЙТИ  '; col="$C_YE" ;;
    WARN)     icon='[~]  '; label='ВНИМАН.'; col="$C_YE" ;;
    ABSENT)   icon='[-]  '; label='нет    '; col="$C_GY" ;;
    MISSING)  icon='[X]  '; label='НЕТ    '; col="$C_RD" ;;
    BLOCKED)  icon='[X]  '; label='ЗАКРЫТ '; col="$C_RD" ;;
    ERROR)    icon='[!!] '; label='ОШИБКА '; col="$C_RD" ;;
    *)        icon='[?]  '; label="${R_ST[$i]}"; col='' ;;
  esac
  say "$col" "    $icon $label  $(pad "${R_NAME[$i]}" 22) $(pad "${R_VER[$i]}" 20) ${R_ACT[$i]}"
  if [ -n "${R_DET[$i]}" ] && [ "${R_DET[$i]}" != '-' ]; then say "$C_GY" "           - ${R_DET[$i]}"; fi
}
open_target() { # что-открыть: путь к .app или адрес
  if open "$1" >/dev/null 2>&1; then return 0; fi
  say "$C_YE" "   Не удалось открыть: $1"
  return 1
}

# ---- Память проекта -----------------------------------------------------------
# Проверка только что выяснила про Mac то, что агент в первой сессии выясняет
# наугад: версию macOS, что стоит и каких версий, куда выполнен вход, какие
# ИИ-сервисы открываются. Раскладываем это в память проекта, которую агент
# читает при старте (CLAUDE.md + memory/infra_status.md).
# Правила:
#  - НИЧЕГО не перезаписываем; свежий infra_status ложится рядом как infra_status.new.md;
#  - в файлах нет имени компьютера, имени пользователя, IP и путей с домашней
#    папкой: файл уходит вместе с проектом (git, чаты, скриншоты);
#  - нет шаблонов или что-то не вышло — серая строка, пакет идёт дальше.
# bash 3.2: подстановка без ${x//…/…} (в bash 5.2+ «&» в замене — спецсимвол),
# только отрезанием префикса и суффикса.
MEM_DONE=0; MEM_SHOWN=''
home_short() { # путь -> тот же путь, но с ~ вместо домашней папки
  # shellcheck disable=SC2088
  case "$1" in
    "$HOME") printf '%s' '~' ;;
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
row_idx() { # имя пункта -> индекс строки результата или пусто
  local i=0
  while [ "$i" -lt "$R_N" ]; do
    [ "${R_NAME[$i]}" = "$1" ] && { printf '%s' "$i"; return 0; }
    i=$(( i + 1 ))
  done
  return 1
}
mem_version() { # имя пункта -> версия / installed / not installed
  local i v
  i="$(row_idx "$1")" || { printf 'not installed'; return; }
  v="${R_VER[$i]}"
  case "${R_ST[$i]}" in
    READY|FRESH) [ -n "$v" ] && [ "$v" != '-' ] || v='installed' ;;
    WARN) [ "${R_CODE[$i]}" = 'not_in_path' ] || { printf 'not installed'; return; }
          [ -n "$v" ] && [ "$v" != '-' ] || v='installed'
          v="$v (not in PATH)" ;;
    *) v='not installed' ;;
  esac
  printf '%s' "$v"
}
mem_reach() { # имя пункта проверки доступа -> yes / no / not checked
  local i
  i="$(row_idx "$1")" || { printf 'not checked'; return; }
  case "${R_ST[$i]}" in READY) printf 'yes' ;; *) printf 'no' ;; esac
}
mem_lang_ru() { # системный язык русский?
  local l
  l="$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' "(),\n' | cut -c1-2)"
  [ -n "$l" ] || l="${LC_ALL:-${LANG:-}}"
  case "$l" in ru*|RU*) return 0 ;; esac
  return 1
}
mem_shell() { # -> «имя|версия» оболочки, которую открывает Терминал
  local n v
  n="${SHELL##*/}"
  case "$n" in
    zsh|bash|fish) v="$("$SHELL" --version 2>/dev/null < /dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -n 1)" ;;
    *) n='bash'; v="${BASH_VERSION%%(*}" ;;
  esac
  printf '%s|%s' "$n" "${v:-unknown}"
}
# Подстановка в MEM_TXT: все вхождения {{КЛЮЧ}} -> значение (буквально).
mem_put() {
  local ph="{{$1}}" pre
  while :; do
    case "$MEM_TXT" in *"$ph"*) ;; *) return 0 ;; esac
    pre="${MEM_TXT%%"$ph"*}"
    MEM_TXT="$pre$2${MEM_TXT#*"$ph"}"
  done
}
# Строка в обезличенную сводку без вывода на экран (ключ и код — из фиксированного набора).
mem_row() { # статус код
  R_CAT[$R_N]="$CAT2"; R_NAME[$R_N]='Память проекта'; R_ST[$R_N]="$1"; R_VER[$R_N]='-'
  R_ACT[$R_N]='-'; R_DET[$R_N]=''; R_KEY[$R_N]='project_memory'; R_CODE[$R_N]="$2"
  R_N=$(( R_N + 1 ))
}
init_project_memory() { # папка проекта
  local proj="$1" tpl="$SCRIPT_DIR/templates" memdir created='' kept='' src dst claude_md sh infra
  if [ ! -f "$tpl/memory/infra_status.template.md" ]; then
    say "$C_GY" '  Память проекта: шаблоны не найдены в служебной папке — пропускаю.'
    mem_row ABSENT not_found; return 0
  fi
  memdir="$proj/memory"
  if ! mkdir -p "$memdir" "$proj/scratch" "$proj/backup" 2>/dev/null; then
    say "$C_GY" "  Память проекта: не получилось создать папку $(home_short "$proj") — пропускаю."
    mem_row WARN install_failed; return 0
  fi
  claude_md='CLAUDE.md'
  mem_lang_ru && [ -f "$tpl/CLAUDE.ru.md" ] && claude_md='CLAUDE.ru.md'
  for src in "$claude_md:CLAUDE.md" 'memory/README.md:memory/README.md' \
             'memory/PROJECT_status.md:memory/PROJECT_status.md' \
             'memory/PROJECT_backlog.md:memory/PROJECT_backlog.md' \
             'memory/PROJECT_history.md:memory/PROJECT_history.md'; do
    dst="${src#*:}"; src="${src%%:*}"
    [ -f "$tpl/$src" ] || continue
    if [ -e "$proj/$dst" ]; then kept="$kept $dst"; continue; fi
    cp "$tpl/$src" "$proj/$dst" 2>/dev/null && created="$created $dst"
  done

  # infra_status.md — не шаблон, а факты только что прошедшей проверки.
  MEM_TXT="$(cat "$tpl/memory/infra_status.template.md" 2>/dev/null)"
  sh="$(mem_shell)"
  mem_put DATE "$(date '+%Y-%m-%d %H:%M')"
  mem_put OS_NAME 'macOS'
  if [ -n "$MAC_VER" ]; then mem_put OS_BUILD "$MAC_VER ($MAC_ARCH)"; else mem_put OS_BUILD 'unknown'; fi
  if [ -n "$FREE_GB" ]; then mem_put DISK_FREE "$FREE_GB GB"; else mem_put DISK_FREE 'unknown'; fi
  mem_put PROJECT_DIR "$(home_short "$proj")"
  mem_put REPORT_DIR "$(home_short "$REPORT_DIR")"
  mem_put GIT_VERSION "$(mem_version 'Git')"
  mem_put NODE_VERSION "$(mem_version 'Node.js')"
  mem_put PKG_MANAGER 'Homebrew'
  mem_put PKG_VERSION "$(mem_version 'Homebrew')"
  mem_put SHELL_NAME "${sh%%|*}"
  mem_put SHELL_VERSION "${sh#*|}"
  mem_put CLAUDE_INSTALLED "$(mem_version 'Claude Code CLI')"
  mem_put CODEX_INSTALLED "$(mem_version 'Codex CLI')"
  mem_put GEMINI_INSTALLED "$(mem_version 'Gemini CLI')"
  mem_put CLAUDE_LOGGED_IN "${IN_claude:-—}"
  mem_put CODEX_LOGGED_IN "${IN_codex:-—}"
  mem_put GEMINI_LOGGED_IN "${IN_gemini:-—}"
  mem_put EP_ANTHROPIC "$(mem_reach 'Claude (Anthropic)')"
  mem_put EP_OPENAI "$(mem_reach 'ChatGPT/Codex (OpenAI)')"
  mem_put EP_GOOGLE "$(mem_reach 'Gemini (Google)')"
  infra="$memdir/infra_status.md"
  if [ -n "$MEM_TXT" ]; then
    if [ -e "$infra" ]; then
      kept="$kept memory/infra_status.md"
      printf '%s\n' "$MEM_TXT" > "$memdir/infra_status.new.md" 2>/dev/null &&
        created="$created memory/infra_status.new.md (свежие данные — сравни с infra_status.md)"
    else
      printf '%s\n' "$MEM_TXT" > "$infra" 2>/dev/null && created="$created memory/infra_status.md"
    fi
  fi

  MEM_SHOWN="$(home_short "$proj")"
  say '' ''
  say "$C_CY" "  ── ПАМЯТЬ ПРОЕКТА ── $MEM_SHOWN"
  [ -n "$created" ] && say "$C_GR" "   создано:$created"
  [ -n "$kept" ] && say "$C_GY" "   не тронуто (уже было):$kept"
  say "$C_GY" '   Агент читает CLAUDE.md и memory/infra_status.md при старте — и не гадает, что у тебя установлено.'
  if [ -n "$created" ]; then MEM_DONE=1; mem_row FRESH ''; else mem_row WARN install_failed; fi
  return 0
}
# Когда заводить: в режиме установки — с вопросом; с --project-dir — без вопроса
# (и в режиме проверки, для тестов); без терминала и без флага — молча пропускаем.
maybe_project_memory() {
  local proj
  if [ -n "$PROJECT_DIR_ARG" ]; then
    proj="$PROJECT_DIR_ARG"
    # «~/папка» в кавычках оболочка не раскрывает — раскрываем сами (срезаем 2 символа).
    # shellcheck disable=SC2088
    case "$proj" in '~') proj="$HOME" ;; '~/'*) proj="$HOME/${proj#??}" ;; esac
  else
    [ "$INSTALL_MISSING" -eq 1 ] || return 0
    if ! is_interactive; then mem_row ABSENT not_selected; return 0; fi
    read_ask 'ЗАВЕСТИ ПАПКУ ПРОЕКТА С ПАМЯТЬЮ АГЕНТА?' '1 — да (~/stereo-vibe: CLAUDE.md + memory/)   ·   2 — не надо'
    if ! answer_is_1; then mem_row ABSENT declined; return 0; fi
    proj="$HOME/stereo-vibe"
  fi
  init_project_memory "$proj"
  return 0
}

# ==========================================================================
#  ЗАПУСК
# ==========================================================================
write_banner
check_new_version

IS_ADMIN=0
id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin && IS_ADMIN=1
MAC_VER="$(sw_vers -productVersion 2>/dev/null)"
# Архитектура железа, а не процесса: под Rosetta uname честно скажет x86_64.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = '1' ]; then MAC_ARCH='arm64'; else MAC_ARCH="$(uname -m 2>/dev/null)"; fi
AI_OK_openai=0; AI_OK_anthropic=0; AI_OK_gemini=0; AI_ACCESS=0; TOOL_BLOCKERS=0

CAT0='Система'; CAT1='Инструменты'; CAT2='ИИ-инструменты'; CAT3='Доступ к ИИ-сервисам'

say '' ''
say "$C_CY" '  ══════════════════  ШАГ 1 · СИСТЕМА  ══════════════════'
step 'свободное место на диске'
# LC_ALL=C: в русской локали дробная часть могла бы уйти через запятую.
FREE_GB="$(df -k "$HOME" 2>/dev/null | LC_ALL=C awk 'NR==2 { printf "%.1f", $4 / 1048576 }')"
if [ -z "$FREE_GB" ]; then
  add_result "$CAT0" 'Диск' ERROR '-' 'проверить вручную' '' disk check_failed
elif LC_ALL=C awk -v f="$FREE_GB" 'BEGIN { exit !(f >= 10) }'; then
  add_result "$CAT0" 'Диск' READY "$FREE_GB ГБ" 'свободно' '' disk
elif LC_ALL=C awk -v f="$FREE_GB" 'BEGIN { exit !(f >= 2) }'; then
  add_result "$CAT0" 'Диск' WARN "$FREE_GB ГБ" 'мало места — стоит почистить' '' disk low_space
else
  add_result "$CAT0" 'Диск' BLOCKED "$FREE_GB ГБ" 'критически мало — установка может падать' '' disk critical_space
fi
step 'версия macOS'
MAC_MAJ="${MAC_VER%%.*}"
if [ -z "$MAC_VER" ] || ! printf '%s' "$MAC_MAJ" | grep -qE '^[0-9]+$'; then
  add_result "$CAT0" 'macOS' WARN '-' 'не удалось определить версию' '' macos check_failed
elif [ "$MAC_MAJ" -ge 14 ]; then
  add_result "$CAT0" 'macOS' READY "$MAC_VER ($MAC_ARCH)" 'поддерживается' '' macos
else
  add_result "$CAT0" 'macOS' WARN "$MAC_VER" 'старая macOS — Homebrew и приложения могут не работать. Обнови: Системные настройки → Основные → Обновление ПО' '' macos old_macos
fi

say '' ''
say "$C_CY" '  ══════════════════  ШАГ 2 · ИНСТРУМЕНТЫ  ══════════════════'
check_brew
check_formula 'Git'     git     git    'https://git-scm.com/download/mac'            git    '/opt/homebrew/bin/git /usr/local/bin/git'
check_formula 'Node.js' node    node   'https://nodejs.org'                          node   '/opt/homebrew/bin/node /usr/local/bin/node'
check_formula 'Python'  python3 python 'https://www.python.org/downloads/macos/'     python '/opt/homebrew/bin/python3 /usr/local/bin/python3'
check_telegram

# Недоставленное — одним явным блоком, с тем, что из-за этого не поедет дальше.
BASE_BAD=''
i=0
while [ "$i" -lt "$R_N" ]; do
  if [ "${R_CAT[$i]}" = "$CAT1" ]; then
    case "${R_ST[$i]}" in MISSING|ERROR|WARN) BASE_BAD="$BASE_BAD $i" ;; esac
  fi
  i=$(( i + 1 ))
done
if [ -n "$BASE_BAD" ]; then
  say '' ''
  say "$C_YE" '  ── ВНИМАНИЕ: инструменты встали не все ──'
  BAD_NAMES=''
  for i in $BASE_BAD; do
    say "$C_YE" "   ${R_NAME[$i]}: ${R_ACT[$i]}"
    [ -n "${R_DET[$i]}" ] && say "$C_GY" "     причина: ${R_DET[$i]}"
    BAD_NAMES="$BAD_NAMES ${R_NAME[$i]}"
  done
  if [ "$BREW_OK" -ne 1 ] && [ "$INSTALL_MISSING" -eq 1 ]; then
    say '' ''
    say "$C_YE" '   Homebrew — менеджер программ для Mac. Что сделать:'
    say "$C_YE" '    1) Запусти «Запустить Vibe.command» ещё раз и выбери «1 — поставить» Homebrew'
    say "$C_YE" '       (или поставь его сам по инструкции на https://brew.sh).'
    say "$C_YE" '    2) Дальше всё поставится само.'
    say "$C_GY" '   Или поставь программы вручную по ссылкам выше.'
  fi
  case "$BAD_NAMES" in *Node*) say "$C_GY" '   → Gemini CLI ставится через npm и без Node.js не встанет.' ;; esac
  case "$BAD_NAMES" in *Git*)  say "$C_GY" '   → ИИ-агенты ведут историю правок в Git — без него часть их возможностей не работает.' ;; esac
  say '' ''
fi

say '' ''
say "$C_CY" '  ══════════════════  ШАГ 3 · ИИ-ИНСТРУМЕНТЫ  ══════════════════'
select_and_install_ai
if [ "$INSTALL_MISSING" -eq 1 ]; then NOT_CHOSEN='не выбран'; else NOT_CHOSEN='не установлен'; fi
CLI_NOTE="$NOT_CHOSEN — можно поставить повторным запуском"

hash -r
CODEX_P="$(real_cmd codex)"; CLAUDE_P="$(real_cmd claude)"; GEMINI_P="$(real_cmd gemini)"
CODEX_INSTALLED=0; CLAUDE_INSTALLED=0; GEMINI_INSTALLED=0
# Списки путей без пробелов — дробим по словам намеренно.
# shellcheck disable=SC2086
if [ -n "$CODEX_P" ]; then
  CODEX_INSTALLED=1; add_result "$CAT2" 'Codex CLI' READY "$(get_version "$CODEX_P")" 'установлен' '' codex_cli
elif P="$(find_outside_path $CODEX_PATHS)"; then
  add_result "$CAT2" 'Codex CLI' WARN "$(get_version "$P")" 'стоит, но не виден в PATH — открой новое окно Терминала' "$P" codex_cli not_in_path
else
  add_not_installed "$CAT2" 'Codex CLI' codex "$CLI_NOTE" codex_cli
fi
# shellcheck disable=SC2086
if [ -n "$CLAUDE_P" ]; then
  CLAUDE_INSTALLED=1; add_result "$CAT2" 'Claude Code CLI' READY "$(get_version "$CLAUDE_P")" 'установлен' '' claude_code
elif P="$(find_outside_path $CLAUDE_PATHS)"; then
  add_result "$CAT2" 'Claude Code CLI' WARN "$(get_version "$P")" 'стоит, но не виден в PATH — открой новое окно Терминала' "$P" claude_code not_in_path
else
  add_not_installed "$CAT2" 'Claude Code CLI' claude "$CLI_NOTE" claude_code
fi
if [ -n "$GEMINI_P" ]; then
  GEMINI_INSTALLED=1; add_result "$CAT2" 'Gemini CLI' READY "$(get_version "$GEMINI_P")" 'установлен' '' gemini_cli
else
  add_not_installed "$CAT2" 'Gemini CLI' gemini "$CLI_NOTE" gemini_cli
fi

# Claude Desktop пакет не ставит — только показываем, если он уже стоит.
step 'Claude Desktop'
CLAUDE_APP="$(app_path 'Claude')"
[ -n "$CLAUDE_APP" ] && add_result "$CAT2" 'Claude Desktop' READY "$(app_version "$CLAUDE_APP")" 'установлен' '' claude_desktop
step 'ChatGPT'
CHATGPT_APP="$(app_path 'ChatGPT')"
if [ -n "$CHATGPT_APP" ]; then
  add_result "$CAT2" 'ChatGPT' READY "$(app_version "$CHATGPT_APP")" 'приложение установлено' '' chatgpt
elif [ -d "$(webapp_path 'ChatGPT')" ]; then
  add_result "$CAT2" 'ChatGPT' READY '-' 'веб-версия в «Программах»' '' chatgpt web
else
  add_not_installed "$CAT2" 'ChatGPT' chatgptweb "$NOT_CHOSEN; веб-версия: https://chatgpt.com" chatgpt
fi
step 'Gemini'
GEMINI_APP="$(app_path 'Gemini')"
if [ -n "$GEMINI_APP" ]; then
  add_result "$CAT2" 'Gemini' READY "$(app_version "$GEMINI_APP")" 'приложение установлено' '' gemini_desktop
elif [ -d "$(webapp_path 'Gemini')" ]; then
  add_result "$CAT2" 'Gemini' READY '-' 'веб-версия в «Программах»' '' gemini_web
else
  add_not_installed "$CAT2" 'Gemini' geminiweb "$NOT_CHOSEN; веб-версия: https://gemini.google.com" gemini_web
fi

say '' ''
say "$C_CY" '  ── ПРОВЕРКА РАБОТОСПОСОБНОСТИ ─────────────────'
PY_FB='/opt/homebrew/bin/python3 /usr/local/bin/python3'
test_runtime 'Git'     git_run    ''       git     --version
test_runtime 'Node.js' node_run   ''       node    -e "process.stdout.write('OK')"
test_runtime 'npm'     npm_run    ''       npm     --version
test_runtime 'Python'  python_run "$PY_FB" python3 -c "import ssl, venv; print('OK')"
test_runtime 'pip'     pip_run    "$PY_FB" python3 -m pip --version

step 'вход в ИИ-агентов'
LOGGED=''; NEED=''
# IN_* — для памяти проекта: yes / no / — (агент не установлен).
IN_codex='—'; IN_claude='—'; IN_gemini='—'
if [ "$CODEX_INSTALLED" -eq 1 ]; then
  if codex_login; then LOGGED="$LOGGED; Codex"; IN_codex='yes'; else NEED="$NEED; Codex → команда: codex login"; IN_codex='no'; fi
fi
if [ "$CLAUDE_INSTALLED" -eq 1 ]; then
  if claude_login; then LOGGED="$LOGGED; Claude Code"; IN_claude='yes'; else NEED="$NEED; Claude Code → запусти claude, затем /login"; IN_claude='no'; fi
fi
if [ "$GEMINI_INSTALLED" -eq 1 ]; then
  if gemini_login; then LOGGED="$LOGGED; Gemini"; IN_gemini='yes'; else NEED="$NEED; Gemini → запусти gemini и войди Google-аккаунтом"; IN_gemini='no'; fi
fi
LOGGED="${LOGGED#; }"; NEED="${NEED#; }"
if [ -n "$LOGGED" ] && [ -z "$NEED" ]; then add_result "$CAT2" 'Вход в агентов' READY "$LOGGED" 'вход выполнен' '' ai_login
elif [ -n "$LOGGED" ]; then add_result "$CAT2" 'Вход в агентов' WARN "$LOGGED" "часть без входа: $NEED" '' ai_login partial_login
elif [ -n "$NEED" ]; then add_result "$CAT2" 'Вход в агентов' LOGIN '-' 'НУЖЕН ВХОД' "$NEED" ai_login login_needed
else add_result "$CAT2" 'Вход в агентов' ABSENT '-' 'агенты не установлены — запусти пакет ещё раз и выбери 1, 2 или 3' '' ai_login no_agent
fi

say '' ''
say "$C_CY" '  ══════════════════  ШАГ 4 · ДОСТУП К ИИ-СЕРВИСАМ  ══════════════════'
# Только проверяем, открываются ли сервисы из этой сети. Ничего не настраиваем.
# EP_OK — коды, которые означают «ответил сам сервис». Из России OpenAI и
# Anthropic отвечают 403 с отказом по стране, поэтому 403 в них не входит (кроме
# Google: там 403 = нет ключа, а отказ по стране узнаём по тексту ответа).
GEO_BLOCK_RE='unsupported_country|location is not supported|not available in your (country|region)|country.{0,20}not supported'
EP_NAME=('ChatGPT/Codex (OpenAI)' 'Claude (Anthropic)' 'Gemini (Google)' 'ChatGPT (сайт)' 'GitHub')
EP_KEY=('openai' 'anthropic' 'gemini' '' 'github')
EP_URL=('https://api.openai.com/v1/models' 'https://api.anthropic.com/v1/messages'
        'https://generativelanguage.googleapis.com/v1beta/models' 'https://chatgpt.com' 'https://github.com')
EP_OK=('200 401' '200 400 401 405' '200 400 401 403' '' '')
ANY_ANSWER=0
e=0
while [ "$e" -lt 5 ]; do
  N="${EP_NAME[$e]}"
  step "доступ: $N"
  for _try in 1 2; do
    http_probe "${EP_URL[$e]}" 10
    [ "$PROBE_CODE" -ne 0 ] && break
    sleep 1
  done
  CODE="$PROBE_CODE"
  [ "$CODE" -ne 0 ] && ANY_ANSWER=1
  OK=0
  if [ -n "${EP_OK[$e]}" ]; then
    if printf '%s' "$PROBE_BODY" | grep -qiE "$GEO_BLOCK_RE"; then add_result "$CAT3" "$N" BLOCKED '-' "закрыт из этой сети (HTTP $CODE)"
    elif [ "$CODE" -ne 0 ] && case " ${EP_OK[$e]} " in *" $CODE "*) true ;; *) false ;; esac; then
      OK=1; add_result "$CAT3" "$N" READY '-' "отвечает (HTTP $CODE)"
    elif [ "$CODE" -eq 403 ]; then add_result "$CAT3" "$N" BLOCKED '-' 'закрыт из этой сети (HTTP 403)'
    elif [ "$CODE" -ne 0 ]; then add_result "$CAT3" "$N" WARN '-' "неожиданный ответ HTTP $CODE"
    else add_result "$CAT3" "$N" BLOCKED '-' 'не отвечает'
    fi
  else
    if [ "$CODE" -eq 0 ]; then add_result "$CAT3" "$N" WARN '-' 'не отвечает'
    elif printf '%s' "$PROBE_BODY" | grep -qiE "$GEO_BLOCK_RE"; then add_result "$CAT3" "$N" WARN '-' "закрыт из этой сети (HTTP $CODE)"
    elif [ "$CODE" -eq 403 ] && [ "$PROBE_CHALLENGE" -eq 1 ]; then OK=1; add_result "$CAT3" "$N" READY '-' 'доступен (сайт проверяет браузер — это норма)'
    elif [ "$CODE" -eq 403 ]; then add_result "$CAT3" "$N" WARN '-' 'ответ HTTP 403 — открой сайт в браузере и проверь'
    else OK=1; add_result "$CAT3" "$N" READY '-' 'доступен'
    fi
  fi
  case "${EP_KEY[$e]}" in
    openai) AI_OK_openai="$OK" ;; anthropic) AI_OK_anthropic="$OK" ;; gemini) AI_OK_gemini="$OK" ;;
  esac
  e=$(( e + 1 ))
done
if [ "$AI_OK_openai" -eq 1 ] && [ "$AI_OK_anthropic" -eq 1 ]; then AI_ACCESS=1; fi

# ==== ИТОГ ===================================================================
say '' ''
OK_COUNT=0; ABSENT_COUNT=0; BAD_COUNT=0; ABSENT_NAMES=''; NEED_LOGIN=0
i=0
while [ "$i" -lt "$R_N" ]; do
  case "${R_ST[$i]}" in
    READY|FRESH) OK_COUNT=$(( OK_COUNT + 1 )) ;;
    ABSENT) ABSENT_COUNT=$(( ABSENT_COUNT + 1 )); ABSENT_NAMES="$ABSENT_NAMES, ${R_NAME[$i]}" ;;
    *) BAD_COUNT=$(( BAD_COUNT + 1 )) ;;
  esac
  [ "${R_ST[$i]}" = 'LOGIN' ] && NEED_LOGIN=1
  # Вердикт — по инструментам. Доступ к ИИ-сервисам зависит от сети, а не от
  # компьютера, поэтому о нём — отдельное сообщение ниже.
  if [ "${R_CAT[$i]}" != "$CAT3" ]; then
    case "${R_ST[$i]}" in MISSING|ERROR|BLOCKED) TOOL_BLOCKERS=$(( TOOL_BLOCKERS + 1 )) ;; esac
  fi
  i=$(( i + 1 ))
done
if [ "$BAD_COUNT" -gt 0 ]; then
  say "$C_YE" '  ── ТРЕБУЕТ ВНИМАНИЯ ───────────────────────────'
  for CAT in "$CAT0" "$CAT1" "$CAT2" "$CAT3"; do
    HEADER=0
    i=0
    while [ "$i" -lt "$R_N" ]; do
      if [ "${R_CAT[$i]}" = "$CAT" ]; then
        case "${R_ST[$i]}" in
          READY|FRESH|ABSENT) ;;
          *)
            [ "$HEADER" -eq 0 ] && { say "$C_CY" "  [ $CAT ]"; HEADER=1; }
            format_status_line "$i" ;;
        esac
      fi
      i=$(( i + 1 ))
    done
  done
  say '' ''
fi
if [ "$ABSENT_COUNT" -gt 0 ]; then
  say "$C_GY" "  Не ставили: ${ABSENT_NAMES#, } — можно добавить позже повторным запуском"
fi
CHECKED=$(( R_N - ABSENT_COUNT ))
if [ "$BAD_COUNT" -gt 0 ]; then say "$C_GY" "  В порядке: $OK_COUNT из $CHECKED пунктов · требует внимания: $BAD_COUNT"
else say "$C_GY" "  В порядке: $OK_COUNT из $CHECKED пунктов — всё"; fi

if [ "$TOOL_BLOCKERS" -eq 0 ]; then
  if [ "$ANY_ANSWER" -eq 1 ] && [ "$AI_ACCESS" -eq 0 ]; then SUB='ИИ-сервисы из этой сети закрыты — см. ниже'
  elif [ "$NEED_LOGIN" -eq 1 ]; then SUB='осталось войти в ИИ-агента'
  else SUB='можно работать'; fi
  big_box 'И Н С Т Р У М Е Н Т Ы   Г О Т О В Ы' "$SUB" "$C_GR"
else
  big_box 'С Р Е Д А   Н Е   Г О Т О В А' 'закрой пункты ниже' "$C_RD"
  i=0
  while [ "$i" -lt "$R_N" ]; do
    if [ "${R_CAT[$i]}" != "$CAT3" ]; then
      case "${R_ST[$i]}" in MISSING|ERROR|BLOCKED) say "$C_YE" "     - ${R_NAME[$i]}: ${R_ACT[$i]}" ;; esac
    fi
    i=$(( i + 1 ))
  done
  say '' ''
fi

if [ "$ANY_ANSWER" -eq 0 ]; then
  say "$C_YE" '  ИИ-сервисы не ответили вообще — похоже, нет интернета. Проверь подключение и запусти пакет ещё раз.'
  say '' ''
elif [ "$AI_ACCESS" -eq 0 ]; then
  say "$C_CY" '  ── ДОСТУП К ИИ ────────────────────────────────'
  if [ "$TOOL_BLOCKERS" -eq 0 ]; then
    say "$C_YE" '  Инструменты готовы. Чтобы войти в ChatGPT/Codex из России, нужен доступ —'
  else
    say "$C_YE" '  Чтобы войти в ChatGPT/Codex из России, нужен доступ —'
  fi
  say "$C_YE" '  как мы его настраиваем, показываем на практикуме:'
  say "$C_CY" "  $PRACTICUM_URL"
  say '' ''
  if [ "$INSTALL_MISSING" -eq 1 ] && is_interactive; then
    read_ask 'ОТКРЫТЬ СТРАНИЦУ ПРАКТИКУМА?' '1 — открыть в браузере   ·   Enter — дальше'
    answer_is_1 && open_target "$PRACTICUM_URL"
  fi
fi

# Папка проекта с памятью агента — после вердикта и до отправки сводки.
# Любая неудача здесь только печатает серую строку и не прерывает пакет.
maybe_project_memory

if [ "$MEM_DONE" -eq 1 ]; then
  say '' ''
  say "$C_GY" '  Как начать: открой НОВОЕ окно Терминала (⌘ + Пробел → «Терминал») и набери:'
  say "$C_CY" "     cd $MEM_SHOWN"
  say "$C_GY" '  затем claude, codex или gemini. При первом запуске агент попросит войти в аккаунт.'
  say '' ''
elif [ "$CODEX_INSTALLED" -eq 1 ] || [ "$CLAUDE_INSTALLED" -eq 1 ] || [ "$GEMINI_INSTALLED" -eq 1 ]; then
  say "$C_GY" '  Как начать: открой НОВОЕ окно Терминала (⌘ + Пробел → «Терминал»), создай папку'
  say "$C_GY" '  проекта, перейди в неё и набери codex, claude или gemini. При первом запуске'
  say "$C_GY" '  агент попросит войти в аккаунт.'
  say '' ''
fi

# Локальный JSON-отчёт (с подробностями) — только на этом компьютере.
write_local_report

send_summary

say '' ''
say "$C_GY" '  Лог этой проверки (только на этом компьютере):'
say "$C_GY" "     $LOG_PATH"
say '' ''

# Открыть установленное приложение с чатом.
if is_interactive && [ "$INSTALL_MISSING" -eq 1 ]; then
  TO_OPEN_N=0
  if [ -n "$CHATGPT_APP" ]; then TO_OPEN_NAME[$TO_OPEN_N]='ChatGPT'; TO_OPEN_PATH[$TO_OPEN_N]="$CHATGPT_APP"; TO_OPEN_N=$(( TO_OPEN_N + 1 ))
  elif [ -d "$(webapp_path 'ChatGPT')" ]; then TO_OPEN_NAME[$TO_OPEN_N]='ChatGPT'; TO_OPEN_PATH[$TO_OPEN_N]="$(webapp_path 'ChatGPT')"; TO_OPEN_N=$(( TO_OPEN_N + 1 )); fi
  if [ -n "$CLAUDE_APP" ]; then TO_OPEN_NAME[$TO_OPEN_N]='Claude'; TO_OPEN_PATH[$TO_OPEN_N]="$CLAUDE_APP"; TO_OPEN_N=$(( TO_OPEN_N + 1 )); fi
  if [ -n "$GEMINI_APP" ]; then TO_OPEN_NAME[$TO_OPEN_N]='Gemini'; TO_OPEN_PATH[$TO_OPEN_N]="$GEMINI_APP"; TO_OPEN_N=$(( TO_OPEN_N + 1 ))
  elif [ -d "$(webapp_path 'Gemini')" ]; then TO_OPEN_NAME[$TO_OPEN_N]='Gemini'; TO_OPEN_PATH[$TO_OPEN_N]="$(webapp_path 'Gemini')"; TO_OPEN_N=$(( TO_OPEN_N + 1 )); fi
  if [ "$TO_OPEN_N" -gt 0 ]; then
    say "$C_CY" '  ── ОТКРЫТЬ ИИ ─────────────────────────────────'
    i=0
    while [ "$i" -lt "$TO_OPEN_N" ]; do say "$C_YE" "   [$(( i + 1 ))] ${TO_OPEN_NAME[$i]}"; i=$(( i + 1 )); done
    read_ask 'КАКОЕ ПРИЛОЖЕНИЕ ОТКРЫТЬ?' 'номер из списка выше   ·   Enter — закончить'
    CH="${ASK_ANSWER// /}"
    if [ -n "$CH" ]; then
      if printf '%s' "$CH" | grep -qE '^[0-9]+$' && [ "$CH" -ge 1 ] && [ "$CH" -le "$TO_OPEN_N" ]; then
        K=$(( CH - 1 ))
        open_target "${TO_OPEN_PATH[$K]}" && say "$C_GR" "   ${TO_OPEN_NAME[$K]} открыт."
      else
        say "$C_YE" "   Нет такого варианта: «$CH»."
      fi
    fi
  fi
fi

wait_end
if [ "$TOOL_BLOCKERS" -gt 0 ]; then exit 1; else exit 0; fi
