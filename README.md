# booked-utils
Perl scripts for Booked Scheduler

## booked-user-add.pl
Creates a new user.

### Usage
booked-user-add.pl [OPTION] ... LOGIN PASSWD FIRST_NAME LAST_NAME MAIL [LANG TIMEZONE PHONE ORG POSITION] ...

### Example 1
    $ perl booked-user-add.pl --url=http://www.gnr.com/booked -u admin -p password axl jungle Axl Rose a.rose@gnr.com America/Chicago 0120-777-777 GnR Vocal

### Example 2
Edit booked.csv and booked-user-add.bat, and execute booked-user-add.bat.

## booked-resource-add.pl
Creates a new resource.

### Usage
booked-resource-add.pl [OPTION] ... NAME [SCHEDULE_ID LOCATION CONTACT DESCRIPTION NOTES] ...

### Example 1
    $ perl booked-resource-add.pl --url=http://www.gnr.com/booked \
    -u admin -p password "Reception Room" 1 "White House" 0120-999-999

### Example 2
Edit booked-resource.csv and booked-resource-add.bat, and execute booked-resource-add.bat.

## Licence
[GNU General Public License v3.0](https://github.com/taqueci/booked-utils/blob/master/LICENSE)

## Author
Takeshi Nakamura
