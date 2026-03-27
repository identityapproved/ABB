#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${WG_CONFIG_DIR:-/var/lib/mullvad/profiles}"
mkdir -p "${CONFIG_DIR}"

TMP_SCRIPT="$(mktemp)"
if ! curl -fsSL "https://raw.githubusercontent.com/mullvad/mullvad-wg.sh/main/mullvad-wg.sh" -o "${TMP_SCRIPT}"; then
  echo "[bootstrap] Failed to download mullvad-wg.sh" >&2
  rm -f "${TMP_SCRIPT}"
  exit 1
fi
chmod 0755 "${TMP_SCRIPT}"

cat <<'EOF'
[bootstrap] Running mullvad-wg.sh inside the VPN container.
[bootstrap] Follow the prompts to authenticate and download fresh Mullvad configs dedicated to Docker.
EOF

if ! "${TMP_SCRIPT}"; then
  echo "[bootstrap] mullvad-wg.sh exited with an error. Check the output above." >&2
  rm -f "${TMP_SCRIPT}"
  exit 1
fi

shopt -s nullglob
found_any=false
for cfg in /etc/wireguard/*.conf; do
  found_any=true
  base="$(basename "${cfg}")"
  install -D -m 0600 "${cfg}" "${CONFIG_DIR}/${base}"
done

rm -f /etc/wireguard/*.conf 2>/dev/null || true
rm -f "${TMP_SCRIPT}"

if [[ "${found_any}" != "true" ]]; then
  echo "[bootstrap] mullvad-wg.sh did not produce any configs. Rerun the bootstrap command." >&2
  exit 1
fi

echo "[bootstrap] Stored $(ls -1 "${CONFIG_DIR}" | wc -l | tr -d ' ') profiles under ${CONFIG_DIR}."
