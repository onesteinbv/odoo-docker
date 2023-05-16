FROM ghcr.io/acsone/odoo-bedrock:16.0-py310-latest

COPY ./custom/odoo /odoo/src/odoo
RUN apt-get update && apt-get install gcc python3-dev -y --no-install-recommends
RUN \
  pip install --no-cache-dir \
    -r /odoo/src/odoo/requirements.txt \
    -f https://wheelhouse.acsone.eu/manylinux2014
RUN pip install -e /odoo/src/odoo

COPY ./package /odoo/custom
COPY ./requirements.txt ./custom/requirements.tx[t] /odoo/custom/
RUN pip install --no-cache-dir -r /odoo/custom/requirements.txt
RUN pip install click-odoo-contrib
COPY ./custom/script[s]/ /odoo/scripts/
COPY ./bin/entrypoint.sh /usr/local/bin/entrypoint.sh

ENV ADDONS_PATH=/odoo/src/odoo/addons,/odoo/src/odoo/odoo/addons,/odoo/custom
