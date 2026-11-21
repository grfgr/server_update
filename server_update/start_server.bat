@echo off
rem ==== Обновить моды и запустить сервер DayZ ====
rem -mod= собирается из mods.txt сам (в том же порядке).
setlocal enabledelayedexpansion
chcp 65001 >nul

rem ---- НАСТРОЙКИ ----
set "SERVER=C:\Program Files (x86)\Steam\steamapps\common\DayZServer"
set "PROFILES=profiles"
set "CONFIG=serverDZ.cfg"
set "PORT=2302"
rem 1 = перезапускать сервер, если он упал или выключился по рестарту
set "AUTO_RESTART=1"
rem -------------------

:start
call "%~dp0update_mods.bat"

set "MODS="
for /f "usebackq eol=# tokens=1,2" %%A in ("%~dp0mods.txt") do (
  if defined MODS (set "MODS=!MODS!;%%B") else (set "MODS=%%B")
)

echo === Запуск сервера: -mod=!MODS! ===
cd /d "%SERVER%"
start /wait "" DayZServer_x64.exe -config=%CONFIG% -port=%PORT% -profiles=%PROFILES% "-mod=!MODS!" -dologs -adminlog -netlog -freezecheck

if "%AUTO_RESTART%"=="1" (
  echo Сервер остановлен, перезапуск через 10 секунд... ^(Ctrl+C — отмена^)
  timeout /t 10
  goto start
)
endlocal
