FROM alpine:3.19

ENV TZ=UTC \
    OPENVPN_CONFIG= \
    OPENVPN_EXTRA_ARGS= \
    OPENVPN_AUTH_FILE= \
    OPENVPN_AUTH_USER= \
    OPENVPN_AUTH_PASS= \
    OPENVPN_SRC_DIR=/opt/openvpn-configs \
    OPENVPN_CONFIG_DIR=/etc/openvpn/configs \
    OPENVPN_ACTIVE_CONFIG=/etc/openvpn/configs/active.ovpn \
    OPENVPN_STATE_DIR=/var/run/openvpn

RUN apk add --no-cache \
      bash \
      ca-certificates \
      coreutils \
      iproute2 \
      iptables \
      ip6tables \
      openresolv \
      openvpn \
      tzdata \
      util-linux \
      curl && \
    mkdir -p "${OPENVPN_CONFIG_DIR}" "${OPENVPN_STATE_DIR}"

COPY openvpn-gw/entrypoint.sh /entrypoint.sh
COPY openvpn-gw/openvpn-config-switch.sh /usr/local/bin/openvpn-config-switch
COPY openvpn-gw/update-resolv-conf.sh /etc/openvpn/update-resolv-conf

RUN chmod +x /entrypoint.sh /usr/local/bin/openvpn-config-switch /etc/openvpn/update-resolv-conf

ENTRYPOINT ["/entrypoint.sh"]
