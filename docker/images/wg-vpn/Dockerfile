FROM debian:bookworm-slim

ENV WG_INTERFACE=wg0 \
    WG_CONFIG_DIR=/var/lib/mullvad/profiles \
    WG_ROTATE_SECONDS=900

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      wireguard-tools \
      iproute2 \
      iptables \
      nftables \
      resolvconf \
      curl \
      jq \
      bash \
      ca-certificates \
      procps \
      coreutils \
      findutils && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/mullvad/profiles /etc/wireguard

COPY docker/images/wg-vpn/entrypoint.sh /usr/local/bin/wg-entrypoint.sh
COPY docker/images/wg-vpn/bootstrap-mullvad.sh /usr/local/bin/bootstrap-mullvad
COPY docker/images/wg-vpn/rotate-wg.sh /usr/local/bin/container-rotate-wg.sh

RUN chmod 0755 /usr/local/bin/wg-entrypoint.sh \
    /usr/local/bin/bootstrap-mullvad \
    /usr/local/bin/container-rotate-wg.sh

ENTRYPOINT ["/usr/local/bin/wg-entrypoint.sh"]
