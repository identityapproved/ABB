FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PROTONVPN_CONNECT="--fastest"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      protonvpn-cli \
      wireguard-tools \
      openresolv \
      iproute2 \
      curl \
      ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY protonvpn-gw/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
