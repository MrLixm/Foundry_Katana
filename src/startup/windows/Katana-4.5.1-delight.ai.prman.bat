:: Katana launcher script
:: variables starting by "U" are only useful in this script and not used by Katana itself
@echo on

:: constants to easily upgrade between versions
set "U_KATANA_VERSION=4.5v1"
set "U_KATANA_HOME=C:\Program Files\Katana%U_KATANA_VERSION%"
set "U_USER_PREFS=Z:\dccs\katana\library\shelf0006\prefs"

:: Katana agnostic config
set "DEFAULT_RENDERER=dl"
set "KATANA_TAGLINE=With 3Delight, Arnold 4.0.0.2, RenderMan 24.3, XGEN"
set KATANA_CATALOG_RECT_UPDATE_BUFFER_SIZE=1
set "KATANA_USER_RESOURCE_DIRECTORY=%U_USER_PREFS%"

set "PATH=%PATH%;%U_KATANA_HOME%\bin";
rem for opscripting :
set "LUA_PATH=%LUA_PATH%;whatever\?.lua"

:: Delight config
set "U_DELIGHT=C:\Program Files\3Delight"
set "DLFK_INSTALL_PATH=%U_DELIGHT%\3DelightForKatana"
set "DL_DISPLAYS_PATH=%U_DELIGHT%\displays"
set "DL_SHADERS_PATH=%U_DELIGHT%\shaders"
set "DLC_KATANA=%DLFK_INSTALL_PATH%\Plugins"
set "PATH=%PATH%;%U_DELIGHT%\bin"
set "KATANA_RESOURCES=%KATANA_RESOURCES%;%DLFK_INSTALL_PATH%"

:: Arnold config
set "U_KTOA_VERSION=ktoa-4.0.0.2-kat4.5-windows"
set "U_KTOA_HOME=C:\Users\lcoll\ktoa\%U_KTOA_VERSION%"
set "ARNOLD_PLUGIN_PATH=%U_KTOA_HOME%\Plugins"
set "PATH=%PATH%;%U_KTOA_HOME%\bin"
set "KATANA_RESOURCES=%KATANA_RESOURCES%;%U_KTOA_HOME%"

:: Prman config
set "U_PRMAN_KATANA_VERSION=katana4.5"
set "U_PRMAN_HOME=C:\Program Files\Pixar\RenderManForKatana-24.3"
set "RMANTREE=C:\Program Files\Pixar\RenderManProServer-24.3"
set "KATANA_RESOURCES=%KATANA_RESOURCES%;%U_PRMAN_HOME%\plugins\%U_PRMAN_KATANA_VERSION%"

:: Xgen configuration
set "U_MAYA_INSTALLATION=C:\Program Files\Autodesk\Maya2020"
set "U_XGEN_LOCATION=%U_MAYA_INSTALLATION%\plug-ins\xgen"
set "PATH=%PATH%;%U_XGEN_LOCATION%;%U_XGEN_LOCATION%\bin;%U_MAYA_INSTALLATION%\bin;"

start "" "%U_KATANA_HOME%\bin\katanaBin.exe"
