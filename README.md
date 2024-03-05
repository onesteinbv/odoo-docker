# odoo-docker

Based on: https://github.com/onesteinbv/odoo-bedrock

## Usage modes
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

## Installation methodology
Once the Odoo database is detected, the container will try to find a table
called `curq-state-history`. If this table does not exist, it will be created
and a new record will be added. Every time an update, install or maintenance
is executed, two records are created: the first one with the name
of the state (`Updating`, `Creating`, `Maintenance`), and the second one when
the work is completed (`Ready`).

A running container will check the latest
state, and if it's not `Ready` or `Reset`, will check when the last update happened. If
that exceeds a timeout value, the container will add a `Reset` record, and will
exit with an error, prompting a restart. If the state is `Ready` or `Reset`, the
container run will proceed.

## TODO

* Install apt packages listed in a file like requirements.txt for pipy
* Rebase on the official Odoo 16.0 image for faster installation?