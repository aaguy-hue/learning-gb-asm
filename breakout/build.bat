cd %0\..\

for %%a in ("%~dp0\.") do set "projectname=%%~nxa"

rgbasm -H -L -o main.o main.asm
rgblink -o %projectname%.gb main.o
rgblink -n %projectname%.sym main.o
rgbfix -v -p 0xFF %projectname%.gb
