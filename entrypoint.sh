#!/bin/sh
set -e

: "${PHANTUN_LOCAL:=0.0.0.0:51820}"
: "${PHANTUN_REMOTE:?PHANTUN_REMOTE is required, for example lax.newco.homes:18443}"
: "${PHANTUN_TUN:=phantun0}"
: "${PHANTUN_TUN_LOCAL:=192.168.200.1}"
: "${PHANTUN_TUN_PEER:=192.168.200.2}"
: "${PHANTUN_IPV4_ONLY:=1}"

if [ -n "${PHANTUN_GATEWAY:-}" ]; then
  if [ "${PHANTUN_GATEWAY_ONLINK:-0}" = 1 ]; then
    OUT_IF=${PHANTUN_OUT_IF:-$(ip -o link show | awk -F': ' '$2 != "lo" { sub(/@.*/, "", $2); print $2; exit }')}
    : "${OUT_IF:?PHANTUN_OUT_IF is required when no non-loopback interface is found}"
    ip route replace default via "$PHANTUN_GATEWAY" dev "$OUT_IF" onlink
  else
    ip route replace default via "$PHANTUN_GATEWAY"
  fi
fi

args="--local $PHANTUN_LOCAL --remote $PHANTUN_REMOTE --tun $PHANTUN_TUN --tun-local $PHANTUN_TUN_LOCAL --tun-peer $PHANTUN_TUN_PEER"
if [ "$PHANTUN_IPV4_ONLY" = 1 ] || [ "$PHANTUN_IPV4_ONLY" = true ] || [ "$PHANTUN_IPV4_ONLY" = yes ]; then
  args="$args --ipv4-only"
fi

# shellcheck disable=SC2086
exec phantun_client $args
