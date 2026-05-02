#!/bin/sh
set -ex

D=/data; P=; K=; PD=; PL=
: "${VXLAN_PORT:=4789}" "${PEERS:=}" "${SS2022_METHOD:=2022-blake3-aes-128-gcm}" "${SS2022_PASSWORD:=YuV9jUXztSPJ4QgMZrFMdw==}"
: "${SS2022_SERVER_PORT:=16384}" "${SS2022_REMOTE_ADDRESS:=127.0.0.1}" "${SS2022_REMOTE_PORT:=$VXLAN_PORT}"
ROUTER_IP=${ROUTER_IP:-$(ip route | awk '/default/ {print $3; exit}')}
: "${ROUTER_IP:?ROUTER_IP is required}"
mkdir -p "$D"

peer() {
  P=$1; case $P in [!A-Za-z_]*|*[!A-Za-z0-9_-]*) echo "Invalid peer: $P" >&2; exit 1;; esac
  K=$(printf '%s' "$P" | tr '[:lower:]-' '[:upper:]_')
  eval "PD=\${${K}_DOMAIN:-}"; eval "PL=\${${K}_LOCAL_VTEP_IP:-}"
  : "${PD:?${K}_DOMAIN is required}" "${PL:?${K}_LOCAL_VTEP_IP is required}"
}

peers() { printf '%s\n' "$PEERS" | tr ',' '\n'; }

if [ -n "${PEERS:-}" ]; then
  pids=
  for P in $(peers); do
    [ -z "$P" ] && continue
    peer "$P"
    cat >"$D/client-$P.json" <<EOF
{
  "server": "$PD",
  "server_port": $SS2022_SERVER_PORT,
  "method": "$SS2022_METHOD",
  "password": "$SS2022_PASSWORD",
  "timeout": 600,
  "locals": [
    {
      "protocol": "tunnel",
      "local_address": "$PL",
      "local_port": $VXLAN_PORT,
      "forward_address": "$SS2022_REMOTE_ADDRESS",
      "forward_port": $SS2022_REMOTE_PORT,
      "mode": "udp_only"
    }
  ]
}
EOF
    sslocal -c "$D/client-$P.json" &
    pids="$pids $!"
  done
  # shellcheck disable=SC2086
  wait $pids
  exit $?
fi

: "${DOMAIN:?DOMAIN is required}" "${VTEP_IP:?VTEP_IP is required}"
cat >"$D/server.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": $SS2022_SERVER_PORT,
  "method": "$SS2022_METHOD",
  "password": "$SS2022_PASSWORD",
  "mode": "tcp_and_udp",
  "timeout": 600
}
EOF

exec ssserver -c "$D/server.json"
