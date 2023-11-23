#!/bin/bash
set -Eeuo pipefail

# allow to customize the UID of the odoo user,
# so we can share the same than the host's.
# If no user id is set, we use 999
# TODO: Big cleanup

# Chown /odoo/data/odoo directory (in case of docker without k8s)
if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then  # Just to be sure I don't break k8s stuff
  echo "Chown /odoo/data/odoo"
  chown -R odoo:odoo /odoo/data  # Test
  if [ ! -d "/odoo/data/odoo" ]; then
    mkdir "/odoo/data/odoo"
  fi
  chown -R odoo:odoo /odoo/data/odoo
fi

# Create configuration file from the template
TEMPLATES_DIR=/templates
CONFIG_TARGET=/odoo/odoo.cfg
if [ -e $TEMPLATES_DIR/odoo.cfg.tmpl ]; then
  echo "Dockerize...";
  if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
    gosu odoo dockerize -template $TEMPLATES_DIR/odoo.cfg.tmpl:$CONFIG_TARGET
  else
    dockerize -template $TEMPLATES_DIR/odoo.cfg.tmpl:$CONFIG_TARGET
  fi
  # Verify
  if [ ! -e $CONFIG_TARGET ]; then
    echo "Dockerize failed"
    exit 1
  fi
else
  echo "No template for odoo.conf found"
  exit 1
fi

# TODO this could (should?) be sourced from file(s) under confd control
#export PGHOST=${DB_HOST}
#export PGPORT=${DB_PORT:-5432}
#export PGUSER=${DB_USER}
#export PGPASSWORD=${DB_PASSWORD}
#export PGDATABASE=${DB_NAME}

if [[ -z "$DB_NAME" || "$DB_NAME" == "False" || "$DB_NAME" == ".*" ]]; then
  echo "No DB_NAME environment variable: Skipping update";
elif [[ -z "$MODULES" ]]; then
  echo "No MODULES environment variable";
else
  # NOTE: Using click-odoo for ease. Either marabunta (camp2camp) and click-odoo (acsone) don't support uninstalling modules.
  echo "Init database";
  if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
    if [ -f "/odoo/scripts/pre-init.sh" ]; then
      echo "Run /odoo/scripts/pre-init.sh";
      gosu odoo /odoo/scripts/pre-init.sh
    else
      echo "/odoo/scripts/pre-init.sh not found; skipping";
    fi
    gosu odoo click-odoo-initdb -c $ODOO_RC -m "$MODULES" -n $DB_NAME --unless-exists --no-demo --cache-max-age -1 --cache-max-size -1 --no-cache --log-level $LOG_LEVEL
    if [ -f "/odoo/scripts/pre-update.sh" ]; then
      echo "Run /odoo/scripts/pre-update.sh";
      gosu odoo /odoo/scripts/pre-update.sh
    else
      echo "/odoo/scripts/pre-update.sh not found; skipping";
    fi
    echo "Update database";
    gosu odoo click-odoo-update -c $ODOO_RC -d $DB_NAME
  else
    if [ -f "/odoo/scripts/pre-init.sh" ]; then
      echo "Run /odoo/scripts/pre-init.sh";
      /odoo/scripts/pre-init.sh
    else
      echo "/odoo/scripts/pre-init.sh not found; skipping";
    fi
    click-odoo-initdb -c $ODOO_RC -m "$MODULES" -n $DB_NAME --unless-exists --no-demo --cache-max-age -1 --cache-max-size -1 --no-cache --log-level $LOG_LEVEL
    if [ -f "/odoo/scripts/pre-update.sh" ]; then
      echo "Run /odoo/scripts/pre-update.sh";
      /odoo/scripts/pre-update.sh
    else
      echo "/odoo/scripts/pre-update.sh not found; skipping";
    fi
    echo "Update database";
    click-odoo-update -c $ODOO_RC -d $DB_NAME
  fi

  if [ -f "/odoo/scripts/run.sh" ]; then
    echo "Run /odoo/scripts/run.sh";
    if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
      gosu odoo /odoo/scripts/run.sh
    else
      /odoo/scripts/run.sh
    fi
  else
    echo "/odoo/scripts/run.sh not found; skipping";
  fi

fi

if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
  exec gosu odoo "$@"
else
  exec "$@"
fi
