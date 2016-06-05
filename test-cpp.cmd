@echo off
echo Cleaning...
if exist dump\cpp rd /s /q dump\cpp

haxelib list | findstr haxe-doctest >NUL
if errorlevel 1 (
    echo Installing [haxe-doctest]...
    haxelib install haxe-doctest
)

haxelib list | findstr hxcpp >NUL
if errorlevel 1 (
    echo Installing [hxcpp]...
    haxelib install hxcpp
)

echo Compiling...
haxe -main hx.strings.TestRunner ^
-lib haxe-doctest ^
-cp src ^
-cp test ^
-dce full ^
-debug ^
-D dump=pretty ^
-cpp target\cpp || goto :eof

echo Testing...
target\cpp\TestRunner-Debug.exe
