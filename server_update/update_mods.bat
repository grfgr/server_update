@echo off
rem ==== Обновление модов сервера DayZ из мастерской Steam (SteamCMD) ====
rem Скачивает свежие версии модов из mods.txt, копирует их в папку сервера
rem и кладёт ключи модов в <сервер>\keys. Запускайте перед стартом сервера
rem (start_server.bat делает это сам).
setlocal enabledelayedexpansion
chcp 65001 >nul

rem ---- НАСТРОЙКИ: поправьте под себя ----
set "STEAMCMD=C:\steamcmd\steamcmd.exe"
set "STEAM_USER=ваш_логин_steam"
set "SERVER=C:\Program Files (x86)\Steam\steamapps\common\DayZServer"
rem 1 = заодно обновлять сам сервер DayZ
set "UPDATE_SERVER=0"
rem ---------------------------------------

set "STEAMDIR=%~dp0steamcmd_data"
set "CONTENT=%STEAMDIR%\steamapps\workshop\content\221100"
set "LIST=%~dp0mods.txt"

if not exist "%STEAMCMD%" (
  echo [!] Не найден SteamCMD: %STEAMCMD%
  echo     Скачайте steamcmd.zip с developer.valvesoftware.com/wiki/SteamCMD и распакуйте в C:\steamcmd
  pause & exit /b 1
)

rem одна команда SteamCMD на все моды: так быстрее и логин один раз
set "CMD=+force_install_dir "%STEAMDIR%" +login %STEAM_USER%"
for /f "usebackq eol=# tokens=1,2" %%A in ("%LIST%") do (
  set "CMD=!CMD! +workshop_download_item 221100 %%A validate"
)
if "%UPDATE_SERVER%"=="1" set "CMD=!CMD! +force_install_dir "%SERVER%" +app_update 223350 validate"
set "CMD=!CMD! +quit"

echo === Скачиваю моды из мастерской ===
"%STEAMCMD%" !CMD!

echo === Копирую моды на сервер ===
for /f "usebackq eol=# tokens=1,2" %%A in ("%LIST%") do (
  if exist "%CONTENT%\%%A" (
    echo   %%B  ^(id %%A^)
    robocopy "%CONTENT%\%%A" "%SERVER%\%%B" /MIR /R:2 /W:2 /NFL /NDL /NJH /NJS /NP >nul
    for %%K in (keys Keys key Key) do (
      if exist "%SERVER%\%%B\%%K" robocopy "%SERVER%\%%B\%%K" "%SERVER%\keys" *.bikey /R:2 /W:2 /NFL /NDL /NJH /NJS /NP >nul
    )
  ) else (
    echo [!] %%B ^(id %%A^) не скачан: проверьте ID и логин
  )
)
echo === Готово ===
endlocal
