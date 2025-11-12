FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PROTONVPN_CONNECT="--fastest"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openvpn \
      dialog \
      python3-pip \
      python3-setuptools \
      wireguard-tools \
      openresolv \
      iproute2 \
      curl \
      ca-certificates && \
    pip3 install --no-cache-dir protonvpn-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY protonvpn-gw/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
