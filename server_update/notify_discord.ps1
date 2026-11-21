# Отправляет в Discord список обновлённых модов.
# Вызывается из update_mods.bat; список — файл со строками "ID папка new|updated".
param(
  [Parameter(Mandatory = $true)][string]$Webhook,
  [Parameter(Mandatory = $true)][string]$ListFile,
  [string]$ServerName = 'DayZ сервер'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$items = @(Get-Content -LiteralPath $ListFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object {
  $p = $_.Trim() -split '\s+'
  [pscustomobject]@{ Id = $p[0]; Folder = $p[1]; State = $p[2] }
})
if ($items.Count -eq 0) { exit 0 }

# Названия модов и время обновления из мастерской (ключ API не нужен)
$details = @{}
try {
  $body = @{ itemcount = $items.Count }
  for ($i = 0; $i -lt $items.Count; $i++) { $body["publishedfileids[$i]"] = $items[$i].Id }
  $r = Invoke-RestMethod -Method Post -TimeoutSec 15 -Body $body `
    -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
  foreach ($d in $r.response.publishedfiledetails) { $details[[string]$d.publishedfileid] = $d }
} catch {
  Write-Host "[!] Не удалось получить названия модов из Steam: $($_.Exception.Message)"
}

$lines = foreach ($it in $items) {
  $d = $details[$it.Id]
  $name = if ($d -and $d.title) { "$($d.title) ($($it.Folder))" } else { $it.Folder }
  $link = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($it.Id)"
  $what = if ($it.State -eq 'new') { 'установлен' } else { 'обновлён' }
  $line = "• [$name]($link) — $what"
  if ($d -and $d.time_updated) { $line += ", версия от <t:$($d.time_updated):f>" }
  $line
}

$payload = @{
  username = $ServerName
  embeds   = @(@{
    title       = "Обновлены моды: $($items.Count)"
    description = ($lines -join "`n")
    color       = 3066993
    footer      = @{ text = 'Если вас не пускает на сервер — перезапустите Steam / лаунчер, чтобы скачались новые версии.' }
    timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  })
}
$json = $payload | ConvertTo-Json -Depth 6

try {
  Invoke-RestMethod -Method Post -Uri $Webhook -TimeoutSec 15 `
    -ContentType 'application/json; charset=utf-8' `
    -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
  Write-Host "Уведомление отправлено: $($items.Count) мод(ов)."
} catch {
  # Ошибка Discord не должна мешать запуску сервера
  Write-Host "[!] Не удалось отправить уведомление в Discord: $($_.Exception.Message)"
}
