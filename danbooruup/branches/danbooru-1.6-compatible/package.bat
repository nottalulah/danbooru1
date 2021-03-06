@echo off
if not "%1"=="release" goto skip
call vim -o install.rdf chrome\content\danbooruup\contents.rdf
:skip
del /f danbooruup.xpi > nul
del /f chrome\danbooruup.jar > nul
cd chrome
zip -9r danbooruup.jar . -x .cvsignore
cd ..
rem components\*.xpt components\*.js
zip -9r danbooruup.xpi chrome.manifest install.rdf chrome\danbooruup.jar defaults
copy /y components\danbooru\danbruac.dll platform\WINNT_x86-msvc\components
copy /y components\danbooru\_xpidlgen\danbooruac.xpt components
rem copy /y components\_xpidlgen\danbooruUpHelper.xpt components
zip -9r danbooruup.xpi components\danbooruUpHelper.js components\danbooruUpJSAutoComplete.js components\*.xpt platform
