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
  if [[ -z "$DB_NAME" || "$DB_NAME" == "False" || "$DB_NAME" == ".*" ]]; then
    echo "No valid DB_NAME environment variable.";
    if [[ $1 == "Strict" ]]; then
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
  echo "Initialization complete."
}

function UpdateOdoo() {
  # Update the Odoo modules that have changed since the last update.
  echo "Running pre-update script...";
  if [ -f "/odoo/scripts/pre-update.sh" ]; then
    echo "Running /odoo/scripts/pre-update.sh";
    WithCorrectUser /odoo/scripts/pre-update.sh
    echo "Completed pre-update script."
  else
    echo "/odoo/scripts/pre-update.sh not found; skipping";
  fi

  echo "Updating database '$DB_NAME'...";
  click-odoo-update -c $ODOO_RC -d $DB_NAME
  echo "Update complete."
}

function PerformMaintenance() {
  # Run maintenance operations
  if [ -f "/odoo/scripts/run.sh" ]; then
    echo "Running maintenance script...";
    WithCorrectUser /odoo/scripts/run.sh
    echo "Maintenance script complete."
  else
    echo "Maintenance script not found; skipping maintenance.";
  fi
}

case ${MODE:-"InstallAndRun"} in

  "InstallOnly")
    echo "Installing Odoo..."
    if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
      SetDockerFileStorePermissions
    fi
    CreateConfigFile
    CheckDb
    CheckModules Strict
    InstallOdoo
    PerformMaintenance
    ;;

  "UpdateOnly")
    echo "Updating Odoo..."
    CreateConfigFile
    CheckDb Strict
    CheckModules
    UpdateOdoo
    PerformMaintenance
    ;;

  "RunOnly")
    echo "Running Odoo..."
    CreateConfigFile
    CheckDb Strict
    WithCorrectUser "$@"
    ;;

  "InstallAndRun")
    echo "Installing and running Odoo..."
    if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
      SetDockerFileStorePermissions
    fi
    CreateConfigFile
    CheckDb
    CheckModules Strict
    InstallOdoo
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  "UpdateAndRun")
    echo "Updating and running Odoo..."
    CreateConfigFile
    CheckDb Strict
    CheckModules
    UpdateOdoo
    PerformMaintenance
    WithCorrectUser "$@"
    ;;

  *)
    echo "Unknown operation. Exiting..."
    exit 1
    ;;
esac
