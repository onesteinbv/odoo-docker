#!/bin/bash
set -Eeuo pipefail

# Create configuration file from the template
TEMPLATES_DIR=/templates
CONFIG_TARGET=/odoo/odoo.cfg

function WithCorrectUser() {
  if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
    gosu odoo "$@"
  else
    "$@"
  fi
}

function SetDockerFileStorePermissions() {
  # Make the Odoo user the owner of the filestore
  echo "Chown /odoo/data/odoo"
  chown -R odoo:odoo /odoo/data  # Test
  if [ ! -d "/odoo/data/odoo" ]; then
    mkdir "/odoo/data/odoo"
  fi
  chown -R odoo:odoo /odoo/data/odoo
}


function CreateConfigFile() {
    # Check if a config template file exists.
  if [ -z $TEMPLATES_DIR ]; then
    echo "Template folder not defined."
    exit 1
  fi
  if [ ! -e $TEMPLATES_DIR/odoo.cfg.tmpl ]; then
    echo "Template file does not exist."
    exit 1
  fi

  # Create a config file.
  echo "Creating Odoo configuration file...";
  WithCorrectUser dockerize -template $TEMPLATES_DIR/odoo.cfg.tmpl:$CONFIG_TARGET

  # Check that a config file was created.
  if [ ! -e $CONFIG_TARGET ]; then
    echo "Dockerize failed"
    exit 1
  fi
}

function CheckDb() {
  # Check that the database environment variable exists.
  # Pass "Strict" as the first function parameter to indicate that the function
  # should exit providing an error code if the DB_NAME variable is set or valid.
  STRICT=false
  if [[ "$#" -gt  0 ]]; then
    STRICT="$1"
  fi
  if [[ -z "$DB_NAME" || "$DB_NAME" == "False" || "$DB_NAME" == ".*" ]]; then
    echo "No valid DB_NAME environment variable.";
    if [[ $STRICT == "Strict" ]]; then
      exit 1
    fi
  elif [[ $(CheckDbState) == "Not existing" ]]; then
    echo "Database $DB_NAME does not exist.";
    if [[ $STRICT == "Strict" ]]; then
      exit 1
    fi
  fi
}

function CheckModules() {
  # Check that the modules environment variable exists.
  # Pass "Strict" as the first function parameter to indicate that the function
  # should exit providing an error code if the MODULES variable is not set.
  if [[ -z "$MODULES" ]]; then
    echo "No MODULES environment variable.";
    if [[ $1 == "Strict" ]]; then
      exit 1
    else
      MODULES="all";
    fi
  fi
}

function InstallOdoo() {
  # Initialize a new database if it doesn't exist yet.
  # NOTE: Using click-odoo for ease. Either marabunta (camp2camp) and click-odoo
  # (acsone) don't support uninstalling modules.
  echo "Running pre-init script...";
  if [ -f "/odoo/scripts/pre-init.sh" ]; then
    echo "Running /odoo/scripts/pre-init.sh...";
    WithCorrectUser /odoo/scripts/pre-init.sh
    echo "Completed pre-init script."
  else
    echo "Pre-init script /odoo/scripts/pre-init.sh not found; skipping";
  fi

  echo "Initializing database '$DB_NAME'...";
  click-odoo-initdb -c $ODOO_RC -m "$MODULES" -n $DB_NAME --unless-exists --no-demo --cache-max-age -1 --cache-max-size -1 --no-cache --log-level $LOG_LEVEL
  EnsureInstallationTableExists
  WriteState "Ready"
  echo "Initialization complete."
}

function UpdateOdoo() {
  # Update the Odoo modules that have changed since the last update.
  echo "Running pre-update script...";
  WriteState "Updating"
  if [ -f "/odoo/scripts/pre-update.sh" ]; then
    echo "Running /odoo/scripts/pre-update.sh";
    WithCorrectUser /odoo/scripts/pre-update.sh
    echo "Completed pre-update script."
  else
    echo "/odoo/scripts/pre-update.sh not found; skipping";
  fi

  echo "Updating database '$DB_NAME'...";
  click-odoo-update -c $ODOO_RC -d $DB_NAME

  WriteState "Ready"
  echo "Update complete."
}

function PerformMaintenance() {
  # Run maintenance operations
  if [ -f "/odoo/scripts/run.sh" ]; then
    echo "Running maintenance script...";
    WriteState "Maintenance"
    WithCorrectUser /odoo/scripts/run.sh
    WriteState "Ready"
    echo "Maintenance script complete."
  else
    echo "Maintenance script not found; skipping maintenance.";
  fi
}

function WaitForPostgres() {
  until pg_isready -h $DB_HOST -p $DB_PORT -t 5 >/dev/null
  do
    echo "Waiting for Postgres server $DB_HOST:$DB_PORT..."
  done
  unset PGPASSWORD
}

function CheckDbState() {
  RESULT="$(PGPASSWORD=$DB_PASSWORD psql -XtA -U $DB_USER -h $DB_HOST -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")"
  if [ "$RESULT" != '1' ]
  then
      echo "Not existing"
  else
      echo "Existing"
  fi
}

function EnsureInstallationTableExists() {
  RESULT="$(PGPASSWORD=$DB_PASSWORD psql -XtA -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "SELECT to_regclass('curq_state_history');")"
  if [ "$RESULT" != 'curq_state_history' ]
  then
      PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
      "CREATE TABLE curq_state_history (id SERIAL PRIMARY KEY, state VARCHAR(255), write_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP); CREATE INDEX write_date_idx ON curq_state_history (write_date);" >/dev/null
      WriteState "Creating"
  fi
}

function WriteState() {
  PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "INSERT INTO curq_state_history (state) VALUES ('$(echo "$1" | sed "s|'|''|g")');" >/dev/null
}

function GetState() {
  PGPASSWORD=$DB_PASSWORD psql -XtA -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "SELECT state, DATE_PART('minute', CURRENT_TIMESTAMP - write_date)::integer AS delta_t FROM curq_state_history ORDER BY write_date DESC LIMIT 1"
}

function WaitForReadyState() {
  EnsureInstallationTableExists

  TIMEOUT=30
  RESULT=$(GetState)
  IFS='|' read -ra ARRAY_RESULT <<<"$RESULT" ; declare -p ARRAY_RESULT >/dev/null
  OPERATION="${ARRAY_RESULT[0]}"
  MINUTES_SINCE_LAST_UPDATE="${ARRAY_RESULT[1]}"

  while [[ $OPERATION != "Ready" && $OPERATION != "Reset" ]]; do
    if [[ $MINUTES_SINCE_LAST_UPDATE -gt $TIMEOUT ]]; then
      echo "Timeout on update loop. Resetting installation status and restarting container..."
      WriteState "Reset"
      unset PGPASSWORD
      exit 1
    fi

    echo "Waiting for other installation to finish..."
    sleep 10

    RESULT="$(GetState)"
    IFS='|' read -ra ARRAY_RESULT <<<$RESULT; declare -p ARRAY_RESULT >/dev/null
    OPERATION="${ARRAY_RESULT[0]}"
    MINUTES_SINCE_LAST_UPDATE="${ARRAY_RESULT[1]}"
  done
}

if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
  SetDockerFileStorePermissions
fi

case ${MODE:="InstallAndRun"} in

  "InstallOnly")
    echo "Installing Odoo..."
    CreateConfigFile
    CheckModules Strict
    CheckDb
    InstallOdoo
    PerformMaintenance
    ;;

  "UpdateOnly")
    echo "Updating Odoo..."
    CreateConfigFile
    CheckModules
    CheckDb Strict
    WaitForReadyState
    UpdateOdoo
    PerformMaintenance
    ;;

  "RunOnly")
    echo "Running Odoo..."
    CreateConfigFile
    CheckDb Strict
    WaitForReadyState
    WithCorrectUser "$@"
    ;;

  "InstallAndRun")
    echo "Installing and running Odoo..."
    CreateConfigFile
    CheckModules Strict
    CheckDb
    InstallOdoo
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  "UpdateAndRun")
    echo "Updating and running Odoo..."
    CreateConfigFile
    CheckModules
    CheckDb Strict
    WaitForReadyState
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  *)
    echo "Unknown operation '$MODE'. Exiting..."
    exit 1
    ;;
esac
