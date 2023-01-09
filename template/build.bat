cd %0\..\

for %%a in ("%~dp0\.") do set "projectname=%%~nxa"

:: create object file
rgbasm -H -L -o .\build\main.o main.asm

:: link object
rgblink -o .\build\%projectname%.gb .\build\main.o

:: create template.sym, which shows labels and what they correspond to
rgblink -n .\build\%projectname%.sym .\build\main.o

:: create template.map, which I think stores a memory map
rgblink  -m .\build\%projectname%.map .\build\main.o

:: "fix" the binary (add metadata and pass nintendo piracy check)
rgbfix -v -p 0xFF .\build\%projectname%.gb
