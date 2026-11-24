# ==== Слежение за обновлениями модов и рестарты сервера DayZ ====
# Запускается из start_server.bat (работает одна копия) и крутится в фоне:
#  - раз в CHECK_MINUTES сверяет моды из mods.txt с мастерской Steam;
#  - если вышло обновление, объявляет рестарт через UPDATE_RESTART_DELAY минут
#    (Discord + предупреждения в чат через RCon), потом выключает сервер;
#    start_server.bat запускает его снова, скачав свежие моды;
#  - если плановый рестарт (раз в RESTART_HOURS) и так будет раньше, отдельного рестарта нет.
# Настройки берутся из config.bat.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot
$LogFile = Join-Path $Root 'watch_updates.log'
$Warnings = @(60, 30, 15, 10, 5, 3, 1)   # за сколько минут предупреждать игроков
$TickSeconds = 20

# ---------------------------------------------------------------- общее

function Log([string]$Text) {
  $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Text
  Write-Host $line
  try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Read-Config {
  $cfg = @{}
  $path = Join-Path $Root 'config.bat'
  foreach ($l in (Get-Content -LiteralPath $path -Encoding UTF8)) {
    if ($l -match '^\s*set\s+"([^=]+)=(.*)"') { $cfg[$Matches[1].Trim()] = $Matches[2] }
  }
  return $cfg
}

function CfgInt([string]$Name, [int]$Default) {
  $v = [string]$script:Cfg[$Name]
  if ($v -match '^\s*\d+\s*$') { return [int]$v }
  return $Default
}

function Get-Mods {
  $mods = @()
  foreach ($l in (Get-Content -LiteralPath (Join-Path $Root 'mods.txt') -Encoding UTF8)) {
    if ($l -match '^\s*(\d+)\s+(\S+)') { $mods += [pscustomobject]@{ Id = $Matches[1]; Folder = $Matches[2] } }
  }
  return $mods
}

# ---------------------------------------------------------------- версии модов

# Что скачано сейчас: SteamCMD хранит время версии каждого мода в appworkshop_221100.acf
function Get-InstalledVersions {
  $result = @{}
  $acf = Join-Path $Root 'steamcmd_data\steamapps\workshop\appworkshop_221100.acf'
  if (-not (Test-Path -LiteralPath $acf)) { return $result }
  $text = [IO.File]::ReadAllText($acf)
  $from = $text.IndexOf('"WorkshopItemsInstalled"')
  if ($from -lt 0) { return $result }
  $to = $text.IndexOf('"WorkshopItemDetails"')
  if ($to -lt $from) { $to = $text.Length }
  $part = $text.Substring($from, $to - $from)
  foreach ($m in [regex]::Matches($part, '"(\d+)"\s*\{[^{}]*?"timeupdated"\s*"(\d+)"')) {
    $result[$m.Groups[1].Value] = [long]$m.Groups[2].Value
  }
  return $result
}

# Что лежит в мастерской: время последней версии и название (ключ API не нужен)
function Get-WorkshopDetails($Ids) {
  $body = @{ itemcount = $Ids.Count }
  for ($i = 0; $i -lt $Ids.Count; $i++) { $body["publishedfileids[$i]"] = $Ids[$i] }
  $r = Invoke-RestMethod -Method Post -TimeoutSec 20 -Body $body `
    -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
  $result = @{}
  foreach ($d in $r.response.publishedfiledetails) {
    if ($d.result -eq 1) { $result[[string]$d.publishedfileid] = $d }
  }
  return $result
}

function Find-OutdatedMods {
  $mods = @(Get-Mods)
  if ($mods.Count -eq 0) { return @() }
  $installed = Get-InstalledVersions
  $remote = Get-WorkshopDetails @($mods | ForEach-Object { $_.Id })
  $outdated = @()
  foreach ($m in $mods) {
    $d = $remote[$m.Id]
    if (-not $d) { continue }
    $have = $installed[$m.Id]
    if (-not $have -or [long]$d.time_updated -gt $have) {
      $title = $m.Folder
      if ($d.title) { $title = "$($d.title) ($($m.Folder))" }
      $outdated += [pscustomobject]@{ Id = $m.Id; Title = $title }
    }
  }
  return $outdated
}

# ---------------------------------------------------------------- сервер

function Get-ServerProcess {
  $exe = Join-Path $script:Cfg['SERVER'] 'DayZServer_x64.exe'
  $all = @(Get-Process -Name DayZServer_x64 -ErrorAction SilentlyContinue)
  foreach ($p in $all) {
    $path = $null
    try { $path = $p.Path } catch { }
    if ($path -and $path -eq $exe) { return $p }
  }
  # путь недоступен (другой пользователь): если сервер один, берём его
  if ($all.Count -eq 1) { return $all[0] }
  return $null
}

function Send-Discord([string]$Title, [string]$Text, [int]$Color) {
  $hook = $script:Cfg['DISCORD_WEBHOOK']
  if (-not $hook) { return }
  $name = $script:Cfg['SERVER_NAME']
  if (-not $name) { $name = 'DayZ сервер' }
  $json = @{
    username = $name
    embeds   = @(@{
      title       = $Title
      description = $Text
      color       = $Color
      timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    })
  } | ConvertTo-Json -Depth 5
  try {
    Invoke-RestMethod -Method Post -Uri $hook -TimeoutSec 15 -ContentType 'application/json; charset=utf-8' `
      -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
  } catch {
    Log "[!] Discord: $($_.Exception.Message)"
  }
}

# ---------------------------------------------------------------- RCon BattlEye

$script:CrcTable = $null
function Get-Crc32([byte[]]$Bytes) {
  if (-not $script:CrcTable) {
    $script:CrcTable = New-Object 'uint32[]' 256
    for ($n = 0; $n -lt 256; $n++) {
      [uint32]$c = $n
      for ($k = 0; $k -lt 8; $k++) {
        if ($c -band 1) { $c = [uint32](([uint32]3988292384) -bxor ($c -shr 1)) } else { $c = [uint32]($c -shr 1) }
      }
      $script:CrcTable[$n] = $c
    }
  }
  [uint32]$crc = 4294967295
  foreach ($b in $Bytes) {
    $crc = [uint32]($script:CrcTable[[int](($crc -bxor $b) -band 255)] -bxor ($crc -shr 8))
  }
  return [uint32]($crc -bxor ([uint32]4294967295))
}

# пакет: 'B' 'E' CRC32(LE) 0xFF тип данные
function New-BEPacket([byte]$Type, [byte[]]$Payload) {
  $body = New-Object 'System.Collections.Generic.List[byte]'
  $body.Add(255); $body.Add($Type)
  if ($Payload) { $body.AddRange($Payload) }
  $bodyArr = $body.ToArray()
  $packet = New-Object 'System.Collections.Generic.List[byte]'
  $packet.Add(66); $packet.Add(69)
  $packet.AddRange([BitConverter]::GetBytes((Get-Crc32 $bodyArr)))
  $packet.AddRange($bodyArr)
  return , $packet.ToArray()
}

function Test-RconEnabled {
  return ([string]$script:Cfg['RCON_PORT'] -match '^\d+$') -and [bool]$script:Cfg['RCON_PASSWORD']
}

function Receive-BEPacket($Udp) {
  $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
  try { return , $Udp.Receive([ref]$ep) } catch { return $null }
}

function Invoke-RCon([string[]]$Commands) {
  $udp = New-Object Net.Sockets.UdpClient
  $udp.Client.ReceiveTimeout = 3000
  try {
    $udp.Connect('127.0.0.1', [int]$script:Cfg['RCON_PORT'])
    $login = New-BEPacket 0 ([Text.Encoding]::ASCII.GetBytes([string]$script:Cfg['RCON_PASSWORD']))
    [void]$udp.Send($login, $login.Length)
    $ok = $null
    for ($i = 0; $i -lt 5 -and $null -eq $ok; $i++) {
      $r = Receive-BEPacket $udp
      if ($r -and $r.Length -ge 9 -and $r[7] -eq 0) { $ok = ($r[8] -eq 1) }
    }
    if ($ok -ne $true) { throw 'RCon: нет ответа или неверный пароль (проверьте RCON_PORT / RCON_PASSWORD)' }

    $seq = 0
    foreach ($cmd in $Commands) {
      $payload = New-Object 'System.Collections.Generic.List[byte]'
      $payload.Add([byte]$seq)
      $payload.AddRange([Text.Encoding]::UTF8.GetBytes($cmd))
      $pkt = New-BEPacket 1 $payload.ToArray()
      [void]$udp.Send($pkt, $pkt.Length)
      for ($i = 0; $i -lt 5; $i++) {
        $r = Receive-BEPacket $udp
        if (-not $r -or $r.Length -lt 9) { break }
        if ($r[7] -eq 2) {
          # сообщение сервера: его надо подтвердить
          $ack = New-BEPacket 2 ([byte[]]@($r[8]))
          [void]$udp.Send($ack, $ack.Length)
          continue
        }
        if ($r[7] -eq 1 -and $r[8] -eq $seq) { break }
      }
      $seq = ($seq + 1) % 256
    }
  } finally {
    $udp.Close()
  }
}

function Say([string]$Text) {
  Log "Игрокам: $Text"
  if (-not (Test-RconEnabled)) { return }
  try { Invoke-RCon @("say -1 $Text") } catch { Log "[!] $($_.Exception.Message)" }
}

function Stop-Server($Proc) {
  if (Test-RconEnabled) {
    try {
      Invoke-RCon @('#shutdown')
      Log 'Отправлен #shutdown'
    } catch {
      Log "[!] $($_.Exception.Message)"
    }
    if ($Proc.WaitForExit(180000)) { return }
    Log '[!] Сервер не выключился за 3 минуты, завершаю процесс'
  } else {
    Log 'RCon не настроен: закрываю окно сервера'
    try { [void]$Proc.CloseMainWindow() } catch { }
    if ($Proc.WaitForExit(60000)) { return }
    Log '[!] Сервер не закрылся за минуту, завершаю процесс'
  }
  try { $Proc.Kill() } catch { }
}

# ---------------------------------------------------------------- основной цикл

if (-not (Test-Path -LiteralPath (Join-Path $Root 'config.bat'))) {
  Write-Host 'Нет config.bat рядом со скриптом. Запустите start_server.bat.'
  exit 1
}

# одна копия на папку
$mutexName = 'Local\DayZModWatcher_' + (($Root -replace '[^A-Za-z0-9]', '_').ToLower())
$mutex = New-Object Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { exit 0 }

try {
  if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 2MB) {
    Remove-Item -LiteralPath $LogFile -Force
  }
} catch { }

$script:Cfg = Read-Config
Log ("Запущено: проверка модов раз в {0} мин, рестарт через {1} мин после обновления, плановый рестарт каждые {2} ч, RCon: {3}" -f `
  (CfgInt 'CHECK_MINUTES' 15), (CfgInt 'UPDATE_RESTART_DELAY' 60), (CfgInt 'RESTART_HOURS' 12), $(if (Test-RconEnabled) { 'да' } else { 'нет' }))

$countdown = $null          # активный отсчёт до рестарта
$lastCheck = Get-Date       # сразу после старта сервера моды свежие
$deferredFor = $null        # о каком отложенном обновлении уже сообщили

while ($true) {
  try {
    $script:Cfg = Read-Config
    $checkMinutes = [Math]::Max(1, (CfgInt 'CHECK_MINUTES' 15))
    $delay = [Math]::Max(1, (CfgInt 'UPDATE_RESTART_DELAY' 60))
    $restartHours = CfgInt 'RESTART_HOURS' 12
    $scriptRestarts = (CfgInt 'SCRIPT_RESTARTS' 1) -eq 1
    $now = Get-Date

    $proc = Get-ServerProcess
    if (-not $proc) {
      if ($countdown) { Log 'Сервер выключен, отсчёт отменён'; $countdown = $null }
      $lastCheck = $now
      Start-Sleep -Seconds $TickSeconds
      continue
    }

    $started = $proc.StartTime
    if ($countdown -and $countdown.ServerStart -ne $started) {
      Log 'Сервер перезапустился сам, отсчёт отменён'
      $countdown = $null
    }

    $planned = $null
    if ($restartHours -gt 0) { $planned = $started.AddHours($restartHours) }

    # плановый рестарт
    if (-not $countdown -and $planned -and $scriptRestarts -and $planned -le $now.AddMinutes($Warnings[0])) {
      $target = $planned
      if ($target -lt $now.AddMinutes(1)) { $target = $now.AddMinutes(1) }
      $countdown = @{ Target = $target; ServerStart = $started; Reason = 'плановый рестарт'; Warned = @{} }
      Log ('Плановый рестарт в {0:HH:mm}' -f $target)
    }

    # проверка обновлений модов
    if (-not $countdown -and ($now - $lastCheck).TotalMinutes -ge $checkMinutes) {
      $lastCheck = $now
      $outdated = @()
      try { $outdated = @(Find-OutdatedMods) } catch { Log "[!] Не удалось проверить моды: $($_.Exception.Message)" }

      if ($outdated.Count -eq 0) {
        Log 'Моды актуальны'
      } else {
        $list = ($outdated | ForEach-Object { "• [$($_.Title)](https://steamcommunity.com/sharedfiles/filedetails/?id=$($_.Id))" }) -join "`n"
        $names = ($outdated | ForEach-Object { $_.Title }) -join ', '
        $target = $now.AddMinutes($delay)

        if ($planned -and $planned -le $target) {
          # плановый рестарт и так раньше: моды обновятся на нём
          $key = "$started|$names"
          if ($deferredFor -ne $key) {
            $deferredFor = $key
            $at = $planned.ToString('HH:mm')
            Log "Обновление ($names) установится на плановом рестарте в $at"
            Send-Discord 'Вышло обновление модов' "$list`n`nУстановится на плановом рестарте в **$at**." 15105570
          }
        } else {
          $countdown = @{ Target = $target; ServerStart = $started; Reason = 'обновление модов'; Warned = @{} }
          $at = $target.ToString('HH:mm')
          Log "Обновление: $names. Рестарт в $at"
          Send-Discord 'Вышло обновление модов' "$list`n`nРестарт сервера в **$at** (через $delay мин)." 15105570
        }
      }
    }

    # отсчёт до рестарта
    if ($countdown) {
      $left = ($countdown.Target - $now).TotalMinutes
      if ($left -le 0) {
        Say "Рестарт сервера! ($($countdown.Reason))"
        Start-Sleep -Seconds 5
        Log "Выключаю сервер: $($countdown.Reason)"
        Stop-Server $proc
        $countdown = $null
        $lastCheck = Get-Date
      } else {
        foreach ($w in ($Warnings | Sort-Object)) {
          if ($left -le $w) {
            if (-not $countdown.Warned.ContainsKey($w)) {
              foreach ($x in $Warnings) { if ($x -ge $w) { $countdown.Warned[$x] = $true } }
              Say "Рестарт сервера через $([Math]::Ceiling($left)) мин ($($countdown.Reason))"
            }
            break
          }
        }
      }
    }
  } catch {
    Log "[!] Ошибка: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds $TickSeconds
}
