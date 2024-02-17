@ECHO OFF
REM quick and dirty make file
IF "%~1" == "" GOTO usage
@echo on
ca65 -vvv --cpu 6502 -l build/%1-LST.txt -o  build/%1.o %1.s
ld65 -o build/%1.bin -C memmap.cfg "./build/%1.o" 
@echo off
REM /opt/homebrew/bin/minipro -s -p "W27C512@DIP28" -w  build/%1%.bin
goto :eof

:usage
@echo Usage: %0 ^<file-to-make^>
@echo        Use only the file name without the .s extension 
:
exit /B 1