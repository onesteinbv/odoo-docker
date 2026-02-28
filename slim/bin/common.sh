#!/bin/bash

# Map environment variables to Postgres client environment variables for convenience.
export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$DB_USER"
export PGPASSWORD="$DB_PASSWORD"
export PGDATABASE="$DB_NAME"

function WithCorrectUser() {
  if [[ -n "$DOCKER" && "$DOCKER" == "true" ]]; then
    gosu odoo "$@"
  else
    "$@"
  fi
}

function WaitForPostgres() {
  until pg_isready -t 5 >/dev/null
  do
    echo "Waiting for Postgres server $PGHOST:$PGPORT..."
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
