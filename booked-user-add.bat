@echo off
setlocal

set URL=http://www.example.com/booked
set USER=admin
set PASSWORD=password
set CSV=booked.csv

perl booked-user-add.pl --verbose -l booked.log ^
	--url=%URL% --user=%USER% --password=%PASSWORD% ^
	-c %CSV%

pause
