#!/bin/bash

function WithCorrectUser() {
  if [[ -n "${DOCKER:-}" && "$DOCKER" == "true" ]]; then
    gosu odoo "$@"
  else
    "$@"
  fi
}

function WaitForPostgres() {
  until pg_isready -h $DB_HOST -p $DB_PORT -t 5 >/dev/null
  do
    echo "Waiting for Postgres server $DB_HOST:$DB_PORT..."
    sleep 1
  done
}

function CreateConfigFile() {
  # Create a config file.
  echo "Creating Odoo configuration file...";
  WithCorrectUser dockerize -template /templates/odoo.cfg.tmpl:/odoo/odoo.cfg

  # Check that a config file was created.
  if [ ! -e /odoo/odoo.cfg ]; then
    echo "Dockerize failed. Failing."
    exit 1
  fi
}
