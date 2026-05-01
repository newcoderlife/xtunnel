# xtunnel examples

这个目录放 `xtunnel` 的部署示例，所有示例都只通过环境变量配置容器。容器启动时会重新生成 `/data/Caddyfile`、`/data/server.json` 或 `/data/client.json`，不需要也不支持挂载自定义 Xray/Caddy 配置。

- [server.md](server.md)：server 侧 RouterOS Container 配置、变量说明和 Docker 参考命令。
- [client.md](client.md)：client 侧 RouterOS Container 配置、单 server、多 server 和 Docker 参考命令。

示例里的 IP、域名、UUID 和 Cloudflare API token 都需要替换成你自己的值。RouterOS 的容器 veth 也必须实际拥有示例中的 VTEP IP，否则 Xray 无法绑定本地 UDP 入口或按指定源地址发包。server 只需要开放 `443/udp`，xtunnel 只使用 HTTP/3 over QUIC 承载公网 tunnel。

这些示例使用三层 routed overlay，不做二层桥接：

- `172.18.0.0/24` 是每台 RouterOS 本机到 xtunnel 容器的 transport 网段，可以在 client 和所有 server 上重复使用。
- `192.168.66.0/24` 是 VXLAN 里的业务网段，配置在 `vxlan-xtunnel` 上。
- client/home 使用 `192.168.66.1/24`。
- 出口 server 从 `192.168.66.2/24` 开始顺序编号，例如第一个出口 server 使用 `192.168.66.2/24`。
- client 把 `vxlan-xtunnel` 放进 `WAN` interface-list，并添加低优先级默认路由指向出口 server。
- server 把 `vxlan-xtunnel` 放进 `LAN` interface-list，复用 `LAN -> WAN` masquerade 作为出口 NAT。
- RouterOS VXLAN 使用 `mtu=1200 rem-csum=both hw=no`。`rem-csum=both` 用于处理 RouterOS 本机 TCP over VXLAN 的 Remote Checksum Offload，`hw=no` 避免 hardware offload 忽略 RCO 设置。

注意：RouterOS VXLAN 的 `local-address` 和 `/interface/vxlan/vteps remote-ip` 是 underlay VTEP 地址。在这个项目里，`remote-ip` 指向的是本机 xtunnel 容器地址，例如 `172.18.0.2`，不是远端 server。真正跨站点的业务 IP 是 `192.168.66.x`。
