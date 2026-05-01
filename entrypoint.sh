#!/bin/sh
set -ex

D=/data; P=; K=; PD=; PL=
: "${VXLAN_PORT:=4789}" "${PEERS:=}" "${OUTER:=udp2faketcp}" "${FAKETCP_PORT:=443}" "${FAKETCP_MTU:=1440}"
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

setup_phantun() {
  IPTABLES=iptables
  if command -v iptables-legacy >/dev/null 2>&1; then
    IPTABLES=iptables-legacy
  fi
  sysctl -w net.ipv4.ip_forward=1 || true
  if [ -n "${PEERS:-}" ]; then
    "$IPTABLES" -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  else
    "$IPTABLES" -t nat -A PREROUTING -p tcp -i eth0 --dport "$FAKETCP_PORT" -j DNAT --to-destination "${PHANTUN_TUN_PEER:-192.168.201.2}"
  fi
}

run_client() {
  peer "$1"
  case "$OUTER" in
    phantun)
      setup_phantun
      exec phantun_client --ipv4-only --tun tun0 --local "$PL:$VXLAN_PORT" --remote "$PD:$FAKETCP_PORT"
      ;;
    udp2faketcp)
      exec udp2faketcp --client --listen "$PL:$VXLAN_PORT" --remote "$PD:$FAKETCP_PORT" --mtu "$FAKETCP_MTU"
      ;;
    *) echo "Invalid OUTER: $OUTER" >&2; exit 1 ;;
  esac
}

run_server() {
  case "$OUTER" in
    phantun)
      setup_phantun
      exec phantun_server --ipv4-only --tun tun0 --local "$FAKETCP_PORT" --remote "$ROUTER_IP:$VXLAN_PORT"
      ;;
    udp2faketcp)
      exec udp2faketcp --server --listen "0.0.0.0:$FAKETCP_PORT" --remote "$ROUTER_IP:$VXLAN_PORT" --mtu "$FAKETCP_MTU"
      ;;
    *) echo "Invalid OUTER: $OUTER" >&2; exit 1 ;;
  esac
}

if [ -n "${PEERS:-}" ]; then
  first_peer=
  for P in $(peers); do
    [ -z "$P" ] && continue
    first_peer=$P
    break
  done
  : "${first_peer:?PEERS must include at least one peer}"
  run_client "$first_peer"
fi

: "${DOMAIN:?DOMAIN is required}" "${VTEP_IP:?VTEP_IP is required}"
run_server
