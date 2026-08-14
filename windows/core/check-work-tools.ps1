[CmdletBinding()]
param(
  [switch]$InstallMissing = $true,
  [switch]$Update = $true,
  [switch]$ReportOnly,
  [switch]$LiveTest,       # реальный мини-запрос к ИИ (тратит немного квоты); только если регион пускает
  [switch]$NoReport,       # выключить отправку отчёта явно (без -ReportUrl она и так выключена)
  # Отчёт куратору ВЫКЛЮЧЕН, пока не указан свой приёмник. Эндпоинта по умолчанию
  # здесь нет и быть не должно: инструмент, который на чужой машине молча стучится
  # на сервер автора, — это не инструмент, а сюрприз. Пустой URL = не отправляем
  # ничего и не заводим machine-id. Свой приёмник:
  #   -ReportUrl https://your.server/kit-report [-PairUrl ... -PairBot ...]
  [string]$ReportUrl = '',
  [string]$PairUrl   = '',
  [string]$PairBot   = '',
  [switch]$ForceVpnOff,    # ТЕСТ: форсит «выход из РФ», чтобы прогнать ветку не трогая сеть
  [ValidateSet('Codex','Claude','Gemini')][string]$PreferredAI,
  [ValidateSet('en','ru')][string]$Lang,   # язык шаблонов памяти; по умолчанию — по языку системы
  [string]$ReportDir       # куда писать лог+JSON; по умолчанию — папка \reports рядом со скриптом
)

# ==========================================================================
#  Проверщик рабочей среды вайб-кодера (Windows). Портативный — можно с флешки.
#
#  Проверяет: PowerShell, WinGet, Git, Node.js LTS, Codex/Claude Code и
#  ГЛАВНОЕ — авторизацию ИИ (установленный CLI != рабочий, нужен вход).
#  В конце: заводит папку проекта и РАЗВОРАЧИВАЕТ ПАМЯТЬ АГЕНТА — CLAUDE.md +
#  memory\, причём infra_status.md заполняется фактами этой самой проверки.
#
#  Принципы:
#   - presence-first: инструмент СТОИТ = зелёный. Апдейт — необязательный бонус.
#   - каждый пункт независим: сбой одного не роняет остальные.
#   - проверка апдейта read-only (winget list --upgrade-available) — сама
#     ничего не устанавливает. Ставит/обновляет только repair-режим.
#   - офлайн-фолбэк: если рядом папка installers\ с установщиками — ставим
#     из них, когда нет интернета/winget.
#   - автолог: каждый запуск пишет log_*.txt + report_*.json (на флешку).
# ==========================================================================

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---- Папка отчётов (рядом со скриптом / на флешке; фолбэк — TEMP) ---------
if (-not $ReportDir) { $ReportDir = Join-Path $PSScriptRoot 'reports' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
  if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
  '' | Out-File -LiteralPath (Join-Path $ReportDir '.wtest') -ErrorAction Stop; Remove-Item (Join-Path $ReportDir '.wtest') -ErrorAction SilentlyContinue
} catch {
  $ReportDir = Join-Path $env:TEMP 'starter_kit_reports'
  if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
}
$LogPath  = Join-Path $ReportDir "log_$stamp.txt"
$JsonPath = Join-Path $ReportDir "report_$stamp.json"
$InstallersDir = Join-Path $PSScriptRoot 'installers'
try { Start-Transcript -LiteralPath $LogPath -Force | Out-Null } catch {}

if ($ReportOnly) { $InstallMissing = $false; $Update = $false }

# ---- Интерфейс -----------------------------------------------------------
$script:BW = 52   # внутренняя ширина рамки
function Box-Row([string]$text,[string]$color) {
  if ($text.Length -gt $script:BW) { $text = $text.Substring(0,$script:BW) }
  Write-Host ('  │' + $text.PadRight($script:BW) + '│') -ForegroundColor $color
}
function Write-Banner {
  Write-Host ''
  Write-Host '  ███████ ████████ ███████ ██████  ███████  ██████'   -ForegroundColor Cyan
  Write-Host '  ██         ██    ██      ██   ██  ██      ██    ██'   -ForegroundColor Cyan
  Write-Host '  ███████    ██    █████   ██████   █████   ██    ██'   -ForegroundColor Cyan
  Write-Host '       ██    ██    ██      ██   ██  ██      ██    ██'   -ForegroundColor Cyan
  Write-Host '  ███████    ██    ███████ ██   ██  ███████  ██████  ·AI' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '  ─────  V I B E · стартер-кит вайб-кодера  ─────'     -ForegroundColor Yellow
  Write-Host '  проверка рабочей среды · один клик'                  -ForegroundColor DarkGray
  Write-Host ''
  if ($ReportOnly) { Write-Host '  Режим: только отчёт (ничего не меняем)' -ForegroundColor DarkGray }
  else { Write-Host '  Режим: проверка и ремонт (ставим/обновляем недостающее)' -ForegroundColor DarkGray }
  if (Test-Path $InstallersDir) { Write-Host "  Офлайн-установщики: найдены" -ForegroundColor DarkGray }
  Write-Host ''
}
function Wait-Start {
  # Не блокируем не-интерактивный запуск (пайп/автотест).
  try { if ([Console]::IsInputRedirected) { return } } catch {}
  $msg = '►►►   НАЖМИ  ENTER  ДЛЯ  ПРОВЕРКИ   ◄◄◄'
  $pad = 4; $w = $msg.Length + $pad * 2; $sp = ' ' * $w; $l = ' ' * $pad
  Write-Host ''
  Write-Host ('  ╔' + ('═' * $w) + '╗') -ForegroundColor Magenta
  Write-Host ('  ║' + $sp + '║') -ForegroundColor Magenta
  Write-Host ('  ║' + $l + $msg + $l + '║') -ForegroundColor Magenta
  Write-Host ('  ║' + $sp + '║') -ForegroundColor Magenta
  Write-Host ('  ╚' + ('═' * $w) + '╝') -ForegroundColor Magenta
  [void](Read-Host)
  Write-Host ''
}
function Wait-End {
  try { if ([Console]::IsInputRedirected) { return } } catch {}
  Write-Host '  ─────────────────────────────────────────────' -ForegroundColor DarkGray
  Write-Host '  ►►►   Нажми  ENTER,  чтобы  закрыть  окно   ◄◄◄' -ForegroundColor Magenta
  [void](Read-Host)
}
function Write-Step([string]$Name) { Write-Host "  • Проверяю: $Name..." -ForegroundColor DarkGray }

$Results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Category,[string]$Name,[string]$Status,[string]$Version='-',[string]$Action='-',[string]$Details='') {
  $Results.Add([pscustomobject]@{Category=$Category;Component=$Name;Status=$Status;Version=$Version;Action=$Action;Details=$Details})
}

# ---- Низкоуровневые помощники --------------------------------------------
function Invoke-CheckedCommand([string]$FilePath,[string[]]$Arguments) {
  $text = & $FilePath @Arguments 2>&1 | Out-String
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}
function Get-Version([string]$Exe,[string[]]$VersionArguments=@('--version')) {
  $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  $run = Invoke-CheckedCommand $cmd.Source $VersionArguments
  if ($run.ExitCode -ne 0) { throw "${Exe} вернул код выхода $($run.ExitCode)" }
  $m = [regex]::Match($run.Text,'(?<!\d)(\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $run.Text.Trim().Replace("`r",'').Replace("`n",' ')
}
# Проверка апдейта — ЧИСТО read-only: winget list --upgrade-available только
# листинг, физически не может ничего установить. Источник только winget (без
# msstore, который виснет на РФ-сетях: 0x80072ee2). 'OK'/'UPDATE'/'SKIP'.
function Get-WingetUpdate([string]$Id) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return 'SKIP' }
  try { $run = Invoke-CheckedCommand 'winget' @('list','--id',$Id,'--exact','--upgrade-available','--source','winget','--disable-interactivity','--accept-source-agreements') }
  catch { return 'SKIP' }
  $out = $run.Text
  if ($out -match '(?im)no installed package found|no package found') { return 'OK' }
  if ($run.ExitCode -eq 0 -and $out -match "(?i)$([regex]::Escape($Id))") { return 'UPDATE' }
  if ($run.ExitCode -eq 0) { return 'OK' }
  return 'SKIP'
}
function Invoke-Winget([string]$Verb,[string]$Id) {
  & winget $Verb --id $Id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "winget ${Verb} для ${Id} завершился с ошибкой" }
}
# Офлайн-установщик: ищем в installers\ файл по маске, ставим молча.
function Find-LocalInstaller([string[]]$Patterns) {
  if (-not (Test-Path $InstallersDir)) { return $null }
  foreach ($p in $Patterns) {
    $f = Get-ChildItem -LiteralPath $InstallersDir -Filter $p -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
  }
  return $null
}
function Install-Local([string]$Path) {
  $ext = [System.IO.Path]::GetExtension($Path).ToLower()
  switch ($ext) {
    '.msi'        { Start-Process msiexec.exe -ArgumentList @('/i',"`"$Path`"",'/qn','/norestart') -Wait -PassThru | ForEach-Object { if ($_.ExitCode -ne 0) { throw "msiexec код $($_.ExitCode)" } } }
    '.msixbundle' { Add-AppxPackage -Path $Path -ErrorAction Stop }
    '.appxbundle' { Add-AppxPackage -Path $Path -ErrorAction Stop }
    default       { $p = Start-Process $Path -ArgumentList '/VERYSILENT','/NORESTART','/SUPPRESSMSGBOXES' -Wait -PassThru; if ($p.ExitCode -ne 0) { throw "установщик код $($p.ExitCode)" } }
  }
}

# Из процесса с админом обычный Start-Process рождает ТАКОГО ЖЕ админского потомка.
# Для ИИ-агента это лишние права, а для ВХОДА В АККАУНТ — прямой блокер: браузер
# открывается в чужом сеансе, без кук ученика, и вход не завершается («ничего не
# произошло»). Проводник работает от обычного пользователя, поэтому запущенное им
# наследует его уровень. Подтверждение старта — флаг-файл от самого ярлыка.
function Start-UnelevatedCmd([string]$Dir,[string]$FileName,[string[]]$Body,[int]$WaitSec=9) {
  try {
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $shim = Join-Path $Dir $FileName
    # ASCII-only: cmd.exe парсит батник в OEM-кодировке, кириллица внутри его ломает.
    [System.IO.File]::WriteAllLines($shim, $Body, [System.Text.Encoding]::ASCII)
    $flag = Join-Path $env:TEMP 'stereo_agent_launched.flag'
    Remove-Item $flag -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe -ArgumentList "`"$shim`"" -ErrorAction Stop
    $steps = [int]([math]::Ceiling($WaitSec / 0.7))
    for ($t = 0; $t -lt $steps; $t++) {
      Start-Sleep -Milliseconds 700
      if (Test-Path $flag) { Remove-Item $flag -Force -ErrorAction SilentlyContinue; return $true }
    }
  } catch {}
  return $false
}

# ---- Сеть: внешний IP/гео (ipinfo) + реальная доступность AI-эндпоинтов ----
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
# ОДИН источник гео = единая точка отказа: моргнул ipinfo (таймаут в момент
# переподключения туннеля / лимит запросов) — и кит объявляет «нет VPN», гонит
# ученика в мастер подключения, а живой тест пропускает. Поэтому цепочка источников.
function Get-ExitInfo {
  try {
    $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8 -ErrorAction Stop
    if ($r -and $r.ip) { return $r }
  } catch {}
  try {
    $t = (Invoke-WebRequest -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop).Content
    $ip = ''; $loc = ''
    foreach ($ln in ($t -split "`n")) {
      if ($ln.StartsWith('ip='))  { $ip  = $ln.Substring(3).Trim() }
      if ($ln.StartsWith('loc=')) { $loc = $ln.Substring(4).Trim() }
    }
    if ($ip) { return [pscustomobject]@{ ip = $ip; country = $loc; org = '(источник: cloudflare trace)' } }
  } catch {}
  return $null
}
# Единая точка записи состояния выхода. Раньше мастер VPN определял страну, писал
# «VPN АКТИВЕН», но состояние НЕ обновлял -> автологин потом отказывал «нет VPN»,
# а отчёт куратору уходил с vpn=неизвестно.
function Set-ExitState($ex) {
  if ($ex -and $ex.ip) {
    $script:ExitIp = $ex.ip; $script:ExitCountry = $ex.country; $script:ExitOrg = $ex.org
    return $true
  }
  return $false
}
# Реальный HTTPS-запрос (TLS+SNI) — ловит SNI-блок РКН. Любой HTTP-ответ (даже 4xx) = доступен.
# ОДНА попытка = один шанс промахнуться: туннель периодически роняет соединение,
# и единственный таймаут переворачивал вердикт в «СРЕДА НЕ ГОТОВА» на ровном месте
# (замер 12.08: 5 ответов по 0.3-0.85с и один таймаут 7с подряд). Поэтому ретраи.
function Test-Https([string]$url,[int]$sec=10,[int]$tries=3) {
  for ($i = 1; $i -le $tries; $i++) {
    try { Invoke-WebRequest -Uri $url -Method Head -TimeoutSec $sec -UseBasicParsing -ErrorAction Stop | Out-Null; return $true }
    catch { if ($_.Exception.Response) { return $true } }
    if ($i -lt $tries) { Start-Sleep -Milliseconds 800 }
  }
  return $false
}

# Инструмент может СТОЯТЬ, но не попасть в PATH текущего процесса (типовая грабля:
# поставили и не открыли новый терминал). Тогда честнее сказать «стоит, но не в PATH»,
# чем «НЕТ» и гнать ученика ставить то, что у него уже есть.
function Find-ExeOutsidePath([string[]]$Candidates) {
  foreach ($c in $Candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}
function Get-VersionAt([string]$ExePath) {
  try {
    $run = Invoke-CheckedCommand $ExePath @('--version')
    $m = [regex]::Match($run.Text,'(?<!\d)(\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
  } catch {}
  return '-'
}
$script:NodePaths  = @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")
# Codex CLI после слияния с ChatGPT (09.07.2026) приезжает нативным установщиком,
# НЕ через npm. Команда осталась `codex`, но в PATH попадает не всегда.
$script:CodexPaths = @("$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe", "$env:ProgramFiles\OpenAI\Codex\bin\codex.exe")

# presence-first проверка инструмента: winget + офлайн-фолбэк
function Test-Tool([string]$Category,[string]$Name,[string]$Exe,[string]$Id,[string[]]$LocalPatterns=@(),[string[]]$FallbackPaths=@()) {
  try {
    Write-Step $Name
    $version = Get-Version $Exe
    if (-not $version -and $FallbackPaths.Count -gt 0) {
      $fb = Find-ExeOutsidePath $FallbackPaths
      if ($fb) {
        Add-Result $Category $Name 'WARN' (Get-VersionAt $fb) 'СТОИТ, но не виден в PATH — закрой окно и открой заново' $fb
        return
      }
    }
    if (-not $version) {
      if ($InstallMissing) {
        $local = Find-LocalInstaller $LocalPatterns
        if ($local) { Install-Local $local; Add-Result $Category $Name 'REPAIRED' '-' 'Поставлено из офлайн-установщика; откройте новый терминал'; return }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Add-Result $Category $Name 'MISSING' '-' 'Нет интернета/winget и нет офлайн-установщика'; return }
        Invoke-Winget 'install' $Id; Add-Result $Category $Name 'REPAIRED' '-' 'Установлено; откройте новый терминал'; return
      }
      Add-Result $Category $Name 'MISSING' '-' "Установить: winget install --id $Id --exact"; return
    }
    $state = Get-WingetUpdate $Id
    if ($state -eq 'UPDATE') {
      if ($Update) { try { Invoke-Winget 'upgrade' $Id; Add-Result $Category $Name 'REPAIRED' $version 'Обновлено; перезапустите проверку' }
                     catch { Add-Result $Category $Name 'READY' $version 'Стоит; автообновление не удалось' $_.Exception.Message } }
      else { Add-Result $Category $Name 'UPDATE' $version "Обновить: winget upgrade --id $Id --exact" }
    }
    elseif ($state -eq 'OK') { Add-Result $Category $Name 'READY' $version 'Актуально' }
    else { Add-Result $Category $Name 'READY' $version 'Стоит (апдейт не проверяли)' }
  } catch { Add-Result $Category $Name 'ERROR' '-' 'Проверить вручную' $_.Exception.Message }
}

Write-Banner
# Права администратора: без них winget-установки падают на середине (ученик видит
# «начало ставить и бросило»). Предупреждаем ДО начала, а не постфактум.
$script:IsAdmin = $false
try { $script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
if ($InstallMissing -and -not $script:IsAdmin) {
  Write-Host '  ── ВНИМАНИЕ: запуск БЕЗ прав администратора ───' -ForegroundColor Yellow
  Write-Host '  Права запрашивались при старте, но выданы не были.' -ForegroundColor Yellow
  Write-Host '  Установка и обновление программ могут не пройти.' -ForegroundColor Yellow
  Write-Host '  Если что-то не поставится — закрой окно, запусти run-check-windows.cmd' -ForegroundColor DarkGray
  Write-Host '  заново и нажми «Да» в окне Windows.' -ForegroundColor DarkGray
  Write-Host ''
}
Wait-Start

# ==== БЛОК 0. СИСТЕМА =====================================================
$CAT0 = 'Система'
try {
  Write-Step 'Свободное место на диске'
  $sd = $env:SystemDrive
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sd'"
  $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
  if     ($freeGB -ge 10) { Add-Result $CAT0 "Диск $sd" 'READY'   "$freeGB ГБ" 'свободно' }
  elseif ($freeGB -ge 2)  { Add-Result $CAT0 "Диск $sd" 'WARN'    "$freeGB ГБ" 'мало места — стоит почистить' }
  else                    { Add-Result $CAT0 "Диск $sd" 'BLOCKED' "$freeGB ГБ" 'критически мало — установка/сборка могут падать' }
} catch { Add-Result $CAT0 'Диск' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message }
try {
  Write-Step 'Версия Windows'
  $os = Get-CimInstance Win32_OperatingSystem
  $b = [int]$os.BuildNumber
  if     ($b -ge 22000) { Add-Result $CAT0 'Windows' 'READY' "11 (build $b)" 'поддерживается' }
  elseif ($b -ge 17763) { Add-Result $CAT0 'Windows' 'READY' "10 (build $b)" 'поддерживается' }  # 1809+
  else { $script:WinOld = $true; Add-Result $CAT0 'Windows' 'WARN' "build $b" 'старая Windows — winget/приложения могут не работать. Обнови до 10/11 (это бесплатно)' }
} catch { Add-Result $CAT0 'Windows' 'WARN' '-' 'не удалось определить версию' $_.Exception.Message }

# ==== БЛОК 1. ИНСТРУМЕНТЫ ==================================================
$CAT1 = 'Инструменты'
Test-Tool $CAT1 'PowerShell' 'pwsh' 'Microsoft.PowerShell' @('PowerShell*.msi')

try {
  Write-Step 'WinGet'
  $wv = Get-Version 'winget'
  if (-not $wv) {
    $local = Find-LocalInstaller @('*AppInstaller*.msixbundle','*DesktopAppInstaller*.msixbundle')
    if ($InstallMissing -and $local) { Install-Local $local; Add-Result $CAT1 'WinGet' 'REPAIRED' '-' 'Поставлено из офлайн-установщика' }
    else { Add-Result $CAT1 'WinGet' 'MISSING' '-' 'Поставьте App Installer из Microsoft Store' }
  } else { Add-Result $CAT1 'WinGet' 'READY' $wv 'Стоит (апдейт ведёт Microsoft Store)' }
} catch { Add-Result $CAT1 'WinGet' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message }

Test-Tool $CAT1 'Git' 'git' 'Git.Git' @('Git-*.exe')
Test-Tool $CAT1 'Node.js LTS' 'node' 'OpenJS.NodeJS.LTS' @('node-*.msi') $script:NodePaths

# ==== БЛОК 2. ДОСТУП К ИИ ==================================================
$CAT2 = 'Доступ к ИИ'
$codexInstalled = $false; $claudeInstalled = $false; $geminiInstalled = $false
try {
  Write-Step 'Codex / Claude Code / Gemini CLI'
  $codex = $null; $claude = $null; $gemini = $null; $aiErrors = @()
  try { $codex = Get-Version 'codex' } catch { $aiErrors += "Codex: $($_.Exception.Message)" }
  # Codex мог приехать нативным установщиком мимо PATH (после слияния с ChatGPT).
  $codexOutside = $null
  if (-not $codex) { $codexOutside = Find-ExeOutsidePath $script:CodexPaths }
  try { $claude = Get-Version 'claude' } catch { $aiErrors += "Claude Code: $($_.Exception.Message)" }
  try { $gemini = Get-Version 'gemini' } catch { $aiErrors += "Gemini: $($_.Exception.Message)" }
  $codexInstalled = [bool]$codex; $claudeInstalled = [bool]$claude; $geminiInstalled = [bool]$gemini
  # Если НЕТ ни одного — ставим выбранный (или указанный) и перечитываем версии.
  if (-not $codex -and -not $claude -and -not $gemini -and -not $codexOutside -and $aiErrors.Count -eq 0) {
    if (-not $PreferredAI -and -not $ReportOnly) {
      do { $choice = Read-Host '  Какой ИИ-CLI поставить: 1 = Codex, 2 = Claude Code, 3 = Gemini (бесплатный тир)' } until ($choice -in @('1','2','3'))
      $PreferredAI = switch ($choice) { '1' { 'Codex' } '2' { 'Claude' } '3' { 'Gemini' } }
    }
    if (-not $PreferredAI) { $PreferredAI = 'Codex' }
    $pkg = switch ($PreferredAI) { 'Codex' { '@openai/codex' } 'Claude' { '@anthropic-ai/claude-code' } 'Gemini' { '@google/gemini-cli' } }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { }  # ниже покажем MISSING на всех (нет ни одного)
    elseif ($InstallMissing) {
      $npmOptions = @(); if ($pkg -eq '@anthropic-ai/claude-code') { $npmOptions += '--allow-scripts=@anthropic-ai/claude-code' }
      & npm install --global $pkg @npmOptions
      if ($LASTEXITCODE -eq 0) {
        try {
          switch ($pkg) {
            '@openai/codex'             { $codex  = Get-Version 'codex' }
            '@anthropic-ai/claude-code' { $claude = Get-Version 'claude' }
            '@google/gemini-cli'        { $gemini = Get-Version 'gemini' }
          }
        } catch {}
      }
    }
    $codexInstalled = [bool]$codex; $claudeInstalled = [bool]$claude; $geminiInstalled = [bool]$gemini
  }

  # Три ЯВНЫЕ строки: видно статус каждого CLI. Отсутствие ОДНОГО — не блокер
  # (правило «достаточно любого»); блокер только если НЕТ НИ ОДНОГО.
  $noneAI = (-not $codexInstalled) -and (-not $claudeInstalled) -and (-not $geminiInstalled) -and (-not $codexOutside)
  if ($codexInstalled) { Add-Result $CAT2 'Codex' 'READY' "$codex" 'Стоит' }
  elseif ($codexOutside) { Add-Result $CAT2 'Codex' 'WARN' (Get-VersionAt $codexOutside) 'СТОИТ, но не виден в PATH — закрой окно и открой заново' $codexOutside }
  elseif ($aiErrors -match 'Codex') { Add-Result $CAT2 'Codex' 'ERROR' '-' 'Проверить вручную' (($aiErrors | Where-Object {$_ -match 'Codex'}) -join '; ') }
  elseif ($noneAI) { Add-Result $CAT2 'Codex' 'MISSING' '-' 'Нет ни одного ИИ-CLI — поставить Codex CLI (это НЕ приложение ChatGPT)' }
  else { Add-Result $CAT2 'Codex' 'ABSENT' '-' 'CLI не установлен (приложение ChatGPT — это не он; не требуется, есть другой ИИ-CLI)' }

  if ($claudeInstalled) { Add-Result $CAT2 'Claude Code' 'READY' "$claude" 'Стоит' }
  elseif ($aiErrors -match 'Claude') { Add-Result $CAT2 'Claude Code' 'ERROR' '-' 'Проверить вручную' (($aiErrors | Where-Object {$_ -match 'Claude'}) -join '; ') }
  elseif ($noneAI) { Add-Result $CAT2 'Claude Code' 'MISSING' '-' 'Нет ни одного ИИ-CLI — установить: npm i -g @anthropic-ai/claude-code' }
  else { Add-Result $CAT2 'Claude Code' 'ABSENT' '-' 'Не установлен (не требуется — есть другой ИИ-CLI)' }

  # Gemini CLI — бесплатный тир 60 запросов/мин, 1000/день (Gemini 2.5 Pro, окно 1M).
  # Вариант для ученика без карты и подписки.
  if ($geminiInstalled) { Add-Result $CAT2 'Gemini CLI' 'READY' "$gemini" 'Стоит' }
  elseif ($aiErrors -match 'Gemini') { Add-Result $CAT2 'Gemini CLI' 'ERROR' '-' 'Проверить вручную' (($aiErrors | Where-Object {$_ -match 'Gemini'}) -join '; ') }
  elseif ($noneAI) { Add-Result $CAT2 'Gemini CLI' 'MISSING' '-' 'Нет ни одного ИИ-CLI — установить: npm i -g @google/gemini-cli' }
  else { Add-Result $CAT2 'Gemini CLI' 'ABSENT' '-' 'Не установлен (не требуется — есть другой ИИ-CLI)' }
} catch { Add-Result $CAT2 'ИИ-CLI' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message }

# Авторизация ИИ — главный реальный блокер: установлен != залогинен.
function Test-CodexLogin {
  if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { return $null }
  try { $run = Invoke-CheckedCommand (Get-Command codex).Source @('login','status')
        if ($run.Text -match '(?i)not logged in|logged out|no credentials') { return $false }
        if ($run.ExitCode -eq 0) { return $true } } catch {}
  $h = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
  return (Test-Path (Join-Path $h 'auth.json'))
}
function Test-ClaudeLogin {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { return $null }
  if ($env:ANTHROPIC_API_KEY) { return $true }
  $cred = Join-Path $env:USERPROFILE '.claude\.credentials.json'
  return ((Test-Path $cred) -and (Get-Item $cred).Length -gt 10)
}
# Gemini: либо API-ключ в переменной окружения, либо OAuth-вход через Google-аккаунт
# (gemini CLI кладёт токен в ~\.gemini\oauth_creds.json).
function Test-GeminiLogin {
  if (-not (Get-Command gemini -ErrorAction SilentlyContinue)) { return $null }
  if ($env:GEMINI_API_KEY -or $env:GOOGLE_API_KEY) { return $true }
  $cred = Join-Path $env:USERPROFILE '.gemini\oauth_creds.json'
  return ((Test-Path $cred) -and (Get-Item $cred).Length -gt 10)
}
try {
  Write-Step 'Авторизация ИИ (вход в подписку/ключ)'
  $logged = @(); $need = @()
  if ($codexInstalled) { $c = Test-CodexLogin; if ($c -eq $true) { $logged += 'Codex' } elseif ($c -eq $false) { $need += 'Codex → команда: codex login' } }
  if ($claudeInstalled) { $c = Test-ClaudeLogin; if ($c -eq $true) { $logged += 'Claude Code' } elseif ($c -eq $false) { $need += 'Claude Code → запусти claude, затем /login' } }
  if ($geminiInstalled) { $c = Test-GeminiLogin; if ($c -eq $true) { $logged += 'Gemini' } elseif ($c -eq $false) { $need += 'Gemini → запусти gemini и войди Google-аккаунтом' } }
  if ($logged.Count -gt 0 -and $need.Count -eq 0) { Add-Result $CAT2 'Авторизация ИИ' 'READY' ($logged -join '; ') 'Вход выполнен' }
  # Частичный вход — НЕ блокер (работать есть на чём), но и не зелёный: иначе
  # «Codex ГОТОВ» сверху + недоступный пункт в меню «В работу» = выглядит как баг.
  elseif ($logged.Count -gt 0) { Add-Result $CAT2 'Авторизация ИИ' 'WARN' ($logged -join '; ') ('Часть без входа: ' + ($need -join '; ')) }
  elseif ($need.Count -gt 0) { Add-Result $CAT2 'Авторизация ИИ' 'LOGIN' '-' 'НУЖЕН ВХОД' ($need -join '; ') }
  else { Add-Result $CAT2 'Авторизация ИИ' 'MISSING' '-' 'Сначала поставьте ИИ-CLI' }
} catch { Add-Result $CAT2 'Авторизация ИИ' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message }

# ==== БЛОК 2.5. ДЕСКТОП-ПРИЛОЖЕНИЯ ========================================
# Claude Desktop / ChatGPT Desktop ставятся как MSIX/Store-пакеты (WindowsApps),
# в классическом реестре Uninstall их НЕТ — надёжно детектит только Get-AppxPackage.
# Отсутствие — не блокер (для кодинга главное CLI выше).
$CATD = 'Десктоп-приложения'
try {
  Write-Step 'Claude Desktop'
  $cd = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue
  if ($cd) { Add-Result $CATD 'Claude Desktop' 'READY' "$($cd.Version)" 'установлен' }
  else { Add-Result $CATD 'Claude Desktop' 'ABSENT' '-' 'не установлен (не критично — есть CLI)' }
} catch { Add-Result $CATD 'Claude Desktop' 'WARN' '-' 'не удалось проверить' $_.Exception.Message }
try {
  Write-Step 'ChatGPT Desktop'
  # ВАЖНО: официальное Windows-приложение ChatGPT упаковано как Appx 'OpenAI.Codex'
  # (DisplayName='ChatGPT', exe app\ChatGPT.exe — Chat+Work+Codex в одном). Ищем по нему,
  # НЕ по имени 'ChatGPT' (такого пакета нет) и НЕ исключая 'Codex'.
  $gpt = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
  if ($gpt) { Add-Result $CATD 'ChatGPT Desktop' 'READY' "$($gpt.Version)" 'установлен — это ПРИЛОЖЕНИЕ, а не codex CLI (для терминала нужен отдельный codex)' }
  else { Add-Result $CATD 'ChatGPT Desktop' 'ABSENT' '-' 'не установлен (не критично)' }
} catch { Add-Result $CATD 'ChatGPT Desktop' 'WARN' '-' 'не удалось проверить' $_.Exception.Message }
# Gemini: официального ДЕСКТОП-приложения под Windows НЕТ (апрель 2026). То, что
# Google выпустил для Windows — «Google app for desktop», Alt+Space лаунчер поиска,
# а не чат-клиент Gemini. Нативное приложение есть только под macOS.
Add-Result $CATD 'Gemini Desktop' 'N/A' '-' 'под Windows приложения нет — веб gemini.google.com или CLI'

# ==== БЛОК 3. СЕТЬ / ДОСТУП К ИИ ==========================================
# Проверяем НЕ «стоит ли VPN», а реально ли открываются AI-эндпоинты.
# Рос-ресурсы намеренно идут напрямую (сплит) — их тут НЕ проверяем.
$CAT3 = 'Сеть / доступ к ИИ'
try {
  Write-Step 'Внешний IP и гео'
  $exit = Get-ExitInfo
  if ($ForceVpnOff) { $exit = [pscustomobject]@{ ip = '(тест: нет VPN)'; country = 'RU'; org = 'ForceVpnOff' } }  # симуляция «нет VPN» в одной точке
  if (Set-ExitState $exit) {
    if ($exit.country -eq 'RU') { Add-Result $CAT3 'Внешний IP' 'WARN' "$($exit.ip) · $($exit.country)" 'РФ-IP — ИИ может резать, нужен VPN/обход' "$($exit.org)" }
    else { Add-Result $CAT3 'Внешний IP' 'READY' "$($exit.ip) · $($exit.country)" 'выход не через РФ' "$($exit.org)" }
  } else { Add-Result $CAT3 'Внешний IP' 'WARN' '-' 'Не определить (нет сети?)' }
} catch { Add-Result $CAT3 'Внешний IP' 'WARN' '-' 'Не определить' $_.Exception.Message }

$AIEndpoints = @(
  @{n='Claude (Anthropic)';     u='https://api.anthropic.com'; key=$true},
  @{n='ChatGPT/Codex (OpenAI)'; u='https://api.openai.com';    key=$true},
  @{n='Gemini (Google)';        u='https://generativelanguage.googleapis.com'; key=$true},
  @{n='ChatGPT web';            u='https://chatgpt.com';       key=$false},
  @{n='Cursor';                 u='https://api2.cursor.sh';    key=$false},
  @{n='GitHub (Copilot)';       u='https://github.com';        key=$false}
)
foreach ($e in $AIEndpoints) {
  try {
    Write-Step "Доступ: $($e.n)"
    if (Test-Https $e.u) { Add-Result $CAT3 $e.n 'READY' '-' 'доступен' }
    elseif ($e.key)      { Add-Result $CAT3 $e.n 'BLOCKED' '-' 'НЕДОСТУПЕН — нужен VPN/обход' }
    else                 { Add-Result $CAT3 $e.n 'WARN' '-' 'недоступен (не критично)' }
  } catch { Add-Result $CAT3 $e.n 'WARN' '-' 'ошибка проверки' $_.Exception.Message }
}

# ==== ЖИВОЙ ТЕСТ ИИ (опц.) — реальный мини-запрос ========================
# ЖЁСТКИЙ ГЕЙТ: только под VPN (выход ≠ РФ, положительно известно). Запрос с
# РФ-IP = риск бана аккаунта за регион → под РФ/неизвестно НЕ шлём вообще.
function Invoke-AiProbe([scriptblock]$cmd,[int]$sec=45) {
  $probe = Join-Path $env:TEMP ('ai_probe_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Path $probe -Force | Out-Null
  try {
    $j = Start-Job -ScriptBlock { param($dir,$sb) Set-Location $dir; & ([scriptblock]::Create($sb)) 2>&1 } -ArgumentList $probe,$cmd.ToString()
    if (Wait-Job $j -Timeout $sec) { $out = (Receive-Job $j | Out-String).Trim(); $to = $false } else { Stop-Job $j; $out = ''; $to = $true }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Text = $out; Timeout = $to }
  } finally { Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue }
}
$errRe = '(?i)not logged in|logged out|no credentials|401|403|unauthor|forbidden|rate.?limit|quota|not inside a trusted'

$doLive = [bool]$LiveTest
if (-not $doLive -and $InstallMissing -and -not $ReportOnly -and -not ([Console]::IsInputRedirected)) {
  $ans = Read-Host '  Сделать живой тест ИИ (реальный мини-запрос, потратит немного квоты)? [y/N]'
  if ($ans -match '^(y|yes|д|да)$') { $doLive = $true }
}
if ($doLive) {
  $vpnOk = $script:ExitCountry -and $script:ExitCountry -ne 'RU'
  if (-not $vpnOk) {
    Add-Result $CAT2 'Живой тест ИИ' 'WARN' '-' 'пропущен — нет VPN (не рискуем баном)'
  } else {
    $anthReach = $Results | Where-Object { $_.Category -eq $CAT3 -and $_.Component -match 'Anthropic' -and $_.Status -eq 'READY' }
    $oaiReach  = $Results | Where-Object { $_.Category -eq $CAT3 -and $_.Component -match 'OpenAI'   -and $_.Status -eq 'READY' }
    if ($claudeInstalled) {
      if ((Test-ClaudeLogin) -eq $true -and $anthReach) {
        Write-Step 'Живой тест: Claude'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-AiProbe { claude -p "Ответь ровно одним словом: OK" } 45
        $sw.Stop(); $t = [math]::Round($sw.Elapsed.TotalSeconds,1)
        if ($r.Timeout) { Add-Result $CAT2 'Claude live-тест' 'BLOCKED' '-' 'таймаут 45s' }
        elseif ($r.Text -match $errRe) { Add-Result $CAT2 'Claude live-тест' 'BLOCKED' '-' 'ошибка/лимит' $r.Text }
        elseif ($r.Text) { Add-Result $CAT2 'Claude live-тест' 'READY' "ответ ${t}s" 'ИИ реально отвечает' }
        else { Add-Result $CAT2 'Claude live-тест' 'BLOCKED' '-' 'пустой ответ' }
      } else { Add-Result $CAT2 'Claude live-тест' 'WARN' '-' 'пропущен (нет логина/эндпоинт закрыт)' }
    }
    if ($codexInstalled) {
      if ((Test-CodexLogin) -eq $true -and $oaiReach) {
        Write-Step 'Живой тест: Codex'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-AiProbe { '' | codex exec --skip-git-repo-check "reply with just: OK" } 45
        $sw.Stop(); $t = [math]::Round($sw.Elapsed.TotalSeconds,1)
        if ($r.Timeout) { Add-Result $CAT2 'Codex live-тест' 'BLOCKED' '-' 'таймаут 45s' }
        elseif ($r.Text -match $errRe) { Add-Result $CAT2 'Codex live-тест' 'BLOCKED' '-' 'ошибка/лимит' $r.Text }
        elseif ($r.Text) { Add-Result $CAT2 'Codex live-тест' 'READY' "ответ ${t}s" 'ИИ реально отвечает' }
        else { Add-Result $CAT2 'Codex live-тест' 'BLOCKED' '-' 'пустой ответ' }
      } else { Add-Result $CAT2 'Codex live-тест' 'WARN' '-' 'пропущен (нет логина/эндпоинт закрыт)' }
    }
    if ($geminiInstalled) {
      $gemReach = $Results | Where-Object { $_.Category -eq $CAT3 -and $_.Component -match 'Gemini' -and $_.Status -eq 'READY' }
      if ((Test-GeminiLogin) -eq $true -and $gemReach) {
        Write-Step 'Живой тест: Gemini'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-AiProbe { gemini -p "Ответь ровно одним словом: OK" } 45
        $sw.Stop(); $t = [math]::Round($sw.Elapsed.TotalSeconds,1)
        if ($r.Timeout) { Add-Result $CAT2 'Gemini live-тест' 'BLOCKED' '-' 'таймаут 45s' }
        elseif ($r.Text -match $errRe) { Add-Result $CAT2 'Gemini live-тест' 'BLOCKED' '-' 'ошибка/лимит' $r.Text }
        elseif ($r.Text) { Add-Result $CAT2 'Gemini live-тест' 'READY' "ответ ${t}s" 'ИИ реально отвечает' }
        else { Add-Result $CAT2 'Gemini live-тест' 'BLOCKED' '-' 'пустой ответ' }
      } else { Add-Result $CAT2 'Gemini live-тест' 'WARN' '-' 'пропущен (нет логина/эндпоинт закрыт)' }
    }
  }
}

# ==== ВЫВОД ================================================================
function Format-StatusLine($r) {
  switch ($r.Status) {
    'READY'    { $icon='[OK] '; $col='Green';    $label='ГОТОВ  ' }
    'REPAIRED' { $icon='[+]  '; $col='Green';    $label='ПОЧИНЕН' }
    'UPDATE'   { $icon='[^]  '; $col='Yellow';   $label='АПДЕЙТ ' }
    'LOGIN'    { $icon='[!]  '; $col='Yellow';   $label='ВОЙТИ  ' }
    'WARN'     { $icon='[~]  '; $col='Yellow';   $label='ВНИМАН.' }
    'ABSENT'   { $icon='[-]  '; $col='DarkGray'; $label='нет    ' }
    'MISSING'  { $icon='[X]  '; $col='Red';      $label='НЕТ    ' }
    'BLOCKED'  { $icon='[X]  '; $col='Red';      $label='БЛОК   ' }
    'ERROR'    { $icon='[!!] '; $col='Red';      $label='ОШИБКА ' }
    'N/A'      { $icon='[-]  '; $col='DarkGray'; $label='—      ' }
    default    { $icon='[?]  '; $col='Gray';     $label=$r.Status }
  }
  # Вся строка одним Write-Host — чтобы Start-Transcript писал её в файл ровно
  # (цепочка -NoNewline разъезжается в транскрипте по строкам).
  $line = "    $icon $label  " + $r.Component.PadRight(22) + ' ' + ($r.Version).PadRight(24) + ' ' + $r.Action
  Write-Host $line -ForegroundColor $col
  if ($r.Details -and $r.Details -ne '-') { Write-Host "           - $($r.Details)" -ForegroundColor DarkGray }
}

Write-Host ''
foreach ($cat in @($CAT0,$CAT1,$CAT2,$CATD,$CAT3)) {
  Write-Host "  [ $cat ]" -ForegroundColor Cyan
  $Results | Where-Object { $_.Category -eq $cat } | ForEach-Object { Format-StatusLine $_ }
  Write-Host ''
}

# JSON-отчёт
try { $Results | ConvertTo-Json | Set-Content -LiteralPath $JsonPath -Encoding utf8 } catch {}

# Итоговый вердикт — КРУПНЫМ блоком
function Write-BigBox([string]$title,[string]$subtitle,[string]$color) {
  $lines = @($title,$subtitle) | Where-Object { $_ }
  $maxlen = ($lines | Measure-Object -Property Length -Maximum).Maximum
  $w = [math]::Max(46, $maxlen + 8)
  $center = { param($t) $p = $w - $t.Length; $lft = [math]::Floor($p/2); (' ' * $lft) + $t + (' ' * ($p - $lft)) }
  Write-Host ''
  Write-Host ('  ╔' + ('═' * $w) + '╗') -ForegroundColor $color
  Write-Host ('  ║' + (' ' * $w) + '║') -ForegroundColor $color
  Write-Host ('  ║' + (& $center $title) + '║') -ForegroundColor $color
  if ($subtitle) { Write-Host ('  ║' + (& $center $subtitle) + '║') -ForegroundColor $color }
  Write-Host ('  ║' + (' ' * $w) + '║') -ForegroundColor $color
  Write-Host ('  ╚' + ('═' * $w) + '╝') -ForegroundColor $color
  Write-Host ''
}
# КРУПНАЯ плашка VPN — отдельно и заметно: активен ли туннель + куда выход
if ($script:ExitCountry -and $script:ExitCountry -ne 'RU') {
  Write-BigBox 'V P N :   А К Т И В Е Н' "выход $($script:ExitCountry) · $($script:ExitIp)" 'Green'
} elseif ($script:ExitCountry -eq 'RU') {
  Write-BigBox 'V P N :   В Ы К Л  (РФ-выход)' 'прямой РФ-IP — ИИ может резать, включи VPN' 'Yellow'
} else {
  Write-BigBox 'V P N :   не определён' 'нет данных о внешнем IP (сеть?)' 'DarkGray'
}

$blockers = $Results | Where-Object { $_.Status -in @('MISSING','ERROR','LOGIN','BLOCKED') }
if (-not $blockers) {
  Write-BigBox 'С Р Е Д А   Г О Т О В А' 'можно работать' 'Green'
} else {
  Write-BigBox 'С Р Е Д А   Н Е   Г О Т О В А' 'закрой пункты ниже' 'Red'
  foreach ($b in $blockers) { Write-Host "     - $($b.Component): $($b.Action) $(if($b.Details -and $b.Details -ne '-'){"($($b.Details))"})" -ForegroundColor Yellow }
}
# ---- Регион закрыт: что делать ------------------------------------------
# В боевой версии кита здесь стоит мастер подключения туннеля: ставит клиент,
# ведёт за ключом доступа, перепроверяет выход и обновляет состояние. В публичной
# версии его нет — он завязан на частный сервис выдачи доступа, который к самому
# инструменту отношения не имеет. Остаётся диагностика выше: она называет
# поимённо, какие эндпоинты недоступны с этой машины, а это и есть та часть,
# которая одинаково работает и за корпоративным прокси, и в гостиничном Wi-Fi.
if ((-not $script:ExitCountry -or $script:ExitCountry -eq 'RU') -and -not ([Console]::IsInputRedirected)) {
  $blockedEp = @($Results | Where-Object { $_.Category -eq $CAT3 -and $_.Status -eq 'BLOCKED' })
  if ($blockedEp.Count -gt 0) {
    Write-Host ''
    Write-Host '  ── ДОСТУП К ИИ ЗАКРЫТ ИЗ ЭТОЙ СЕТИ ────────────' -ForegroundColor Yellow
    foreach ($b in $blockedEp) { Write-Host "   • $($b.Component) — не отвечает" -ForegroundColor Yellow }
    Write-Host '   Дело не в установке: инструменты на месте, до серверов ИИ не доходит сеть.' -ForegroundColor DarkGray
    Write-Host '   Меняй сеть или маршрут до этих адресов и запусти проверку заново.' -ForegroundColor DarkGray
    Write-Host '   ВХОД В АККАУНТ до этого лучше не делать: провайдеры ИИ ограничивают' -ForegroundColor DarkGray
    Write-Host '   доступ по региону, и попытка входа из закрытого региона стоит аккаунта.' -ForegroundColor DarkGray
  }
}

# ---- Обновление Windows (старая версия) — предложить официальный помощник -
if ($script:WinOld -and $InstallMissing -and -not $ReportOnly -and -not ([Console]::IsInputRedirected)) {
  Write-Host ''
  Write-Host '  ── ОБНОВЛЕНИЕ WINDOWS ─────────────────────────' -ForegroundColor Yellow
  Write-Host '  У тебя старая Windows — часть инструментов и ИИ-приложений может не работать.' -ForegroundColor Yellow
  Write-Host '  Рекомендуем обновить Windows — это БЕСПЛАТНО.' -ForegroundColor Yellow
  if ((Read-Host '   Запустить официальный помощник обновления Windows? [Y/n]') -notmatch '^(n|no|нет)$') {
    try {
      $wexe = Join-Path $env:TEMP 'Windows11InstallationAssistant.exe'
      Write-Host '   Качаю официальный помощник Microsoft...' -ForegroundColor DarkGray
      Invoke-WebRequest 'https://go.microsoft.com/fwlink/?linkid=2171764' -OutFile $wexe -UseBasicParsing -TimeoutSec 120
      Start-Process $wexe
      Write-Host '   Помощник запущен — он сам проверит совместимость (TPM/CPU/место) и обновит.' -ForegroundColor Green
    } catch { Write-Host "   Не удалось скачать помощник: $($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host '   Обнови вручную: Параметры → Центр обновления Windows.' -ForegroundColor DarkGray }
  }
}

# ---- Отчёт куратору (ВЫКЛЮЧЕН, пока не задан свой -ReportUrl) -------------
# Зачем это вообще есть: на живом потоке куратор должен видеть, у кого среда не
# поднялась, ДО того как человек сдастся и уйдёт молча. Отправляется одна строка
# вердикта и список блокеров — ни путей, ни имён файлов, ни внешнего IP.
# Стабильный machine-id (создаётся раз, хранится локально). Личность к нему
# привязывает бот — ученику НЕ надо вводить/вставлять ник.
# Без -ReportUrl не создаётся даже machine-id: нет приёмника — нет и следа.
function Get-KitMid {
  $f = Join-Path $env:APPDATA 'stereo_kit_id.txt'
  if (Test-Path $f) { $m = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue).Trim(); if ($m) { return $m } }
  $m = 'MID-' + [guid]::NewGuid().ToString('N').Substring(0,12)
  try { Set-Content -LiteralPath $f -Value $m -Encoding utf8 } catch {}
  return $m
}
function Test-KitPaired([string]$mid) {
  if (-not $PairUrl) { return $null }
  try { $r = Invoke-RestMethod -Uri "$PairUrl`?mid=$mid" -TimeoutSec 8; return $r } catch { return $null }
}
$doReport = $ReportUrl -and -not $NoReport
if ($doReport) {
  try {
    $mid = Get-KitMid
    $pair = Test-KitPaired $mid
    # Ещё не привязан → предложить один клик в боте (без ввода ника)
    if ($PairBot -and -not ($pair -and $pair.paired) -and -not ([Console]::IsInputRedirected)) {
      Write-Host ''
      Write-Host '  ── ПРИВЯЗКА К TELEGRAM (для куратора) ─────────' -ForegroundColor Cyan
      Write-Host '  Чтобы куратор видел твой прогресс — привяжи установщик к Telegram.' -ForegroundColor DarkGray
      Write-Host '  Ничего вводить не нужно: открой бота, нажми СТАРТ, вернись сюда.' -ForegroundColor DarkGray
      if ((Read-Host '   Открыть бота для привязки? [Y/n]') -notmatch '^(n|no|нет)$') {
        Start-Process "$PairBot`?start=kit_$mid"
        Write-Host '   Нажми в боте СТАРТ (кнопку внизу), затем вернись сюда.' -ForegroundColor Yellow
        [void](Read-Host '   Нажал СТАРТ в боте? Enter — проверю привязку')
        for ($i=0; $i -lt 5 -and -not ($pair -and $pair.paired); $i++) { Start-Sleep -Seconds 2; $pair = Test-KitPaired $mid }
      }
      if ($pair -and $pair.paired) { Write-Host "   Привязано: $($pair.name) $(if($pair.username){"(@$($pair.username))"})" -ForegroundColor Green }
      else { Write-Host '   Пока не привязано — отчёт уйдёт обезличенным (можно привязать позже).' -ForegroundColor DarkGray }
    }
    $verdictTxt = if ($blockers) { 'НЕ ГОТОВА' } else { 'ГОТОВА' }
    $vpnTxt = if ($script:ExitCountry -and $script:ExitCountry -ne 'RU') { "выход $($script:ExitCountry)" } elseif ($script:ExitCountry -eq 'RU') { 'РФ-выход' } else { 'неизвестно' }
    $problems = @()
    $problems += @($blockers | ForEach-Object {
      $p = "$($_.Component): $($_.Action)"
      if ($_.Details -and $_.Details -ne '-') { $p += " [$($_.Details)]" }
      $p
    })
    # WARN-строки — НЕ блокеры, но куратор должен их видеть: частичный вход,
    # РФ-выход, мало места. Раньше они терялись — отчёт «ГОТОВА» без единого намёка.
    $warnings = @($Results | Where-Object { $_.Status -eq 'WARN' } | ForEach-Object {
      $w = "$($_.Component): $($_.Action)"
      if ($_.Details -and $_.Details -ne '-') { $w += " [$($_.Details)]" }
      $w
    })
    # Режим прогона: dry-run и неудачный ремонт давали ОДИНАКОВЫЙ отчёт «НЕ ГОТОВА».
    $modeTxt = if ($ReportOnly) { 'report-only' } elseif ($InstallMissing) { 'repair' } else { 'check' }
    # Права: без админа winget-установки молча не проходят (из разбора реального
    # прогона у ученика: «начало ставить и бросило» = запуск был без админа).
    $payload = @{ mid = "$mid"; host = "$env:COMPUTERNAME"; os = 'windows'; verdict = $verdictTxt; vpn = $vpnTxt;
                  mode = $modeTxt; admin = [bool]$script:IsAdmin; problems = $problems; warnings = $warnings } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
    Write-Host "  Отчёт куратору отправлен." -ForegroundColor DarkGray
  } catch { }  # молча — отчёт не должен мешать ученику
}

Write-Host ''
Write-Host "  Отчёт сохранён:" -ForegroundColor DarkGray
Write-Host "     лог : $LogPath" -ForegroundColor DarkGray
Write-Host "     json: $JsonPath" -ForegroundColor DarkGray
Write-Host ''

# ==== ПАМЯТЬ ПРОЕКТА ======================================================
# Проверка только что выяснила про машину всё, что агент в первой сессии
# выясняет наугад: ОС и билд, что установлено и каких версий, в какой ИИ выполнен
# вход, какие эндпоинты закрыты. Выбросить это в лог — значит заставить агента
# гадать заново. Поэтому раскладываем в память проекта, которую он читает при старте.
#
# ПРАВИЛА (нарушать нельзя, они же записаны в самом CLAUDE.md):
#  - НИЧЕГО не перезаписываем. Существующий файл — правда человека, а не наша.
#    Свежий infra_status при повторном прогоне ложится рядом как infra_status.new.md.
#  - Внешний IP НЕ пишем: файл живёт у человека и однажды попадёт в чей-нибудь git.
#    Достаточно «доступен / недоступен».
#  - Нет шаблонов (скопировали на флешку только windows\) — не падаем, а говорим
#    одной строкой и идём дальше. Каждый пункт независим.
function Get-MemRow([string]$Component) {
  return ($Results | Where-Object { $_.Component -eq $Component } | Select-Object -First 1)
}
function Get-MemVersion([string]$Component) {
  $r = Get-MemRow $Component
  if ($r -and $r.Version -and $r.Version -ne '-') { return $r.Version }
  return 'not installed'
}
function Get-MemReach([string]$Component) {
  $r = Get-MemRow $Component
  if (-not $r) { return 'not checked' }
  if ($r.Status -eq 'READY') { return 'yes' }
  return 'no'
}
function Get-MemLogin($installed, [scriptblock]$probe) {
  if (-not $installed) { return '—' }
  try { if ((& $probe) -eq $true) { return 'yes' } } catch {}
  return 'no'
}
function Initialize-ProjectMemory([string]$ProjectDir) {
  # templates\ ищем сначала рядом с ядром (раздача одной платформы на флешке),
  # потом в корне репозитория: <repo>\windows\core\ -> два уровня вверх.
  $tpl = @(
    (Join-Path $PSScriptRoot 'templates'),
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'templates')
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $tpl) {
    Write-Host '  Память проекта: шаблоны (templates\) не найдены — пропускаю.' -ForegroundColor DarkGray
    return
  }
  if (-not $Lang) {
    $Lang = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' }
  }
  $memDir = Join-Path $ProjectDir 'memory'
  foreach ($d in @($memDir, (Join-Path $ProjectDir 'scratch'), (Join-Path $ProjectDir 'backup'))) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
  $created = @(); $kept = @()

  $claudeMd = if ($Lang -eq 'ru') { 'CLAUDE.ru.md' } else { 'CLAUDE.md' }
  $plan = @(
    @{ src = (Join-Path $tpl $claudeMd);                    dst = (Join-Path $ProjectDir 'CLAUDE.md') },
    @{ src = (Join-Path $tpl 'memory\README.md');           dst = (Join-Path $memDir 'README.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_status.md');   dst = (Join-Path $memDir 'PROJECT_status.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_backlog.md');  dst = (Join-Path $memDir 'PROJECT_backlog.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_history.md');  dst = (Join-Path $memDir 'PROJECT_history.md') }
  )
  foreach ($p in $plan) {
    if (-not (Test-Path -LiteralPath $p.src)) { continue }
    $leaf = Split-Path $p.dst -Leaf
    if (Test-Path -LiteralPath $p.dst) { $kept += $leaf; continue }
    Copy-Item -LiteralPath $p.src -Destination $p.dst -Force
    $created += $leaf
  }

  # infra_status.md — не шаблон, а ФАКТЫ только что прошедшей проверки.
  $tplInfra = Join-Path $tpl 'memory\infra_status.template.md'
  if (Test-Path -LiteralPath $tplInfra) {
    $txt = [System.IO.File]::ReadAllText($tplInfra)
    $osRow = Get-MemRow 'Windows'
    $map = [ordered]@{
      '{{DATE}}'             = (Get-Date -Format 'yyyy-MM-dd HH:mm')
      '{{OS_NAME}}'          = 'Windows'
      '{{OS_BUILD}}'         = $(if ($osRow) { [string]$osRow.Version } else { 'unknown' })
      '{{HOSTNAME}}'         = "$env:COMPUTERNAME"
      # Единица из русского вывода — в англоязычном файле памяти читается мусором.
      '{{DISK_FREE}}'        = ((Get-MemVersion "Диск $env:SystemDrive") -replace 'ГБ','GB')
      '{{PROJECT_DIR}}'      = $ProjectDir
      '{{REPORT_DIR}}'       = $ReportDir
      '{{GIT_VERSION}}'      = (Get-MemVersion 'Git')
      '{{NODE_VERSION}}'     = (Get-MemVersion 'Node.js LTS')
      '{{PKG_MANAGER}}'      = 'WinGet'
      '{{PKG_VERSION}}'      = (Get-MemVersion 'WinGet')
      '{{SHELL_NAME}}'       = 'PowerShell'
      '{{SHELL_VERSION}}'    = "$($PSVersionTable.PSVersion)"
      '{{CLAUDE_INSTALLED}}' = (Get-MemVersion 'Claude Code')
      '{{CODEX_INSTALLED}}'  = (Get-MemVersion 'Codex')
      '{{GEMINI_INSTALLED}}' = (Get-MemVersion 'Gemini CLI')
      '{{CLAUDE_LOGGED_IN}}' = (Get-MemLogin $claudeInstalled { Test-ClaudeLogin })
      '{{CODEX_LOGGED_IN}}'  = (Get-MemLogin $codexInstalled  { Test-CodexLogin })
      '{{GEMINI_LOGGED_IN}}' = (Get-MemLogin $geminiInstalled { Test-GeminiLogin })
      '{{EP_ANTHROPIC}}'     = (Get-MemReach 'Claude (Anthropic)')
      '{{EP_OPENAI}}'        = (Get-MemReach 'ChatGPT/Codex (OpenAI)')
      '{{EP_GOOGLE}}'        = (Get-MemReach 'Gemini (Google)')
    }
    foreach ($k in $map.Keys) { $txt = $txt.Replace($k, [string]$map[$k]) }
    $enc = New-Object System.Text.UTF8Encoding($false)
    $infra = Join-Path $memDir 'infra_status.md'
    if (Test-Path -LiteralPath $infra) {
      [System.IO.File]::WriteAllText((Join-Path $memDir 'infra_status.new.md'), $txt, $enc)
      $kept += 'infra_status.md'; $created += 'infra_status.new.md (среда могла измениться — сравни и перенеси руками)'
    } else {
      [System.IO.File]::WriteAllText($infra, $txt, $enc)
      $created += 'infra_status.md'
    }
  }

  Write-Host ''
  Write-Host '  ── ПАМЯТЬ ПРОЕКТА ─────────────────────────────' -ForegroundColor Cyan
  if ($created.Count -gt 0) { Write-Host ('   создано: ' + ($created -join ', ')) -ForegroundColor Green }
  if ($kept.Count -gt 0)    { Write-Host ('   не тронуто (уже было): ' + ($kept -join ', ')) -ForegroundColor DarkGray }
  Write-Host '   Агент прочитает CLAUDE.md и memory\infra_status.md при старте —' -ForegroundColor DarkGray
  Write-Host '   и не будет гадать, что у тебя установлено.' -ForegroundColor DarkGray
}

# ---- В РАБОТУ: запустить агента прямо тут, без перезапуска ---------------
if (-not ([Console]::IsInputRedirected)) {
  # Показываем ВСЕ установленные CLI, даже без входа. Раньше пункт без логина молча
  # исчезал: сверху «Codex ГОТОВ», а нажатие его номера не делало НИЧЕГО — ученик
  # читал это как поломку. Номера считаем динамически, дырок в нумерации нет.
  $agents = @()
  if ($claudeInstalled) { $agents += [pscustomobject]@{ Name='Claude Code'; Cmd='claude'; Ready=((Test-ClaudeLogin) -eq $true); Fix='запусти claude, затем /login' } }
  if ($codexInstalled)  { $agents += [pscustomobject]@{ Name='Codex';       Cmd='codex';  Ready=((Test-CodexLogin)  -eq $true); Fix='выполни: codex login' } }
  if ($geminiInstalled) { $agents += [pscustomobject]@{ Name='Gemini';      Cmd='gemini'; Ready=((Test-GeminiLogin) -eq $true); Fix='запусти gemini и войди Google-аккаунтом' } }
  if ($agents.Count -gt 0) {
    Write-Host ''
    Write-Host '  ── В РАБОТУ ───────────────────────────────────' -ForegroundColor Cyan
    Write-Host '   Начать кодить прямо сейчас?' -ForegroundColor Yellow
    for ($i = 0; $i -lt $agents.Count; $i++) {
      $a = $agents[$i]; $n = $i + 1
      if ($a.Ready) { Write-Host "   [$n] $($a.Name)" -ForegroundColor Yellow }
      else          { Write-Host "   [$n] $($a.Name) — нужен вход (выберу — войдём)" -ForegroundColor DarkGray }
    }
    Write-Host '   [Enter] выйти' -ForegroundColor DarkGray
    $c = Read-Host '   Выбор'
    $launch = $null
    if ($c) {
      $idx = 0
      if ([int]::TryParse($c, [ref]$idx) -and $idx -ge 1 -and $idx -le $agents.Count) {
        $a = $agents[$idx - 1]
        if ($a.Ready) { $launch = $a.Cmd }
        else {
          # Не отфутболиваем ученика командой — логиним прямо тут.
          # ГЕЙТ VPN: вход с РФ-IP = риск бана аккаунта (то же правило, что у живого теста).
          $vpnOkLogin = $script:ExitCountry -and $script:ExitCountry -ne 'RU'
          if (-not $vpnOkLogin) {
            Write-Host "   $($a.Name) установлен, но вход не выполнен." -ForegroundColor Yellow
            Write-Host '   ВХОДИТЬ СЕЙЧАС ОПАСНО: выход через РФ (или не определён) — рискуешь баном аккаунта.' -ForegroundColor Red
            Write-Host '   Включи VPN и запусти проверку заново.' -ForegroundColor Yellow
          }
          elseif ((Read-Host "   $($a.Name): вход не выполнен. Войти сейчас? [Y/n]") -notmatch '^(n|no|нет)$') {
            if ($a.Cmd -eq 'codex') {
              # `codex login` поднимает локальный сервер на :1455 и открывает браузер,
              # а подсказку со ссылкой печатает в stderr. Из АДМИНСКОГО процесса браузер
              # уходит в чужой сеанс (без кук ученика) -> «ничего не произошло».
              # Поэтому вход уводим в отдельное окно от обычного пользователя.
              Write-Host '   Открываю вход в Codex в отдельном окне...' -ForegroundColor Cyan
              $loginBody = @(
                '@echo off',
                'chcp 65001 >nul',
                'echo ok> "%TEMP%\stereo_agent_launched.flag"',
                'title STEREO AI - Codex login',
                'echo.',
                'echo Sign in to Codex in the browser that opens.',
                'echo If the browser did not open, copy the link below into it manually.',
                'echo.',
                'call codex login',
                'echo.',
                'echo You can close this window now.',
                'pause >nul'
              )
              $okWin = Start-UnelevatedCmd (Join-Path $env:TEMP 'stereo_kit') 'codex-login.cmd' $loginBody
              if (-not $okWin) {
                Write-Host '   Отдельное окно не открылось — пробую прямо здесь.' -ForegroundColor Yellow
                try { & codex login } catch { Write-Host "   Не удалось запустить вход: $($_.Exception.Message)" -ForegroundColor Yellow }
              } else {
                Write-Host '   В открывшемся окне подтверди вход (браузер), затем вернись сюда.' -ForegroundColor DarkGray
                [void](Read-Host '   Нажми Enter, когда вход завершён')
              }
              if ((Test-CodexLogin) -eq $true) { Write-Host '   Вход выполнен.' -ForegroundColor Green; $launch = 'codex' }
              else {
                Write-Host '   Вход пока не завершён.' -ForegroundColor Yellow
                Write-Host '   Если браузер не открылся — в том окне есть ссылка, открой её вручную.' -ForegroundColor DarkGray
                Write-Host '   Запасной вариант для сложных случаев: codex login --device-auth' -ForegroundColor DarkGray
              }
            } else {
              # Claude Code и Gemini спрашивают вход сами при первом запуске —
              # просто запускаем, ученик проходит вход внутри.
              Write-Host "   Запускаю $($a.Name) — пройди вход прямо в нём." -ForegroundColor Cyan
              $launch = $a.Cmd
            }
          }
        }
      } else {
        Write-Host "   Нет такого варианта: «$c». Доступны 1..$($agents.Count), либо Enter — выйти." -ForegroundColor Yellow
      }
    }
    if ($launch) {
      $proj = Join-Path $env:USERPROFILE 'stereo-vibe'
      if (-not (Test-Path $proj)) { New-Item -ItemType Directory -Path $proj -Force | Out-Null }
      if ((Get-Command git -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $proj '.git'))) {
        Push-Location $proj; & git init -q 2>$null; Pop-Location
      }
      # Память агента. Обёрнуто в try: сорваться на записи файлов и не запустить
      # агента — цена несоразмерная, память не настолько важна.
      try { Initialize-ProjectMemory $proj }
      catch { Write-Host "  Память проекта: пропущено ($($_.Exception.Message))" -ForegroundColor DarkGray }
      # Ярлык запуска остаётся в проекте: ученик может перезапустить агента
      # двойным кликом в любой момент — и всегда БЕЗ прав администратора.
      # ASCII-only + пути через %~dp0: cmd.exe парсит батник в OEM-кодировке,
      # кириллица внутри (в т.ч. в пути пользователя) его ломает.
      $shimName = "СТАРТ-$launch.cmd" -replace '[^\w\-\.]', '_'
      $shim = Join-Path $proj $shimName
      $shimLines = @(
        '@echo off',
        'chcp 65001 >nul',
        'cd /d "%~dp0"',
        'echo ok> "%TEMP%\stereo_agent_launched.flag"',
        "title STEREO AI - $launch",
        "call $launch %*",
        'echo.',
        'echo Agent finished. Press any key to close.',
        'pause >nul'
      )
      [System.IO.File]::WriteAllLines($shim, $shimLines, [System.Text.Encoding]::ASCII)

      # Из процесса с админом обычный Start-Process рождает ТАКОГО ЖЕ админского
      # потомка — ИИ-агент унаследовал бы полные права. Проводник работает от
      # обычного пользователя, поэтому запущенное им идёт с его уровнем.
      $flag = Join-Path $env:TEMP 'stereo_agent_launched.flag'
      Remove-Item $flag -Force -ErrorAction SilentlyContinue
      $started = $false
      try {
        Start-Process explorer.exe -ArgumentList "`"$shim`"" -ErrorAction Stop
        for ($t = 0; $t -lt 12 -and -not $started; $t++) {
          Start-Sleep -Milliseconds 700
          if (Test-Path $flag) { $started = $true }
        }
      } catch {}

      Write-Host ''
      if ($started) {
        Remove-Item $flag -Force -ErrorAction SilentlyContinue
        Write-Host "  $launch запущен в ОТДЕЛЬНОМ окне (без прав администратора)." -ForegroundColor Green
        Write-Host "  Проект: $proj" -ForegroundColor DarkGray
        Write-Host "  Перезапустить потом: двойной клик по $shimName в папке проекта." -ForegroundColor DarkGray
      } else {
        # Проводник может быть не запущен / политика запрета — не бросаем ученика.
        Write-Host '  Не удалось открыть отдельное окно — запускаю прямо здесь.' -ForegroundColor Yellow
        if ($script:IsAdmin) { Write-Host '  Учти: агент пойдёт с правами администратора.' -ForegroundColor Yellow }
        Set-Location $proj
        try { Stop-Transcript | Out-Null } catch {}   # TUI не должен писаться в транскрипт
        switch ($launch) { 'claude' { & claude } 'codex' { & codex } 'gemini' { & gemini } }
        exit 0
      }
      Write-Host ''
    }
  }
}

Wait-End
try { Stop-Transcript | Out-Null } catch {}
if ($blockers) { exit 1 } else { exit 0 }
