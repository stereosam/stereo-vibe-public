[CmdletBinding()]
param(
  [switch]$InstallMissing = $true,
  [switch]$ReportOnly,     # только проверка: ничего не ставим и не спрашиваем
  [switch]$NoReport,       # не отправлять обезличенную сводку после проверки
  [string]$PreferredApps,  # пункты меню ИИ через запятую (1,2); пусто = спросить
  [string]$ReportDir,      # куда писать локальный лог и JSON; по умолчанию %LOCALAPPDATA%\STEREO-Vibe-Lite\logs
  [string]$ProjectDir      # завести папку проекта с памятью агента здесь, без вопроса (по умолчанию спрашиваем про ~\stereo-vibe)
)

# ==========================================================================
#  STEREO Vibe Lite — стартовый пакет вайбкодера для Windows.
#
#  Проверяет систему и ставит через winget то, что нужно для вайбкодинга:
#  PowerShell 7, Git, Node.js LTS, Python, Telegram Desktop, ИИ-агенты.
#  Проверяет, открываются ли ИИ-сервисы из этой сети (ничего не настраивает).
#
#  Связь с сервером пакета (адреса — константами ниже):
#   1) при запуске читаем номер свежей версии (version.json, только поле
#      version) и, если он новее, печатаем строку со ссылкой на бота. Ничего
#      не скачиваем и не выполняем;
#   2) обезличенная сводка после проверки (версии программ и статусы, без
#      имени пользователя/компьютера, путей и ключей). Отключается -NoReport.
#  Если WinGet нет или он не работает — чиним: перерегистрация, а с согласия
#  человека — официальные пакеты Microsoft с GitHub (блок WINGET-REPAIR ниже).
#  Лог и JSON-отчёт остаются только на этом компьютере.
#  В конце (с согласия) заводит папку проекта с памятью агента: CLAUDE.md +
#  memory\, где infra_status.md заполнен фактами этой проверки. Без имени
#  компьютера, пользователя и IP — файл живёт в проекте и уходит дальше.
# ==========================================================================

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- Адреса сервера пакета, бот и ссылка на практикум -----------------------
$script:VersionUrl   = 'https://stereosam.ru/vibe-lite/version.json'
$script:SummaryUrl   = 'https://stereosam.ru/vibe-lite/report'
$script:BotUpdateUrl = 'https://t.me/stereo_practicum_bot?start=vibe_update'
$script:PracticumUrl = 'https://stereosam.ru/ai?utm_source=kit_lite&utm_medium=app&utm_campaign=stereovibe'

$script:RunClock = [Diagnostics.Stopwatch]::StartNew()

# Версия пакета живёт в version.txt рядом со скриптом (показывается и уходит в сводку).
$script:PkgVersion = '0.0.0'
try {
  $pv = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.txt') -Raw -ErrorAction Stop).Trim()
  if ($pv -match '^\d+(\.\d+){1,3}$') { $script:PkgVersion = $pv }
} catch {}

# ---- Локальные данные: лог, JSON-отчёт, id установки -----------------------
# Не в папке пакета: в корне распакованного архива должны лежать только
# лаунчер и служебная папка, а сам архив можно скачать и распаковать заново.
$script:DataDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'STEREO-Vibe-Lite' } else { Join-Path $env:TEMP 'STEREO-Vibe-Lite' }
if (-not $ReportDir) { $ReportDir = Join-Path $script:DataDir 'logs' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
  if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
  '' | Out-File -LiteralPath (Join-Path $ReportDir '.wtest') -ErrorAction Stop; Remove-Item -LiteralPath (Join-Path $ReportDir '.wtest') -ErrorAction SilentlyContinue
} catch {
  $ReportDir = Join-Path $env:TEMP 'stereo_vibe_lite_logs'
  if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
}
$LogPath     = Join-Path $ReportDir "log_$stamp.txt"
$JsonPath    = Join-Path $ReportDir "report_$stamp.json"
$SummaryPath = Join-Path $ReportDir "summary_$stamp.json"
try { Start-Transcript -LiteralPath $LogPath -Force | Out-Null } catch {}

# Выключаем «быстрое выделение» (QuickEdit) для этого окна. В обычной консоли клик
# мышью начинает выделение, и Windows ставит программу на паузу, пока не нажмут
# Enter/Esc — внешне это «зависло». Меняем только это окно, не настройки системы.
try {
  if (-not [Console]::IsInputRedirected) {
    Add-Type -Namespace StereoVibe -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@ -ErrorAction Stop
    $hIn = [StereoVibe.ConsoleMode]::GetStdHandle(-10)   # STD_INPUT_HANDLE
    $mode = [uint32]0
    if ([StereoVibe.ConsoleMode]::GetConsoleMode($hIn, [ref]$mode)) {
      # снять ENABLE_QUICK_EDIT_MODE (0x40), поставить ENABLE_EXTENDED_FLAGS (0x80)
      [void][StereoVibe.ConsoleMode]::SetConsoleMode($hIn, (($mode -band [uint32]4294967231) -bor [uint32]0x80))
    }
  }
} catch {}

if ($ReportOnly) { $InstallMissing = $false }

# ---- Интерфейс -----------------------------------------------------------
function Write-Banner {
  Write-Host ''
  Write-Host '  ███████ ████████ ███████ ██████  ███████  ██████'   -ForegroundColor Cyan
  Write-Host '  ██         ██    ██      ██   ██  ██      ██    ██'   -ForegroundColor Cyan
  Write-Host '  ███████    ██    █████   ██████   █████   ██    ██'   -ForegroundColor Cyan
  Write-Host '       ██    ██    ██      ██   ██  ██      ██    ██'   -ForegroundColor Cyan
  Write-Host '  ███████    ██    ███████ ██   ██  ███████  ██████  ·AI' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '  ─────  STEREO Vibe Lite · стартовый пакет вайбкодера  ─────' -ForegroundColor Yellow
  Write-Host "  версия пакета: $($script:PkgVersion)"                        -ForegroundColor DarkGray
  Write-Host ''
  if ($ReportOnly) {
    Write-Host '  Режим: только проверка — ничего не ставлю.' -ForegroundColor DarkGray
  } else {
    Write-Host '  Что сейчас будет:' -ForegroundColor Gray
    Write-Host '   1. Проверю систему: место на диске и версию Windows.' -ForegroundColor Gray
    Write-Host '   2. Проверю инструменты и поставлю недостающие через winget.' -ForegroundColor Gray
    Write-Host '   3. Предложу выбрать ИИ-агента (Codex, Claude Code, Gemini).' -ForegroundColor Gray
    Write-Host '   4. Проверю, открываются ли ИИ-сервисы из твоей сети.' -ForegroundColor Gray
    Write-Host '  Окно не закрывай до надписи «Нажми ENTER». Установка может идти несколько минут.' -ForegroundColor DarkGray
  }
  if (-not $NoReport) {
    Write-Host '  После проверки отправим обезличенную сводку (версии программ, без личных данных) — чтобы улучшать пакет' -ForegroundColor DarkGray
  }
  Write-Host ''
}
function Wait-End {
  try { if ([Console]::IsInputRedirected) { return } } catch {}
  Write-Host '  ─────────────────────────────────────────────' -ForegroundColor DarkGray
  Write-Host '  ►►►   Нажми  ENTER,  чтобы  закрыть  окно   ◄◄◄' -ForegroundColor Magenta
  [void](Read-Host)
}
function Write-Step([string]$Name) { Write-Host "  • Проверяю: $Name..." -ForegroundColor DarkGray }

# Вопрос человеку — крупной рамкой: среди серых служебных строк он иначе теряется.
function Write-AskBox([string[]]$Lines,[string]$Color='Magenta') {
  $maxlen = ($Lines | Measure-Object -Property Length -Maximum).Maximum
  $w = [math]::Max(50, $maxlen + 6)
  $center = { param($t) $p = $w - $t.Length; $l = [math]::Floor($p/2); (' ' * $l) + $t + (' ' * ($p - $l)) }
  Write-Host ''
  Write-Host ('  ╔' + ('═' * $w) + '╗') -ForegroundColor $Color
  Write-Host ('  ║' + (' ' * $w) + '║') -ForegroundColor $Color
  foreach ($ln in $Lines) { Write-Host ('  ║' + (& $center $ln) + '║') -ForegroundColor $Color }
  Write-Host ('  ║' + (' ' * $w) + '║') -ForegroundColor $Color
  Write-Host ('  ╚' + ('═' * $w) + '╝') -ForegroundColor $Color
}
function Read-Ask([string]$Question,[string]$Hint='') {
  $lines = @($Question); if ($Hint) { $lines += $Hint }
  Write-AskBox $lines
  return (Read-Host '   твой ответ (цифра)')
}
function Test-Interactive {
  try { return (-not [Console]::IsInputRedirected) } catch { return $false }
}

$Results = [System.Collections.Generic.List[object]]::new()
$script:StatusMark  = @{ READY='ОК'; REPAIRED='ПОСТАВЛЕНО'; LOGIN='НУЖЕН ВХОД';
                         WARN='ВНИМАНИЕ'; ABSENT='нет'; MISSING='НЕТ'; BLOCKED='ЗАКРЫТ'; ERROR='ОШИБКА' }
$script:StatusColor = @{ READY='Green'; REPAIRED='Green'; LOGIN='Yellow';
                         WARN='Yellow'; ABSENT='DarkGray'; MISSING='Red'; BLOCKED='Red'; ERROR='Red' }
# $Key/$Code — для обезличенной сводки: имя пункта из фиксированного набора и
# короткий код причины. Свободный текст (пути, сообщения ошибок) в сводку не идёт.
function Add-Result([string]$Category,[string]$Name,[string]$Status,[string]$Version='-',[string]$Action='-',[string]$Details='',[string]$Key='',[string]$Code='') {
  $Results.Add([pscustomobject]@{Category=$Category;Component=$Name;Status=$Status;Version=$Version;Action=$Action;Details=$Details;Key=$Key;Code=$Code})
  # Гасим полоску прогресса перед своей строкой, иначе вывод слипается.
  try { if (-not [Console]::IsInputRedirected) { [Console]::Write("`r" + (' ' * 78) + "`r") } } catch {}
  $mark = $script:StatusMark[$Status];  if (-not $mark) { $mark = $Status }
  $col  = $script:StatusColor[$Status]; if (-not $col)  { $col  = 'Gray' }
  $line = '      ' + $mark + ' · ' + $Name
  if ($Version -and $Version -ne '-') { $line += ' ' + $Version }
  if ($Status -ne 'READY' -and $Action -and $Action -ne '-') { $line += ' — ' + $Action }
  Write-Host $line -ForegroundColor $col
}

# ---- Низкоуровневые помощники --------------------------------------------
# Запуск проверяемой программы (`pwsh --version`, `git --version`, `codex login status`)
# — с лимитом времени. Первый запуск только что поставленной программы бывает долгим
# (антивирус проверяет новые файлы), а без лимита пакет стоял бы молча, пока окно не
# закроют. Отдельный runspace того же процесса: запускается мгновенно, PATH общий.
# Не ответила за лимит — идём дальше с кодом -1, как при обычной ошибке запуска.
function Invoke-CheckedCommand([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSec=30) {
  $ps = [powershell]::Create()
  # Внутри локально Continue: под Stop PowerShell 5.1 превращает первую строку stderr
  # нативной команды в исключение. Судим по коду выхода и тексту.
  [void]$ps.AddScript({
    param($f, $a)
    $ErrorActionPreference = 'Continue'
    $t = & $f @a 2>&1 | ForEach-Object { "$_" } | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $t }
  }.ToString()).AddArgument($FilePath).AddArgument($Arguments)
  $name = [System.IO.Path]::GetFileName($FilePath)
  $quiet = -not (Test-Interactive)
  $h = $ps.BeginInvoke()
  $sw = [Diagnostics.Stopwatch]::StartNew(); $shown = $false
  while (-not $h.IsCompleted -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    Start-Sleep -Milliseconds 200
    # Обычный ответ — доли секунды; строку показываем, только если ждём дольше 3 с.
    # Мимо транскрипта, как и полоски: в лог уходит только итог.
    if (-not $quiet -and $sw.Elapsed.TotalSeconds -ge 3) {
      [Console]::Write(("`r      жду ответа: $name ... " + [int]$sw.Elapsed.TotalSeconds + "s из $TimeoutSec").PadRight(78)); $shown = $true
    }
  }
  if ($shown) { Clear-Bar }
  if ($h.IsCompleted) {
    try {
      $r = @($ps.EndInvoke($h)) | Select-Object -Last 1
      if ($r) { return [pscustomobject]@{ ExitCode = $r.ExitCode; Text = "$($r.Text)"; TimedOut = $false } }
      return [pscustomobject]@{ ExitCode = -1; Text = ''; TimedOut = $false }
    } catch {
      return [pscustomobject]@{ ExitCode = -1; Text = "$($_.Exception.Message)"; TimedOut = $false }
    } finally { $ps.Dispose() }
  }
  # Зависший вызов просим остановиться и не ждём: Dispose работающего runspace сам бы встал.
  try { [void]$ps.BeginStop($null, $null) } catch {}
  Write-Host "      $name не ответил за $TimeoutSec сек — пропускаю и иду дальше" -ForegroundColor Yellow
  return [pscustomobject]@{ ExitCode = -1; Text = "$name не ответил за $TimeoutSec сек"; TimedOut = $true }
}
# Любой вызов winget ходит в сеть и на плохом канале может не вернуться вовсе.
# Поэтому каждый внешний вызов идёт через job с лимитом времени и живой полоской.
function Invoke-WithTimeout([scriptblock]$Body,[int]$TimeoutSec,[string]$Hint='') {
  $j = $null
  if ($Hint) { Write-Host "      $Hint — до $TimeoutSec сек" -ForegroundColor DarkGray }
  $quiet = -not (Test-Interactive)
  $bars = 24
  try {
    $j = Start-Job -ScriptBlock { param($sb) & ([scriptblock]::Create($sb)) 2>&1 } -ArgumentList $Body.ToString()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($j.State -eq 'Running' -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
      if (-not $quiet -and $Hint) {
        $el = [int]$sw.Elapsed.TotalSeconds
        $fill = [int][math]::Min($bars, [math]::Floor($bars * $el / [math]::Max(1,$TimeoutSec)))
        $line = '      ' + $Hint + '  [' + ('#' * $fill) + ('.' * ($bars - $fill)) + "] ${el}s"
        # Только [Console]::Write: так полоска не попадает в лог-транскрипт.
        [Console]::Write("`r" + $line.PadRight(78))
      }
      Start-Sleep -Milliseconds 400
    }
    if (-not $quiet -and $Hint) { [Console]::Write("`r" + (' ' * 78) + "`r") }
    if ($j.State -ne 'Running') {
      $out = (Receive-Job $j | Out-String)
      $code = if ($j.ChildJobs[0].JobStateInfo.State -eq 'Failed') { 1 } else { 0 }
      # КОД ВЫХОДА — МЕТКОЙ В ВЫВОДЕ. `exit N` внутри задачи код наружу НЕ передаёт: задача
      # просто «Completed», и раньше здесь всегда выходил 0. Проваленный winget install
      # показывался как «ПОСТАВЛЕНО», хотя программа не встала (аудит 03.10.2026,
      # проверено на PS 5.1). Поэтому тело задачи печатает последней строкой '##EXIT=<код>'.
      $em = [regex]::Matches($out, '##EXIT=(-?\d+)')
      if ($em.Count) {
        $code = [int]$em[$em.Count - 1].Groups[1].Value
        $out = [regex]::Replace($out, '(?m)^##EXIT=-?\d+\s*$', '').Trim()
      }
      return [pscustomobject]@{ Text = $out; ExitCode = $code; TimedOut = $false }
    }
    Stop-Job $j -ErrorAction SilentlyContinue
    if ($Hint) { Write-Host "      $Hint - не ответило за $TimeoutSec сек, иду дальше" -ForegroundColor Yellow }
    return [pscustomobject]@{ Text = ''; ExitCode = -1; TimedOut = $true }
  } catch {
    return [pscustomobject]@{ Text = "$($_.Exception.Message)"; ExitCode = -1; TimedOut = $false }
  } finally { if ($j) { Remove-Job $j -Force -ErrorAction SilentlyContinue } }
}
# В PATH лежат заглушки Microsoft Store (WindowsApps\python.exe): это не Python, а
# ярлык в Store. Опознаём по пути и размеру и считаем, что команды нет.
function Test-IsStoreStub([string]$Path) {
  if (-not $Path) { return $false }
  # Только python.exe/python3.exe. В WindowsApps лежат и настоящие псевдонимы приложений
  # (winget.exe, pwsh.exe из Store) — тоже файлы нулевой длины, но рабочие.
  if ([System.IO.Path]::GetFileName($Path) -notmatch '(?i)^python3?\.exe$') { return $false }
  return ($Path -match '(?i)\\Microsoft\\WindowsApps\\') -and ((Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).Length -lt 200KB)
}
function Get-Version([string]$Exe,[string[]]$VersionArguments=@('--version')) {
  $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  if (Test-IsStoreStub $cmd.Source) { return $null }
  $run = Invoke-CheckedCommand $cmd.Source $VersionArguments
  # Не ответила за лимит — программа ЕСТЬ (команда найдена), просто медленно стартует.
  # Версия «?», а не «нет»: иначе кит счёл бы её отсутствующей и полез ставить заново
  # (git без запасных путей) или написал бы ложное «не видна в PATH» (pwsh). Аудит 03.10.2026.
  if ($run.TimedOut) { return '?' }
  if ($run.ExitCode -ne 0) { throw "${Exe} вернул код выхода $($run.ExitCode)" }
  $m = [regex]::Match($run.Text,'(?<!\d)(\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $run.Text.Trim().Replace("`r",'').Replace("`n",' ')
}
function Invoke-Winget([string]$Id) {
  $run = Invoke-WithTimeout ([scriptblock]::Create("winget install --id $Id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements; '##EXIT=' + `$LASTEXITCODE")) 300 "устанавливаю $Id"
  if ($run.TimedOut) { throw "winget install ${Id}: нет ответа 300 сек (проверь интернет)" }
  if ($run.ExitCode -ne 0) {
    # Текст winget в сообщении обязателен: без него «нет пакета», «нет сети» и
    # «нужно согласие источника» неотличимы.
    $why = ($run.Text -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
    throw "winget install ${Id}: $why"
  }
}
# winget может лежать на диске, но не запускаться (сборки без Store: «No applicable
# app licenses found»). Проверяем реальную работоспособность один раз.
function Test-WingetWorks {
  $cmd = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $cmd) { return $false }
  try {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    $probe = Invoke-WithTimeout ([scriptblock]::Create("& '$($cmd.Source)' --version; '##EXIT=' + `$LASTEXITCODE")) 20 'проверяю WinGet'
    $ErrorActionPreference = $old
    if ($probe.TimedOut) { return $false }
    $out = $probe.Text; $code = $probe.ExitCode
    if ($out -match '(?i)no applicable app licenses|failed to run|0x') { return $false }
    return ($code -eq 0 -and $out -match 'v?\d+\.\d+')
  } catch { return $false }
}
# После установки обновляем PATH прямо в этом процессе, иначе поставленное видно
# только в новом окне. Делаем это и ПЕРЕД каждой проверкой.
function Update-ProcessPath {
  try {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machine,$user) | Where-Object { $_ }) -join ';'
  } catch {}
}
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

# >>> WINGET-REPAIR BEGIN
# ---- Починка WinGet («Установщик приложений» от Microsoft) --------------------
# Единственное место пакета, где что-то скачивается на диск и ставится. Правила
# (их проверяет build.py):
#  - сперва без скачивания: перерегистрация уже лежащего в системе пакета;
#  - скачивание — только с явного согласия и только официальные файлы Microsoft
#    с релизов github.com/microsoft/winget-cli; после редиректов хост сверяется
#    с белым списком;
#  - перед установкой КАЖДЫЙ файл проверяется Get-AuthenticodeSignature:
#    статус Valid и издатель O=Microsoft Corporation. Иначе не ставим ничего.
# Наш сервер здесь не участвует.
$script:WingetBundleUrl = 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$script:WingetDepsUrl   = 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip'
$script:WingetHosts     = @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')

function Write-ByteBar([string]$Label,[long]$Done,[long]$Total) {
  if (-not (Test-Interactive)) { return }
  $bars = 24
  $frac = if ($Total -gt 0) { [math]::Min(1.0, $Done / $Total) } else { 0 }
  $fill = [int][math]::Floor($bars * $frac)
  $line = '      ' + $Label + '  [' + ('#' * $fill) + ('.' * ($bars - $fill)) + '] ' + [math]::Round($Done / 1MB) + '/' + [math]::Round($Total / 1MB) + ' МБ'
  [Console]::Write("`r" + $line.PadRight(78))
}
function Clear-Bar { if (Test-Interactive) { [Console]::Write("`r" + (' ' * 78) + "`r") } }
# Пусто — подпись в порядке; иначе — причина одной строкой.
function Get-MicrosoftSignatureProblem([string]$Path) {
  $name = [System.IO.Path]::GetFileName($Path)
  try {
    $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ("$($s.Status)" -ne 'Valid') { return "подпись $name недействительна ($($s.Status))" }
    if (-not $s.SignerCertificate -or $s.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { return "$name подписан не Microsoft" }
    return ''
  } catch { return "подпись $name не проверить: $($_.Exception.Message)" }
}
function Save-MicrosoftFile([string]$Url,[string]$Dest,[string]$Label) {
  if ($Url -notlike 'https://github.com/microsoft/winget-cli/releases/*') { throw "адрес не из белого списка: $Url" }
  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.Timeout = 30000
  $req.ReadWriteTimeout = 60000
  $req.AllowAutoRedirect = $true
  $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) stereo-vibe-lite'
  $resp = $req.GetResponse()
  try {
    $final = $resp.ResponseUri
    if ($final.Scheme -ne 'https' -or $script:WingetHosts -notcontains $final.Host) { throw "после редиректа чужой адрес: $($final.Host)" }
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [System.IO.File]::Create($Dest)
    $done = 0L
    try {
      $buf = New-Object byte[] (1MB)
      $sw = [Diagnostics.Stopwatch]::StartNew()
      while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $out.Write($buf, 0, $n); $done += $n
        if ($sw.ElapsedMilliseconds -ge 300) { Write-ByteBar $Label $done $total; $sw.Restart() }
      }
    } finally { $out.Dispose(); $in.Dispose(); Clear-Bar }
    if ($total -gt 0 -and $done -ne $total) { throw "$Label скачался не полностью" }
  } finally { $resp.Close() }
}
# Возвращает код для сводки: repaired_register / repaired_download /
# repair_declined / repair_failed.
function Repair-Winget {
  $wa = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
  $refresh = { Update-ProcessPath; if ($env:Path -notlike "*$wa*") { $env:Path = $env:Path + ';' + $wa } }

  # 1. Без скачивания: пакет часто уже лежит в системе, но не зарегистрирован.
  Write-Host '      WinGet не работает — пробую перерегистрировать «Установщик приложений» (без скачивания)...' -ForegroundColor Cyan
  try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
    & $refresh; Start-Sleep -Seconds 2
    if (Test-WingetWorks) { Write-Host '      WinGet заработал после перерегистрации.' -ForegroundColor Green; return 'repaired_register' }
    Write-Host '      перерегистрация прошла, но WinGet всё ещё не отвечает.' -ForegroundColor DarkGray
  } catch {
    $m = "$($_.Exception.Message)".Trim(); if ($m.Length -gt 160) { $m = $m.Substring(0,160) + '…' }
    Write-Host "      перерегистрация не помогла: $m" -ForegroundColor DarkGray
  }

  # 2. Скачать официальные пакеты Microsoft — только с явного согласия.
  if (-not (Test-Interactive)) { return 'repair_failed' }
  if ($script:WinBuild -and $script:WinBuild -lt 17763) {
    Write-Host '      Для этой версии Windows «Установщик приложений» недоступен — нужна Windows 10 1809 или новее.' -ForegroundColor Yellow
    return 'repair_failed'
  }
  $ans = Read-Ask 'ПОСТАВИТЬ «УСТАНОВЩИК ПРИЛОЖЕНИЙ» ОТ MICROSOFT?' '1 — поставить Установщик приложений от Microsoft (около 300 МБ с GitHub Microsoft)   ·   2 — нет'
  Write-Host "   ответ: «$ans»" -ForegroundColor DarkGray
  if ($ans -notmatch '^\s*1') { return 'repair_declined' }

  $cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  $arch = switch ($cpu) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } 'x86' { 'x86' } default { '' } }
  if (-not $arch) { Write-Host "      Неизвестная архитектура процессора: $cpu" -ForegroundColor Yellow; return 'repair_failed' }
  $dir = Join-Path $env:TEMP ('stereo_vibe_winget_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $bundle  = Join-Path $dir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    $depsZip = Join-Path $dir 'DesktopAppInstaller_Dependencies.zip'
    Write-Host '      качаю официальные пакеты Microsoft с github.com/microsoft/winget-cli — это несколько минут' -ForegroundColor DarkGray
    Save-MicrosoftFile $script:WingetDepsUrl $depsZip 'зависимости WinGet'
    Save-MicrosoftFile $script:WingetBundleUrl $bundle 'Установщик приложений'

    # Из архива зависимостей берём только пакеты своей архитектуры.
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $deps = @()
    $z = [System.IO.Compression.ZipFile]::OpenRead($depsZip)
    try {
      foreach ($e in $z.Entries) {
        if ($e.FullName -match "^$arch/[^/]+\.appx$") {
          $t = Join-Path $dir $e.Name
          [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $t, $true)
          $deps += $t
        }
      }
    } finally { $z.Dispose() }
    if (-not $deps.Count) { throw "в архиве зависимостей нет пакетов для $arch" }

    # Подпись — у всех файлов ДО первой установки. Хоть один не прошёл — не ставим ничего.
    foreach ($f in @($deps + $bundle)) {
      $why = Get-MicrosoftSignatureProblem $f
      if ($why) { Write-Host "      Не ставлю: $why" -ForegroundColor Yellow; return 'repair_failed' }
    }
    Write-Host '      подписи проверены: Valid, издатель Microsoft Corporation' -ForegroundColor DarkGray

    foreach ($d in $deps) {
      # «Уже стоит версия новее» — не ошибка, идём дальше.
      try { Add-AppxPackage -Path $d -ErrorAction Stop }
      catch {
        $m = "$($_.Exception.Message)".Trim(); if ($m.Length -gt 120) { $m = $m.Substring(0,120) + '…' }
        Write-Host "      $([System.IO.Path]::GetFileName($d)): $m" -ForegroundColor DarkGray
      }
    }
    Write-Host '      ставлю «Установщик приложений» — до пары минут, не закрывай окно' -ForegroundColor DarkGray
    Add-AppxPackage -Path $bundle -ErrorAction Stop
    & $refresh; Start-Sleep -Seconds 2
    if (Test-WingetWorks) { Write-Host '      WinGet установлен и работает.' -ForegroundColor Green; return 'repaired_download' }
    Write-Host '      «Установщик приложений» встал, но WinGet пока не отвечает.' -ForegroundColor Yellow
    return 'repair_failed'
  } catch {
    $m = "$($_.Exception.Message)".Trim(); if ($m.Length -gt 200) { $m = $m.Substring(0,200) + '…' }
    Write-Host "      Поставить не вышло: $m" -ForegroundColor Yellow
    return 'repair_failed'
  } finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
# <<< WINGET-REPAIR END

# ---- HTTP без мусора в логе ------------------------------------------------
# Invoke-WebRequest на любой 4xx бросает исключение, и транскрипт пишет его в лог
# даже пойманным. HttpWebRequest в транскрипт не пишет; прокси — системный.
function Invoke-Http([string]$Url,[string]$Method='GET',[byte[]]$Body=$null,[string]$ContentType='',[int]$TimeoutSec=8) {
  $res = [pscustomobject]@{ Code = 0; Bytes = $null; Challenge = $false }
  $resp = $null
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) stereo-vibe-lite'
    if ($Body) {
      $req.ContentType = $ContentType
      $req.ContentLength = $Body.Length
      $rq = $req.GetRequestStream()
      try { $rq.Write($Body, 0, $Body.Length) } finally { $rq.Close() }
    }
    $resp = $req.GetResponse()
  } catch {
    # 4xx/5xx — ответ есть, это не сбой сети. Исключение может прийти обёрнутым.
    $ex = $_.Exception
    while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
    if ($ex) { $resp = $ex.Response }
  }
  if ($resp) {
    try { $res.Code = [int]$resp.StatusCode } catch {}
    try { $res.Challenge = ("$($resp.Headers['cf-mitigated'])" -match '(?i)challenge') } catch {}
    if ($Method -ne 'HEAD') {
      try {
        $ms = New-Object System.IO.MemoryStream
        $rs = $resp.GetResponseStream(); $rs.CopyTo($ms); $rs.Close()
        $res.Bytes = $ms.ToArray()
      } catch {}
    }
    try { $resp.Close() } catch {}
  }
  return $res
}
function Get-HttpText($r,[int]$Max=4000) {
  if (-not $r.Bytes) { return '' }
  try {
    $t = [System.Text.Encoding]::UTF8.GetString($r.Bytes)
    if ($t.Length -gt $Max) { $t = $t.Substring(0,$Max) }
    return $t
  } catch { return '' }
}

# ---- Обезличенная сводка ---------------------------------------------------
# id установки — случайный, создаётся один раз и хранится локально. К человеку,
# компьютеру и учётной записи не привязан.
# ---- Уведомление о новой версии ---------------------------------------------
# Только уведомление: читаем из version.json одно поле version и сравниваем со
# своим. Ничего не скачиваем и не выполняем. Любая ошибка — молча дальше.
function Test-NewVersion {
  try {
    $r = Invoke-Http $script:VersionUrl 'GET' $null '' 5
    if ($r.Code -ne 200 -or -not $r.Bytes) { return }
    $m = [regex]::Match((Get-HttpText $r 2000), '"version"\s*:\s*"(\d+(?:\.\d+){1,3})"')
    if (-not $m.Success) { return }
    $fresh = $m.Groups[1].Value
    if ([version]$fresh -gt [version]$script:PkgVersion) {
      Write-Host ''
      Write-Host "  ►►► Вышла новая версия StereoVibe $fresh — возьми свежий архив в боте: $($script:BotUpdateUrl)" -ForegroundColor Magenta
      Write-Host ''
    }
  } catch {}
}

# ---- Обезличенная сводка: id установки ---------------------------------------
function Get-InstallId {
  $f = Join-Path $script:DataDir 'install_id.txt'
  try {
    if (Test-Path -LiteralPath $f) {
      $v = (Get-Content -LiteralPath $f -Raw -ErrorAction Stop).Trim()
      if ($v -match '^[0-9a-f]{32}$') { return $v }
    }
  } catch {}
  $v = [guid]::NewGuid().ToString('N')
  try {
    if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
    Set-Content -LiteralPath $f -Value $v -Encoding ascii
  } catch {}
  return $v
}
# В сводку уходят только версии из цифр и латиницы — никакого свободного текста.
function Protect-Version([string]$v) {
  if ($v -and $v -ne '-' -and $v -match '^[0-9A-Za-z .()+\-]{1,40}$') { return $v }
  return ''
}
function New-Summary {
  $map = @{ READY='ok'; REPAIRED='installed'; ERROR='error'; MISSING='error'; BLOCKED='error'; WARN='warn'; ABSENT='absent'; LOGIN='login' }
  $tools = @()
  foreach ($r in $Results) {
    if (-not $r.Key) { continue }
    $tools += [ordered]@{ tool = $r.Key; status = $map[$r.Status]; version = (Protect-Version $r.Version); code = $r.Code }
  }
  $id = if ($NoReport) { '' } else { Get-InstallId }
  return [ordered]@{
    schema          = 1
    package_version = $script:PkgVersion
    install_id      = $id
    mode            = $(if ($ReportOnly) { 'check' } else { 'install' })
    windows         = [ordered]@{ major = "$($script:WinMajor)"; build = [int]$script:WinBuild }
    admin           = [bool]$script:IsAdmin
    tools           = $tools
    ai_access       = [bool]$script:AiAccess
    ai_services     = [ordered]@{ openai = [bool]$script:AiOk['openai']; anthropic = [bool]$script:AiOk['anthropic']; gemini = [bool]$script:AiOk['gemini'] }
    verdict         = $(if ($script:ToolBlockers.Count) { 'not_ready' } else { 'tools_ready' })
    duration_sec    = [int]$script:RunClock.Elapsed.TotalSeconds
  }
}
function Send-Summary {
  try {
    $json = (New-Summary) | ConvertTo-Json -Depth 5 -Compress
    # Копия того, что отправляется (или отправилось бы), лежит рядом с логом.
    try { [System.IO.File]::WriteAllText($SummaryPath, $json, (New-Object System.Text.UTF8Encoding($false))) } catch {}
    if ($NoReport) { return }
    $r = Invoke-Http $script:SummaryUrl 'POST' ([System.Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8' 8
    # Ошибка отправки молчит: на работу пакета она не влияет.
    if ($r.Code -ge 200 -and $r.Code -lt 300) { Write-Host '  Обезличенная сводка отправлена. Спасибо!' -ForegroundColor DarkGray }
  } catch {}
}

# ---- Где лежат программы, если их нет в PATH ------------------------------
$script:PwshPaths   = @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramW6432\PowerShell\7\pwsh.exe", "$env:LOCALAPPDATA\Microsoft\powershell\pwsh.exe")
$script:NodePaths   = @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")
$script:PythonPaths = @(
  "$env:ProgramFiles\Python314\python.exe", "$env:ProgramFiles\Python313\python.exe",
  "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe"
)
$script:CodexPaths  = @("$env:LOCALAPPDATA\Microsoft\WinGet\Links\codex.exe", "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe", "$env:ProgramFiles\OpenAI\Codex\bin\codex.exe")

# Проверка инструмента: стоит — ОК; нет — ставим через winget (в режиме установки).
# winget не работает или не смог — понятное сообщение, где взять вручную.
function Test-Tool([string]$Category,[string]$Name,[string]$Exe,[string]$Id,[string]$ManualUrl,[string]$Key,[string[]]$FallbackPaths=@()) {
  try {
    Write-Step $Name
    Update-ProcessPath
    $version = $null
    try { $version = Get-Version $Exe } catch { $version = $null }
    if ($version) { Add-Result $Category $Name 'READY' $version 'Стоит' '' $Key; return }
    if ($FallbackPaths.Count -gt 0) {
      $fb = Find-ExeOutsidePath $FallbackPaths
      if ($fb) {
        Add-Result $Category $Name 'WARN' (Get-VersionAt $fb) 'стоит, но не виден в PATH — закрой окно и запусти пакет заново' $fb $Key 'not_in_path'
        return
      }
    }
    if (-not $InstallMissing) { Add-Result $Category $Name 'MISSING' '-' "не установлен. Поставить: winget install --id $Id --exact" '' $Key 'not_installed'; return }
    if (-not $script:WingetOk) { Add-Result $Category $Name 'MISSING' '-' "не установлен, а WinGet не работает — поставь вручную: $ManualUrl" '' $Key 'no_winget'; return }
    $why = ''
    try { Invoke-Winget $Id } catch { $why = $_.Exception.Message }
    Update-ProcessPath
    try { $version = Get-Version $Exe } catch { $version = $null }
    if (-not $version -and $FallbackPaths.Count -gt 0) {
      $fb = Find-ExeOutsidePath $FallbackPaths
      if ($fb) { $version = Get-VersionAt $fb }
    }
    if ($version) { Add-Result $Category $Name 'REPAIRED' $version 'Установлено через winget' '' $Key; return }
    Add-Result $Category $Name 'MISSING' '-' "winget не смог поставить — поставь вручную: $ManualUrl" $why $Key 'winget_failed'
  } catch { Add-Result $Category $Name 'ERROR' '-' 'Проверить вручную' $_.Exception.Message $Key 'check_failed' }
}

# ---- Telegram Desktop -------------------------------------------------------
function Test-TelegramInstalled {
  if (Find-ExeOutsidePath @("$env:APPDATA\Telegram Desktop\Telegram.exe",
                            "$env:LOCALAPPDATA\Programs\Telegram Desktop\Telegram.exe",
                            "$env:ProgramFiles\Telegram Desktop\Telegram.exe")) { return $true }
  try {
    $keys = @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    if (Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)^Telegram Desktop' }) { return $true }
  } catch {}
  return $false
}
function Test-Telegram([string]$Category) {
  $name = 'Telegram Desktop'
  try {
    Write-Step $name
    if (Test-TelegramInstalled) { Add-Result $Category $name 'READY' '-' 'Стоит' '' 'telegram'; return }
    if (-not $InstallMissing -or -not (Test-Interactive)) {
      Add-Result $Category $name 'ABSENT' '-' 'не установлен (нужен для работы с Telegram-ботами)' '' 'telegram' 'not_installed'; return
    }
    # Спрашиваем: ставить мессенджер на чужой компьютер молча нельзя.
    $ans = Read-Ask 'ПОСТАВИТЬ TELEGRAM DESKTOP?' '1 — поставить (пригодится для своих Telegram-ботов)   ·   2 — не надо'
    Write-Host "   ответ: «$ans»" -ForegroundColor DarkGray
    if ($ans -notmatch '^\s*1') { Add-Result $Category $name 'ABSENT' '-' 'не ставили — по желанию' '' 'telegram' 'declined'; return }
    if (-not $script:WingetOk) { Add-Result $Category $name 'MISSING' '-' 'WinGet не работает — скачай с https://desktop.telegram.org' '' 'telegram' 'no_winget'; return }
    $why = ''
    try { Invoke-Winget 'Telegram.TelegramDesktop' } catch { $why = $_.Exception.Message }
    if (Test-TelegramInstalled) { Add-Result $Category $name 'REPAIRED' '-' 'Установлено через winget' '' 'telegram' }
    else { Add-Result $Category $name 'MISSING' '-' 'не встал — скачай с https://desktop.telegram.org' $why 'telegram' 'winget_failed' }
  } catch { Add-Result $Category $name 'ERROR' '-' 'Проверить вручную' $_.Exception.Message 'telegram' 'check_failed' }
}

# ---- ИИ-приложения и агенты -------------------------------------------------
# ChatGPT для Windows (пакет Store «OpenAI.Codex», в нём же Codex Desktop) —
# ищем только чтобы показать, что он уже стоит. Поставить его отсюда нельзя.
function Get-ChatGPTDesktop {
  try { return (Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { return $null }
}
function Get-ClaudeDesktop {
  try {
    $appx = Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appx) { return [pscustomobject]@{ Version="$($appx.Version)"; Path=$appx.InstallLocation } }
  } catch {}
  $exe = Find-ExeOutsidePath @("$env:LOCALAPPDATA\Programs\Claude\Claude.exe", "$env:LOCALAPPDATA\AnthropicClaude\Claude.exe", "$env:ProgramFiles\Claude\Claude.exe")
  if ($exe) {
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).ProductVersion
    return [pscustomobject]@{ Version=$(if($v){$v}else{'-'}); Path=$exe }
  }
  try {
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match '^Claude' } | Select-Object -First 1
    if ($reg) { return [pscustomobject]@{ Version=$(if($reg.DisplayVersion){$reg.DisplayVersion}else{'-'}); Path=$reg.InstallLocation } }
  } catch {}
  return $null
}
function Get-WebAppShortcutPath([string]$Name) {
  return (Join-Path ([Environment]::GetFolderPath('Programs')) "$Name (веб-приложение).lnk")
}
# Веб-версия как приложение: ярлык в «Пуск», Edge открывает сайт отдельным окном.
function Install-WebAppShortcut([string]$Name,[string]$Url) {
  $shortcutPath = Get-WebAppShortcutPath $Name
  $edge = Find-ExeOutsidePath @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  if ($edge) {
    $shortcut.TargetPath = $edge
    $shortcut.Arguments = "--app=$Url"
    $shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($edge)
    $shortcut.IconLocation = "$edge,0"
  } else {
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'explorer.exe'
    $shortcut.Arguments = $Url
  }
  $shortcut.Description = "$Name — веб-версия"
  $shortcut.Save()
  Write-Host "    Ярлык «$Name» добавлен в меню «Пуск»." -ForegroundColor Green
}
function Install-ChatGPTWeb {
  Write-Host '    ChatGPT и Codex для Windows раздаются только через Microsoft Store,' -ForegroundColor Yellow
  Write-Host '    а из России Store их не отдаёт — поставить приложение отсюда нельзя.' -ForegroundColor Yellow
  Write-Host '    Делаю ярлык веб-версии https://chatgpt.com — вход и подписка там те же.' -ForegroundColor DarkGray
  Write-Host '    Для работы с кодом есть Codex CLI (пункт 1).' -ForegroundColor DarkGray
  Install-WebAppShortcut 'ChatGPT' 'https://chatgpt.com'
}
function Test-CodexPresent { return [bool]((Get-Command codex -ErrorAction SilentlyContinue) -or (Find-ExeOutsidePath $script:CodexPaths)) }
function Install-CodexCli {
  if (Test-CodexPresent) { Write-Host '    Codex CLI уже установлен.' -ForegroundColor DarkGray; return }
  if (-not $script:WingetOk) { throw 'WinGet не работает. Если Node.js стоит — в новом окне PowerShell выполни: npm install -g @openai/codex' }
  $why = ''
  try { Invoke-Winget 'OpenAI.Codex' } catch { $why = $_.Exception.Message }
  Update-ProcessPath
  if (Get-Command codex -ErrorAction SilentlyContinue) { Write-Host '    Codex CLI установлен.' -ForegroundColor Green; return }
  if (Find-ExeOutsidePath $script:CodexPaths) { Write-Host '    Codex CLI установлен; команда codex появится в НОВОМ окне терминала.' -ForegroundColor Yellow; return }
  throw "winget не смог поставить Codex CLI ($why). Запасной путь — в новом окне PowerShell: npm install -g @openai/codex"
}
function Install-ClaudeCli {
  if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host '    Claude Code CLI уже установлен.' -ForegroundColor DarkGray; return }
  if (-not $script:WingetOk) { throw 'WinGet не работает. Инструкция по ручной установке: https://docs.anthropic.com/en/docs/claude-code/setup' }
  $why = ''
  try { Invoke-Winget 'Anthropic.ClaudeCode' } catch { $why = $_.Exception.Message }
  Update-ProcessPath
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host '    Claude Code CLI установлен.' -ForegroundColor Green
    Write-Host '    Учти: Claude Code работает с подпиской Pro/Max, на бесплатном аккаунте — нет.' -ForegroundColor DarkGray
    return
  }
  throw "winget не смог поставить Claude Code ($why). Инструкция: https://docs.anthropic.com/en/docs/claude-code/setup"
}
function Install-GeminiCli {
  if (Get-Command gemini -ErrorAction SilentlyContinue) { Write-Host '    Gemini CLI уже установлен.' -ForegroundColor DarkGray; return }
  Update-ProcessPath
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'нужен Node.js — он ставится в этом же пакете; запусти пакет ещё раз' }
  $r = Invoke-WithTimeout { npm install -g @google/gemini-cli 2>&1 | Out-Null; '##EXIT=' + $LASTEXITCODE } 300 'ставлю Gemini CLI (npm)'
  if ($r.TimedOut) { throw 'npm не ответил за 300 сек' }
  Update-ProcessPath
  if (Get-Command gemini -ErrorAction SilentlyContinue) { Write-Host '    Gemini CLI установлен.' -ForegroundColor Green }
  else { throw 'npm не смог поставить Gemini CLI — в новом окне PowerShell выполни: npm install -g @google/gemini-cli' }
}
function Select-AndInstallAiApps {
  if ($ReportOnly -or -not $InstallMissing) { return }
  if (-not (Test-Interactive) -and -not $PreferredApps) { return }
  Write-Host ''
  Write-Host '  ── ВЫБОР ИИ-ИНСТРУМЕНТОВ ─────────────────────' -ForegroundColor Cyan
  Write-Host '   АГЕНТЫ (правят файлы и запускают код — это и есть вайбкодинг):' -ForegroundColor Cyan
  Write-Host '   [1] Codex CLI — агент OpenAI (нужна подписка ChatGPT Plus)' -ForegroundColor Yellow
  Write-Host '   [2] Claude Code CLI — агент Anthropic (нужна подписка Pro/Max)' -ForegroundColor Yellow
  Write-Host '   [3] Gemini CLI — агент Google (ставится через npm)' -ForegroundColor Yellow
  Write-Host '   ПРИЛОЖЕНИЯ (окно с чатом):' -ForegroundColor Cyan
  Write-Host '   [4] ChatGPT — веб-версия как приложение (из Microsoft Store в РФ не ставится)' -ForegroundColor Yellow
  Write-Host '   [5] Gemini — веб-версия как приложение' -ForegroundColor Yellow
  Write-Host '   Можно несколько: 1,4   ·   [9] всё сразу   ·   [0] пропустить' -ForegroundColor DarkGray
  $answer = $PreferredApps
  if (-not $answer) { $answer = Read-Ask 'ЧТО УСТАНОВИТЬ?' 'номера через запятую: 1,4   ·   9 — всё сразу   ·   0 — пропустить' }
  $parts = @("$answer" -split '[,;\s]+' | Where-Object { $_ })
  if ($parts -contains '0' -or $parts.Count -eq 0) {
    Write-Host "   ответ: «$answer» → ничего не ставим" -ForegroundColor DarkGray
    return
  }
  $selected = @()
  if ($parts -contains '9') {
    $selected = @('CodexCli','ClaudeCli','GeminiCli','ChatGPTWeb','GeminiWeb')
  } else {
    foreach ($p in $parts) {
      switch -Regex ($p) {
        '^1$' { if ($selected -notcontains 'CodexCli')      { $selected += 'CodexCli' } }
        '^2$' { if ($selected -notcontains 'ClaudeCli')     { $selected += 'ClaudeCli' } }
        '^3$' { if ($selected -notcontains 'GeminiCli')     { $selected += 'GeminiCli' } }
        '^4$' { if ($selected -notcontains 'ChatGPTWeb')    { $selected += 'ChatGPTWeb' } }
        '^5$' { if ($selected -notcontains 'GeminiWeb')     { $selected += 'GeminiWeb' } }
        default { Write-Host "   Неизвестный вариант: $p" -ForegroundColor Yellow }
      }
    }
  }
  $script:SelectedApps = $selected
  Write-Host "   ответ: «$answer» → выбрано: $($selected -join ', ')" -ForegroundColor DarkGray
  foreach ($app in $selected) {
    try {
      switch ($app) {
        'CodexCli'      { Install-CodexCli }
        'ClaudeCli'     { Install-ClaudeCli }
        'GeminiCli'     { Install-GeminiCli }
        'ChatGPTWeb'    { Install-ChatGPTWeb }
        'GeminiWeb'     { Install-WebAppShortcut 'Gemini' 'https://gemini.google.com' }
      }
      $script:Installed[$app] = $true
    } catch {
      $script:AppFail[$app] = $_.Exception.Message
      Write-Host "    Не удалось: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
}
# «Не выбрано» (серое, не проблема) или «выбрано, но не встало» (жёлтое, с причиной).
function Add-NotInstalled([string]$Category,[string]$Name,[string]$AppKey,[string]$NotChosenNote,[string]$Key) {
  if ($script:SelectedApps -contains $AppKey) {
    $why = $script:AppFail[$AppKey]
    Add-Result $Category $Name 'WARN' '-' 'выбран, но не установился' $(if ($why) { $why } else { '' }) $Key 'install_failed'
  } else {
    Add-Result $Category $Name 'ABSENT' '-' $NotChosenNote '' $Key 'not_selected'
  }
}
function Test-RuntimeCommand([string]$Category,[string]$Name,[string]$Exe,[string[]]$Arguments,[string]$Key,[string[]]$FallbackPaths=@()) {
  try {
    Write-Step $Name
    $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
    $src = if ($cmd) { $cmd.Source } else { $null }
    if ($src -and (Test-IsStoreStub $src)) { $src = Find-ExeOutsidePath $FallbackPaths }
    elseif (-not $src -and $FallbackPaths.Count -gt 0) { $src = Find-ExeOutsidePath $FallbackPaths }
    if (-not $src) { Add-Result $Category "$Name · запуск" 'MISSING' '-' 'команда не найдена' '' $Key 'not_found'; return }
    $run = Invoke-CheckedCommand $src $Arguments
    if ($run.ExitCode -eq 0) { Add-Result $Category "$Name · запуск" 'READY' '-' 'Работает' '' $Key }
    elseif ($run.TimedOut) { Add-Result $Category "$Name · запуск" 'WARN' '-' 'не ответил за 30 сек — запусти проверку ещё раз' '' $Key 'run_timeout' }
    else { Add-Result $Category "$Name · запуск" 'ERROR' '-' "Код выхода $($run.ExitCode)" $run.Text.Trim() $Key 'run_failed' }
  } catch { Add-Result $Category "$Name · запуск" 'ERROR' '-' 'Не запускается' $_.Exception.Message $Key 'run_failed' }
}
# Вход в агентов проверяем по локальным файлам, ничего никуда не отправляя.
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
function Test-GeminiLogin {
  if (-not (Get-Command gemini -ErrorAction SilentlyContinue)) { return $null }
  if ($env:GEMINI_API_KEY -or $env:GOOGLE_API_KEY) { return $true }
  $cred = Join-Path $env:USERPROFILE '.gemini\oauth_creds.json'
  return ((Test-Path $cred) -and (Get-Item $cred).Length -gt 10)
}
function Start-AiApplication([string]$AppName) {
  try {
    if ($AppName -in @('ChatGPT','Gemini')) {
      if ($AppName -eq 'ChatGPT' -and (Get-ChatGPTDesktop)) {
        Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' -ErrorAction Stop
        return $true
      }
      $lnk = Get-WebAppShortcutPath $AppName
      $url = if ($AppName -eq 'ChatGPT') { 'https://chatgpt.com' } else { 'https://gemini.google.com' }
      if (Test-Path -LiteralPath $lnk) { Start-Process explorer.exe -ArgumentList "`"$lnk`"" -ErrorAction Stop }
      else { Start-Process $url -ErrorAction Stop }
      return $true
    }
    $startApp = Get-StartApps -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match 'Claude|Anthropic' -or $_.AppID -match 'Claude|Anthropic' } |
      Select-Object -First 1
    if ($startApp -and $startApp.AppID) {
      Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($startApp.AppID)" -ErrorAction Stop
      return $true
    }
    Start-Process 'https://claude.ai' -ErrorAction Stop
    return $true
  } catch {
    Write-Host "   Не удалось открыть ${AppName}: $($_.Exception.Message)" -ForegroundColor Yellow
    return $false
  }
}
# ---- Память проекта ----------------------------------------------------------
# Проверка только что выяснила про машину то, что агент в первой сессии угадывал бы:
# ОС, что установлено и каких версий, куда выполнен вход, какие ИИ-сервисы открываются.
# Раскладываем это в память проекта, которую агент читает при старте (CLAUDE.md + memory\).
# Правила:
#  - НИЧЕГО не перезаписываем: существующий файл — правка человека. Свежий infra_status
#    при повторном прогоне ложится рядом как infra_status.new.md.
#  - Ни имени компьютера, ни имени пользователя, ни IP: файл живёт в проекте и уходит
#    дальше (git, чаты, скриншоты). Пути пишем от домашней папки: ~\stereo-vibe.
#  - Нет шаблонов или сбой — одна строка и идём дальше, прогон не роняем.
function Get-MemRow([string]$Component) {
  return ($Results | Where-Object { $_.Component -eq $Component } | Select-Object -First 1)
}
function Get-MemVersion([string]$Component) {
  $r = Get-MemRow $Component
  if ($r -and $r.Version -and $r.Version -ne '-') { return [string]$r.Version }
  return 'not installed'
}
function Get-MemReach([string]$Component) {
  $r = Get-MemRow $Component
  if (-not $r) { return 'not checked' }
  if ($r.Status -eq 'READY') { return 'yes' }
  return 'no'
}
function Get-MemLogin($Installed,[scriptblock]$Probe) {
  if (-not $Installed) { return '—' }
  try { if ((& $Probe) -eq $true) { return 'yes' } } catch {}
  return 'no'
}
function Hide-Home([string]$Path) {
  if ($env:USERPROFILE -and $Path -and $Path.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) {
    return '~' + $Path.Substring($env:USERPROFILE.Length)
  }
  return $Path
}
# Возвращает список созданного (пустой — всё уже было).
function Initialize-ProjectMemory([string]$Dir) {
  $tpl = Join-Path $PSScriptRoot 'templates'
  if (-not (Test-Path -LiteralPath $tpl)) { throw 'в пакете нет шаблонов памяти (templates)' }
  $memDir = Join-Path $Dir 'memory'
  foreach ($d in @($Dir, $memDir, (Join-Path $Dir 'scratch'), (Join-Path $Dir 'backup'))) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
  $created = @(); $kept = @()
  $claudeMd = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru') { 'CLAUDE.ru.md' } else { 'CLAUDE.md' }
  $plan = @(
    @{ src = (Join-Path $tpl $claudeMd);                   dst = (Join-Path $Dir 'CLAUDE.md') },
    @{ src = (Join-Path $tpl 'memory\README.md');          dst = (Join-Path $memDir 'README.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_status.md');  dst = (Join-Path $memDir 'PROJECT_status.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_backlog.md'); dst = (Join-Path $memDir 'PROJECT_backlog.md') },
    @{ src = (Join-Path $tpl 'memory\PROJECT_history.md'); dst = (Join-Path $memDir 'PROJECT_history.md') }
  )
  foreach ($p in $plan) {
    if (-not (Test-Path -LiteralPath $p.src)) { continue }
    $leaf = Split-Path $p.dst -Leaf
    if (Test-Path -LiteralPath $p.dst) { $kept += $leaf; continue }
    Copy-Item -LiteralPath $p.src -Destination $p.dst
    $created += $leaf
  }
  # infra_status.md — не шаблон, а ФАКТЫ только что прошедшей проверки.
  $tplInfra = Join-Path $tpl 'memory\infra_status.template.md'
  if (Test-Path -LiteralPath $tplInfra) {
    $txt = [System.IO.File]::ReadAllText($tplInfra)
    $pwshV = Get-MemVersion 'PowerShell 7'
    $map = [ordered]@{
      '{{DATE}}'             = (Get-Date -Format 'yyyy-MM-dd HH:mm')
      '{{OS_NAME}}'          = 'Windows'
      '{{OS_BUILD}}'         = (Get-MemVersion 'Windows')
      '{{DISK_FREE}}'        = ((Get-MemVersion "Диск $env:SystemDrive") -replace 'ГБ','GB')
      '{{PROJECT_DIR}}'      = (Hide-Home $Dir)
      '{{REPORT_DIR}}'       = (Hide-Home $ReportDir)
      '{{GIT_VERSION}}'      = (Get-MemVersion 'Git')
      '{{NODE_VERSION}}'     = (Get-MemVersion 'Node.js LTS')
      '{{PKG_MANAGER}}'      = 'WinGet'
      '{{PKG_VERSION}}'      = (Get-MemVersion 'WinGet')
      '{{SHELL_NAME}}'       = $(if ($pwshV -ne 'not installed') { 'PowerShell 7' } else { 'Windows PowerShell' })
      '{{SHELL_VERSION}}'    = $(if ($pwshV -ne 'not installed') { $pwshV } else { "$($PSVersionTable.PSVersion)" })
      '{{CLAUDE_INSTALLED}}' = (Get-MemVersion 'Claude Code CLI')
      '{{CODEX_INSTALLED}}'  = (Get-MemVersion 'Codex CLI')
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
      $kept += 'infra_status.md'; $created += 'infra_status.new.md (сравни со старым и перенеси руками)'
    } else {
      [System.IO.File]::WriteAllText($infra, $txt, $enc)
      $created += 'infra_status.md'
    }
  }
  Write-Host ''
  Write-Host '  ── ПАМЯТЬ ПРОЕКТА ─────────────────────────────' -ForegroundColor Cyan
  Write-Host "   папка: $(Hide-Home $Dir)" -ForegroundColor DarkGray
  if ($created.Count) { Write-Host ('   создано: ' + ($created -join ', ')) -ForegroundColor Green }
  if ($kept.Count)    { Write-Host ('   не тронуто (уже было): ' + ($kept -join ', ')) -ForegroundColor DarkGray }
  Write-Host '   Агент прочитает CLAUDE.md и memory\infra_status.md при старте —' -ForegroundColor DarkGray
  Write-Host '   и не будет гадать, что у тебя установлено.' -ForegroundColor DarkGray
  return ,$created
}

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
function Format-StatusLine($r) {
  switch ($r.Status) {
    'READY'    { $icon='[OK] '; $col='Green';    $label='ГОТОВ  ' }
    'REPAIRED' { $icon='[+]  '; $col='Green';    $label='ПОСТАВЛ' }
    'LOGIN'    { $icon='[!]  '; $col='Yellow';   $label='ВОЙТИ  ' }
    'WARN'     { $icon='[~]  '; $col='Yellow';   $label='ВНИМАН.' }
    'ABSENT'   { $icon='[-]  '; $col='DarkGray'; $label='нет    ' }
    'MISSING'  { $icon='[X]  '; $col='Red';      $label='НЕТ    ' }
    'BLOCKED'  { $icon='[X]  '; $col='Red';      $label='ЗАКРЫТ ' }
    'ERROR'    { $icon='[!!] '; $col='Red';      $label='ОШИБКА ' }
    default    { $icon='[?]  '; $col='Gray';     $label=$r.Status }
  }
  $line = "    $icon $label  " + $r.Component.PadRight(22) + ' ' + ($r.Version).PadRight(20) + ' ' + $r.Action
  Write-Host $line -ForegroundColor $col
  if ($r.Details -and $r.Details -ne '-') { Write-Host "           - $($r.Details)" -ForegroundColor DarkGray }
}

# ==========================================================================
#  ЗАПУСК
# ==========================================================================
Write-Banner
Test-NewVersion

# Права администратора: без них winget-установки могут упасть на середине.
$script:IsAdmin = $false
try { $script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
if ($InstallMissing -and -not $script:IsAdmin) {
  Write-Host '  ── ВНИМАНИЕ: запуск БЕЗ прав администратора ───' -ForegroundColor Yellow
  Write-Host '  Установка программ может не пройти.' -ForegroundColor Yellow
  Write-Host '  Если что-то не поставится — закрой окно, запусти «Запустить Vibe.cmd»' -ForegroundColor DarkGray
  Write-Host '  заново и нажми «Да» в окне Windows.' -ForegroundColor DarkGray
  Write-Host ''
}

$script:WingetOk = Test-WingetWorks
$script:SelectedApps = @(); $script:AppFail = @{}; $script:Installed = @{}
$script:AiOk = @{}; $script:AiAccess = $false; $script:ToolBlockers = @()
$script:WinMajor = ''; $script:WinBuild = 0

Write-Host ''
Write-Host '  ══════════════════  ШАГ 1 · СИСТЕМА  ══════════════════' -ForegroundColor Cyan
$CAT0 = 'Система'
try {
  Write-Step 'Свободное место на диске'
  $sd = $env:SystemDrive
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sd'"
  $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
  if     ($freeGB -ge 10) { Add-Result $CAT0 "Диск $sd" 'READY'   "$freeGB ГБ" 'свободно' '' 'disk' }
  elseif ($freeGB -ge 2)  { Add-Result $CAT0 "Диск $sd" 'WARN'    "$freeGB ГБ" 'мало места — стоит почистить' '' 'disk' 'low_space' }
  else                    { Add-Result $CAT0 "Диск $sd" 'BLOCKED' "$freeGB ГБ" 'критически мало — установка может падать' '' 'disk' 'critical_space' }
} catch { Add-Result $CAT0 'Диск' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message 'disk' 'check_failed' }
try {
  Write-Step 'Версия Windows'
  $os = Get-CimInstance Win32_OperatingSystem
  $b = [int]$os.BuildNumber
  $script:WinBuild = $b
  if     ($b -ge 22000) { $script:WinMajor = '11'; Add-Result $CAT0 'Windows' 'READY' "11 (build $b)" 'поддерживается' '' 'windows' }
  elseif ($b -ge 17763) { $script:WinMajor = '10'; Add-Result $CAT0 'Windows' 'READY' "10 (build $b)" 'поддерживается' '' 'windows' }
  else {
    $script:WinMajor = 'old'
    Add-Result $CAT0 'Windows' 'WARN' "build $b" 'старая Windows — winget и приложения могут не работать. Обнови: Параметры → Центр обновления Windows' '' 'windows' 'old_windows'
  }
} catch { Add-Result $CAT0 'Windows' 'WARN' '-' 'не удалось определить версию' $_.Exception.Message 'windows' 'check_failed' }

Write-Host ''
Write-Host '  ══════════════════  ШАГ 2 · ИНСТРУМЕНТЫ  ══════════════════' -ForegroundColor Cyan
$CAT1 = 'Инструменты'
try {
  Write-Step 'WinGet'
  $wgCode = ''
  # Нет или не работает — чиним (только в режиме установки; в «только проверке» не трогаем систему).
  if (-not $script:WingetOk -and $InstallMissing) {
    try { $wgCode = Repair-Winget } catch { $wgCode = 'repair_failed' }
    if ($wgCode -like 'repaired_*') { $script:WingetOk = $true }
  }
  if ($script:WingetOk) {
    # winget.exe в PATH — псевдоним приложения (0 байт в WindowsApps), фильтр
    # Store-заглушек его отсеял бы; версию спрашиваем у него напрямую.
    $wgAct = switch ($wgCode) { 'repaired_register' { 'починен перерегистрацией' } 'repaired_download' { 'поставлен с GitHub Microsoft' } default { 'Работает' } }
    $wgStatus = if ($wgCode) { 'REPAIRED' } else { 'READY' }
    Add-Result $CAT1 'WinGet' $wgStatus (Get-VersionAt (Get-Command winget).Source) $wgAct '' 'winget' $wgCode
  } else {
    $wgFail = if ($wgCode) { $wgCode } else { 'no_winget' }
    Add-Result $CAT1 'WinGet' 'MISSING' '-' 'не работает — установить программы автоматически не выйдет' '' 'winget' $wgFail
  }
} catch { Add-Result $CAT1 'WinGet' 'MISSING' '-' 'не работает' $_.Exception.Message 'winget' $(if ($wgCode) { 'repair_failed' } else { 'no_winget' }) }

Test-Tool $CAT1 'PowerShell 7' 'pwsh' 'Microsoft.PowerShell' 'https://aka.ms/powershell' 'pwsh' $script:PwshPaths
Test-Tool $CAT1 'Git' 'git' 'Git.Git' 'https://git-scm.com/download/win' 'git'
Test-Tool $CAT1 'Node.js LTS' 'node' 'OpenJS.NodeJS.LTS' 'https://nodejs.org' 'node' $script:NodePaths
Test-Tool $CAT1 'Python' 'python' 'Python.Python.3.14' 'https://www.python.org/downloads/windows/' 'python' $script:PythonPaths
Test-Telegram $CAT1

# Недоставленное — одним явным блоком, с тем, что из-за этого не поедет дальше.
$baseBad = @($Results | Where-Object { $_.Category -eq $CAT1 -and $_.Status -in @('MISSING','ERROR','WARN') })
if ($baseBad) {
  Write-Host ''
  Write-Host '  ── ВНИМАНИЕ: инструменты встали не все ──' -ForegroundColor Yellow
  foreach ($bb in $baseBad) {
    Write-Host ("   {0}: {1}" -f $bb.Component, $bb.Action) -ForegroundColor Yellow
    if ($bb.Details -and $bb.Details -ne '-') { Write-Host ("     причина: " + $bb.Details) -ForegroundColor DarkGray }
  }
  if (-not $script:WingetOk -and $InstallMissing) {
    Write-Host ''
    Write-Host '   WinGet — это «Установщик приложений» от Microsoft. Что сделать:' -ForegroundColor Yellow
    Write-Host '    1) Открой Microsoft Store и обнови «Установщик приложений» (App Installer):' -ForegroundColor Yellow
    Write-Host '       https://apps.microsoft.com/detail/9NBLGGH4NNS1' -ForegroundColor Yellow
    Write-Host '       либо скачай его с https://aka.ms/getwinget' -ForegroundColor Yellow
    Write-Host '    2) Запусти «Запустить Vibe.cmd» ещё раз — дальше всё поставится само.' -ForegroundColor Yellow
    Write-Host '   Или поставь программы вручную по ссылкам выше.' -ForegroundColor DarkGray
  }
  $badNames = ($baseBad | ForEach-Object { $_.Component }) -join ' '
  if ($badNames -match 'Node') { Write-Host '   → Gemini CLI ставится через npm и без Node.js не встанет.' -ForegroundColor DarkGray }
  if ($badNames -match 'Git')  { Write-Host '   → Claude Code берёт из Git свой Bash — без Git будет работать криво.' -ForegroundColor DarkGray }
  Write-Host ''
}

Write-Host ''
Write-Host '  ══════════════════  ШАГ 3 · ИИ-ИНСТРУМЕНТЫ  ══════════════════' -ForegroundColor Cyan
$CAT2 = 'ИИ-инструменты'
Select-AndInstallAiApps
$script:NotChosenTxt = if ($ReportOnly -or -not $InstallMissing) { 'не установлен' } else { 'не выбран' }
$cliNote = "$($script:NotChosenTxt) — можно поставить повторным запуском"

Update-ProcessPath
$codex = $null; $claude = $null; $gemini = $null; $codexOutside = $null
try { $codex = Get-Version 'codex' } catch {}
if (-not $codex) { $codexOutside = Find-ExeOutsidePath $script:CodexPaths }
try { $claude = Get-Version 'claude' } catch {}
try { $gemini = Get-Version 'gemini' } catch {}
$codexInstalled = [bool]$codex; $claudeInstalled = [bool]$claude; $geminiInstalled = [bool]$gemini

if ($codexInstalled) { Add-Result $CAT2 'Codex CLI' 'READY' "$codex" 'Установлен' '' 'codex_cli' }
elseif ($codexOutside) { Add-Result $CAT2 'Codex CLI' 'WARN' (Get-VersionAt $codexOutside) 'стоит, но не виден в PATH — открой новое окно' $codexOutside 'codex_cli' 'not_in_path' }
else { Add-NotInstalled $CAT2 'Codex CLI' 'CodexCli' $cliNote 'codex_cli' }
if ($claudeInstalled) { Add-Result $CAT2 'Claude Code CLI' 'READY' "$claude" 'Установлен' '' 'claude_code' }
else { Add-NotInstalled $CAT2 'Claude Code CLI' 'ClaudeCli' $cliNote 'claude_code' }
if ($geminiInstalled) { Add-Result $CAT2 'Gemini CLI' 'READY' "$gemini" 'Установлен' '' 'gemini_cli' }
else { Add-NotInstalled $CAT2 'Gemini CLI' 'GeminiCli' $cliNote 'gemini_cli' }

try {
  Write-Step 'Claude Desktop'
  $claudeDesktop = Get-ClaudeDesktop
  # Пакет Claude Desktop не ставит (из РФ через winget может не скачаться) —
  # только показываем, если он уже стоит.
  if ($claudeDesktop) { Add-Result $CAT2 'Claude Desktop' 'READY' "$($claudeDesktop.Version)" 'установлен' '' 'claude_desktop' }
} catch { Add-Result $CAT2 'Claude Desktop' 'WARN' '-' 'не удалось проверить' $_.Exception.Message 'claude_desktop' 'check_failed' }
$chatgptDesktop = $null
try {
  Write-Step 'ChatGPT'
  $chatgptDesktop = Get-ChatGPTDesktop
  if ($chatgptDesktop) { Add-Result $CAT2 'ChatGPT' 'READY' "$($chatgptDesktop.Version)" 'приложение установлено' '' 'chatgpt' }
  elseif (Test-Path -LiteralPath (Get-WebAppShortcutPath 'ChatGPT')) { Add-Result $CAT2 'ChatGPT' 'READY' '-' 'веб-версия в меню «Пуск» (приложение из Store в РФ не ставится)' '' 'chatgpt' 'web' }
  else { Add-NotInstalled $CAT2 'ChatGPT' 'ChatGPTWeb' "$($script:NotChosenTxt); веб-версия: https://chatgpt.com" 'chatgpt' }
} catch { Add-Result $CAT2 'ChatGPT' 'WARN' '-' 'не удалось проверить' $_.Exception.Message 'chatgpt' 'check_failed' }
$geminiWeb = Test-Path -LiteralPath (Get-WebAppShortcutPath 'Gemini')
if ($geminiWeb) { Add-Result $CAT2 'Gemini' 'READY' '-' 'веб-версия в меню «Пуск»' '' 'gemini_web' }
else { Add-NotInstalled $CAT2 'Gemini' 'GeminiWeb' "$($script:NotChosenTxt); веб-версия: https://gemini.google.com" 'gemini_web' }

Write-Host ''
Write-Host '  ── ПРОВЕРКА РАБОТОСПОСОБНОСТИ ─────────────────' -ForegroundColor Cyan
Test-RuntimeCommand $CAT1 'Git' 'git' @('--version') 'git_run'
Test-RuntimeCommand $CAT1 'Node.js' 'node' @('-e',"process.stdout.write('OK')") 'node_run'
Test-RuntimeCommand $CAT1 'npm' 'npm' @('--version') 'npm_run'
Test-RuntimeCommand $CAT1 'Python' 'python' @('-c',"import ssl, venv; print('OK')") 'python_run' $script:PythonPaths
Test-RuntimeCommand $CAT1 'pip' 'python' @('-m','pip','--version') 'pip_run' $script:PythonPaths

try {
  Write-Step 'Вход в ИИ-агентов'
  $logged = @(); $need = @()
  if ($codexInstalled)  { $c = Test-CodexLogin;  if ($c -eq $true) { $logged += 'Codex' }       elseif ($c -eq $false) { $need += 'Codex → команда: codex login' } }
  if ($claudeInstalled) { $c = Test-ClaudeLogin; if ($c -eq $true) { $logged += 'Claude Code' } elseif ($c -eq $false) { $need += 'Claude Code → запусти claude, затем /login' } }
  if ($geminiInstalled) { $c = Test-GeminiLogin; if ($c -eq $true) { $logged += 'Gemini' }      elseif ($c -eq $false) { $need += 'Gemini → запусти gemini и войди Google-аккаунтом' } }
  if ($logged.Count -gt 0 -and $need.Count -eq 0) { Add-Result $CAT2 'Вход в агентов' 'READY' ($logged -join '; ') 'Вход выполнен' '' 'ai_login' }
  elseif ($logged.Count -gt 0) { Add-Result $CAT2 'Вход в агентов' 'WARN' ($logged -join '; ') ('Часть без входа: ' + ($need -join '; ')) '' 'ai_login' 'partial_login' }
  elseif ($need.Count -gt 0) { Add-Result $CAT2 'Вход в агентов' 'LOGIN' '-' 'НУЖЕН ВХОД' ($need -join '; ') 'ai_login' 'login_needed' }
  else { Add-Result $CAT2 'Вход в агентов' 'ABSENT' '-' 'агенты не установлены — запусти пакет ещё раз и выбери 1, 2 или 3' '' 'ai_login' 'no_agent' }
} catch { Add-Result $CAT2 'Вход в агентов' 'ERROR' '-' 'Проверить вручную' $_.Exception.Message 'ai_login' 'check_failed' }

Write-Host ''
Write-Host '  ══════════════════  ШАГ 4 · ДОСТУП К ИИ-СЕРВИСАМ  ══════════════════' -ForegroundColor Cyan
# Только проверяем, открываются ли сервисы из этой сети. Ничего не настраиваем.
# ok — коды, которые означают «ответил сам сервис». Из России OpenAI и Anthropic
# отвечают 403 с отказом по стране, поэтому 403 в ok не входит (кроме Google:
# там 403 = нет ключа, а отказ по стране узнаём по тексту ответа).
$CAT3 = 'Доступ к ИИ-сервисам'
$script:GeoBlockRe = '(?i)unsupported_country|location is not supported|not available in your (country|region)|country.{0,20}not supported'
$AIEndpoints = @(
  @{n='ChatGPT/Codex (OpenAI)'; k='openai';    u='https://api.openai.com/v1/models';        ok=@(200,401)},
  @{n='Claude (Anthropic)';     k='anthropic'; u='https://api.anthropic.com/v1/messages';   ok=@(200,400,401,405)},
  @{n='Gemini (Google)';        k='gemini';    u='https://generativelanguage.googleapis.com/v1beta/models'; ok=@(200,400,401,403)},
  @{n='ChatGPT (сайт)';         k='';          u='https://chatgpt.com'},
  @{n='GitHub';                 k='github';    u='https://github.com'}
)
$anyAnswer = $false
foreach ($e in $AIEndpoints) {
  try {
    Write-Step "Доступ: $($e.n)"
    $p = $null
    for ($i = 1; $i -le 2; $i++) {
      $p = Invoke-Http $e.u 'GET' $null '' 10
      if ($p.Code) { break }
      Start-Sleep -Milliseconds 800
    }
    $code = $p.Code
    if ($code) { $anyAnswer = $true }
    $body = Get-HttpText $p
    $ok = $false
    if ($e.ok) {
      if ($body -match $script:GeoBlockRe) { Add-Result $CAT3 $e.n 'BLOCKED' '-' "закрыт из этой сети (HTTP $code)" }
      elseif ($e.ok -contains $code)      { $ok = $true; Add-Result $CAT3 $e.n 'READY' '-' "отвечает (HTTP $code)" }
      elseif ($code -eq 403)              { Add-Result $CAT3 $e.n 'BLOCKED' '-' 'закрыт из этой сети (HTTP 403)' }
      elseif ($code)                      { Add-Result $CAT3 $e.n 'WARN' '-' "неожиданный ответ HTTP $code" }
      else                                { Add-Result $CAT3 $e.n 'BLOCKED' '-' 'не отвечает' }
    } else {
      if (-not $code)                         { Add-Result $CAT3 $e.n 'WARN' '-' 'не отвечает' }
      elseif ($body -match $script:GeoBlockRe) { Add-Result $CAT3 $e.n 'WARN' '-' "закрыт из этой сети (HTTP $code)" }
      elseif ($code -eq 403 -and $p.Challenge) { $ok = $true; Add-Result $CAT3 $e.n 'READY' '-' 'доступен (сайт проверяет браузер — это норма)' }
      elseif ($code -eq 403)                   { Add-Result $CAT3 $e.n 'WARN' '-' 'ответ HTTP 403 — открой сайт в браузере и проверь' }
      else                                     { $ok = $true; Add-Result $CAT3 $e.n 'READY' '-' 'доступен' }
    }
    if ($e.k) { $script:AiOk[$e.k] = $ok }
  } catch { Add-Result $CAT3 $e.n 'WARN' '-' 'ошибка проверки' $_.Exception.Message }
}
$script:AiAccess = [bool]($script:AiOk['openai'] -and $script:AiOk['anthropic'])

# ==== ИТОГ =================================================================
Write-Host ''
$okCount = @($Results | Where-Object { $_.Status -in @('READY','REPAIRED') }).Count
$absent = @($Results | Where-Object { $_.Status -eq 'ABSENT' })
$bad = @($Results | Where-Object { $_.Status -notin @('READY','REPAIRED','ABSENT') })
if ($bad.Count) {
  Write-Host '  ── ТРЕБУЕТ ВНИМАНИЯ ───────────────────────────' -ForegroundColor Yellow
  foreach ($cat in @($CAT0,$CAT1,$CAT2,$CAT3)) {
    $rows = @($bad | Where-Object { $_.Category -eq $cat })
    if (-not $rows.Count) { continue }
    Write-Host "  [ $cat ]" -ForegroundColor Cyan
    $rows | ForEach-Object { Format-StatusLine $_ }
  }
  Write-Host ''
}
if ($absent.Count) {
  Write-Host ("  Не ставили: " + (($absent | ForEach-Object { $_.Component }) -join ', ') + " — можно добавить позже повторным запуском") -ForegroundColor DarkGray
}
$checked = $Results.Count - $absent.Count
Write-Host ("  В порядке: $okCount из $checked пунктов" + $(if ($bad.Count) { " · требует внимания: $($bad.Count)" } else { ' — всё' })) -ForegroundColor DarkGray

# Вердикт — по инструментам. Доступ к ИИ-сервисам зависит от сети, а не от
# компьютера, поэтому о нём — отдельное сообщение ниже.
$script:ToolBlockers = @($Results | Where-Object { $_.Category -ne $CAT3 -and $_.Status -in @('MISSING','ERROR','BLOCKED') })
$needLogin = @($Results | Where-Object { $_.Status -eq 'LOGIN' })
if (-not $script:ToolBlockers.Count) {
  $sub = if ($anyAnswer -and -not $script:AiAccess) { 'ИИ-сервисы из этой сети закрыты — см. ниже' }
         elseif ($needLogin.Count) { 'осталось войти в ИИ-агента' } else { 'можно работать' }
  Write-BigBox 'И Н С Т Р У М Е Н Т Ы   Г О Т О В Ы' $sub 'Green'
} else {
  Write-BigBox 'С Р Е Д А   Н Е   Г О Т О В А' 'закрой пункты ниже' 'Red'
  foreach ($b in $script:ToolBlockers) { Write-Host "     - $($b.Component): $($b.Action)" -ForegroundColor Yellow }
  Write-Host ''
}

if (-not $anyAnswer) {
  Write-Host '  ИИ-сервисы не ответили вообще — похоже, нет интернета. Проверь подключение и запусти пакет ещё раз.' -ForegroundColor Yellow
  Write-Host ''
} elseif (-not $script:AiAccess) {
  Write-Host '  ── ДОСТУП К ИИ ────────────────────────────────' -ForegroundColor Cyan
  if (-not $script:ToolBlockers.Count) {
    Write-Host '  Инструменты готовы. Чтобы войти в ChatGPT/Codex из России, нужен доступ —' -ForegroundColor Yellow
  } else {
    Write-Host '  Чтобы войти в ChatGPT/Codex из России, нужен доступ —' -ForegroundColor Yellow
  }
  Write-Host '  как мы его настраиваем, показываем на практикуме:' -ForegroundColor Yellow
  Write-Host "  $($script:PracticumUrl)" -ForegroundColor Cyan
  Write-Host ''
  if ($InstallMissing -and (Test-Interactive)) {
    $ans = Read-Ask 'ОТКРЫТЬ СТРАНИЦУ ПРАКТИКУМА?' '1 — открыть в браузере   ·   Enter — дальше'
    if ($ans -match '^\s*1') { try { Start-Process $script:PracticumUrl -ErrorAction Stop } catch {} }
  }
}

# ---- Папка проекта с памятью агента -----------------------------------------
# Только в режиме установки и с согласия; -ProjectDir — без вопроса (так же для тестов,
# в том числе в режиме проверки). Сбой здесь прогон не роняет.
$script:MemoryDir = $null
$memTarget = $null; $memCode = 'not_selected'
if ($ProjectDir) { $memTarget = $ProjectDir }
elseif ($InstallMissing -and (Test-Interactive)) {
  $ans = Read-Ask 'ЗАВЕСТИ ПАПКУ ПРОЕКТА С ПАМЯТЬЮ АГЕНТА?' '1 — да (~\stereo-vibe: CLAUDE.md + memory\)   ·   2 — не надо'
  Write-Host "   ответ: «$ans»" -ForegroundColor DarkGray
  if ($ans -match '^\s*1') { $memTarget = Join-Path $env:USERPROFILE 'stereo-vibe' } else { $memCode = 'declined' }
}
$memName = 'Папка проекта с памятью агента'
if ($memTarget) {
  try {
    $made = @(Initialize-ProjectMemory $memTarget)
    $script:MemoryDir = $memTarget
    if ($made.Count) { Add-Result 'Проект' $memName 'REPAIRED' '-' (Hide-Home $memTarget) '' 'project_memory' }
    else             { Add-Result 'Проект' $memName 'READY' '-' 'уже была — ничего не перезаписано' '' 'project_memory' }
  } catch {
    Write-Host "   Память проекта завести не вышло: $($_.Exception.Message)" -ForegroundColor Yellow
    Add-Result 'Проект' $memName 'WARN' '-' 'завести не вышло' $_.Exception.Message 'project_memory' 'memory_failed'
  }
} elseif ($InstallMissing) {
  Add-Result 'Проект' $memName 'ABSENT' '-' 'не заводили — можно повторным запуском' '' 'project_memory' $memCode
}

if ($codexInstalled -or $claudeInstalled -or $geminiInstalled) {
  if ($script:MemoryDir) {
    Write-Host '  Как начать: открой НОВОЕ окно PowerShell (Пуск → «Терминал»), перейди в папку' -ForegroundColor DarkGray
    Write-Host "  проекта командой  cd $(Hide-Home $script:MemoryDir)  и набери codex, claude или gemini." -ForegroundColor DarkGray
    Write-Host '  Агент сам прочитает CLAUDE.md и memory\. При первом запуске он попросит войти.' -ForegroundColor DarkGray
  } else {
    Write-Host '  Как начать: открой НОВОЕ окно PowerShell (Пуск → «Терминал»), создай папку' -ForegroundColor DarkGray
    Write-Host '  проекта, перейди в неё и набери codex, claude или gemini. При первом запуске' -ForegroundColor DarkGray
    Write-Host '  агент попросит войти в аккаунт.' -ForegroundColor DarkGray
  }
  Write-Host ''
}

# Локальный JSON-отчёт (с подробностями) — только на этом компьютере.
try { $Results | Select-Object Category,Component,Status,Version,Action,Details | ConvertTo-Json | Set-Content -LiteralPath $JsonPath -Encoding utf8 } catch {}

Send-Summary

Write-Host ''
Write-Host '  Лог этой проверки (только на этом компьютере):' -ForegroundColor DarkGray
Write-Host "     $LogPath" -ForegroundColor DarkGray
Write-Host ''

# Открыть установленное приложение с чатом.
if ((Test-Interactive) -and $InstallMissing) {
  $toOpen = @()
  if ($chatgptDesktop -or (Test-Path -LiteralPath (Get-WebAppShortcutPath 'ChatGPT'))) { $toOpen += 'ChatGPT' }
  if (Get-ClaudeDesktop) { $toOpen += 'Claude' }
  if (Test-Path -LiteralPath (Get-WebAppShortcutPath 'Gemini')) { $toOpen += 'Gemini' }
  if ($toOpen.Count -gt 0) {
    Write-Host '  ── ОТКРЫТЬ ИИ ─────────────────────────────────' -ForegroundColor Cyan
    for ($i = 0; $i -lt $toOpen.Count; $i++) { Write-Host "   [$($i + 1)] $($toOpen[$i])" -ForegroundColor Yellow }
    $appChoice = Read-Ask 'КАКОЕ ПРИЛОЖЕНИЕ ОТКРЫТЬ?' 'номер из списка выше   ·   Enter — закончить'
    if ($appChoice) {
      $appIndex = 0
      if ([int]::TryParse($appChoice, [ref]$appIndex) -and $appIndex -ge 1 -and $appIndex -le $toOpen.Count) {
        $sel = $toOpen[$appIndex - 1]
        if (Start-AiApplication $sel) { Write-Host "   $sel открыт." -ForegroundColor Green }
      } else { Write-Host "   Нет такого варианта: «$appChoice»." -ForegroundColor Yellow }
    }
  }
}

Wait-End
try { Stop-Transcript | Out-Null } catch {}
if ($script:ToolBlockers.Count) { exit 1 } else { exit 0 }
