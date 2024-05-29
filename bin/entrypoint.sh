#!/bin/bash
set -Eeuo pipefail

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
    echo "Template folder not defined. Failing."
    exit 1
  fi
  if [ ! -e $TEMPLATES_DIR/odoo.cfg.tmpl ]; then
    echo "Template file does not exist. Failing."
    exit 1
  fi

  # Create a config file.
  echo "Creating Odoo configuration file...";
  WithCorrectUser dockerize -template $TEMPLATES_DIR/odoo.cfg.tmpl:$CONFIG_TARGET

  # Check that a config file was created.
  if [ ! -e $CONFIG_TARGET ]; then
    echo "Dockerize failed. Failing."
    exit 1
  fi
}

function CheckDbVariable() {
  if [[ -z $DB_NAME || $DB_NAME == "False" || $DB_NAME == ".*" ]]; then
    echo "Invalid variable.";
  fi
}

function CheckDbState() {
  RESULT="$(PGPASSWORD="$DB_PASSWORD" psql -XtA -U "$DB_USER" -h "$DB_HOST" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$(echo "$DB_NAME" | sed "s|'|''|g")';")"
  if [ "$RESULT" != '1' ]
  then
      echo "Not existing"
  else
      echo "Existing"
  fi
}

# shellcheck disable=SC2120
function CheckDb() {
  if [[ ${LIST_DB:-"False"} == "True" ]]; then
    return
  fi

  # If the user sets the "Strict" parameter, the function will error
  # out if it finds any issue with the database.
  STRICT=false
  if [[ "$#" -gt  0 ]]; then
    STRICT="$1"
  fi
  DB_NAME_CHECK=$(CheckDbVariable)
  if [[ $DB_NAME_CHECK == "Invalid variable." ]]; then
    if [[ $STRICT == "Strict" ]]; then
      echo "Variable $DB_NAME is an invalid database name. Failing."
      exit 1
    fi
    echo "Variable $DB_NAME is an invalid database name."
  elif [[ $(CheckDbState) == "Not existing" ]]; then
    if [[ $STRICT == "Strict" ]]; then
      echo "Database $DB_NAME does not exist. Failing.";
      exit 1
    fi
    echo "Database $DB_NAME does not exist.";
  else
     echo "Database $DB_NAME exists."
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
}

function EnsureInstallationTableExists() {
  RESULT="$(PGPASSWORD=$DB_PASSWORD psql -XtA -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "SELECT to_regclass('curq_state_history');")"
  if [ "$RESULT" != 'curq_state_history' ]
  then
      echo "State history table does not exist. Creating table..."
      PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
      "CREATE TABLE curq_state_history (id SERIAL PRIMARY KEY, state VARCHAR(255), write_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP); CREATE INDEX write_date_idx ON curq_state_history (write_date);" >/dev/null
      echo "State history table created."
      WriteState "Creating"
  fi
}

function WriteState() {
  STATE_TO_WRITE=$(echo "$1" | sed "s|'|''|g")
  echo "Writing state '$STATE_TO_WRITE' to state history table..."
  PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "INSERT INTO curq_state_history (state) VALUES ('$STATE_TO_WRITE');" >/dev/null
}

function GetState() {
  PGPASSWORD=$DB_PASSWORD psql -XtA -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -c \
  "SELECT state, DATE_PART('minute', CURRENT_TIMESTAMP - write_date)::integer AS delta_t FROM curq_state_history ORDER BY write_date DESC LIMIT 1"
}

function ForceReadyState() {
  echo "Setting 'Force Ready' state..."
  EnsureInstallationTableExists
  RESULT=$(GetState)
  IFS='|' read -ra ARRAY_RESULT <<<"$RESULT" ; declare -p ARRAY_RESULT >/dev/null
  OPERATION="${ARRAY_RESULT[0]}"
  if [[ $OPERATION != "Ready" && $OPERATION != "Reset" && $OPERATION != "Force Ready" ]]; then
    WriteState "Force Ready"
  fi
  echo "'Force Ready' state set."
}

function AbortIfNotReady() {
  EnsureInstallationTableExists
  echo "Checking readiness..."
  RESULT=$(GetState)
  IFS='|' read -ra ARRAY_RESULT <<<"$RESULT" ; declare -p ARRAY_RESULT >/dev/null
  OPERATION="${ARRAY_RESULT[0]}"
  MINUTES_SINCE_LAST_UPDATE="${ARRAY_RESULT[1]}"

  if [[ $OPERATION != "Ready" && $OPERATION != "Reset" && $OPERATION != "Force Ready" ]]; then
    echo "Database is not ready. Failing."
    exit 1
  fi
  echo "Database is ready."
}

function ExitIfListDb() {
  if [[ ${LIST_DB:-"False"} != "False" ]]; then
    if [[ $# -gt 0 && $1 == "Strict" ]]; then
      echo "Mode '$MODE' does not allow LIST_DB being set. Failing."
      exit 1
    fi
    echo "Mode '$MODE' requires no further action due to LIST_DB being set. Exiting."
    exit 0
  fi
}

function ExitIfDbExists() {
  if [[ $(CheckDb) == "Database $DB_NAME exists." ]]; then
    echo "Database $DB_NAME already exists. Exiting."
    exit 0
  fi
}

function WaitForReadyState() {
  if [[ ${LIST_DB:-"False"} != "False" ]]; then
    echo "Skipping readiness check as this is a LIST_DB container."
    return
  fi

  echo "Waiting for readiness..."
  if [[ $(CheckDbVariable) != "Invalid variable." ]]; then
    EnsureInstallationTableExists

    TIMEOUT=30
    RESULT=$(GetState)
    IFS='|' read -ra ARRAY_RESULT <<<"$RESULT" ; declare -p ARRAY_RESULT >/dev/null
    OPERATION="${ARRAY_RESULT[0]}"
    MINUTES_SINCE_LAST_UPDATE="${ARRAY_RESULT[1]}"

    while [[ $OPERATION != "Ready" && $OPERATION != "Reset" && $OPERATION != "Force Ready" ]]; do
      if [[ $MINUTES_SINCE_LAST_UPDATE -gt $TIMEOUT ]]; then
        echo "Timeout on readiness check. Resetting installation status and restarting container..."
        WriteState "Reset"
        exit 1
      fi

      echo "Waiting for other installation to finish..."
      sleep 10

      RESULT="$(GetState)"
      IFS='|' read -ra ARRAY_RESULT <<<$RESULT; declare -p ARRAY_RESULT >/dev/null
      OPERATION="${ARRAY_RESULT[0]}"
      MINUTES_SINCE_LAST_UPDATE="${ARRAY_RESULT[1]}"
    done
  fi
  echo "Ready for use."
}

function EnsureDatabaseUser() {
  cat << EOF | PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d postgres -h $DB_HOST -p $DB_PORT >/dev/null
DO
\$\$
BEGIN
   IF EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE rolname = '$DB_CLIENT_USER') THEN
      RAISE NOTICE 'Role "$DB_CLIENT_USER" already exists. Skipping.';
   ELSE
      BEGIN   -- nested block
         CREATE ROLE "$DB_CLIENT_USER" WITH LOGIN PASSWORD '$DB_CLIENT_PASSWORD';
      EXCEPTION
         WHEN duplicate_object THEN
            RAISE NOTICE 'Role "$DB_CLIENT_USER" was just created by a concurrent transaction. Skipping.';
      END;
   END IF;
END
\$\$;
EOF
}

function GrantPrivileges() {
  cat << EOF | PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT"
DO
\$\$
BEGIN
  EXECUTE FORMAT('GRANT CONNECT ON DATABASE "%s" TO cnpg_pooler_pgbouncer', '$DB_NAME');
  EXECUTE FORMAT('GRANT "%s" TO "%s"', '$DB_CLIENT_USER', '$DB_USER');
  EXECUTE FORMAT('ALTER DATABASE "%s" OWNER TO "%s"', '$DB_NAME', '$DB_CLIENT_USER');
END
\$\$;
EOF
}

function Encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
           [-_.~a-zA-Z0-9] ) o="${c}" ;;
           * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
  SetDockerFileStorePermissions
fi
export SESSION_DB_URI="postgresql://$(Encode "$DB_USER"):$(Encode "$DB_PASSWORD")@$(Encode "$DB_HOST"):$(Encode "$DB_PORT")/$(Encode "$DB_NAME")"

case ${MODE:="InstallAndRun"} in

  "Init")
    echo "Initializing Odoo..."
    ExitIfListDb
    EnsureDatabaseUser
    ExitIfDbExists
    CreateConfigFile
    CheckModules Strict
    InstallOdoo
    GrantPrivileges
    UpdateOdoo
    PerformMaintenance
    echo "Complete. Exiting."
    ;;

  # Should not be used in K8s
  "InstallOnly")
    echo "Installing Odoo..."
    ExitIfListDb Strict
    CreateConfigFile
    CheckModules Strict
    CheckDb
    InstallOdoo
    UpdateOdoo
    PerformMaintenance
    echo "Complete. Exiting."
    ;;

  "UpdateOnly")
    echo "Updating Odoo..."
    ExitIfListDb Strict
    CreateConfigFile
    CheckModules
    CheckDb Strict
    AbortIfNotReady
    UpdateOdoo
    PerformMaintenance
    echo "Complete. Exiting."
    ;;

  "RunOnly")
    echo "Running Odoo..."
    CreateConfigFile
    CheckDb Strict
    WaitForReadyState
    WithCorrectUser "$@"
    ;;

  # Should not be used in K8s
  "InstallAndRun")
    echo "Installing and running Odoo..."
    ExitIfListDb Strict
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
    ExitIfListDb Strict
    CreateConfigFile
    CheckModules
    CheckDb Strict
    WaitForReadyState
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  "ForceRunOnly")
    ExitIfListDb Strict
    echo "Waiting 30 seconds before forcing run...."
    sleep 30
    echo "Running Odoo (forced)..."
    CreateConfigFile
    CheckDb Strict
    ForceReadyState
    WithCorrectUser "$@"
    ;;

  "ForceUpdateOnly")
    ExitIfListDb Strict
    echo "Waiting 30 seconds before forcing update..."
    sleep 30
    echo "Updating Odoo (forced)..."
    CreateConfigFile
    CheckModules
    CheckDb Strict
    ForceReadyState
    UpdateOdoo
    PerformMaintenance
    echo "Complete. Exiting."
    ;;

  "ForceReadyState")
    ExitIfListDb Strict
    echo "Waiting 30 seconds before setting ForceReady state..."
    sleep 30
    echo "Enforcing Ready state on database..."
    CheckDb Strict
    ForceReadyState
    echo "Complete. Exiting."
    ;;

  *)
    echo "Unknown operation '$MODE'. Exiting..."
    exit 1
    ;;
esac
