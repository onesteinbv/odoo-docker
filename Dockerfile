FROM docker.io/ubuntu:22.04

ARG PYTHONBIN=python3.10
ARG USER_ID=999

ENV \
  ODOO_VERSION=16.0 \
  ODOO_BIN=odoo \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive \
  KWKHTMLTOPDF_SERVER_URL=http://kwkhtmltopdf

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
  && /tmp/install/post-install-clean.sh

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

RUN set -x \
  && /tmp/install/arm64-odoo-requirements.sh \
  && rm -r /tmp/install

RUN pip install click-odoo-contrib awscli

COPY ./dockerize/${ODOO_VERSION} /templates
COPY ./bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*

ENV ADDONS_PATH=/odoo/src/odoo/addons,/odoo/src/odoo/odoo/addons,/odoo/custom

EXPOSE 8069 8072
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["odoo"]
