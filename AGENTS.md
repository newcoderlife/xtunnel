# xtunnel Agent Instructions

**xtunnel** is a minimal Docker image for RouterOS VXLAN over Xray VLESS xHTTP/H3. It generates all runtime config from environment variables.

## Rules

- Keep changes focused; this repository is intentionally small and should stay easy to audit.
- Do not introduce application frameworks, package managers, or build systems unless the user explicitly asks for them.
- Prefer Alpine BusyBox `ash` in `entrypoint.sh`; avoid Bash-specific features.
- Preserve `set -ex`; startup tracing is an intentional feature.
- Do not support custom mounted Xray or Caddy config files.
- Preserve `/data` as the persistent runtime state directory for UUIDs, generated configs, and Caddy data.
- Preserve server mode's two-process runtime model: Caddy handles HTTPS and path routing, Xray listens on `127.0.0.1:8080`.
- Preserve client mode as Xray-only; client mode is selected by `PEERS` being set.
- Keep the Docker image multi-arch friendly for `linux/amd64`, `linux/arm64`, and `linux/arm/v7`.
- Keep the Xray version and per-architecture SHA256 checksums pinned in `Dockerfile`.
- Before changing CI behavior, verify `.github/workflows/ci.yml`.
- Before changing release behavior, verify `.github/workflows/release.yml`.

## Conventions

- Do not add a `MODE` variable. Server/client role is inferred from `PEERS`.
- `XHTTP_PATH` defaults to `/tunnel`; `VXLAN_PORT` defaults to `4789`.
- Server mode requires `DOMAIN` and `VTEP_IP`.
- Server mode uses two UUIDs: `FORWARD_UUID` for client-to-server traffic and `REVERSE_UUID` for server-to-client traffic. Missing UUIDs are generated under `/data`.
- Client mode requires `PEERS` plus `<PEER>_DOMAIN`, `<PEER>_FORWARD_UUID`, `<PEER>_REVERSE_UUID`, and `<PEER>_LOCAL_VTEP_IP` for each peer.
- Peer variable names are derived by uppercasing peer names and replacing `-` with `_`.
- Use `dokodemo-door` for local VXLAN UDP ingress and `freedom` with `redirect`, `sendThrough`, and `ipsBlocked: []` for traffic back to RouterOS.
- Keep xHTTP in HTTP/3 mode with TLS/H3 on clients and Caddy terminating H3/TLS on servers.
- Multi-server support should stay client-local: add one client VTEP IP and one peer block per server; existing servers should not need changes.
- The CI workflow validates pull requests with ShellCheck and `linux/amd64,linux/arm64,linux/arm/v7` Docker builds.
- The release workflow publishes multi-arch `ghcr.io/${{ github.repository }}` images for version tags.
