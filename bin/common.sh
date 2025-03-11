#!/bin/bash

function WithCorrectUser() {
  if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
    gosu odoo "$@"
  else
    "$@"
  fi
}

function WaitForPostgres() {
  until pg_isready -h $DB_HOST -p $DB_PORT -t 5 >/dev/null
  do
    echo "Waiting for Postgres server $DB_HOST:$DB_PORT..."
  done
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
