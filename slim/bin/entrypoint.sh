#!/bin/bash
set -Eeuo pipefail

# Include common functions and environment variable mappings
. common.sh

# Apply backwards compatibility shims (legacy MODE aliases, etc.)
. compat.sh

# Configuration for `session_db` (https://github.com/OCA/server-tools)
if [[ "${DB_NAME:-False}" != "False" && -z "${SESSION_DB_URI:-}" ]]; then
  SESSION_DB_URI="postgresql://$(Encode "$DB_USER"):$(Encode "$DB_PASSWORD")@$(Encode "$DB_HOST"):$(Encode "$DB_PORT")/$(Encode "$DB_NAME")"
  export SESSION_DB_URI
fi

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
    result="$(psql -XtA -c "SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = 'public' AND tablename <> 'spatial_ref_sys' LIMIT 1;")"
    [[ "$result" != "1" ]]
}

function LegacyDatabaseUserConfigured() {
  if [[ -z "${DB_CLIENT_USER:-}" && -z "${DB_CLIENT_PASSWORD:-}" ]]; then
    return 1
  fi
  if [[ -z "${DB_CLIENT_USER:-}" || -z "${DB_CLIENT_PASSWORD:-}" ]]; then
    echo "COMPAT: Both DB_CLIENT_USER and DB_CLIENT_PASSWORD must be set to enable legacy database-user setup."
    exit 1
  fi
  return 0
}

function EnsureLegacyDatabaseUser() {
  echo "COMPAT: Ensuring legacy database user '$DB_CLIENT_USER' exists..."
  psql -U "$DB_USER" -d postgres \
    -v client_user="$DB_CLIENT_USER" \
    -v client_password="$DB_CLIENT_PASSWORD" <<'SQL' >/dev/null
\set ON_ERROR_STOP on
SELECT format(
  'DO $do$
   BEGIN
     IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = %L) THEN
       CREATE ROLE %I WITH LOGIN PASSWORD %L;
     END IF;
   EXCEPTION
     WHEN duplicate_object THEN NULL;
   END
   $do$',
  :'client_user',
  :'client_user',
  :'client_password'
)
\gexec
SQL
}

function GrantLegacyDatabasePrivileges() {
  echo "COMPAT: Granting legacy database-user privileges..."
  psql -U "$DB_USER" -d "$DB_NAME" \
    -v client_user="$DB_CLIENT_USER" \
    -v db_user="$DB_USER" \
    -v db_name="$DB_NAME" <<'SQL'
\set ON_ERROR_STOP on
SELECT format('GRANT %I TO %I', :'client_user', :'db_user')
\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'client_user')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'db_user')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'client_user')
\gexec
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'db_name')
\gexec
SELECT format('ALTER TABLE %I.%I OWNER TO %I', schemaname, tablename, :'client_user')
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
\gexec
SELECT format('ALTER SEQUENCE %I.%I OWNER TO %I', sequence_schema, sequence_name, :'client_user')
FROM information_schema.sequences
WHERE sequence_schema = 'public'
\gexec
SELECT format('ALTER VIEW %I.%I OWNER TO %I', table_schema, table_name, :'client_user')
FROM information_schema.views
WHERE table_schema = 'public'
\gexec
SQL
}

function InstallOdoo() {
  if [[ "${DB_NAME:-False}" == "False" ]]; then
    echo "Database name not provided. Exiting."
    exit 1
  fi
  if DatabaseExists && ! DatabaseEmpty; then
    echo "Database '$DB_NAME' already exists and is not empty; skipping installation."
    return
  fi
  local flags=()
  if [[ ${WITHOUT_DEMO:-"True"} == "True" ]]; then
    flags+=(--without-demo all)
  fi
  echo "Initializing database '$DB_NAME'...";
  WithCorrectUser "$ODOO_BIN" -c "$ODOO_RC" -d "$DB_NAME" -i "${MODULES:-base}" --stop-after-init --no-http "${flags[@]}"
  echo "Initialization complete."
}

function UpdateOdoo() {
  if [[ "${DB_NAME:-False}" == "False" ]]; then
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

function PreMaintenance() {
  if [ -f "/odoo/scripts/pre.sh" ]; then
    echo "Running pre-maintenance script...";
    WithCorrectUser /odoo/scripts/pre.sh
    echo "Pre-maintenance script complete."
  else
    echo "Pre-maintenance script not found; skipping.";
  fi
}

function PostMaintenance() {
  if [ -f "/odoo/scripts/post.sh" ]; then
    echo "Running post-maintenance script...";
    WithCorrectUser /odoo/scripts/post.sh
    echo "Post-maintenance script complete."
  else
    echo "Post-maintenance script not found; skipping.";
  fi
}

if [[ "${DOCKER:-"false"}" == "true" ]]; then
  SetDockerFileStorePermissions
fi

case ${MODE:="InstallAndRun"} in

  "Install")
    WaitForPostgres
    echo "Installing Odoo..."
    CreateConfigFile
    if LegacyDatabaseUserConfigured; then
      EnsureLegacyDatabaseUser
    fi
    InstallOdoo
    if LegacyDatabaseUserConfigured; then
      GrantLegacyDatabasePrivileges
    fi
    PostMaintenance
    echo "Complete; exiting."
    ;;

  "Update")
    WaitForPostgres
    echo "Updating Odoo..."
    CreateConfigFile
    PreMaintenance
    UpdateOdoo
    PostMaintenance
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
    if LegacyDatabaseUserConfigured; then
      EnsureLegacyDatabaseUser
    fi
    InstallOdoo
    if LegacyDatabaseUserConfigured; then
      GrantLegacyDatabasePrivileges
    fi
    PreMaintenance
    UpdateOdoo
    PostMaintenance
    WithCorrectUser "$@"
    ;;

  *)
    echo "Unknown operation '$MODE'. Exiting..."
    exit 1
    ;;
esac
