# odoo-docker

Based on: https://github.com/onesteinbv/odoo-bedrock

# Usage modes
The created Docker files can be provided various usage modes by\
setting the "MODE" environment variables. Currently supported modes
are:

 - `InstallOnly` - installs all modules in the MODULES and SERVER_WIDE_MODULES, then 
   performs the operations in the maintenance script (`run.sh`), then quits the 
   container. This is meant for a fresh database.
 - `RunOnly` - Does no updating, simply runs Odoo.
 - `UpdateOnly` - updates all installed modules, then performs the operations in the
   maintenance script (`run.sh`) then quits the container. Can be used to update Odoo
   without downtime, provided no locks occur.
 - `InstallAndRun` - installs all modules in the MODULES and SERVER_WIDE_MODULES,
   then performs the operations in the maintenance script (`run.sh`), then runs 
   Odoo. This is the previous run mode.
 - `UpdateAndRun` - updates all modules in the MODULES and SERVER_WIDE_MODULES,
   then performs the operations in the maintenance script (`run.sh`), then runs 
   Odoo.

# TODO

* Install apt packages listed in a file like requirements.txt for pipy
