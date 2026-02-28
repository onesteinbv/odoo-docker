#!/bin/bash
set -Eeuo pipefail

# Include common functions and environment variable mappings
. common.sh

export SESSION_DB_URI="postgresql://$(Encode "$DB_USER"):$(Encode "$DB_PASSWORD")@$(Encode "$DB_HOST"):$(Encode "$DB_PORT")/$(Encode "$DB_NAME")"

function SetDockerFileStorePermissions() {
  # Make the Odoo user the owner of the filestore
  echo "Chown /odoo/data/odoo"
  chown -R odoo:odoo /odoo/data
  if [ ! -d "/odoo/data/odoo" ]; then
    mkdir -p /odoo/data/odoo/{addons,filestore,sessions}
  fi
  chown -R odoo:odoo /odoo/data/odoo
}

function DatabaseExists() {
  local db_name
  local result

  db_name="$(echo "$DB_NAME" | sed "s|'|''|g")"
  result="$(PGDATABASE=postgres psql -XtA -c "SELECT 1 FROM pg_database WHERE datname='${db_name}';")"
  [[ "$result" == "1" ]]
}

function DatabaseEmpty() {
    local result
    result="$(psql -XtA -c "SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = 'public' LIMIT 1;")"
    [[ "$result" != "1" ]]
}

function InstallOdoo() {
  if [[ -z $DB_NAME || $DB_NAME == "False" ]]; then
    echo "Database name not provided. Exiting."
    exit 1
  fi
  if DatabaseExists && ! DatabaseEmpty; then
    echo "Database '$DB_NAME' already exists and is not empty; skipping installation."
    return
  fi
  local flags=()
  if [[ ${NO_DEMO:-"True"} == "True" ]]; then
    flags+=(--without-demo all)
  fi
  echo "Initializing database '$DB_NAME'...";
  WithCorrectUser "$ODOO_BIN" -c "$ODOO_RC" -d "$DB_NAME" -i "$MODULES" --stop-after-init --no-http "${flags[@]}"
  echo "Initialization complete."
}

function UpdateOdoo() {
  if [[ -z $DB_NAME || $DB_NAME == "False" ]]; then
    echo "Database name not provided; exiting."
    exit 1
  fi
  if ! DatabaseExists; then
    echo "Database '$DB_NAME' does not exist; exiting."
    exit 1
  fi
  if DatabaseEmpty; then
    echo "Database '$DB_NAME' is empty; exiting."
    exit 1
  fi
  
  echo "Updating database '$DB_NAME'...";
  WithCorrectUser click-odoo-update -c "$ODOO_RC" -d "$DB_NAME"
  echo "Update complete."
}

function PerformMaintenance() {
  if [ -f "/odoo/scripts/run.sh" ]; then
    echo "Running maintenance script...";
    WithCorrectUser /odoo/scripts/run.sh
    echo "Maintenance script complete."
  else
    echo "Maintenance script not found; skipping maintenance.";
  fi
}

if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
  SetDockerFileStorePermissions
fi

case ${MODE:="InstallAndRun"} in

  "Install")
    WaitForPostgres
    echo "Installing Odoo..."
    CreateConfigFile
    InstallOdoo
    PerformMaintenance
    echo "Complete; exiting."
    ;;

  "Update")
    WaitForPostgres
    echo "Updating Odoo..."
    CreateConfigFile
    UpdateOdoo
    PerformMaintenance
    echo "Complete; exiting."
    ;;

  "Run")
    WaitForPostgres
    echo "Running Odoo..."
    CreateConfigFile
    WithCorrectUser "$@"
    ;;

  "InstallAndRun")
    WaitForPostgres
    echo "Installing and running Odoo..."
    CreateConfigFile
    InstallOdoo
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  *)
    echo "Unknown operation '$MODE'. Exiting..."
    exit 1
    ;;
esac
