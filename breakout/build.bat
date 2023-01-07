cd %0\..\

for %%a in ("%~dp0\.") do set "projectname=%%~nxa"

rgbasm -H -L -o .\build\main.o .\main.asm
rgblink -o .\build\%projectname%.gb .\build\main.o
rgblink -n .\build\%projectname%.sym .\build\main.o
rgbfix -v -p 0xFF .\build\%projectname%.gb
