rem ==== Настройки сервера ====
rem Скопируйте этот файл в config.bat (start_server.bat сделает это сам) и поправьте под себя.
rem config.bat не загружается на GitHub (.gitignore), поэтому логин, вебхук и пароль RCon пишите только в него.

rem ---- SteamCMD и сервер ----
set "STEAMCMD=C:\steamcmd\steamcmd.exe"
rem аккаунт, на котором есть DayZ (без него моды мастерской не скачать)
set "STEAM_USER=ваш_логин_steam"
set "SERVER=C:\Program Files (x86)\Steam\steamapps\common\DayZServer"
rem 1 = при каждом рестарте обновлять и сам сервер DayZ
set "UPDATE_SERVER=0"

rem ---- Запуск ----
set "PROFILES=profiles"
set "CONFIG=serverDZ.cfg"
set "PORT=2302"
rem 1 = перезапускать сервер, если он упал или выключился по рестарту
set "AUTO_RESTART=1"

rem ---- Проверка обновлений и рестарты (watch_updates.ps1) ----
rem как часто проверять моды на обновления, минут
set "CHECK_MINUTES=15"
rem через сколько минут после найденного обновления делать рестарт
set "UPDATE_RESTART_DELAY=60"
rem плановый рестарт каждые N часов работы сервера (0 = плановых рестартов нет)
set "RESTART_HOURS=12"
rem 1 = плановые рестарты делает этот скрипт (с предупреждениями игрокам)
rem 0 = плановые рестарты делает что-то другое (messages.xml, хостинг), скрипт их только учитывает
set "SCRIPT_RESTARTS=1"

rem ---- RCon BattlEye: предупреждения игрокам в чат и мягкое выключение сервера ----
rem Те же значения, что RConPort и RConPassword в battleye\BEServer_x64.cfg. Пусто = без RCon.
set "RCON_PORT="
set "RCON_PASSWORD="

rem ---- Discord ----
rem URL вебхука канала (пусто = без уведомлений)
set "DISCORD_WEBHOOK="
set "SERVER_NAME=DayZ сервер"
