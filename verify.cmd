@echo off
cd /d X:\premiumcaption_player
set PUB_CACHE=C:\Users\ABBA AMINU\AppData\Local\Pub\Cache
echo === FORMAT === > verify_log.txt
call X:\Documents\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test >> verify_log.txt 2>&1
echo FORMAT_EXIT=%ERRORLEVEL% >> verify_log.txt
echo === ANALYZE === >> verify_log.txt
call X:\Documents\flutter\bin\flutter.bat analyze --no-pub >> verify_log.txt 2>&1
echo ANALYZE_EXIT=%ERRORLEVEL% >> verify_log.txt
echo === TEST === >> verify_log.txt
call X:\Documents\flutter\bin\flutter.bat test --no-pub >> verify_log.txt 2>&1
echo TEST_EXIT=%ERRORLEVEL% >> verify_log.txt
echo === DONE === >> verify_log.txt
