#!/bin/bash

function WaitForPostgres() {
  until pg_isready -h $DB_HOST -p $DB_PORT -t 5 >/dev/null
  do
    echo "Waiting for Postgres server $DB_HOST:$DB_PORT..."
  done
}
