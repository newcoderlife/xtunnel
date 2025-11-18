#!/usr/bin/env bash

set -ex

caddy run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

/usr/local/bin/xray -config /etc/xray/config.json &
XRAY_PID=$!

wait $CADDY_PID $XRAY_PID
