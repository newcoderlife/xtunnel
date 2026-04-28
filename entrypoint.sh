#!/bin/sh
set -ex; umask 077

D=/data; C=$D/Caddyfile; P=; K=; PD=; PF=; PR=; PL=; PP=; PS=; CADDY_PID=; XRAY_PID=
: "${XHTTP_PATH:=/tunnel}" "${VXLAN_PORT:=4789}" "${PEERS:=}"
ROUTER_IP=${ROUTER_IP:-$(ip route | awk '/default/ {print $3; exit}')}
: "${ROUTER_IP:?ROUTER_IP is required}"
mkdir -p "$D/caddy"

peer() {
  P=$1; case $P in [!A-Za-z_]*|*[!A-Za-z0-9_-]*) echo "Invalid peer: $P" >&2; exit 1;; esac
  K=$(printf '%s' "$P" | tr '[:lower:]-' '[:upper:]_')
  eval "PD=\${${K}_DOMAIN:-}"; eval "PF=\${${K}_FORWARD_UUID:-}"; eval "PR=\${${K}_REVERSE_UUID:-}"
  eval "PL=\${${K}_LOCAL_VTEP_IP:-}"; eval "PP=\${${K}_XHTTP_PATH:-}"; eval "PS=\${${K}_SNI:-}"
  [ -n "$PP" ] || PP=$XHTTP_PATH; [ -n "$PS" ] || PS=$PD
  : "${PD:?${K}_DOMAIN is required}" "${PF:?${K}_FORWARD_UUID is required}" "${PR:?${K}_REVERSE_UUID is required}" "${PL:?${K}_LOCAL_VTEP_IP is required}"
}
peers() { printf '%s\n' "$PEERS" | tr ',' '\n'; }
stream() { printf '"streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"serverName":"%s","alpn":["h3"],"fingerprint":"chrome"},"xhttpSettings":{"path":"%s","mode":"auto"}}' "$PS" "$PP"; }
vless() { printf '{"tag":"%s","protocol":"vless","settings":{"address":"%s","port":443,"id":"%s","encryption":"none"' "$1" "$PD" "$2"; [ -z "${3:-}" ] || printf ',"reverse":{"tag":"%s"}' "$3"; printf '},'; stream; printf '}'; }
inbounds() { s=; peers | while IFS= read -r P; do [ -z "$P" ] && continue; peer "$P"; printf '%s{"tag":"from-router-%s","listen":"%s","port":%s,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":%s,"network":"udp"}}' "$s" "$P" "$PL" "$VXLAN_PORT" "$VXLAN_PORT"; s=,; done; }
outbounds() { peers | while IFS= read -r P; do [ -z "$P" ] && continue; peer "$P"; printf ','; vless "to-server-$P" "$PF"; printf ','; vless "reverse-$P" "$PR" "from-server-$P"; printf ',{"tag":"to-router-%s","sendThrough":"%s","protocol":"freedom","settings":{"redirect":"%s:%s","ipsBlocked":[]}}' "$P" "$PL" "$ROUTER_IP" "$VXLAN_PORT"; done; }
rules() { s=; peers | while IFS= read -r P; do [ -z "$P" ] && continue; peer "$P"; printf '%s{"type":"field","inboundTag":["from-router-%s"],"network":"udp","outboundTag":"to-server-%s"},{"type":"field","inboundTag":["from-server-%s"],"network":"udp","outboundTag":"to-router-%s"}' "$s" "$P" "$P" "$P" "$P"; s=,; done; }

if [ -n "${PEERS:-}" ]; then { printf '{"log":{"loglevel":"info","access":"none","error":"/dev/stderr"},"inbounds":['; inbounds; printf '],"outbounds":[{"tag":"block","protocol":"blackhole"}'; outbounds; printf '],"routing":{"rules":['; rules; printf ']}}'; } >"$D/client.json"; exec xray run -config "$D/client.json"; fi

: "${DOMAIN:?DOMAIN is required}" "${VTEP_IP:?VTEP_IP is required}" "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required for Cloudflare DNS-01}"
[ -n "${FORWARD_UUID:-}" ] || { [ -s "$D/forward_uuid" ] || xray uuid >"$D/forward_uuid"; FORWARD_UUID=$(cat "$D/forward_uuid"); }; [ -n "${REVERSE_UUID:-}" ] || { [ -s "$D/reverse_uuid" ] || xray uuid >"$D/reverse_uuid"; REVERSE_UUID=$(cat "$D/reverse_uuid"); }
printf '%s' "$FORWARD_UUID" >"$D/forward_uuid"; printf '%s' "$REVERSE_UUID" >"$D/reverse_uuid"
printf '{\n    log {\n        output stdout\n        level INFO\n    }\n    auto_https disable_redirects\n    servers :443 {\n        protocols h3\n    }\n}\n%s {\n    tls {\n        dns cloudflare {env.CLOUDFLARE_API_TOKEN}\n        resolvers 1.1.1.1\n    }\n    @xhttp path %s*\n    reverse_proxy @xhttp 127.0.0.1:8080 {\n        flush_interval -1\n    }\n    handle {\n        respond "hello" 200\n    }\n}\n' "$DOMAIN" "$XHTTP_PATH" >"$C"
cat >"$D/server.json" <<EOF
{"log":{"loglevel":"info","access":"none","error":"/dev/stderr"},"inbounds":[{"tag":"vless-in","listen":"127.0.0.1","port":8080,"protocol":"vless","settings":{"clients":[{"id":"${FORWARD_UUID}"},{"id":"${REVERSE_UUID}","reverse":{"tag":"to-client"}}],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"${XHTTP_PATH}","mode":"auto"}}},{"tag":"from-router","listen":"${VTEP_IP}","port":${VXLAN_PORT},"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":${VXLAN_PORT},"network":"udp"}}],"outbounds":[{"tag":"block","protocol":"blackhole"},{"tag":"to-router","sendThrough":"${VTEP_IP}","protocol":"freedom","settings":{"redirect":"${ROUTER_IP}:${VXLAN_PORT}","ipsBlocked":[]}}],"routing":{"rules":[{"type":"field","inboundTag":["from-router"],"network":"udp","outboundTag":"to-client"},{"type":"field","inboundTag":["vless-in"],"network":"udp","outboundTag":"to-router"}]}}
EOF

trap 'trap - EXIT TERM INT; set +e; kill "$CADDY_PID" "$XRAY_PID" 2>/dev/null; wait "$CADDY_PID" "$XRAY_PID" 2>/dev/null' EXIT; trap 'exit 143' TERM INT
XDG_DATA_HOME="$D/caddy" caddy run --config "$C" & CADDY_PID=$!; xray run -config "$D/server.json" & XRAY_PID=$!; set +e
while kill -0 "$CADDY_PID" 2>/dev/null && kill -0 "$XRAY_PID" 2>/dev/null; do sleep 1; done
kill -0 "$CADDY_PID" 2>/dev/null || { wait "$CADDY_PID"; exit $?; }
wait "$XRAY_PID"; exit $?
