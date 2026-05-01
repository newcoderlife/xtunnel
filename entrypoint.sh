#!/bin/sh
set -e; umask 077

D=/data; P=; K=; PD=; PF=; PL=; PS=; PIDS=
: "${VXLAN_PORT:=4789}" "${PEERS:=}" "${HY2_UP:=100 mbps}" "${HY2_DOWN:=1000 mbps}" "${HY2_UDP_TIMEOUT:=600s}"
ROUTER_IP=${ROUTER_IP:-$(ip route | awk '/default/ {print $3; exit}')}
: "${ROUTER_IP:?ROUTER_IP is required}"
mkdir -p "$D"

peer() {
  P=$1; case $P in [!A-Za-z_]*|*[!A-Za-z0-9_-]*) echo "Invalid peer: $P" >&2; exit 1;; esac
  K=$(printf '%s' "$P" | tr '[:lower:]-' '[:upper:]_')
  eval "PD=\${${K}_DOMAIN:-}"; eval "PF=\${${K}_FORWARD_UUID:-}"
  eval "PL=\${${K}_LOCAL_VTEP_IP:-}"; eval "PS=\${${K}_SNI:-}"
  [ -n "$PS" ] || PS=$PD
  : "${PD:?${K}_DOMAIN is required}" "${PF:?${K}_FORWARD_UUID is required}" "${PL:?${K}_LOCAL_VTEP_IP is required}"
}

write_client_config() {
  cat >"$D/client-$P.yaml" <<EOF
server: ${PD}:443
auth: ${PF}
tls:
  sni: ${PS}
  insecure: true
transport:
  type: udp
quic:
  maxIdleTimeout: 60s
  keepAlivePeriod: 10s
bandwidth:
  up: ${HY2_UP}
  down: ${HY2_DOWN}
fastOpen: true
udpForwarding:
  - listen: ${PL}:${VXLAN_PORT}
    remote: ${ROUTER_IP}:${VXLAN_PORT}
    timeout: ${HY2_UDP_TIMEOUT}
EOF
}

wait_all() {
  trap 'trap - EXIT TERM INT; set +e; for pid in $PIDS; do kill "$pid" 2>/dev/null; done; wait; exit 143' TERM INT
  set +e
  while :; do
    for pid in $PIDS; do
      kill -0 "$pid" 2>/dev/null || { wait "$pid"; exit $?; }
    done
    sleep 1
  done
}

if [ -n "${PEERS:-}" ]; then
  for P in $(printf '%s\n' "$PEERS" | tr ',' ' '); do
    [ -z "$P" ] && continue
    peer "$P"
    write_client_config
    hysteria client -c "$D/client-$P.yaml" &
    PIDS="$PIDS $!"
  done
  [ -n "$PIDS" ] || { echo "PEERS did not contain any valid peer" >&2; exit 1; }
  wait_all
fi

: "${DOMAIN:?DOMAIN is required}" "${VTEP_IP:?VTEP_IP is required}"
[ -n "${FORWARD_UUID:-}" ] || { [ -s "$D/forward_uuid" ] || cat /proc/sys/kernel/random/uuid >"$D/forward_uuid"; FORWARD_UUID=$(cat "$D/forward_uuid"); }
[ -n "${REVERSE_UUID:-}" ] || { [ -s "$D/reverse_uuid" ] || cat /proc/sys/kernel/random/uuid >"$D/reverse_uuid"; REVERSE_UUID=$(cat "$D/reverse_uuid"); }
printf '%s' "$FORWARD_UUID" >"$D/forward_uuid"; printf '%s' "$REVERSE_UUID" >"$D/reverse_uuid"

if [ ! -s "$D/hysteria.crt" ] || [ ! -s "$D/hysteria.key" ]; then
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -subj "/CN=${DOMAIN}" -keyout "$D/hysteria.key" -out "$D/hysteria.crt"
fi

cat >"$D/server.yaml" <<EOF
listen: :443
tls:
  cert: ${D}/hysteria.crt
  key: ${D}/hysteria.key
auth:
  type: password
  password: ${FORWARD_UUID}
quic:
  maxIdleTimeout: 60s
disableUDP: false
udpIdleTimeout: ${HY2_UDP_TIMEOUT}
EOF

exec hysteria server -c "$D/server.yaml"
