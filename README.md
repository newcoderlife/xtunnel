# xtunnel

[![CI](https://github.com/newcoderlife/xtunnel/actions/workflows/ci.yml/badge.svg)](https://github.com/newcoderlife/xtunnel/actions/workflows/ci.yml)
[![CodeQL](https://github.com/newcoderlife/xtunnel/actions/workflows/codeql.yml/badge.svg)](https://github.com/newcoderlife/xtunnel/actions/workflows/codeql.yml)
[![GHCR](https://img.shields.io/badge/image-ghcr.io%2Fnewcoderlife%2Fxtunnel-blue)](https://github.com/newcoderlife/xtunnel/pkgs/container/xtunnel)
[![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64%20%7C%20arm%2Fv7-informational)](https://github.com/newcoderlife/xtunnel/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/github/license/newcoderlife/xtunnel)](LICENSE)

`xtunnel` 是一个用于 RouterOS VXLAN tunnel 的极简 Docker 镜像。RouterOS 继续使用原生 VXLAN UDP 4789，容器只负责把 VXLAN 包通过 Xray VLESS xHTTP over TLS/H2 封装到 HTTPS/TCP 链路里。

## 模型

```text
RouterOS VXLAN -> 本机 xtunnel 容器 -> VLESS xHTTP/TLS/H2 -> 对端 xtunnel 容器 -> 对端 RouterOS VXLAN
```

- 设置了 `PEERS` 时，容器以 client 模式运行。
- 没有设置 `PEERS` 时，容器以 server 模式运行。
- 不支持挂载自定义 Xray/Caddy 配置。`/data/Caddyfile`、`/data/server.json`、`/data/client.json` 每次启动都会重新生成。
- tunnel 只使用 `tcp/443`。server 需要公网 `tcp/443` 可达，DNS A/AAAA 记录应直接指向 server 公网地址。
- Caddy 使用默认 ACME 自动签发/续期证书。若域名托管在 Cloudflare，记录必须是 DNS only，不要启用代理云朵。
- Caddy 和 Xray 默认输出低噪声运行日志到 container logs；默认不启用访问日志。
- `VXLAN_PORT` 默认是 `4789`，通常不需要改。RouterOS VXLAN 对端通过 VTEP IP 识别，不是通过 `IP:port` 识别。
- RouterOS 到容器的 `172.18.0.0/24` 是每台设备本机的 transport 网段，不是跨站业务网段，可以在不同站点重复使用。
- VXLAN 业务 IP 需要单独配置在 `vxlan-xtunnel` 上。例如 home/client 使用 `192.168.66.1/24`，出口 server 使用 `192.168.66.2/24`、`192.168.66.3/24` 等。

## Server

每个 server 相互独立，通常只需要区分域名、server 侧 VTEP IP，以及两组 UUID：

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -p 443:443 \
  -v xtunnel:/data \
  -e DOMAIN=s1.example.com \
  -e VTEP_IP=172.18.0.2 \
  -e FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  ghcr.io/newcoderlife/xtunnel:latest
```

`FORWARD_UUID` 和 `REVERSE_UUID` 也可以不传，server 会自动生成并持久化到 `/data/forward_uuid` 和 `/data/reverse_uuid`。RouterOS 示例默认手动指定，省掉读取文件再复制到 client 的步骤。

## Client

一个 client 容器可以连接多个 server。给容器分配每个 server 对应的本地 VTEP IP，然后在 `PEERS` 里列出这些 peer：

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -v xtunnel:/data \
  -e PEERS=s1,s2 \
  -e S1_DOMAIN=s1.example.com \
  -e S1_FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e S1_REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  -e S1_LOCAL_VTEP_IP=172.18.0.2 \
  -e S2_DOMAIN=s2.example.com \
  -e S2_FORWARD_UUID=00000000-0000-4000-8000-000000000003 \
  -e S2_REVERSE_UUID=00000000-0000-4000-8000-000000000004 \
  -e S2_LOCAL_VTEP_IP=172.18.0.3 \
  ghcr.io/newcoderlife/xtunnel:latest
```

`PEERS` 里的 peer 名会被转换成大写变量名，`-` 会转换成 `_`。例如 `hk-1` 对应 `HK_1_DOMAIN`、`HK_1_FORWARD_UUID`、`HK_1_REVERSE_UUID`、`HK_1_LOCAL_VTEP_IP`。

更完整的 RouterOS Container 和 Docker 配置案例见 [example](example/README.md)。

## RouterOS VXLAN

在 RouterOS 上创建一个 VXLAN interface，然后为本机 xtunnel 容器暴露出来的每个 peer IP 添加一个静态 VTEP：

```routeros
/interface/vxlan add name=vxlan-xtunnel vni=100 port=4789 mtu=1200 local-address=172.18.0.1 rem-csum=both hw=no
/interface/vxlan/vteps add interface=vxlan-xtunnel remote-ip=172.18.0.2
/interface/vxlan/vteps add interface=vxlan-xtunnel remote-ip=172.18.0.3
```

`local-address` 是 RouterOS veth 上的本机地址，`remote-ip` 是本机 xtunnel 容器地址。它们不是 VXLAN 业务地址，也不是远端 RouterOS 的公网或内网地址。xtunnel 容器收到本机 VXLAN UDP 包后，才通过 Xray 把它送到远端容器。

在 server 侧 RouterOS 上，remote VTEP 使用该 server 容器的 `VTEP_IP`。在 client 侧 RouterOS 上，remote VTEP 使用每个 `*_LOCAL_VTEP_IP`。RouterOS 的容器 veth 必须实际分配这些地址，否则 Xray 无法绑定或从这些地址发包。

这些 IP 是每台 RouterOS 本机的 container 网段地址，不需要跨站点唯一。单 server 场景通常直接用 RouterOS `172.18.0.1`、xtunnel 容器 `172.18.0.2`；client 连接多个 server 时，再给每个 peer 追加一个本地 VTEP IP，例如 `172.18.0.3`、`172.18.0.4`。

跨站点 IPv4 连通需要另配 overlay 业务 IP，不能复用 `172.18.0.0/24`：

```routeros
# home/client
/ip/address add address=192.168.66.1/24 interface=vxlan-xtunnel

# exit server
/ip/address add address=192.168.66.2/24 interface=vxlan-xtunnel
```

## 环境变量

- `DOMAIN`：server 域名。server 必填。
- `VTEP_IP`：server 侧容器作为 VXLAN VTEP 使用的 IP。server 必填。
- `FORWARD_UUID`：server 专用，client 到 server 方向 UUID；推荐手动设置，不传会自动生成到 `/data/forward_uuid`。
- `REVERSE_UUID`：server 专用，server 到 client 方向 UUID；推荐手动设置，不传会自动生成到 `/data/reverse_uuid`。
- `PEERS`：逗号分隔的 peer 名。设置后启用 client 模式。
- `<PEER>_DOMAIN`：peer server 域名。client 必填。
- `<PEER>_FORWARD_UUID`：client 到 server 方向 VXLAN 流量使用的 UUID。client 必填。
- `<PEER>_REVERSE_UUID`：server 到 client 方向 VXLAN 流量使用的 UUID。client 必填。
- `<PEER>_LOCAL_VTEP_IP`：client 侧该 peer 使用的容器 IP。client 必填。
- `XHTTP_PATH`：可选，xHTTP path，默认 `/tunnel`。
- `<PEER>_XHTTP_PATH`：可选的 peer 级 xHTTP path，默认使用 `XHTTP_PATH`。
- `<PEER>_SNI`：可选的 peer 级 TLS SNI，默认使用 `<PEER>_DOMAIN`。
- `ROUTER_IP`：可选，容器可访问的 RouterOS IP。默认使用容器默认网关。
- `VXLAN_PORT`：可选，VXLAN UDP 端口，默认 `4789`。

## 新增 Server

1. 部署新的 server，设置自己的 `DOMAIN` 和 `VTEP_IP`，并确保公网 `tcp/443` 和 DNS 直连记录已就绪。
2. 生成两组 UUID，分别作为 server 的 `FORWARD_UUID` 和 `REVERSE_UUID`。
3. 给 server 的 `vxlan-xtunnel` 分配下一个 overlay 业务 IP，例如 `192.168.66.3/24`。
4. 在 client 的 `PEERS` 里追加新的 peer 名。
5. 给该 peer 增加四个 client 变量。
6. 给 client 容器 veth 再分配一个本地 transport IP，例如 `172.18.0.3/24`。
7. 在 client 的 RouterOS VXLAN 里再加一个静态 VTEP，指向这个新的本地 transport IP。
8. 在 client 上按需要添加低优先级默认路由，例如 `gateway=192.168.66.3 distance=11`。

已有 server 不需要修改。

## 发布

匹配 `v*` 的版本 tag 会发布 GitHub Container Registry 镜像，支持 `linux/amd64`、`linux/arm64`、`linux/arm/v7`。默认使用最新正式镜像：

```sh
docker pull ghcr.io/newcoderlife/xtunnel:latest
```
