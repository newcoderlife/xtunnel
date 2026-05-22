#!/bin/sh
set -e

: "${UDP2FAKETCP_MODE:=client}"
: "${UDP2FAKETCP_LISTEN:=0.0.0.0:51820}"
: "${UDP2FAKETCP_REMOTE:?UDP2FAKETCP_REMOTE is required, for example lax.newco.homes:51820}"
: "${UDP2FAKETCP_TTL:=180}"
: "${UDP2FAKETCP_MTU:=1440}"

case "$UDP2FAKETCP_MODE" in
  client)
    mode_flag=-c
    ;;
  server)
    mode_flag=-s
    ;;
  *)
    echo "Unsupported UDP2FAKETCP_MODE: $UDP2FAKETCP_MODE" >&2
    exit 1
    ;;
esac

args="$mode_flag -l $UDP2FAKETCP_LISTEN -r $UDP2FAKETCP_REMOTE -t $UDP2FAKETCP_TTL -m $UDP2FAKETCP_MTU"
if [ "${UDP2FAKETCP_DEBUG:-0}" = 1 ] || [ "${UDP2FAKETCP_DEBUG:-0}" = true ] || [ "${UDP2FAKETCP_DEBUG:-0}" = yes ]; then
  args="$args -d"
fi

# shellcheck disable=SC2086
exec udp2faketcp $args
