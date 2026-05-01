#!/bin/sh
set -ex
umask 077

D=/data; C=$D/Caddyfile; P=; K=; PD=; PF=; PL=; PP=; PS=; PIDS=
: "${OUTER:=xhttp}" "${XHTTP_PATH:=/tunnel}" "${TEST_PORT:=2000}" "${PEERS:=}"
: "${HY2_UP:=100 mbps}" "${HY2_DOWN:=1000 mbps}" "${HY2_UDP_TIMEOUT:=600s}"
: "${SS2022_METHOD:=2022-blake3-aes-128-gcm}" "${SS2022_PASSWORD:=YuV9jUXztSPJ4QgMZrFMdw==}"
ROUTER_IP=${ROUTER_IP:-$(ip route | awk '/default/ {print $3; exit}')}
: "${ROUTER_IP:?ROUTER_IP is required}"
mkdir -p "$D/caddy"

peer() {
  P=$1; case $P in [!A-Za-z_]*|*[!A-Za-z0-9_-]*) echo "Invalid peer: $P" >&2; exit 1;; esac
  K=$(printf '%s' "$P" | tr '[:lower:]-' '[:upper:]_')
  eval "PD=\${${K}_DOMAIN:-}"; eval "PF=\${${K}_FORWARD_UUID:-}"
  eval "PL=\${${K}_LOCAL_VTEP_IP:-}"; eval "PP=\${${K}_XHTTP_PATH:-}"; eval "PS=\${${K}_SNI:-}"
  [ -n "$PP" ] || PP=$XHTTP_PATH; [ -n "$PS" ] || PS=$PD
  : "${PD:?${K}_DOMAIN is required}" "${PF:?${K}_FORWARD_UUID is required}" "${PL:?${K}_LOCAL_VTEP_IP is required}"
}

first_peer() {
  printf '%s\n' "$PEERS" | tr ',' '\n' | while IFS= read -r P; do
    [ -z "$P" ] && continue
    printf '%s\n' "$P"
    break
  done
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

ensure_cert() {
  if [ ! -s "$D/test.crt" ] || [ ! -s "$D/test.key" ]; then
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -days 3650 -subj "/CN=${DOMAIN}" -keyout "$D/test.key" -out "$D/test.crt"
  fi
}

run_xhttp_client() {
  cat >"$D/client.json" <<EOF
{"log":{"loglevel":"warning","access":"none","error":"/dev/stderr"},"inbounds":[{"tag":"from-router","listen":"${PL}","port":${TEST_PORT},"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":${TEST_PORT},"network":"tcp,udp"}}],"outbounds":[{"tag":"to-server","protocol":"vless","settings":{"address":"${PD}","port":443,"id":"${PF}","encryption":"none"},"streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"serverName":"${PS}","allowInsecure":true,"fingerprint":"chrome"},"xhttpSettings":{"path":"${PP}"}}}],"routing":{"rules":[{"type":"field","inboundTag":["from-router"],"outboundTag":"to-server"}]}}
EOF
  exec xray run -config "$D/client.json"
}

run_xhttp_server() {
  ensure_cert
  cat >"$C" <<EOF
{
    admin off
    auto_https off
    servers :443 {
        protocols h1 h2 h3
    }
}
:443 {
    tls ${D}/test.crt ${D}/test.key
    @xhttp path ${XHTTP_PATH}*
    handle @xhttp {
        reverse_proxy 127.0.0.1:8080 {
            flush_interval -1
        }
    }
    respond "ok" 200
}
EOF
  cat >"$D/server.json" <<EOF
{"log":{"loglevel":"warning","access":"none","error":"/dev/stderr"},"inbounds":[{"tag":"vless-in","listen":"127.0.0.1","port":8080,"protocol":"vless","settings":{"clients":[{"id":"${FORWARD_UUID}"}],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"${XHTTP_PATH}"}}}],"outbounds":[{"tag":"to-router","sendThrough":"${VTEP_IP}","protocol":"freedom","settings":{"redirect":"${ROUTER_IP}:${TEST_PORT}","ipsBlocked":[]}}],"routing":{"rules":[{"type":"field","inboundTag":["vless-in"],"network":"tcp,udp","outboundTag":"to-router"}]}}
EOF
  XDG_DATA_HOME="$D/caddy" caddy run --config "$C" &
  PIDS="$PIDS $!"
  xray run -config "$D/server.json" &
  PIDS="$PIDS $!"
  wait_all
}

run_hy2_client() {
  cat >"$D/client.yaml" <<EOF
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
tcpForwarding:
  - listen: ${PL}:${TEST_PORT}
    remote: ${ROUTER_IP}:${TEST_PORT}
udpForwarding:
  - listen: ${PL}:${TEST_PORT}
    remote: ${ROUTER_IP}:${TEST_PORT}
    timeout: ${HY2_UDP_TIMEOUT}
EOF
  exec hysteria client -c "$D/client.yaml"
}

run_hy2_server() {
  ensure_cert
  cat >"$D/server.yaml" <<EOF
listen: :443
tls:
  cert: ${D}/test.crt
  key: ${D}/test.key
auth:
  type: password
  password: ${FORWARD_UUID}
quic:
  maxIdleTimeout: 60s
disableUDP: false
udpIdleTimeout: ${HY2_UDP_TIMEOUT}
EOF
  exec hysteria server -c "$D/server.yaml"
}

run_ss2022_client() {
  cat >"$D/client.json" <<EOF
{
  "server": "${PD}",
  "server_port": 443,
  "method": "${SS2022_METHOD}",
  "password": "${SS2022_PASSWORD}",
  "timeout": 600,
  "locals": [
    {
      "protocol": "tunnel",
      "local_address": "${PL}",
      "local_port": ${TEST_PORT},
      "forward_address": "${ROUTER_IP}",
      "forward_port": ${TEST_PORT},
      "mode": "tcp_and_udp"
    }
  ]
}
EOF
  exec sslocal -c "$D/client.json"
}

run_ss2022_server() {
  cat >"$D/server.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": 443,
  "method": "${SS2022_METHOD}",
  "password": "${SS2022_PASSWORD}",
  "mode": "tcp_and_udp",
  "timeout": 600
}
EOF
  exec ssserver -c "$D/server.json"
}

if [ -n "${PEERS:-}" ]; then
  P=$(first_peer)
  : "${P:?PEERS must include at least one peer}"
  peer "$P"
  case "$OUTER" in
    xhttp) run_xhttp_client ;;
    hy2) run_hy2_client ;;
    ss2022) run_ss2022_client ;;
    *) echo "Invalid OUTER: $OUTER" >&2; exit 1 ;;
  esac
fi

: "${DOMAIN:?DOMAIN is required}" "${VTEP_IP:?VTEP_IP is required}"
[ -n "${FORWARD_UUID:-}" ] || { [ -s "$D/forward_uuid" ] || xray uuid >"$D/forward_uuid"; FORWARD_UUID=$(cat "$D/forward_uuid"); }
printf '%s' "$FORWARD_UUID" >"$D/forward_uuid"

case "$OUTER" in
  xhttp) run_xhttp_server ;;
  hy2) run_hy2_server ;;
  ss2022) run_ss2022_server ;;
  *) echo "Invalid OUTER: $OUTER" >&2; exit 1 ;;
esac
