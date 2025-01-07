# odoo-docker

## Usage modes

### `$MODE` parameters
The created Docker files can be provided various usage modes by\
setting the "MODE" environment variables. Currently supported modes
are:

 - `InstallOnly` - installs all modules in the MODULES and SERVER_WIDE_MODULES, then 
   performs the operations in the maintenance script (`run.sh`), then quits the 
   container. This is meant for a fresh database.
 - `RunOnly` - Does no updating, simply runs Odoo. This is the only way to run a 
   deployment that has `LIST_DB` set to `"True"`.
 - `UpdateOnly` - updates all installed modules, then performs the operations in the
   maintenance script (`run.sh`) then quits the container. Can be used to update Odoo
   without downtime, provided no locks occur.
 - `InstallAndRun` - installs all modules in the MODULES and SERVER_WIDE_MODULES,
   then performs the operations in the maintenance script (`run.sh`), then runs 
   Odoo. This is the previous run mode.
 - `UpdateAndRun` - updates all modules in the MODULES and SERVER_WIDE_MODULES,
   then performs the operations in the maintenance script (`run.sh`), then runs 
   Odoo.
 - `ForceRunOnly`: Runs Odoo, even while the state table indicates that Odoo is
   not ready. Can be used on existing databases that don't have a state table but
   that do not have to be updated, or when an update crashed and thus did not
   update the state table.
   **USE WITH CAUTION**. When the state table indicates Odoo is not ready, it's possible
   that another pod is installing/updating Odoo.
 - `ForceUpdateOnly`: Updates Odoo, even while the state table indicates that Odoo is
   not ready. Can be used to retry a crashed update, or to update an Odoo that does
   not have a state table yet.
   **USE WITH CAUTION**. When the state table indicates Odoo is not ready, it's possible
   that another pod is installing/updating Odoo.
 - `ForceReadyState`: Sets the state to `Force Ready`, so that future running of any 
   modes acts as if the database is in Ready state. Does not update or run Odoo and 
   quits when done.
   **USE WITH CAUTION**. When the state table indicates Odoo is not ready, it's possible
   that another pod is installing/updating Odoo.
 - `Init`: Similar to Install, with a few differences:
   - exits *without error* if the database already exists or if called using 
     `LIST_DB="True"`. 
   - runs using the admin user, so it can create databases and roles
   - creates a user specifically for this installation. Normal web-exposed pods only
     access using this user.
   This mode is useful in an init container for a RunOnly mode container. If the 
   database already exists, the init container exits, and the run mode container runs 
   as normal. If not, the database is first initialized.

### Possible database states
The ready mechanism adds a table to the Odoo database called `curq_state_history`. This
table contains a unique `id`, a `state`, and a `write_date`. To find the latest entry, find
either the highest `id`, or the latest `write_date`. Possible states are:
- `Creating`: The state table was just created, and has no data yet. This should be
  followed by future state updates.
- `Ready`: Database is ready to use and is not processing installations or updates.
- `Reset`: When an update or anything takes too long, a Run pod will write a `Reset`
 state after the TIMEOUT expires (default 30 minutes)
- `Force Ready`: A user ran one of the Force modes above, and forced a reset of the
  state.

Example of a typical `curq_state_history`:
```
 id |    state     |          write_date           
----+--------------+-------------------------------
  1 | Creating     | 2024-03-13 09:45:37.431489+00
  2 | Ready        | 2024-03-13 09:45:37.44937+00
  3 | Maintenance  | 2024-03-13 09:45:37.466702+00
  4 | Ready        | 2024-03-13 09:46:14.920772+00
  5 | Ready        | 2024-03-13 09:47:07.458505+00
  6 | Maintenance  | 2024-03-13 09:47:07.477133+00
  7 | Ready        | 2024-03-13 09:47:59.572259+00
  8 | Updating     | 2024-03-14 07:40:54.739312+00
  9 | Ready        | 2024-03-14 07:40:57.838795+00
 10 | Maintenance  | 2024-03-14 07:40:57.856779+00
 11 | Ready        | 2024-03-14 07:41:49.042587+00
 12 | Updating     | 2024-03-14 07:48:52.589312+00
 13 | Ready        | 2024-03-14 07:48:55.257637+00
 14 | Maintenance  | 2024-03-14 07:48:55.275775+00
 15 | Ready        | 2024-03-14 07:49:38.972781+00
 16 | Updating     | 2024-03-14 08:01:01.884157+00
 17 | Force Ready  | 2024-03-14 08:01:04.483985+00

(17 rows)
```

## Installation methodology
Once the Odoo database is detected, the container will try to find a table
called `curq-state-history`. If this table does not exist, it will be created
and a new record will be added. Every time an update, install or maintenance
is executed, two records are created: the first one with the name
of the state (`Updating`, `Creating`, `Maintenance`), and the second one when
the work is completed (`Ready`).

A running container will check the latest state, and if it's not `Ready` or `Reset`, 
will check when the last update happened. If that exceeds a timeout value, the 
container will add a `Reset` record, and will exit with an error, prompting a restart. 
If the state is `Ready` or `Reset`, the container run will proceed.

## TODO

* Install apt packages listed in a file like requirements.txt for pipy
* Rebase on the official Odoo 16.0 image for smaller installation?
* Remove secrets (database name, service, user, password, etc) from env variables
* For safety: use another db for the state history checks?