@echo off
REM Copyright (c) 2016-2017 Vegard IT GmbH, http://vegardit.com
REM SPDX-License-Identifier: Apache-2.0
REM Author: Sebastian Thomschke, Vegard IT GmbH

pushd .

REM cd into project root
cd %~dp0..

echo Cleaning...
if exist dump\lua rd /s /q dump\lua
if exist target\lua rd /s /q target\lua

haxelib list | findstr haxe-doctest >NUL
if errorlevel 1 (
    echo Installing [haxe-doctest]...
    haxelib install haxe-doctest
)

echo Compiling...
haxe -main hx.strings.TestRunner ^
  -lib haxe-doctest ^
  -cp src ^
  -cp test ^
  -dce full ^
  -debug ^
  -D dump=pretty ^
  -D luajit ^
  -lua target\lua\TestRunner.lua
set rc=%errorlevel%
popd
if not %rc% == 0 exit /b %rc%

echo Testing...
lua "%CDP%..\target\lua\TestRunner.lua"
