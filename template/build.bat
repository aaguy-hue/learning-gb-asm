cd %0\..\

for %%a in ("%~dp0\.") do set "projectname=%%~nxa"

:: create object file
rgbasm -H -L -o main.o main.asm

:: link object
rgblink -o %projectname%.gb main.o

:: generate sym file with labels
rgblink -n %projectname%.sym main.o

:: "fix" the binary (add metadata and pass nintendo piracy check)
rgbfix -v -p 0xFF %projectname%.gb
