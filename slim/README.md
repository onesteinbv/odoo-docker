# odoo-docker

This is a base image that does not include Odoo itself. You need to provide both Odoo and your custom modules yourself. Example:

```
FROM ubuntu:22.04 AS wheels
COPY ./odoo/requirements.txt /requirements.txt
COPY ./custom/requirements.txt /custom-requirements.txt
RUN apt-get update \
    && apt-get install -y python3-pip cython3 python3 libldap2-dev libpq-dev libsasl2-dev python3-requests gcc python3-dev \
    && pip install -U pip wheel setuptools \
    && pip wheel -r /requirements.txt -r /curq-requirements.txt --wheel-dir=/wheels

FROM ghcr.io/onesteinbv/odoo-docker:slim
COPY ./odoo /odoo/src/odoo
COPY ./custom /odoo/custom
COPY ./scripts /odoo/scripts
COPY --from=wheels ./wheels /odoo/wheels
RUN pip install --no-cache-dir -r /odoo/src/odoo/requirements.txt -r /odoo/custom/requirements.txt --find-links /odoo/wheels
RUN pip install -e /odoo/src/odoo
RUN rm -rf /odoo/wheels
```

## Scripts

The entrypoint checks for the presence of a script, but are optional.

- `/odoo/scripts/run.sh`: Runs after installing or updating the Odoo database

## Variables

### `$MODE` parameter

 - `Install` - installs modules in `MODULES`, runs the maintenance script (`run.sh`),
   then quits the container. This can be done in an empty database or when it doesn't exist yet.
 - `Update` - updates installed modules, runs the maintenance script (`run.sh`), then
   quits the container. Checks if the database exists.
 - `Run` - does no updating, simply runs Odoo.
 - `InstallAndRun` - installs modules (if needed), updates, runs the maintenance
   script (`run.sh`), then runs Odoo. This is the **default** mode.

### Database environment
The entrypoint exports `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME`
to the matching `PG*` variables so tools like `psql` can be used directly.

### Odoo configuration

See `dockerize/18.0/odoo.cfg.tmpl` for available configuration options. You can set these as environment variables, and they will be substituted into the config file when it's generated. For example, setting `ADMIN_PASSWD` will set the `admin_passwd` option in the config file.
