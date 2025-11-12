FROM alpine:3.19

ENV TZ=UTC \
    OPENVPN_CONFIG= \
    OPENVPN_EXTRA_ARGS= \
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
      openvpn \
      tzdata \
      util-linux \
      curl && \
    mkdir -p "${OPENVPN_CONFIG_DIR}" "${OPENVPN_STATE_DIR}"

COPY docker/openvpn-gw/entrypoint.sh /entrypoint.sh
COPY docker/openvpn-gw/openvpn-config-switch.sh /usr/local/bin/openvpn-config-switch

RUN chmod +x /entrypoint.sh /usr/local/bin/openvpn-config-switch

ENTRYPOINT ["/entrypoint.sh"]
