# Client 配置示例

client 模式设置 `PEERS`。下面按这个约定写：

- `ether1` 是 WAN。
- `veth-xtunnel` 算 LAN。
- `vxlan-xtunnel` 算 WAN，因为出口 server 会作为低优先级上游出口。
- RouterOS 是 `172.18.0.1`，xtunnel 容器是 `172.18.0.2`。
- VXLAN overlay 业务网是 `192.168.66.0/24`。
- client/home 的 overlay 业务 IP 是 `192.168.66.1/24`。
- 第一个出口 server 使用 `192.168.66.2/24`。
- 外置存储是 `disk1`。

把 server 域名和 UUID 换成自己的，然后按顺序执行。

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

/interface/vxlan/add name=vxlan-xtunnel vni=100 port=4789 mtu=1280 local-address=172.18.0.1
/interface/vxlan/vteps/add interface=vxlan-xtunnel remote-ip=172.18.0.2
/ip/address/add address=192.168.66.1/24 interface=vxlan-xtunnel comment="xtunnel overlay"
/interface/list/member/add list=WAN interface=vxlan-xtunnel

/container/config/set registry-url=https://ghcr.io tmpdir=disk1/tmp
/container/envs/add list=ENV_XTUNNEL key=PEERS value="s1"
/container/envs/add list=ENV_XTUNNEL key=S1_DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=S1_FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=S1_REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/envs/add list=ENV_XTUNNEL key=S1_LOCAL_VTEP_IP value="172.18.0.2"
/container/add remote-image=newcoderlife/xtunnel:latest interface=veth-xtunnel root-dir=disk1/xtunnel/root envlist=ENV_XTUNNEL name=xtunnel user=0:0 dns=1.1.1.1 start-on-boot=yes logging=yes
/container/start [find where name="xtunnel"]
```

这里不挂 `/data`，生成配置会保存在 `root-dir` 里的 `/data` 路径下。只要不删除这个 container/root-dir，重启后还在。

`172.18.0.1/24` 和 `172.18.0.2/24` 只用于 RouterOS 到本机容器的 transport。它们可以和 server 上的 transport 网段重复。跨站 IPv4 业务地址是 `192.168.66.0/24`，client 用 `.1`，server 从 `.2` 开始。

添加低优先级默认路由，让第一个出口 server 作为备用出口。这里的 `distance` 数值要大于本机 PPPoE/WAN 默认路由，确保优先级更低：

```routeros
/ip/route/add dst-address=0.0.0.0/0 gateway=192.168.66.2 distance=10 comment="xtunnel s1 exit"
```

后续要让某些流量优先走 xtunnel 时，再调整距离、routing rule 或 mangle 策略。基础示例不创建额外 routing table。

## Firewall / NAT

如果你已有 firewall，只把这些规则放到最终 drop 前面即可。

```routeros
/ip/firewall/filter/add chain=forward action=accept in-interface-list=LAN

/ip/firewall/nat/add chain=srcnat action=masquerade in-interface-list=LAN out-interface-list=WAN

/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu out-interface=vxlan-xtunnel
/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu in-interface=vxlan-xtunnel
```

因为 `vxlan-xtunnel` 在 `WAN` interface-list 里，现有 `LAN -> WAN` masquerade 会自动处理经由出口 server 的 LAN 流量。不需要为 `192.168.66.2` 单独写 NAT。若你使用的是更宽泛的 `out-interface-list=WAN action=masquerade`，也可以继续沿用。

如果你的 input chain 有 `drop in-interface-list=!LAN` 之类规则，从 server ping 或管理 client RouterOS 会被当作 WAN 输入处理。只允许需要的 input，例如 ICMP 或特定管理端口。

UDP full cone 可选；需要时把下面两条加在 `masquerade` 前面。由于这个示例把 `vxlan-xtunnel` 也放进 `WAN`，如果你不希望 full cone 规则匹配 overlay 入站流量，请把物理 WAN 单独放进另一个 interface-list，并把下面的 `in-interface-list=WAN` 改成那个列表：

```routeros
/ip/firewall/nat/add chain=srcnat action=endpoint-independent-nat protocol=udp in-interface-list=LAN out-interface-list=WAN
/ip/firewall/nat/add chain=dstnat action=endpoint-independent-nat protocol=udp in-interface-list=WAN
```

## 多 server

多 server 时，client 仍然只使用一个 overlay 业务 IP `192.168.66.1/24`。每个出口 server 在同一个 VXLAN overlay 里顺序编号，例如 `192.168.66.2`、`192.168.66.3`。本机 container transport 则为每个 peer 分配一个本地 VTEP IP：

```routeros
/interface/veth/add name=veth-xtunnel address=172.18.0.2/24,172.18.0.3/24 gateway=172.18.0.1

/container/envs/add list=ENV_XTUNNEL key=PEERS value="s1,hk-1"
/container/envs/add list=ENV_XTUNNEL key=S1_DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=S1_FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=S1_REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/envs/add list=ENV_XTUNNEL key=S1_LOCAL_VTEP_IP value="172.18.0.2"
/container/envs/add list=ENV_XTUNNEL key=HK_1_DOMAIN value="hk-1.example.com"
/container/envs/add list=ENV_XTUNNEL key=HK_1_FORWARD_UUID value="00000000-0000-4000-8000-000000000003"
/container/envs/add list=ENV_XTUNNEL key=HK_1_REVERSE_UUID value="00000000-0000-4000-8000-000000000004"
/container/envs/add list=ENV_XTUNNEL key=HK_1_LOCAL_VTEP_IP value="172.18.0.3"

/interface/vxlan/vteps/add interface=vxlan-xtunnel remote-ip=172.18.0.3
```

对应的低优先级出口路由可以按 server 顺序递增距离：

```routeros
/ip/route/add dst-address=0.0.0.0/0 gateway=192.168.66.2 distance=10 comment="xtunnel s1 exit"
/ip/route/add dst-address=0.0.0.0/0 gateway=192.168.66.3 distance=11 comment="xtunnel hk-1 exit"
```

如果将来把某个 xtunnel 出口提升为主默认路由，给该 server 的公网地址加一条强制走本机物理 WAN/PPPoE 的 host route，避免 Xray 外层连接递归走进自己的 tunnel。

## 验证

容器启动并且 server 配好后，在 client 上确认 overlay 能 ping 通出口 server：

```routeros
/ping 192.168.66.2 count=5
```

检查关键状态：

```routeros
/interface/vxlan/print detail where name="vxlan-xtunnel"
/interface/vxlan/vteps/print detail where interface="vxlan-xtunnel"
/ip/address/print detail where interface="vxlan-xtunnel"
/interface/list/member/print detail where interface="vxlan-xtunnel"
/ip/route/print detail where comment="xtunnel s1 exit"
```

期望看到：

- `local-address=172.18.0.1`
- `remote-ip=172.18.0.2`
- `mtu=1280`
- `192.168.66.1/24` 配在 `vxlan-xtunnel`
- `vxlan-xtunnel` 在 `WAN`
- `0.0.0.0/0 gateway=192.168.66.2 distance=10`

## Docker 参考

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -v xtunnel:/data \
  -e PEERS=s1 \
  -e S1_DOMAIN=s1.example.com \
  -e S1_FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e S1_REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  -e S1_LOCAL_VTEP_IP=172.18.0.2 \
  ghcr.io/newcoderlife/xtunnel:latest
```

## 可选项

自定义 path 或 SNI：

```routeros
/container/envs/add list=ENV_XTUNNEL key=S1_XHTTP_PATH value="/vxlan"
/container/envs/add list=ENV_XTUNNEL key=S1_SNI value="edge.example.com"
```
