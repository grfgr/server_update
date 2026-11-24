@echo off
rem ==== Обновить моды и запустить сервер DayZ ====
rem -mod= собирается из mods.txt сам (в том же порядке).
rem Заодно запускает watch_updates.ps1: он раз в CHECK_MINUTES проверяет моды
rem и при обновлении делает рестарт через UPDATE_RESTART_DELAY минут.
setlocal enabledelayedexpansion
chcp 65001 >nul

if not exist "%~dp0config.bat" (
  copy "%~dp0config.example.bat" "%~dp0config.bat" >nul
  echo Создан config.bat. Откройте его, впишите свои настройки и запустите снова.
  pause
  exit /b 1
)
call "%~dp0config.bat"

rem фоновая проверка обновлений (вторая копия сама закроется)
start "DayZ: проверка модов" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch_updates.ps1"

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
