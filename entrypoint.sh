#!/bin/sh
set -e

: "${PHANTUN_LOCAL:=0.0.0.0:51820}"
: "${PHANTUN_REMOTE:?PHANTUN_REMOTE is required, for example lax.newco.homes:18443}"
: "${PHANTUN_TUN:=phantun0}"
: "${PHANTUN_TUN_LOCAL:=192.168.200.1}"
: "${PHANTUN_TUN_PEER:=192.168.200.2}"
: "${PHANTUN_IPV4_ONLY:=1}"

if [ -n "${PHANTUN_GATEWAY:-}" ]; then
  ip route replace default via "$PHANTUN_GATEWAY"
fi

OUT_IF=${PHANTUN_OUT_IF:-$(ip route show default 2>/dev/null | awk '{print $5; exit}')}
if [ -z "$OUT_IF" ]; then
  OUT_IF=${PHANTUN_OUT_IF:-eth0}
fi

iptables -t nat -C POSTROUTING -i "$PHANTUN_TUN" -o "$OUT_IF" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -i "$PHANTUN_TUN" -o "$OUT_IF" -j MASQUERADE

args="--local $PHANTUN_LOCAL --remote $PHANTUN_REMOTE --tun $PHANTUN_TUN --tun-local $PHANTUN_TUN_LOCAL --tun-peer $PHANTUN_TUN_PEER"
if [ "$PHANTUN_IPV4_ONLY" = 1 ] || [ "$PHANTUN_IPV4_ONLY" = true ] || [ "$PHANTUN_IPV4_ONLY" = yes ]; then
  args="$args --ipv4-only"
fi

# shellcheck disable=SC2086
exec phantun_client $args
