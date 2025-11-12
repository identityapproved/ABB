FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PROTONVPN_CONNECT="--fastest" \
    PIPX_BIN_DIR=/root/.local/bin \
    PATH="/root/.local/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openvpn \
      curl \
      ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir pipx && \
    /bin/bash -lc "export PIPX_BIN_DIR=${PIPX_BIN_DIR} && python3 -m pipx ensurepath && pipx install protonvpn-cli"

COPY protonvpn-gw/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
