# sx-ui

`sx-ui` 是一个面向 `Xray-core` 与 `sing-box` 的可视化代理面板，目标不是简单复刻传统 `x-ui`，而是把常用的节点管理、双核心切换、分流、防火墙、证书、WARP、Argo、备份恢复和运维脚本整合到一套更完整的日常使用体验里。

项目地址：
- GitHub: [sx-ui2/sx-ui](https://github.com/sx-ui2/sx-ui)

## 安装

推荐直接使用安装脚本：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/sx-ui2/sx-ui/main/install.sh)
```

安装脚本会自动完成：

- 环境检测
- 依赖安装
- 下载并解压面板
- 安装管理脚本到 `/usr/bin/sx-ui`
- 自动设置 `systemd`
- 自动设置开机自启
- 自动启动面板
- 引导配置面板登录信息
- 引导配置证书

安装完成后可直接使用：

```bash
sx-ui
```

## 项目特点

- 双核心架构：同时支持 `xray` 与 `sing-box`，面板首页可查看两套核心状态与版本。
- `sing-box` 深度接入：支持在面板内切换 `sing-box` 版本，并使用自管理的 `stats` 版内核保证流量统计可用。
- 更完整的协议覆盖：除了常见的 `vmess / vless / trojan / shadowsocks`，还接入了 `naive / tuic / hysteria2 / anytls`。
- 入站管理更细：支持多用户、流量限制、到期时间、定时流量重置、手动流量重置、分享链接和二维码。
- 分流规则可视化：支持按优先级管理分流规则，并可直接在面板里拖拽调整顺序。
- 出站能力更强：支持 `IPv4 / IPv6 / WARP / Psiphon / Reject` 等策略，并可把出站策略绑定到单个入站或单条分流规则。
- WARP 集成更贴近日常使用：支持普通账户和 Teams 团队账户，面板可直接生成配置并维护默认端点。
- Argo 隧道内置：支持 `WS` 入站的临时隧道和固定隧道，节点关闭、删除或停用时会同步清理隧道。
- 防火墙联动：面板支持查看规则、去重展示，并能在节点级别自动放行或关闭端口。
- 面板证书体系完整：支持 ACME 账户、DNS 账户、证书申请、上传已有证书、自签证书、自动续期和一键应用到面板。
- 面板自带备份恢复：支持下载数据库备份、上传恢复、自动重启面板、查看运行日志。
- 安装和管理脚本更完善：支持安装后自动开机自启、自动放行面板端口、显示 `xray / sing-box` 状态、纯 IPv6 VPS 的 NAT64/DNS64 处理，以及常用运维入口。

## 支持的核心与协议

### 核心

- `Xray-core`
- `sing-box`

### 主要协议

- `vmess`
- `vless`
- `trojan`
- `shadowsocks`
- `socks`
- `http`
- `dokodemo-door`
- `mtproto`
- `naive`
- `tuic`
- `hysteria2`
- `anytls`

说明：
- 常见传统协议可在 `xray` 和 `sing-box` 场景中按能力使用。
- `naive / tuic / hysteria2 / anytls` 主要面向 `sing-box`。

## 你这版 sx-ui 的主要增强点

和常见的传统 `x-ui` 面板相比，这个仓库额外补了很多日常使用里真正有感的能力：

- 面板首页同时展示 `xray` 与 `sing-box` 的运行状态和版本。
- `sing-box` 节点支持分享链接与二维码生成。
- `sing-box` 入站支持流量统计，并通过自管理 `stats` 内核保持能力可用。
- 分流规则页支持拖拽排序，顶部入口改成更直观的“添加分流规则”。
- 入站详情支持流量监控和单节点流量重置。
- 面板设置页增加了 `sx-ui 版本`、`备份与恢复`、`运行日志`。
- 备份恢复上传后会自动重启面板。
- 安装脚本支持：
  - 自动设置面板用户名、密码、端口、根路径
  - 自动引导配置面板证书
  - 自动设置开机自启
  - 自动放行面板端口
  - 安装完成后显示 `xray / sing-box` 状态
- 管理脚本支持：
  - 查看系统信息、面板状态、开机自启、`xray / sing-box` 状态
  - 一键更新、卸载、改端口、改根路径、看日志、管理 BBR

## 面板能力概览

### 1. 系统状态

- CPU、内存、Swap、磁盘、负载、连接数、网卡速度与累计流量
- `xray` / `sing-box` 状态与版本

### 2. 入站列表

- 节点新增、编辑、启停、删除
- 单入站多用户管理
- 到期时间、流量限制、自动流量重置
- 单节点流量重置
- 节点分享链接、二维码
- 端口放行开关，联动防火墙
- `xray / sing-box` 核心切换

### 3. 出站设置

- 默认出站策略切换
- `IPv4 / IPv6 / WARP / Psiphon / Reject`
- WARP 普通账户与 Teams 账户
- 纯 IPv6 VPS 下的默认 WARP IPv6 端点处理

### 4. 分流规则

- 可视化添加、编辑、删除
- 按优先级匹配
- 拖拽排序
- 支持将流量定向到不同出站策略

### 5. 防火墙

- 查看当前规则
- 规则去重与合并展示
- 节点联动自动放行/关闭端口

### 6. 证书管理

- ACME 账户管理
- DNS 账户管理
- 证书申请
- 上传已有证书
- 自签证书
- 自动续期
- 一键应用到面板

### 7. 面板设置

- 修改用户名、密码、端口、根路径
- 查看 `sx-ui` 版本
- 下载备份
- 上传恢复
- 查看运行日志

## 手动安装 / 升级

1. 从 [Releases](https://github.com/sx-ui2/sx-ui/releases) 下载对应架构压缩包  
2. 上传到服务器后执行：

```bash
cd /root/
rm -rf /usr/local/sx-ui /usr/bin/sx-ui
tar zxf sx-ui-linux-amd64.tar.gz
chmod +x sx-ui/sx-ui sx-ui/bin/xray-linux-* sx-ui/bin/sing-box-linux-* sx-ui/sx-ui.sh
cp sx-ui/sx-ui.sh /usr/bin/sx-ui
cp -f sx-ui/sx-ui.service /etc/systemd/system/
mv sx-ui /usr/local/
systemctl daemon-reload
systemctl enable sx-ui
systemctl restart sx-ui
```

说明：
- `amd64` 请按实际架构替换为对应版本
- 官方 release 当前主要提供 Linux `amd64 / arm64`

## Release 包内容

标准 release 包会包含：

- `sx-ui` 主程序
- 管理脚本 `sx-ui.sh`
- `xray` Linux 内核
- 自管理的 `sing-box stats` Linux 内核
- `geoip.dat`
- `geosite.dat`

这意味着安装后的面板默认就是：

- `xray` 可用
- `sing-box` 可用
- `sing-box` 流量统计可用

## 管理脚本

安装完成后，管理脚本命令为：

```bash
sx-ui
```

常用命令包括：

- `sx-ui start`
- `sx-ui stop`
- `sx-ui restart`
- `sx-ui status`
- `sx-ui log`
- `sx-ui update`
- `sx-ui uninstall`

管理脚本菜单内还提供：

- 修改面板用户名密码
- 修改端口
- 修改根路径
- 重置面板设置
- 设置 / 取消开机自启
- 管理 BBR / 网络加速

## 数据目录

默认数据目录：

- 数据库：`/etc/sx-ui/sx-ui.db`
- 面板证书相关目录：`/etc/sx-ui/cert`
- 证书管理存储目录：`/etc/sx-ui/certificates`

## 证书说明

面板支持：

- ACME 账户
- DNS 账户
- Cloudflare DNS API 申请证书
- 上传已有证书
- 生成自签证书
- 自动续期

如果首次安装时跳过证书，面板会先通过 `HTTP` 提供服务。建议安装后尽快进入面板左侧的“证书管理”为面板配置 `HTTPS`。

## WARP 与 Argo

### WARP

- 支持普通 WARP 账户
- 支持 Teams 团队账户
- 支持手动填写端点
- 默认端点逻辑已按普通账户 / Teams / 纯 IPv6 VPS 区分

### Argo

- 支持 `WS` 入站的临时 Argo 隧道
- 支持固定域名 Argo 隧道
- 关闭或删除对应节点时会自动同步清理隧道

## 适用系统

推荐使用：

- Ubuntu 20.04+
- Debian 11+
- CentOS / Rocky / AlmaLinux 8+

最低兼容目标：

- Ubuntu 16+
- Debian 8+
- CentOS 7+

## 开发

本地常用验证命令：

```bash
go test ./...
bash -n install.sh
bash -n sx-ui.sh
```

## 许可证

本项目使用 [LICENSE](LICENSE) 中定义的许可证。
