#!/bin/bash
set -Eeuo pipefail

# allow to customize the UID of the odoo user,
# so we can share the same than the host's.
# If no user id is set, we use 999
USER_ID=${LOCAL_USER_ID:-999}

# Create configuration file from the template
ls -l /templates
TEMPLATES_DIR=/templates
CONFIG_TARGET=/odoo/odoo.cfg
if [ -e $TEMPLATES_DIR/odoo.cfg.tmpl ]; then
  echo "Dockerize...";
  dockerize -template $TEMPLATES_DIR/odoo.cfg.tmpl:$CONFIG_TARGET
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
export PGHOST=${DB_HOST}
export PGPORT=${DB_PORT:-5432}
export PGUSER=${DB_USER}
export PGPASSWORD=${DB_PASSWORD}
export PGDATABASE=${DB_NAME}

echo "Starting with UID: $USER_ID"

# TODO: We don't care about this we use click-odoo. Can be removed
BASE_CMD=$(basename $1)
if [ "$BASE_CMD" = "odoo" ] || [ "$BASE_CMD" = "odoo.py" ] || [ "$BASE_CMD" = "odoo-bin" ] || [ "$BASE_CMD" = "openerp-server" ] ; then
  START_ENTRYPOINT_DIR=/odoo/start-entrypoint.d
  if [ -d "$START_ENTRYPOINT_DIR" ]; then
    run-parts --verbose "$START_ENTRYPOINT_DIR"
  fi
fi

if [[ -z "$DB_NAME" || "$DB_NAME" == "False" ]]; then
  echo "No DB_NAME environment variable: Skipping update";
elif [[ -z "$MODULES" ]]; then
  echo "No MODULES environment variable";
else
  # NOTE: Using click-odoo for ease. Either marabunta (camp2camp) and click-odoo (acsone) don't support uninstalling modules.
  echo "Init / update database";
  click-odoo-initdb -c $ODOO_RC -m "$MODULES" -n $DB_NAME --unless-exists --no-demo --cache-max-age -1 --cache-max-size -1
  click-odoo-update -c $ODOO_RC -d $DB_NAME

  if [ -f "/odoo/scripts/run.sh" ]; then
    /odoo/scripts/run.sh
  else
    echo "/odoo/scripts/run.sh not found; skipping";
  fi

fi

exec "$@"
