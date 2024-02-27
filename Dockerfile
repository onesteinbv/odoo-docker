FROM docker.io/ubuntu:22.04
MAINTAINER Onestein

ARG PYTHONBIN=python3.10
ARG USER_ID=999

ENV \
  ODOO_VERSION=16.0 \
  ODOO_BIN=odoo \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive \
  KWKHTMLTOPDF_SERVER_URL=http://kwkhtmltopdf

# odoo config file
COPY ./dockerize/${ODOO_VERSION} /templates

COPY ./install /tmp/install
RUN set -x \
  && /tmp/install/pre-install.sh \
  && /tmp/install/tools.sh \
  && /tmp/install/confd.sh \
  && /tmp/install/gosu.sh \
  && /tmp/install/python3.sh \
  && /tmp/install/wkhtmltopdf.sh \
  && /tmp/install/pgdg.sh \
  && /tmp/install/dockerize.sh \
  && /tmp/install/arm64.sh \
  && /tmp/install/post-install-clean.sh \
  && rm -r /tmp/install

# isolate from system python libraries
RUN set -x \
  && $PYTHONBIN -m venv /odoo \
  && /odoo/bin/pip install -U pip wheel setuptools
ENV PATH=/odoo/bin:$PATH

RUN adduser --home /odoo --disabled-password --shell /bin/bash -u 999 --gecos "" odoo
RUN mkdir -p /odoo
RUN touch /odoo/odoo.cfg
RUN chown -R odoo:odoo /odoo

ENV OPENERP_SERVER=/odoo/odoo.cfg
ENV ODOO_RC=/odoo/odoo.cfg

COPY ./custom/odoo /odoo/src/odoo
RUN \
  pip install --no-cache-dir \
    -r /odoo/src/odoo/requirements.txt \
    -f https://wheelhouse.acsone.eu/manylinux2014
RUN pip install -e /odoo/src/odoo

COPY ./package /odoo/custom
COPY ./requirements.txt ./custom/requirements.tx[t] /odoo/custom/
RUN pip install --no-cache-dir -r /odoo/custom/requirements.txt
RUN pip install click-odoo-contrib
COPY ./custom/scripts/ /odoo/scripts/
COPY ./bin/entrypoint.sh /usr/local/bin/entrypoint.sh

ENV ADDONS_PATH=/odoo/src/odoo/addons,/odoo/src/odoo/odoo/addons,/odoo/custom

EXPOSE 8069 8072
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["odoo"]
