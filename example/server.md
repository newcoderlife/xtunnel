# Server 配置示例

server 模式不设置 `PEERS`。下面按这个约定写：

- `ether1` 是 WAN。
- `veth-xtunnel` 和 `vxlan-xtunnel` 都算 LAN。
- RouterOS 是 `172.18.0.1`，xtunnel 容器是 `172.18.0.2`。
- VXLAN overlay 业务网是 `192.168.66.0/24`。
- 这个 server 的 overlay 业务 IP 是 `192.168.66.2/24`。后续 server 可以顺序使用 `192.168.66.3/24`、`192.168.66.4/24`。
- 外置存储是 `disk1`。

把域名、Cloudflare token 和两个 UUID 换成自己的，然后按顺序执行。

## RouterOS Container

如果还没启用 container，先执行一次：

```routeros
/system/device-mode/update container=yes
```

创建接口和容器：

```routeros
/interface/list/add name=WAN
/interface/list/add name=LAN
/interface/list/member/add list=WAN interface=ether1

/interface/veth/add name=veth-xtunnel address=172.18.0.2/24 gateway=172.18.0.1
/ip/address/add address=172.18.0.1/24 interface=veth-xtunnel
/interface/list/member/add list=LAN interface=veth-xtunnel

/interface/vxlan/add name=vxlan-xtunnel vni=100 port=4789 mtu=1200 local-address=172.18.0.1 rem-csum=both hw=no
/interface/vxlan/vteps/add interface=vxlan-xtunnel remote-ip=172.18.0.2
/ip/address/add address=192.168.66.2/24 interface=vxlan-xtunnel comment="xtunnel overlay"
/interface/list/member/add list=LAN interface=vxlan-xtunnel

/container/config/set registry-url=https://ghcr.io tmpdir=disk1/tmp
/container/envs/add list=ENV_XTUNNEL key=DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=VTEP_IP value="172.18.0.2"
/container/envs/add list=ENV_XTUNNEL key=CLOUDFLARE_API_TOKEN value="cf_api_token_here"
/container/envs/add list=ENV_XTUNNEL key=FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/add remote-image=newcoderlife/xtunnel:latest interface=veth-xtunnel root-dir=disk1/xtunnel/root envlist=ENV_XTUNNEL name=xtunnel user=0:0 dns=1.1.1.1 start-on-boot=yes logging=yes
/container/start [find where name="xtunnel"]
```

这里不挂 `/data`，生成配置和 Caddy 证书会保存在 `root-dir` 里的 `/data` 路径下。只要不删除这个 container/root-dir，重启后还在。

`172.18.0.1/24` 和 `172.18.0.2/24` 只用于 RouterOS 到本机容器的 transport。不要把它们当作跨站业务 IP，也不要用它们测试远端连通性。跨站 IPv4 测试应该使用 `192.168.66.x`。

`vxlan-xtunnel` 的 `rem-csum=both` 和 `hw=no` 需要和 client 保持一致。RouterOS 本机发出的 TCP 流量（例如 SSH、BGP、bandwidth-test）经过 VXLAN 时可能依赖 Remote Checksum Offload；启用 RCO 并关闭 VXLAN hardware offload 可以避免远端收到未完成的内层 TCP checksum。

## Firewall / NAT

如果你已有 firewall，只把这些规则放到最终 drop 前面即可。

```routeros
/ip/firewall/filter/add chain=forward action=accept connection-nat-state=dstnat protocol=udp dst-address=172.18.0.2 dst-port=443 in-interface-list=WAN comment="xtunnel H3"
/ip/firewall/filter/add chain=forward action=accept in-interface-list=LAN

/ip/firewall/nat/add chain=dstnat action=dst-nat protocol=udp dst-port=443 in-interface-list=WAN to-addresses=172.18.0.2 to-ports=443
/ip/firewall/nat/add chain=srcnat action=masquerade in-interface-list=LAN out-interface-list=WAN

/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu out-interface=vxlan-xtunnel
/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu in-interface=vxlan-xtunnel
```

UDP full cone 可选；需要时把下面两条加在 `masquerade` 前面，UDP 443 的 `dst-nat` 保持在 generic `endpoint-independent-nat` 前面：

```routeros
/ip/firewall/nat/add chain=srcnat action=endpoint-independent-nat protocol=udp in-interface-list=LAN out-interface-list=WAN
/ip/firewall/nat/add chain=dstnat action=endpoint-independent-nat protocol=udp in-interface-list=WAN
```

作为出口节点时，`vxlan-xtunnel` 在 `LAN` 里，上面的 `LAN -> WAN` masquerade 会自动给 client 经由本 server 出口的流量做 NAT。不需要再加 `src-address=192.168.66.0/24` 的专用 NAT 规则，除非你想收紧 NAT 范围。

## 验证

容器启动并且 client 配好后，在 server 上确认 overlay 能回 ping client：

```routeros
/ping 192.168.66.1 count=5
```

检查关键状态：

```routeros
/interface/vxlan/print detail where name="vxlan-xtunnel"
/interface/vxlan/vteps/print detail where interface="vxlan-xtunnel"
/ip/address/print detail where interface="vxlan-xtunnel"
/interface/list/member/print detail where interface="vxlan-xtunnel"
```

期望看到：

- `local-address=172.18.0.1`
- `remote-ip=172.18.0.2`
- `mtu=1200`
- `rem-csum=both`
- `hw=no`
- `192.168.66.2/24` 配在 `vxlan-xtunnel`
- `vxlan-xtunnel` 在 `LAN`

## Docker 参考

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -p 443:443/udp \
  -v xtunnel:/data \
  -e DOMAIN=s1.example.com \
  -e VTEP_IP=172.18.0.2 \
  -e CLOUDFLARE_API_TOKEN=cf_api_token_here \
  -e FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  ghcr.io/newcoderlife/xtunnel:latest
```

## 可选项

自定义 path：

```routeros
/container/envs/add list=ENV_XTUNNEL key=XHTTP_PATH value="/vxlan"
```
