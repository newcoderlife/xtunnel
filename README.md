# xtunnel

`xtunnel` 是一个用于 RouterOS VXLAN tunnel 的极简 Docker 镜像。RouterOS 继续使用原生 VXLAN UDP 4789，容器只负责把 VXLAN 包通过 Xray VLESS xHTTP/TLS 封装到 HTTPS 链路里。

## 模型

```text
RouterOS VXLAN <-> xtunnel 本地 VTEP IP <-> VLESS xHTTP/TLS <-> xtunnel server VTEP IP <-> RouterOS VXLAN
```

- 设置了 `PEERS` 时，容器以 client 模式运行。
- 没有设置 `PEERS` 时，容器以 server 模式运行。
- 不支持挂载自定义 Xray/Caddy 配置。`/data/Caddyfile`、`/data/server.json`、`/data/client.json` 每次启动都会重新生成。
- `VXLAN_PORT` 默认是 `4789`，通常不需要改。RouterOS VXLAN 对端通过 VTEP IP 识别，不是通过 `IP:port` 识别。

## Server

每个 server 相互独立，通常只需要区分域名、server 侧 VTEP IP，以及两组 UUID：

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v xtunnel:/data \
  -e DOMAIN=s1.example.com \
  -e VTEP_IP=172.18.0.10 \
  ghcr.io/newcoderlife/xtunnel:latest
```

如果没有传入 `FORWARD_UUID` 或 `REVERSE_UUID`，server 会自动生成并持久化到 `/data/forward_uuid` 和 `/data/reverse_uuid`。

## Client

一个 client 容器可以连接多个 server。给容器分配每个 server 对应的本地 VTEP IP，然后在 `PEERS` 里列出这些 peer：

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -v xtunnel:/data \
  -e PEERS=s1,s2 \
  -e S1_DOMAIN=s1.example.com \
  -e S1_FORWARD_UUID=00000000-0000-0000-0000-000000000001 \
  -e S1_REVERSE_UUID=00000000-0000-0000-0000-000000000002 \
  -e S1_LOCAL_VTEP_IP=172.18.0.21 \
  -e S2_DOMAIN=s2.example.com \
  -e S2_FORWARD_UUID=00000000-0000-0000-0000-000000000003 \
  -e S2_REVERSE_UUID=00000000-0000-0000-0000-000000000004 \
  -e S2_LOCAL_VTEP_IP=172.18.0.22 \
  ghcr.io/newcoderlife/xtunnel:latest
```

`PEERS` 里的 peer 名会被转换成大写变量名，`-` 会转换成 `_`。例如 `hk-1` 对应 `HK_1_DOMAIN`、`HK_1_FORWARD_UUID`、`HK_1_REVERSE_UUID`、`HK_1_LOCAL_VTEP_IP`。

## RouterOS VXLAN

在 RouterOS 上创建一个 VXLAN interface，然后为 xtunnel 暴露出来的每个 peer IP 添加一个静态 VTEP：

```routeros
/interface/vxlan add name=vxlan-xtunnel vni=100 port=4789
/interface/vxlan/vteps add interface=vxlan-xtunnel remote-ip=172.18.0.21
/interface/vxlan/vteps add interface=vxlan-xtunnel remote-ip=172.18.0.22
```

在 server 侧 RouterOS 上，remote VTEP 使用该 server 容器的 `VTEP_IP`。在 client 侧 RouterOS 上，remote VTEP 使用每个 `*_LOCAL_VTEP_IP`。RouterOS 的容器 veth 必须实际分配这些地址，否则 Xray 无法绑定或从这些地址发包。

## 环境变量

- `DOMAIN`：server 域名。server 必填。
- `VTEP_IP`：server 侧容器作为 VXLAN VTEP 使用的 IP。server 必填。
- `PEERS`：逗号分隔的 peer 名。设置后启用 client 模式。
- `<PEER>_DOMAIN`：peer server 域名。client 必填。
- `<PEER>_FORWARD_UUID`：client 到 server 方向 VXLAN 流量使用的 UUID。client 必填。
- `<PEER>_REVERSE_UUID`：server 到 client 方向 VXLAN 流量使用的 UUID。client 必填。
- `<PEER>_LOCAL_VTEP_IP`：client 侧该 peer 使用的容器 IP。client 必填。
- `ROUTER_IP`：容器可访问的 RouterOS IP。默认使用容器默认网关。
- `XHTTP_PATH`：xHTTP path，默认 `/tunnel`。
- `<PEER>_XHTTP_PATH`：可选的 peer 级 xHTTP path，默认使用 `XHTTP_PATH`。
- `<PEER>_SNI`：可选的 peer 级 TLS SNI，默认使用 `<PEER>_DOMAIN`。
- `VXLAN_PORT`：VXLAN UDP 端口，默认 `4789`。
- `FALLBACK`：server 专用，非 tunnel 请求的 Caddy fallback upstream。默认返回 `hello`。

## 新增 Server

1. 部署新的 server，设置自己的 `DOMAIN`、`VTEP_IP`、`FORWARD_UUID`、`REVERSE_UUID`。
2. 在 client 的 `PEERS` 里追加新的 peer 名。
3. 给该 peer 增加四个 client 变量。
4. 给 client 容器 veth 再分配一个本地 IP。
5. 在 RouterOS VXLAN 里再加一个静态 VTEP，指向这个新的本地 IP。

已有 server 不需要修改。

## 发布

匹配 `v*` 的版本 tag 会发布 GitHub Container Registry 镜像，支持 `linux/amd64`、`linux/arm64`、`linux/arm/v7`：

```sh
docker pull ghcr.io/newcoderlife/xtunnel:v0.0.1
```
