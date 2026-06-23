@echo on
timeout /t 3 /nobreak > NUL
rename paper.exe paper.exe.old
move /y "f:\Rutu\txt\paper_update.exe" paper.exe
start "" paper.exe
