# mbzdb: MusicBrainz support for othe RDBMS

This fork of elliotchance/mbzdb contains patches to make it work with the latest changes made on
the official MusicBrainz schema and replication FTP.

## Basic usage
- Edit `settings.pl` to match your environment.
- Edit `settings_mysql.pl` or `settings_postgresql.pl` to match your database environment.
- Run `./init.pl`

You may need to install the following CPAN modules in order to proceed:
- `perl -MCPAN -e install LWP::UserAgent`
- `perl -MCPAN -e install DBI`
- `perl -MCPAN -e install DBD::Pg`
- `perl -MCPAN -e install DBD::mysql`

## Version log
### v7.0
Changes for allow parts of the init script to run in batch mode and/or in parallel:

- Create tables
  - `./init.pl --action=2 --ask=0`
- Download mbdump:
  - `./init.pl --action=10 --ask=0`
- Uncompress mbdump
  - Using `lbzip2`:
      - `./init.pl --action=11 --ask=0 --bzip="/usr/bin/lbzip2 -d -k -c -v" --pipe-bzip=1  --parallel=1`
      - `lbzip2` seems to better use all cores on single files and gives a 8x speedup. 
  - Using `pbzip2`:
      - `./init.pl --action=11 --ask=0 --bzip="/usr/bin/pbzip2 -m10240 -p16 -r -v" --pipe-bzip=1  --parallel=1`
      - Note at the moment `pbzip2` can't make use of all cores when decompressing MusicBrainz mbdump files.
  
- Load data:
    - `./init.pl --action=4 --ask=0`
  
After that, you can continue the database creation using the 5, 6 & 7 init.pl options from the interactive
menu (indexing, foreign keys creation, plugins initialization).
    
### v5.0
  * Full support for NGS for both PostgreSQL and MySQL.
  * settings.pl is now split so that each backend gets its own relevant settings
    file.
  * A few minor bug fixes.

## Further improvements
Some ideas may be worth looking at:
  * Create primary keys before LOAD  DATA: https://dev.mysql.com/doc/refman/5.6/en/optimizing-innodb-ddl-operations.html
