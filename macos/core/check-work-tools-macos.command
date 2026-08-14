#!/bin/bash
# ==========================================================================
#  STEREO VIBE — проверщик рабочей среды вайб-кодера (macOS).
#  Паритет с Windows-версией: Система/Инструменты/Доступ к ИИ/Десктоп-
#  приложения/Сеть/живой тест/отчёт/В работу + разворачивание памяти агента.
#  Пакетный менеджер = Homebrew. Каждый пункт независим.
#
#  В конце: заводит папку проекта и РАЗВОРАЧИВАЕТ ПАМЯТЬ АГЕНТА — CLAUDE.md +
#  memory/, причём infra_status.md заполняется фактами этой самой проверки.
#
#  Флаги: --report-only        только отчёт, ничего не менять
#         --live-test          реальный мини-запрос к ИИ (тратит немного квоты)
#         --no-report          выключить отправку отчёта явно
#         --report-url URL     куда слать отчёт (без него отправки НЕТ вообще)
#         --force-vpn-off      ТЕСТ: имитировать «выход из РФ»
#         --lang en|ru         язык шаблонов памяти (по умолчанию — по языку системы)
#         --ai codex|claude|gemini  какой ИИ-CLI ставить, если нет ни одного
# ==========================================================================
set -u
REPORT_ONLY=0; LIVE_TEST=0; NO_REPORT=0; FORCE_VPN_OFF=0; PREFERRED_AI=""; KIT_LANG=""
# Отчёт куратору ВЫКЛЮЧЕН, пока не задан приёмник. Эндпоинта по умолчанию здесь
# нет и быть не должно: инструмент, который на чужой машине молча стучится на
# сервер автора, — это не инструмент, а сюрприз. Пусто = не шлём и не заводим
# machine-id. Свой приёмник: --report-url или переменные окружения.
REPORT_URL="${STEREO_REPORT_URL:-}"
PAIR_URL="${STEREO_PAIR_URL:-}"
PAIR_BOT="${STEREO_PAIR_BOT:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --report-only) REPORT_ONLY=1 ;;
    --live-test) LIVE_TEST=1 ;;
    --no-report) NO_REPORT=1 ;;
    --report-url) shift; REPORT_URL="${1:-}" ;;
    --pair-url) shift; PAIR_URL="${1:-}" ;;
    --pair-bot) shift; PAIR_BOT="${1:-}" ;;
    --force-vpn-off) FORCE_VPN_OFF=1 ;;
    --lang) shift; KIT_LANG="${1:-}" ;;
    --ai) shift; PREFERRED_AI="${1:-}" ;;
  esac; shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLERS="$SCRIPT_DIR/installers/mac"
REPORT_DIR="$SCRIPT_DIR/reports"; mkdir -p "$REPORT_DIR" 2>/dev/null || REPORT_DIR="${TMPDIR:-/tmp}/starter_kit_reports"; mkdir -p "$REPORT_DIR" 2>/dev/null
STAMP="$(date +%Y%m%d_%H%M%S)"; LOG_PATH="$REPORT_DIR/log_$STAMP.txt"
exec > >(tee "$LOG_PATH") 2>&1

C_CY=$'\033[36m'; C_YE=$'\033[33m'; C_GR=$'\033[32m'; C_RD=$'\033[31m'; C_GY=$'\033[90m'; C_MG=$'\033[35m'; C_0=$'\033[0m'

# ---- Баннер --------------------------------------------------------------
printf '%s' "$C_CY"
echo '  ███████ ████████ ███████ ██████  ███████  ██████'
echo '  ██         ██    ██      ██   ██  ██      ██    ██'
echo '  ███████    ██    █████   ██████   █████   ██    ██'
echo '       ██    ██    ██      ██   ██  ██      ██    ██'
echo '  ███████    ██    ███████ ██   ██  ███████  ██████  ·AI'
printf '%s\n%s' "$C_0" "$C_YE"
echo '  ─────  V I B E · стартер-кит вайб-кодера  ─────'
printf '%s' "$C_GY"; echo '  проверка рабочей среды · один клик'; printf '%s\n' "$C_0"
if [ "$REPORT_ONLY" -eq 1 ]; then echo "  Режим: только отчёт (ничего не меняем)"; else echo "  Режим: проверка и ремонт"; fi
echo ""

# ---- Инфраструктура результатов ------------------------------------------
ROWS=(); BLOCKERS=(); EXIT_COUNTRY=""; EXIT_IP=""
add_result() { ROWS+=("$1|$2|$3|$4|$5"); case "$2" in MISSING|ERROR|LOGIN|BLOCKED) BLOCKERS+=("$4: $5");; esac; }
have() { command -v "$1" >/dev/null 2>&1; }
ver() { "$1" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -n1; }
# Инструмент может СТОЯТЬ, но не попасть в PATH текущей сессии (поставили и не
# открыли новый терминал). Честнее сказать «стоит, но не в PATH», чем «НЕТ».
find_outside_path() { for c in "$@"; do [ -x "$c" ] && { echo "$c"; return 0; }; done; return 1; }
NODE_PATHS="/usr/local/bin/node /opt/homebrew/bin/node /usr/local/opt/node/bin/node"
# Codex CLI после слияния с ChatGPT (09.07.2026) ставится нативно, НЕ через npm.
CODEX_PATHS="$HOME/.local/bin/codex /usr/local/bin/codex /opt/homebrew/bin/codex /Applications/ChatGPT.app/Contents/Resources/codex"
ask() { local p="$1"; local a; if [ "$REPORT_ONLY" -eq 1 ] || [ ! -t 0 ]; then echo "n"; else read -r -p "$p" a; echo "$a"; fi; }
# ОДИН источник гео = единая точка отказа: моргнул ipinfo (таймаут при
# переподключении туннеля / лимит) — кит объявляет «нет VPN», хотя туннель жив.
exit_info() {
  J="$(curl -fsS --max-time 8 https://ipinfo.io/json 2>/dev/null)"
  if echo "$J" | grep -q '"ip"'; then echo "$J"; return 0; fi
  # запасной источник: отдаёт ip= и loc= обычным текстом
  T="$(curl -fsS --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  IP2="$(echo "$T" | grep '^ip=' | cut -d= -f2)"
  LOC2="$(echo "$T" | grep '^loc=' | cut -d= -f2)"
  if [ -n "$IP2" ]; then printf '{"ip":"%s","country":"%s","org":"(cloudflare trace)"}' "$IP2" "$LOC2"; return 0; fi
  return 1
}
# Единая точка записи состояния выхода: мастер VPN раньше определял страну, писал
# «VPN АКТИВЕН», но состояние НЕ обновлял -> отчёт уходил с vpn=неизвестно.
set_exit_state() { # $1 = json
  EXIT_IP="$(echo "$1" | grep -oE '"ip"[^,]*' | cut -d'"' -f4)"
  EXIT_COUNTRY="$(echo "$1" | grep -oE '"country"[^,]*' | cut -d'"' -f4)"
  [ -n "$EXIT_IP" ]
}

# ==== БЛОК 0. СИСТЕМА =====================================================
echo "  • Проверяю: система..."
FREE_GB=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$FREE_GB" ]; then
  if [ "$FREE_GB" -ge 10 ]; then add_result "Система" "READY" "${FREE_GB} ГБ" "Диск /" "свободно"
  elif [ "$FREE_GB" -ge 2 ]; then add_result "Система" "WARN" "${FREE_GB} ГБ" "Диск /" "мало места — стоит почистить"
  else add_result "Система" "BLOCKED" "${FREE_GB} ГБ" "Диск /" "критически мало"; fi
fi
MACOS_VER="$(sw_vers -productVersion 2>/dev/null)"; MAJ="${MACOS_VER%%.*}"
if [ -n "$MAJ" ] && [ "$MAJ" -ge 13 ]; then add_result "Система" "READY" "$MACOS_VER" "macOS" "поддерживается"
elif [ -n "$MACOS_VER" ]; then add_result "Система" "WARN" "$MACOS_VER" "macOS" "старая — часть приложений может не работать (обнови, бесплатно)"; fi

# ==== БЛОК 1. ИНСТРУМЕНТЫ ==================================================
echo "  • Проверяю: инструменты..."
if have brew; then add_result "Инструменты" "READY" "$(ver brew)" "Homebrew" "стоит"
elif [ "$REPORT_ONLY" -eq 0 ]; then
  echo "  Ставлю Homebrew..."
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null; then add_result "Инструменты" "REPAIRED" "-" "Homebrew" "установлен; открой новый терминал"
  else add_result "Инструменты" "ERROR" "-" "Homebrew" "поставь вручную: https://brew.sh"; fi
else add_result "Инструменты" "MISSING" "-" "Homebrew" "поставь: https://brew.sh"; fi

check_brew() { # name exe formula [fallback_paths]
  if have "$2"; then add_result "Инструменты" "READY" "$(ver "$2")" "$1" "стоит"; return; fi
  if [ -n "${4:-}" ] && FB="$(find_outside_path ${4})"; then
    add_result "Инструменты" "WARN" "$("$FB" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -n1)" "$1" "СТОИТ ($FB), но не виден в PATH — открой новый терминал"; return
  fi
  if ! have brew; then add_result "Инструменты" "MISSING" "-" "$1" "сначала Homebrew"; return; fi
  if [ "$REPORT_ONLY" -eq 1 ]; then add_result "Инструменты" "MISSING" "-" "$1" "brew install $3"; return; fi
  if brew install "$3"; then add_result "Инструменты" "REPAIRED" "-" "$1" "установлен"; else add_result "Инструменты" "ERROR" "-" "$1" "brew install $3"; fi
}
check_brew "Git" "git" "git"
check_brew "Node.js LTS" "node" "node" "$NODE_PATHS"

# ==== БЛОК 2. ДОСТУП К ИИ (CLI) ===========================================
echo "  • Проверяю: доступ к ИИ..."
CODEX_OK=0; CLAUDE_OK=0; GEMINI_OK=0; CODEX_OUTSIDE=""
have codex && CODEX_OK=1; have claude && CLAUDE_OK=1; have gemini && GEMINI_OK=1
# Codex мог приехать нативным установщиком мимо PATH (после слияния с ChatGPT).
[ "$CODEX_OK" -eq 0 ] && CODEX_OUTSIDE="$(find_outside_path $CODEX_PATHS || true)"
if [ "$CODEX_OK" -eq 0 ] && [ "$CLAUDE_OK" -eq 0 ] && [ "$GEMINI_OK" -eq 0 ] && [ -z "$CODEX_OUTSIDE" ]; then
  if [ -z "$PREFERRED_AI" ] && [ "$REPORT_ONLY" -eq 0 ] && [ -t 0 ]; then
    read -r -p "  Какой ИИ-CLI поставить: 1=Codex, 2=Claude Code, 3=Gemini (бесплатный тир): " a
    case "$a" in 2) PREFERRED_AI="claude" ;; 3) PREFERRED_AI="gemini" ;; *) PREFERRED_AI="codex" ;; esac
  fi
  [ -z "$PREFERRED_AI" ] && PREFERRED_AI="codex"
  case "$PREFERRED_AI" in
    claude) PKG="@anthropic-ai/claude-code" ;;
    gemini) PKG="@google/gemini-cli" ;;
    *)      PKG="@openai/codex" ;;
  esac
  if ! have npm; then add_result "Доступ к ИИ" "MISSING" "-" "ИИ-CLI" "сначала Node.js"
  elif [ "$REPORT_ONLY" -eq 1 ]; then add_result "Доступ к ИИ" "MISSING" "-" "ИИ-CLI" "npm i -g $PKG"
  else
    OPTS=""; [ "$PKG" = "@anthropic-ai/claude-code" ] && OPTS="--allow-scripts=@anthropic-ai/claude-code"
    if npm install --global "$PKG" $OPTS; then
      add_result "Доступ к ИИ" "REPAIRED" "-" "ИИ-CLI" "установлен"
      case "$PKG" in
        "@openai/codex")             CODEX_OK=1 ;;
        "@anthropic-ai/claude-code") CLAUDE_OK=1 ;;
        "@google/gemini-cli")        GEMINI_OK=1 ;;
      esac
    else add_result "Доступ к ИИ" "ERROR" "-" "ИИ-CLI" "npm i -g $PKG"; fi
  fi
fi
if [ "$CODEX_OK" -eq 1 ]; then add_result "Доступ к ИИ" "READY" "$(ver codex)" "Codex" "стоит"
elif [ -n "$CODEX_OUTSIDE" ]; then add_result "Доступ к ИИ" "WARN" "-" "Codex" "СТОИТ ($CODEX_OUTSIDE), но не виден в PATH — открой новый терминал"
else add_result "Доступ к ИИ" "ABSENT" "-" "Codex" "CLI не установлен (приложение ChatGPT — это НЕ он; не требуется, есть другой ИИ-CLI)"; fi
[ "$CLAUDE_OK" -eq 1 ] && add_result "Доступ к ИИ" "READY" "$(ver claude)" "Claude Code" "стоит" || add_result "Доступ к ИИ" "ABSENT" "-" "Claude Code" "не установлен (не требуется — есть другой ИИ-CLI)"
# Gemini CLI — бесплатный тир 60 запросов/мин, 1000/день (Gemini 2.5 Pro, окно 1M).
[ "$GEMINI_OK" -eq 1 ] && add_result "Доступ к ИИ" "READY" "$(ver gemini)" "Gemini CLI" "стоит" || add_result "Доступ к ИИ" "ABSENT" "-" "Gemini CLI" "не установлен (не требуется — есть другой ИИ-CLI)"

# Авторизация ИИ
codex_login() { [ "$CODEX_OK" -eq 1 ] || return 1; codex login status >/dev/null 2>&1 && return 0; [ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; }
claude_login() { [ "$CLAUDE_OK" -eq 1 ] || return 1; [ -n "${ANTHROPIC_API_KEY:-}" ] && return 0; [ -s "$HOME/.claude/.credentials.json" ]; }
# Gemini: API-ключ в окружении ЛИБО OAuth-вход Google-аккаунтом (~/.gemini/oauth_creds.json)
gemini_login() { [ "$GEMINI_OK" -eq 1 ] || return 1; { [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; } && return 0; [ -s "$HOME/.gemini/oauth_creds.json" ]; }
LOGGED=""; NEED=""
[ "$CODEX_OK" -eq 1 ] && { codex_login && LOGGED="$LOGGED Codex" || NEED="$NEED Codex(codex login)"; }
[ "$CLAUDE_OK" -eq 1 ] && { claude_login && LOGGED="$LOGGED Claude" || NEED="$NEED Claude(claude→/login)"; }
[ "$GEMINI_OK" -eq 1 ] && { gemini_login && LOGGED="$LOGGED Gemini" || NEED="$NEED Gemini(запусти gemini→вход Google)"; }
LOGGED="$(echo "$LOGGED"|xargs)"; NEED="$(echo "$NEED"|xargs)"
if [ -n "$LOGGED" ] && [ -z "$NEED" ]; then add_result "Доступ к ИИ" "READY" "$LOGGED" "Авторизация ИИ" "вход выполнен"
# Частичный вход — НЕ блокер, но и не зелёный: иначе «Codex ГОТОВ» сверху +
# недоступный пункт в меню «В работу» = выглядит как баг продукта.
elif [ -n "$LOGGED" ]; then add_result "Доступ к ИИ" "WARN" "$LOGGED" "Авторизация ИИ" "часть без входа: $NEED"
elif [ -n "$NEED" ]; then add_result "Доступ к ИИ" "LOGIN" "-" "Авторизация ИИ" "НУЖЕН ВХОД: $NEED"
else add_result "Доступ к ИИ" "MISSING" "-" "Авторизация ИИ" "сначала ИИ-CLI"; fi

# ==== БЛОК 2.5. ДЕСКТОП-ПРИЛОЖЕНИЯ ========================================
echo "  • Проверяю: десктоп-приложения..."
[ -d "/Applications/Claude.app" ] && add_result "Десктоп" "READY" "-" "Claude Desktop" "установлен" || add_result "Десктоп" "ABSENT" "-" "Claude Desktop" "не установлен (не критично)"
[ -d "/Applications/ChatGPT.app" ] && add_result "Десктоп" "READY" "-" "ChatGPT Desktop" "установлен — это ПРИЛОЖЕНИЕ, а не codex CLI" || add_result "Десктоп" "ABSENT" "-" "ChatGPT Desktop" "не установлен (не критично)"
# Gemini: нативное приложение есть ТОЛЬКО под macOS (с 15.04.2026; нужен Sequoia 15+
# и Apple Silicon). Под Windows официального приложения нет. Скачать: gemini.google/mac
[ -d "/Applications/Gemini.app" ] && add_result "Десктоп" "READY" "-" "Gemini Desktop" "установлен" || add_result "Десктоп" "ABSENT" "-" "Gemini Desktop" "не установлен (не критично; gemini.google/mac)"

# ==== БЛОК 3. СЕТЬ / ДОСТУП К ИИ ==========================================
echo "  • Проверяю: сеть и доступ к ИИ..."
if [ "$FORCE_VPN_OFF" -eq 1 ]; then EXIT_IP="(тест: нет VPN)"; EXIT_COUNTRY="RU"; EXIT_ORG="ForceVpnOff"
else EJ="$(exit_info)"; EXIT_IP="$(echo "$EJ" | grep -oE '"ip"[^,]*' | cut -d'"' -f4)"; EXIT_COUNTRY="$(echo "$EJ" | grep -oE '"country"[^,]*' | cut -d'"' -f4)"; EXIT_ORG="$(echo "$EJ" | grep -oE '"org"[^,]*' | cut -d'"' -f4)"; fi
if [ -n "$EXIT_COUNTRY" ] && [ "$EXIT_COUNTRY" != "RU" ]; then add_result "Сеть" "READY" "$EXIT_IP · $EXIT_COUNTRY" "Внешний IP" "выход не через РФ"
elif [ "$EXIT_COUNTRY" = "RU" ]; then add_result "Сеть" "WARN" "$EXIT_IP · RU" "Внешний IP" "РФ-IP — ИИ может резать, нужен VPN"
else add_result "Сеть" "WARN" "-" "Внешний IP" "не определить (нет сети?)"; fi
check_ep() { # name url key(1=критичный)
  # ДОСТУПНОСТЬ определяем по EXIT-коду curl, НЕ по HTTP-коду:
  #   401/403 = сервер ОТВЕТИЛ (голый API-домен без ключа так и делает) = доступен.
  #   Реальный блок = обрыв: exit 6 (нет DNS) / 7 (не подключиться) / 28 (таймаут) / 35 (TLS).
  curl -sS --max-time 8 -o /dev/null "$2" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 22 ]; then add_result "Сеть" "READY" "-" "$1" "доступен"
  elif [ "$rc" -eq 6 ] || [ "$rc" -eq 7 ] || [ "$rc" -eq 28 ] || [ "$rc" -eq 35 ]; then
    if [ "$3" = "1" ]; then add_result "Сеть" "BLOCKED" "-" "$1" "НЕДОСТУПЕН — этот регион ИИ не пускает, нужен выход через US/EU"
    else add_result "Сеть" "WARN" "-" "$1" "недоступен (не критично)"; fi
  else add_result "Сеть" "READY" "-" "$1" "доступен"; fi
}
check_ep "Claude (Anthropic)" "https://api.anthropic.com" 1
check_ep "ChatGPT/Codex (OpenAI)" "https://api.openai.com" 1
check_ep "Gemini (Google)" "https://generativelanguage.googleapis.com" 1
check_ep "Cursor" "https://api2.cursor.sh" 0
check_ep "GitHub (Copilot)" "https://github.com" 0

# ---- Живой тест ИИ (опц., ТОЛЬКО под VPN) --------------------------------
if [ "$LIVE_TEST" -eq 1 ] || { [ "$REPORT_ONLY" -eq 0 ] && [ -t 0 ] && [ "$(ask '  Живой тест ИИ (мини-запрос, потратит немного квоты)? [y/N]: ')" = "y" ]; }; then
  # Гейт: не по стране, а по РЕАЛЬНОЙ доступности Anthropic-эндпоинта (READY) + логину.
  ANTH_READY=0; for r in "${ROWS[@]}"; do IFS='|' read -r rc st vv nm ac <<< "$r"; [ "$nm" = "Claude (Anthropic)" ] && [ "$st" = "READY" ] && ANTH_READY=1; done
  if [ "$ANTH_READY" -eq 1 ]; then
    if claude_login; then
      OUT="$(cd "${TMPDIR:-/tmp}" && timeout 45 claude -p "Ответь ровно одним словом: OK" 2>&1)"
      echo "$OUT" | grep -qiE 'not logged in|401|403|rate.?limit|quota' && add_result "Доступ к ИИ" "BLOCKED" "-" "Claude live-тест" "ошибка/лимит" || { [ -n "$OUT" ] && add_result "Доступ к ИИ" "READY" "ответ" "Claude live-тест" "ИИ реально отвечает" || add_result "Доступ к ИИ" "BLOCKED" "-" "Claude live-тест" "пустой ответ"; }
    fi
  else add_result "Доступ к ИИ" "WARN" "-" "Живой тест ИИ" "пропущен — Claude недоступен из этого региона"; fi
fi

# ==== ВЫВОД ===============================================================
echo ""
declare -a CATS=("Система" "Инструменты" "Доступ к ИИ" "Десктоп" "Сеть")
icon() { case "$1" in READY) echo "[OK] ГОТОВ ";; REPAIRED) echo "[+]  ПОЧИНЕН";; WARN) echo "[~]  ВНИМАН.";; LOGIN) echo "[!]  ВОЙТИ  ";; ABSENT) echo "[-]  нет    ";; MISSING) echo "[X]  НЕТ    ";; BLOCKED) echo "[X]  БЛОК   ";; ERROR) echo "[!!] ОШИБКА ";; *) echo "[?]  $1";; esac; }
for cat in "${CATS[@]}"; do
  printf '%s  [ %s ]%s\n' "$C_CY" "$cat" "$C_0"
  for r in "${ROWS[@]}"; do IFS='|' read -r rc st vv nm ac <<< "$r"; [ "$rc" = "$cat" ] || continue
    printf '    %s  %-18s %-22s %s\n' "$(icon "$st")" "$nm" "$vv" "$ac"; done
  echo ""
done

# JSON-отчёт
{ echo -n "["; first=1; for r in "${ROWS[@]}"; do IFS='|' read -r rc st vv nm ac <<< "$r"; [ $first -eq 1 ] || echo -n ","; first=0; printf '{"cat":"%s","status":"%s","name":"%s","ver":"%s","action":"%s"}' "$rc" "$st" "$nm" "$vv" "$ac"; done; echo "]"; } > "$REPORT_DIR/report_$STAMP.json"

# ---- VPN-плашка + вердикт ------------------------------------------------
bigbox() { local t="$1" s="$2" c="$3"; local w=52; printf '%s  ╔%s╗%s\n' "$c" "$(printf '═%.0s' $(seq 1 $w))" "$C_0"
  local pt=$(( (w - ${#t}) / 2 )); local ps=$(( (w - ${#s}) / 2 ))
  printf '%s  ║%*s%s%*s║%s\n' "$c" "$pt" "" "$t" "$((w-${#t}-pt))" "" "$C_0"
  [ -n "$s" ] && printf '%s  ║%*s%s%*s║%s\n' "$c" "$ps" "" "$s" "$((w-${#s}-ps))" "" "$C_0"
  printf '%s  ╚%s╝%s\n' "$c" "$(printf '═%.0s' $(seq 1 $w))" "$C_0"; }
echo ""
if [ -n "$EXIT_COUNTRY" ] && [ "$EXIT_COUNTRY" != "RU" ]; then bigbox "VPN: АКТИВЕН" "выход $EXIT_COUNTRY · $EXIT_IP" "$C_GR"
elif [ "$EXIT_COUNTRY" = "RU" ]; then bigbox "VPN: ВЫКЛ (РФ-выход)" "прямой РФ-IP — включи VPN" "$C_YE"
else bigbox "VPN: не определён" "нет данных о внешнем IP" "$C_GY"; fi
echo ""
[ ${#BLOCKERS[@]} -eq 0 ] && { bigbox "СРЕДА ГОТОВА" "можно работать" "$C_GR"; VERDICT="ГОТОВА"; } || { bigbox "СРЕДА НЕ ГОТОВА" "закрой пункты ниже" "$C_RD"; VERDICT="НЕ ГОТОВА"; for b in "${BLOCKERS[@]}"; do echo "     - $b"; done; }

# ---- Регион закрыт: что делать -------------------------------------------
# В боевой версии кита здесь стоит мастер подключения туннеля: ставит клиент,
# ведёт за ключом доступа, перепроверяет выход и обновляет состояние. В публичной
# версии его нет — он завязан на частный сервис выдачи доступа, который к самому
# инструменту отношения не имеет. Остаётся диагностика выше: она называет
# поимённо, какие эндпоинты недоступны с этой машины, а это и есть та часть,
# которая одинаково работает и за корпоративным прокси, и в гостиничном Wi-Fi.
if { [ -z "$EXIT_COUNTRY" ] || [ "$EXIT_COUNTRY" = "RU" ]; } && [ -t 0 ]; then
  BLOCKED_ANY=0
  for r in "${ROWS[@]}"; do IFS='|' read -r rc st vv nm ac <<< "$r"
    [ "$rc" = "Сеть" ] && [ "$st" = "BLOCKED" ] || continue
    [ "$BLOCKED_ANY" -eq 0 ] && { echo ""; printf '%s  ── ДОСТУП К ИИ ЗАКРЫТ ИЗ ЭТОЙ СЕТИ ────────────%s\n' "$C_YE" "$C_0"; BLOCKED_ANY=1; }
    printf '%s   • %s — не отвечает%s\n' "$C_YE" "$nm" "$C_0"
  done
  if [ "$BLOCKED_ANY" -eq 1 ]; then
    printf '%s   Дело не в установке: инструменты на месте, до серверов ИИ не доходит сеть.%s\n' "$C_GY" "$C_0"
    printf '%s   Меняй сеть или маршрут до этих адресов и запусти проверку заново.%s\n' "$C_GY" "$C_0"
    printf '%s   ВХОД В АККАУНТ до этого лучше не делать: провайдеры ИИ ограничивают%s\n' "$C_GY" "$C_0"
    printf '%s   доступ по региону, и попытка входа из закрытого региона стоит аккаунта.%s\n' "$C_GY" "$C_0"
  fi
fi

# ---- Отчёт куратору (ВЫКЛЮЧЕН, пока не задан свой --report-url) -----------
# Зачем это вообще есть: на живом потоке куратор должен видеть, у кого среда не
# поднялась, ДО того как человек сдастся и уйдёт молча. Уходит одна строка
# вердикта и список блокеров — ни путей, ни имён файлов, ни внешнего IP.
# Без --report-url не создаётся даже machine-id: нет приёмника — нет и следа.
if [ -n "$REPORT_URL" ] && [ "$NO_REPORT" -eq 0 ]; then
  # Стабильный machine-id (создаётся раз). Личность привязывает бот — без ввода.
  MID_FILE="$HOME/.stereo_kit_id"
  MID=""; [ -f "$MID_FILE" ] && MID="$(cat "$MID_FILE" 2>/dev/null)"
  if [ -z "$MID" ]; then MID="MID-$(uuidgen 2>/dev/null | tr -d - | cut -c1-12)"; echo "$MID" > "$MID_FILE"; fi
  PAIRED=""
  [ -n "$PAIR_URL" ] && PAIRED="$(curl -fsS --max-time 8 "$PAIR_URL?mid=$MID" 2>/dev/null | grep -o '"paired":[a-z]*' | cut -d: -f2)"
  if [ -n "$PAIR_BOT" ] && [ "$PAIRED" != "true" ] && [ "$REPORT_ONLY" -eq 0 ] && [ -t 0 ]; then
    echo ""; printf '%s  ── ПРИВЯЗКА К TELEGRAM (для куратора) ──%s\n' "$C_CY" "$C_0"
    echo "  Ничего вводить не нужно: откроем бота, нажми СТАРТ, вернись сюда."
    a="$(ask '   Открыть бота для привязки? [Y/n]: ')"
    if [ "$a" != "n" ]; then
      open "$PAIR_BOT?start=kit_$MID"
      read -r -p "   Нажал СТАРТ в боте? Enter — проверю привязку..." _
      for i in 1 2 3 4 5; do PAIRED="$(curl -fsS --max-time 8 "$PAIR_URL?mid=$MID" 2>/dev/null | grep -o '"paired":[a-z]*' | cut -d: -f2)"; [ "$PAIRED" = "true" ] && break; sleep 2; done
    fi
    [ "$PAIRED" = "true" ] && printf '%s   Привязано ✓%s\n' "$C_GR" "$C_0" || printf '%s   Пока не привязано — отчёт уйдёт обезличенным.%s\n' "$C_GY" "$C_0"
  fi
  if [ -n "$EXIT_COUNTRY" ] && [ "$EXIT_COUNTRY" != "RU" ]; then VPNT="выход $EXIT_COUNTRY"
  elif [ "$EXIT_COUNTRY" = "RU" ]; then VPNT="РФ-выход"
  else VPNT="неизвестно"; fi
  PROBS=""; for b in "${BLOCKERS[@]}"; do [ -n "$PROBS" ] && PROBS="$PROBS,"; PROBS="$PROBS\"$b\""; done
  # WARN-строки — не блокеры, но куратор должен их видеть (частичный вход, РФ-выход,
  # мало места). Раньше терялись: отчёт «ГОТОВА» без единого намёка на проблему.
  WARNS=""
  for r in "${ROWS[@]}"; do IFS='|' read -r rc st vv nm ac <<< "$r"
    [ "$st" = "WARN" ] || continue
    [ -n "$WARNS" ] && WARNS="$WARNS,"; WARNS="$WARNS\"$nm: $ac\""
  done
  # Режим прогона: dry-run и неудачный ремонт давали ОДИНАКОВЫЙ отчёт.
  if [ "$REPORT_ONLY" -eq 1 ]; then MODE="report-only"; else MODE="repair"; fi
  PAYLOAD="{\"mid\":\"$MID\",\"host\":\"$(hostname)\",\"os\":\"macos\",\"verdict\":\"$VERDICT\",\"vpn\":\"$VPNT\",\"mode\":\"$MODE\",\"problems\":[$PROBS],\"warnings\":[$WARNS]}"
  curl -fsS --max-time 15 -X POST -H "Content-Type: application/json; charset=utf-8" -d "$PAYLOAD" "$REPORT_URL" >/dev/null 2>&1 && printf '%s  Отчёт куратору отправлен.%s\n' "$C_GY" "$C_0"
fi

echo ""; echo "  Отчёт сохранён: $LOG_PATH"

# ==== ПАМЯТЬ ПРОЕКТА ======================================================
# Проверка только что выяснила про машину всё, что агент в первой сессии
# выясняет наугад: ОС, что установлено и каких версий, в какой ИИ выполнен вход,
# какие эндпоинты закрыты. Выбросить это в лог — значит заставить агента гадать
# заново. Поэтому раскладываем в память проекта, которую он читает при старте.
#
# ПРАВИЛА (те же, что записаны в самом CLAUDE.md):
#  - НИЧЕГО не перезаписываем; свежий infra_status ложится рядом как *.new.md.
#  - Внешний IP НЕ пишем: файл живёт у человека и попадёт в чей-нибудь git.
#  - Нет шаблонов — не падаем, говорим одной строкой и идём дальше.
# NB: macOS до сих пор идёт с bash 3.2, поэтому никаких ассоциативных массивов —
# подстановка плейсхолдеров делается через ${VAR//шаблон/замена}.
row_field() { # $1 = имя компонента, $2 = номер поля (2=статус, 3=версия)
  local r nm
  for r in "${ROWS[@]}"; do
    nm="$(echo "$r" | cut -d'|' -f4)"
    if [ "$nm" = "$1" ]; then echo "$r" | cut -d'|' -f"$2"; return 0; fi
  done
  echo ""
}
mem_version() { local v; v="$(row_field "$1" 3)"; if [ -n "$v" ] && [ "$v" != "-" ]; then echo "$v"; else echo "not installed"; fi; }
mem_reach() { local s; s="$(row_field "$1" 2)"; case "$s" in READY) echo "yes";; "") echo "not checked";; *) echo "no";; esac; }
mem_login() { # $1 = установлен(0/1), $2 = имя функции проверки входа
  [ "$1" -eq 1 ] || { echo "—"; return; }
  if "$2"; then echo "yes"; else echo "no"; fi
}
init_project_memory() { # $1 = папка проекта
  local proj="$1" tpl="" c memdir created kept infra
  for c in "$SCRIPT_DIR/templates" "$SCRIPT_DIR/../../templates"; do
    [ -d "$c" ] && { tpl="$(cd "$c" && pwd)"; break; }
  done
  if [ -z "$tpl" ]; then
    printf '%s  Память проекта: шаблоны (templates/) не найдены — пропускаю.%s\n' "$C_GY" "$C_0"
    return 0
  fi
  if [ -z "$KIT_LANG" ]; then
    case "${LANG:-}" in ru*|RU*) KIT_LANG="ru" ;; *) KIT_LANG="en" ;; esac
  fi
  memdir="$proj/memory"
  mkdir -p "$memdir" "$proj/scratch" "$proj/backup" 2>/dev/null
  created=""; kept=""
  local claude_md="CLAUDE.md"
  [ "$KIT_LANG" = "ru" ] && claude_md="CLAUDE.ru.md"
  copy_if_absent() { # $1 = источник, $2 = приёмник
    [ -f "$1" ] || return 0
    if [ -e "$2" ]; then kept="$kept $(basename "$2")"; return 0; fi
    cp "$1" "$2" && created="$created $(basename "$2")"
  }
  copy_if_absent "$tpl/$claude_md"                     "$proj/CLAUDE.md"
  copy_if_absent "$tpl/memory/README.md"               "$memdir/README.md"
  copy_if_absent "$tpl/memory/PROJECT_status.md"       "$memdir/PROJECT_status.md"
  copy_if_absent "$tpl/memory/PROJECT_backlog.md"      "$memdir/PROJECT_backlog.md"
  copy_if_absent "$tpl/memory/PROJECT_history.md"      "$memdir/PROJECT_history.md"

  # infra_status.md — не шаблон, а ФАКТЫ только что прошедшей проверки.
  if [ -f "$tpl/memory/infra_status.template.md" ]; then
    local TXT
    TXT="$(cat "$tpl/memory/infra_status.template.md")"
    TXT="${TXT//\{\{DATE\}\}/$(date '+%Y-%m-%d %H:%M')}"
    TXT="${TXT//\{\{OS_NAME\}\}/macOS}"
    TXT="${TXT//\{\{OS_BUILD\}\}/$(mem_version 'macOS')}"
    TXT="${TXT//\{\{HOSTNAME\}\}/$(hostname)}"
    # Единица из русского вывода — в англоязычном файле памяти читается мусором.
    TXT="${TXT//\{\{DISK_FREE\}\}/$(mem_version 'Диск /' | sed 's/ГБ/GB/')}"
    TXT="${TXT//\{\{PROJECT_DIR\}\}/$proj}"
    TXT="${TXT//\{\{REPORT_DIR\}\}/$REPORT_DIR}"
    TXT="${TXT//\{\{GIT_VERSION\}\}/$(mem_version 'Git')}"
    TXT="${TXT//\{\{NODE_VERSION\}\}/$(mem_version 'Node.js LTS')}"
    TXT="${TXT//\{\{PKG_MANAGER\}\}/Homebrew}"
    TXT="${TXT//\{\{PKG_VERSION\}\}/$(mem_version 'Homebrew')}"
    TXT="${TXT//\{\{SHELL_NAME\}\}/bash}"
    TXT="${TXT//\{\{SHELL_VERSION\}\}/${BASH_VERSION:-unknown}}"
    TXT="${TXT//\{\{CLAUDE_INSTALLED\}\}/$(mem_version 'Claude Code')}"
    TXT="${TXT//\{\{CODEX_INSTALLED\}\}/$(mem_version 'Codex')}"
    TXT="${TXT//\{\{GEMINI_INSTALLED\}\}/$(mem_version 'Gemini CLI')}"
    TXT="${TXT//\{\{CLAUDE_LOGGED_IN\}\}/$(mem_login "$CLAUDE_OK" claude_login)}"
    TXT="${TXT//\{\{CODEX_LOGGED_IN\}\}/$(mem_login "$CODEX_OK" codex_login)}"
    TXT="${TXT//\{\{GEMINI_LOGGED_IN\}\}/$(mem_login "$GEMINI_OK" gemini_login)}"
    TXT="${TXT//\{\{EP_ANTHROPIC\}\}/$(mem_reach 'Claude (Anthropic)')}"
    TXT="${TXT//\{\{EP_OPENAI\}\}/$(mem_reach 'ChatGPT/Codex (OpenAI)')}"
    TXT="${TXT//\{\{EP_GOOGLE\}\}/$(mem_reach 'Gemini (Google)')}"
    infra="$memdir/infra_status.md"
    if [ -e "$infra" ]; then
      printf '%s\n' "$TXT" > "$memdir/infra_status.new.md"
      kept="$kept infra_status.md"
      created="$created infra_status.new.md(среда могла измениться — сравни руками)"
    else
      printf '%s\n' "$TXT" > "$infra"
      created="$created infra_status.md"
    fi
  fi

  echo ""; printf '%s  ── ПАМЯТЬ ПРОЕКТА ───%s\n' "$C_CY" "$C_0"
  [ -n "$created" ] && printf '%s   создано:%s%s\n' "$C_GR" "$created" "$C_0"
  [ -n "$kept" ] && printf '%s   не тронуто (уже было):%s%s\n' "$C_GY" "$kept" "$C_0"
  printf '%s   Агент прочитает CLAUDE.md и memory/infra_status.md при старте —%s\n' "$C_GY" "$C_0"
  printf '%s   и не будет гадать, что у тебя установлено.%s\n' "$C_GY" "$C_0"
  return 0
}

# ---- В РАБОТУ ------------------------------------------------------------
if [ "$REPORT_ONLY" -eq 0 ] && [ -t 0 ]; then
  # Показываем ВСЕ установленные CLI, даже без входа. Раньше пункт без логина молча
  # исчезал: сверху «Codex ГОТОВ», а нажатие номера не делало НИЧЕГО — читается как
  # поломка. Номера считаем динамически, дырок в нумерации нет.
  A_NAME=(); A_CMD=(); A_READY=(); A_FIX=()
  if [ "$CLAUDE_OK" -eq 1 ]; then A_NAME+=("Claude Code"); A_CMD+=("claude"); A_FIX+=("запусти claude, затем /login")
    if claude_login; then A_READY+=(1); else A_READY+=(0); fi; fi
  if [ "$CODEX_OK" -eq 1 ]; then A_NAME+=("Codex"); A_CMD+=("codex"); A_FIX+=("выполни: codex login")
    if codex_login; then A_READY+=(1); else A_READY+=(0); fi; fi
  if [ "$GEMINI_OK" -eq 1 ]; then A_NAME+=("Gemini"); A_CMD+=("gemini"); A_FIX+=("запусти gemini и войди Google-аккаунтом")
    if gemini_login; then A_READY+=(1); else A_READY+=(0); fi; fi
  if [ "${#A_NAME[@]}" -gt 0 ]; then
    echo ""; printf '%s  ── В РАБОТУ ───%s\n' "$C_CY" "$C_0"
    echo "   Начать кодить прямо сейчас?"
    i=0
    while [ "$i" -lt "${#A_NAME[@]}" ]; do
      n=$((i+1))
      if [ "${A_READY[$i]}" -eq 1 ]; then printf '   [%d] %s\n' "$n" "${A_NAME[$i]}"
      else printf '%s   [%d] %s — нужен вход (выберу — войдём)%s\n' "$C_GY" "$n" "${A_NAME[$i]}" "$C_0"; fi
      i=$((i+1))
    done
    read -r -p "   Выбор ([Enter] — выйти): " CH
    LAUNCH=""
    if [ -n "$CH" ]; then
      if echo "$CH" | grep -qE '^[0-9]+$' && [ "$CH" -ge 1 ] && [ "$CH" -le "${#A_NAME[@]}" ]; then
        k=$((CH-1))
        if [ "${A_READY[$k]}" -eq 1 ]; then LAUNCH="${A_CMD[$k]}"
        else
          # Не отфутболиваем командой — логиним прямо тут.
          # ГЕЙТ VPN: вход с РФ-IP = риск бана аккаунта (правило живого теста).
          if [ -z "$EXIT_COUNTRY" ] || [ "$EXIT_COUNTRY" = "RU" ]; then
            printf '%s   %s установлен, но вход не выполнен.%s\n' "$C_YE" "${A_NAME[$k]}" "$C_0"
            printf '%s   ВХОДИТЬ СЕЙЧАС ОПАСНО: выход через РФ (или не определён) — рискуешь баном аккаунта.%s\n' "$C_RD" "$C_0"
            printf '%s   Включи VPN и запусти проверку заново.%s\n' "$C_YE" "$C_0"
          else
            ANS="$(ask "   ${A_NAME[$k]}: вход не выполнен. Войти сейчас? [Y/n]: ")"
            if [ "$ANS" != "n" ]; then
              if [ "${A_CMD[$k]}" = "codex" ]; then
                # `codex login` поднимает локальный сервер на :1455, открывает браузер,
                # а подсказку со ссылкой печатает в stderr — её легко не заметить.
                printf '%s   Открываю вход в Codex — подтверди в браузере и вернись сюда...%s\n' "$C_CY" "$C_0"
                printf '%s   Если браузер не открылся — ссылка будет напечатана ниже, открой её вручную.%s\n' "$C_GY" "$C_0"
                codex login || true
                if codex_login; then printf '%s   Вход выполнен.%s\n' "$C_GR" "$C_0"; LAUNCH="codex"
                else
                  printf '%s   Вход пока не завершён. Вручную: %s%s\n' "$C_YE" "${A_FIX[$k]}" "$C_0"
                  printf '%s   Запасной вариант: codex login --device-auth%s\n' "$C_GY" "$C_0"
                fi
              else
                # Claude Code и Gemini спрашивают вход сами при первом запуске.
                printf '%s   Запускаю %s — пройди вход прямо в нём.%s\n' "$C_CY" "${A_NAME[$k]}" "$C_0"
                LAUNCH="${A_CMD[$k]}"
              fi
            fi
          fi
        fi
      else
        printf '%s   Нет такого варианта: «%s». Доступны 1..%d, либо Enter — выйти.%s\n' "$C_YE" "$CH" "${#A_NAME[@]}" "$C_0"
      fi
    fi
    if [ -n "$LAUNCH" ]; then
      PROJ="$HOME/stereo-vibe"; mkdir -p "$PROJ"
      ( cd "$PROJ" && have git && [ ! -d .git ] && git init -q ) 2>/dev/null
      # Память агента. Сорваться на записи файлов и не запустить агента — цена
      # несоразмерная, поэтому ошибка тут ничего не роняет.
      init_project_memory "$PROJ" || printf '%s  Память проекта: пропущено.%s\n' "$C_GY" "$C_0"
      # Ярлык остаётся в проекте: ученик может перезапустить агента двойным кликом.
      SHIM="$PROJ/СТАРТ-$LAUNCH.command"
      {
        echo '#!/bin/bash'
        echo 'cd "$(dirname "$0")"'
        printf 'exec %s "$@"\n' "$LAUNCH"
      } > "$SHIM"
      chmod +x "$SHIM" 2>/dev/null
      # Отдельное окно Терминала: кит остаётся жив (ученик видит отчёт и что дальше),
      # агент работает параллельно.
      if open -a Terminal "$SHIM" 2>/dev/null; then
        printf '%s  %s запущен в ОТДЕЛЬНОМ окне Терминала.%s\n' "$C_GR" "$LAUNCH" "$C_0"
        printf '%s  Проект: %s%s\n' "$C_GY" "$PROJ" "$C_0"
        printf '%s  Перезапустить потом: двойной клик по СТАРТ-%s.command в папке проекта.%s\n' "$C_GY" "$LAUNCH" "$C_0"
      else
        printf '%s  Не удалось открыть отдельное окно — запускаю прямо здесь.%s\n' "$C_YE" "$C_0"
        cd "$PROJ"; exec "$LAUNCH"
      fi
    fi
  fi
fi
[ ${#BLOCKERS[@]} -eq 0 ] && exit 0 || exit 1
