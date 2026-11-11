# VPN 双协议部署与客户端导入指南

> Hysteria2 + VLESS-Reality 双协议方案 · 中国电信优化版
> 服务器：AWS 美西（推荐俄勒冈 us-west-2，或 CN2 GIA VPS）

---

## 目录

1. [方案说明](#一方案说明)
2. [服务端部署](#二服务端部署)
3. [客户端导入：v2rayN（Windows）](#三客户端导入v2raynwindows)
4. [客户端导入：Shadowrocket（iOS）](#四客户端导入shadowrocketios)
5. [测试与切换建议](#五测试与切换建议)

---

## 一、方案说明

| 协议 | 用途 | 特点 |
|---|---|---|
| **Hysteria2** | 日常主力 | QUIC 协议，晚高峰丢包线路上速度最快；Salamander 混淆 + 端口跳跃抗电信 UDP QoS |
| **VLESS + Reality** | 抗封锁保底 | 伪装成 microsoft.com 的 HTTPS，TCP 443 永远能连，最难被封 |

两个协议由 sing-box 单进程同时承载，端口不同、互不干扰。

---

## 二、服务端部署

### 步骤 1：登录控制台并确认区域

1. 浏览器打开 `https://console.aws.amazon.com/ec2/`，用你的 AWS 账号登录
2. 看页面**右上角**的区域名称，点开下拉列表，选 **美国西部（俄勒冈）us-west-2**
3. 确认左侧菜单是 **实例 → 实例**（新版控制台叫"实例（运行中）"）

> ⚠️ 区域必须是 `us-west-2`。如果选错（比如默认的 us-east-1 弗吉尼亚），部署能成功，但中美线路会多绕 3000 公里，延迟明显变差。

✅ 检查点：右上角显示 `us-west-2` / Oregon。

---

### 步骤 2：启动 EC2 实例（逐项填写）

点右上角橙色的 **启动实例**，按下表逐项设置（没提到的项保持默认）：

| 向导页 | 设置项 | 填什么 |
|---|---|---|
| 名称和标签 | 名称 | `vpn-us-west` |
| 应用程序和操作系统映像 | 快速启动 | 选 **Ubuntu**，版本 **Ubuntu Server 24.04 LTS (HVM), SSD Volume Type**，架构 **64 位 (x86)** |
| 实例类型 | 实例类型 | `t3.micro` |
| 密钥对（登录） | 密钥对 | **创建新密钥对** → 名称 `vpn-key` → 类型 `RSA` → 格式 **`.pem`** → 点"创建密钥对" |
| 网络设置 | 防火墙（安全组） | 选 **创建安全组**，先按步骤 3 的表格添加规则 |
| 配置存储 | 根卷 | 默认 8 GiB gp3 够用；想省心改成 **16 GiB**（apt 缓存 + 日志不会撑爆） |
| 高级详细信息 | 全部 | 保持默认，**不要**填用户数据 |

**架构必须选 x86_64**：脚本内置的 sing-box 安装包是 `linux_amd64`。如果误选了 `t4g.*`（ARM/Graviton）这类实例，脚本安装内核那一步会直接失败。

点 **启动实例**，等状态从"待处理"变成 **"运行中"**，并且"状态检查"显示 **2/2 项检查通过**（约 1 分钟）。

✅ 检查点：实例列表里该实例状态为 运行中，状态检查 2/2。

---

### 步骤 3：配置安全组（最容易出错的一步）

在实例详情页 → **安全** 选项卡 → 点安全组名称进入 → **编辑入站规则** → 添加规则，四条都要有：

| 类型 | 协议 | 端口范围 | 来源 | 作用 |
|---|---|---|---|---|
| SSH | TCP | `22` | **我的 IP** | 管理用，只放你自己的 IP |
| 自定义 TCP | TCP | `443` | `0.0.0.0/0` | Reality 协议 |
| 自定义 UDP | UDP | `8443` | `0.0.0.0/0` | Hysteria2 主端口 |
| 自定义 UDP | UDP | `20000-50000` | `0.0.0.0/0` | 端口跳跃段（抗电信 UDP 限速） |

要点：

- 第 3、4 条**必须是 UDP**。默认下拉里选"自定义 UDP"，别选成 TCP，否则 Hysteria2 一定连不上
- 第 4 条端口范围是一整段 `20000-50000`，**只加一条规则**，不是加 3 万条
- 出站规则保持默认（全部允许），不要动
- 如果你的宽带是动态 IP，SSH 那条"我的 IP"后续会失效。届时在控制台把来源临时改成 `0.0.0.0/0` 应急，用完再改回来

✅ 检查点：入站规则里能看到 TCP 22 / TCP 443 / UDP 8443 / UDP 20000-50000 四条。

---

### 步骤 4：分配并关联弹性 IP（强烈建议）

EC2 实例默认的公网 IP 在**停止再启动后会被换掉**，客户端配置就失效了。弹性 IP 可以固定：

1. 左侧菜单 → **网络与安全 → 弹性 IP**
2. 点 **分配弹性 IP 地址** → 直接点"分配"（默认即可）
3. 选中刚分配出来的 IP → **操作 → 关联弹性 IP 地址**
4. 资源类型选"实例"，选中你的 `vpn-us-west`，点 **关联**

❌ 常见错误：只是"分配"了弹性 IP 但没点"关联"，实例用的还是原来的自动分配 IP。**必须执行第 3 步的关联操作。**

✅ 检查点：实例详情页的"公有 IPv4 地址"与弹性 IP 列表里的地址**完全一致**。

记下这个 IP，下面统称 `<弹性IP>`。

---

### 步骤 5：在 Windows 本地准备密钥

1. 把下载的 `vpn-key.pem` 移动到固定位置，例如 `C:\Users\ruixi\.ssh\vpn-key.pem`（目录不存在就先建）
2. 如果之后在 Git Bash / WSL 里用 SSH 报错 `UNPROTECTED PRIVATE KEY FILE`，是因为 Windows 上密钥文件权限过宽。在 **PowerShell** 里执行：

```powershell
icacls "C:\Users\ruixi\.ssh\vpn-key.pem" /inheritance:r
icacls "C:\Users\ruixi\.ssh\vpn-key.pem" /grant:r "$($env:USERNAME):(R)"
```

Windows 10/11 自带 OpenSSH 客户端（`ssh.exe` / `scp.exe`），一般无需额外安装。先自检：

```powershell
ssh -V
```

✅ 检查点：能打印出 OpenSSH 版本号。

---

### 步骤 6：上传脚本

在 PowerShell 里，把工作目录切到脚本所在目录后执行（注意路径含空格要加引号）：

```powershell
cd "C:\Users\ruixi\Documents\Trae-CN\temp_20261027_01"
scp -i "C:\Users\ruixi\.ssh\vpn-key.pem" .\setup-dual-vpn.sh ubuntu@<弹性IP>:~/
```

首次连接会提示 `Are you sure you want to continue connecting`，输入 `yes` 回车。

✅ 检查点：输出显示 `setup-dual-vpn.sh   100%  ...`。

---

### 步骤 7：登录服务器并执行安装

```powershell
ssh -i "C:\Users\ruixi\.ssh\vpn-key.pem" ubuntu@<弹性IP>
```

登录成功后提示符变成 `ubuntu@ip-172-31-x-x:~$`，然后：

```bash
sudo bash setup-dual-vpn.sh
```

Ubuntu 镜像的 `ubuntu` 用户有免密 sudo，不会问密码。

> 全程约 2-4 分钟，主要耗在 `apt update` 和从 GitHub 下载 sing-box 安装包。

脚本会依次打印 `[1/6]` 到 `[6/6]`，每步在做的事：

| 阶段 | 脚本动作 | 说明 |
|---|---|---|
| `[1/6]` | 检测网卡名和公网 IP | 打印 `网卡: ens5 / enX0` 和你的弹性 IP。AWS 上内网是 `172.31.x.x`，公网 IP 通过 `checkip.amazonaws.com` 拿到，属正常 |
| `[2/6]` | 装依赖 | `curl qrencode iptables iproute2` |
| `[3/6]` | 装 sing-box | 从 GitHub 取最新版，下载 `sing-box_x.y.z_linux_amd64.deb` 并 `dpkg` 安装 |
| `[4/6]` | 生成凭据 | VLESS UUID、Reality 密钥对（私钥给服务端、公钥给客户端）、Short ID、Hysteria2 密码、混淆密码 |
| `[5/6]` | 写配置 + 端口跳跃 | 生成 `/etc/sing-box/config.json`；加 iptables NAT 规则，把 UDP `20000-50000` 的流量 REDIRECT 到 8443；并创建 `hysteria-port-hop.service` 让规则开机自动生效 |
| `[6/6]` | 启动服务 | `systemctl enable/restart sing-box` |

最后打印两块内容：**两个分享链接 + 两张二维码**（Hysteria2 用 `hysteria2://` 开头，Reality 用 `vless://` 开头），并写入 `/root/vpn-clients/`。

✅ 检查点：末尾出现 `sing-box: 运行中`，并显示二维码。

---

### 步骤 8：部署后验证（4 条命令）

留在 SSH 会话里逐条执行：

```bash
# 1) 服务是否在跑，应为 active (running)
sudo systemctl status sing-box --no-pager

# 2) 配置文件语法是否正确，无输出即正常
sudo sing-box check -c /etc/sing-box/config.json

# 3) 端口是否监听：能看到 tcp 443 和 udp 8443
sudo ss -lntup | grep -E ':443|:8443'

# 4) 端口跳跃 NAT 规则是否存在
sudo iptables -t nat -nL PREROUTING
```

第 4 条应看到一行 `udp dpt:20000-50000 redir ports 8443`。

再从 Windows PowerShell 验证 TCP 443 通达（UDP 无法用此方法测，只能靠客户端实测）：

```powershell
Test-NetConnection -ComputerName <弹性IP> -Port 443
```

`TcpTestSucceeded : True` 即安全组和监听都正常。

若服务没起来，看日志定位：

```bash
sudo journalctl -u sing-box -n 50 --no-pager
```

✅ 检查点：1) running，2) 无报错，3) 443/8443 均出现，4) NAT 规则存在，TcpTestSucceeded=True。

---

### 步骤 9：拉取客户端配置（可选）

客户端文件存放在 `/root/vpn-clients/`，属 root 私有目录，**`ubuntu` 用户直接 scp 会被拒绝（Permission denied）**。先在服务器上把它复制到可读位置：

```bash
sudo cp -r /root/vpn-clients /home/ubuntu/vpn-clients
sudo chown -R ubuntu:ubuntu /home/ubuntu/vpn-clients
sudo chmod 600 /home/ubuntu/vpn-clients/*
```

然后在本地 PowerShell 拉取：

```powershell
scp -i "C:\Users\ruixi\.ssh\vpn-key.pem" -r ubuntu@<弹性IP>:~/vpn-clients ./
```

✅ 检查点：本地 `vpn-clients` 目录里能看到 `hysteria2-client.json`、`reality-client.json`、`README.txt`。

> 手机端不需要这两个 JSON，扫码或复制分享链接更省事；JSON 是给电脑端 sing-box 内核用的。

---

### 步骤 10：可选加固（大流量场景）

Hysteria2 单连接跑满带宽时，Linux 默认的 UDP 接收缓冲可能成为瓶颈；同时启用 BBR 对 TCP 类的 Reality 也有收益。纯优化项，不做也能正常用：

```bash
sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sudo sysctl -p
```

验证是否生效：`sysctl net.ipv4.tcp_congestion_control` 应输出 `net.ipv4.tcp_congestion_control = bbr`。AWS 官方 Ubuntu 内核默认已编译 BBR，通常无需额外操作。

---

### 部署故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 脚本停在 `[2/6] apt update` 很慢或报错 | 实例到 Ubuntu 镜像源较慢 | 重试一次；仍失败则把 `/etc/apt/sources.list.d/ubuntu.sources` 里的源换成 `us-west-2` 区域镜像后重跑 |
| `[3/6]` 报 `package architecture (amd64) does not match system (arm64)` | 实例选了 Graviton（t4g 等 ARM 机型） | 重建 x86_64 实例（`t3.micro`），或手动换 `linux_arm64` 安装包 |
| `[3/6]` 版本号为空 / 下载 404 | GitHub API 限流或网络抖动 | 浏览器打开 sing-box Releases 页手动查版本号，改脚本第 29 行下载地址后重跑 |
| `sing-box: 启动失败` | 443 端口被占用或配置有错 | `sudo ss -lntup \| grep :443` 查占用；`sudo sing-box check -c /etc/sing-box/config.json` 查语法 |
| 服务 running 但手机连不上 Hysteria2 | 安全组缺 UDP 8443 或 20000-50000 | 回步骤 3 补规则，**协议必须是 UDP** |
| 服务 running 但 Reality 连不上 | 安全组缺 TCP 443，或客户端 SNI 填错 | 补规则；客户端 SNI 必须是 `www.microsoft.com` |
| 连上后无网络 | 客户端未设为活动节点 / 未开系统代理 | 见第三、四章客户端设置 |
| 重启实例后客户端全部失效 | 没绑弹性 IP，公网 IP 变了 | 回步骤 4 分配并**关联**弹性 IP，再重跑脚本 |

---

## 三、客户端导入：v2rayN（Windows）

> ⚠️ **核心前提**：v2rayN 默认内置 Xray 内核，**不支持 Hysteria2**。
> 导入 Reality 用默认内核即可；导入 Hysteria2 必须先添加 sing-box 内核。以下步骤以 v2rayN v7 为准。

### A. 安装 v2rayN

1. 浏览器打开 GitHub：`https://github.com/2dust/v2rayN`
2. 点击 Releases，下载 `v2rayN-windows-64.zip`（最新版）
3. 解压到**英文路径**文件夹（如 `D:\v2rayN`），双击 `v2rayN.exe` 启动
4. 若弹出"需要安装 .NET 8 运行库"，点"是"，等待自动安装完成后重新启动 v2rayN

### B. 添加 sing-box 内核（导入 Hysteria2 前必做）

**【截图 1】打开内核设置**
- 点击 v2rayN 顶部菜单栏的 **设置** → **参数设置**（或直接按快捷键 `Ctrl+P`）
- 在弹出的参数设置窗口左侧，点击 **内核设置** 选项卡

**【截图 2】内核列表**
- 该页面列出三个内核：`Xray` / `sing-box` / `mihomo`，每行末尾都有下载/状态按钮
- 找到 **sing-box** 那一行，点击右侧的 **下载**（或"检查更新"）按钮
- 等待下载完成，sing-box 行后面显示版本号和"已安装"即为成功

**【截图 3】确认内核已就绪**
- 关闭参数设置窗口，回到 v2rayN 主界面
- 看主界面**底部会话框**，内核类型下拉框里现在应能选到 `sing-box`

### C. 导入 Hysteria2 节点（具体截图步骤）

**【截图 4】复制分享链接**
- 回到服务器终端（或打开 `README.txt`），找到 **Hysteria2 分享链接**那一行
- 该链接以 `hysteria2://` 开头，末尾以 `#Hysteria2-AWS` 结束
- 从 `hysteria2://` 到 `#Hysteria2-AWS` 完整选中并复制（`Ctrl+C`）

**【截图 5】从剪贴板导入**
- 回到 v2rayN 主界面
- 点击顶部菜单栏 **服务器** → **从剪贴板导入批量分享 URL**
- 或直接在 v2rayN 窗口内按 `Ctrl+V` 粘贴

**【截图 6】确认节点出现**
- 左侧服务器列表会新增一行，名称显示为 `Hysteria2-AWS`
- 协议列显示 `hysteria2`（若显示为其他，说明链接没复制完整，返回截图 4 重试）

**【截图 7】切换内核为 sing-box**
- 在 v2rayN 主界面**底部**，找到"内核"下拉框（默认是 `Xray`）
- 切换为 `sing-box`

**【截图 8】设为活动节点**
- 在左侧列表右键点击 `Hysteria2-AWS` 节点
- 选择 **设为活动服务器**

**【截图 9】开启系统代理**
- 右键节点（或菜单栏 **系统代理**），选择 **自动配置系统代理**
- v2rayN 任务栏托盘/主界面图标变为**红色**，即已连接

### D. 导入 Reality 节点

- Reality 用默认 Xray 内核即可，但如果上面已切到 sing-box 也无妨（sing-box 同样支持 Reality）
- 复制 `vless://` 开头的 **Reality 分享链接**，`Ctrl+V` 粘贴导入，节点名 `Reality-AWS`
- 同样"设为活动服务器"即可使用

> 小技巧：sing-box 内核同时支持 Hysteria2 和 Reality，日常把内核固定在 `sing-box`，两个节点随意切换即可。

---

## 四、客户端导入：Shadowrocket（iOS）

> 国区 App Store 没有，需用**美区 Apple ID** 购买（$2.99）。

1. App Store 安装并打开 Shadowrocket
2. 导入方式二选一：
   - **扫码**：点右上角 `+` → **扫描二维码**，扫脚本输出的二维码
   - **剪贴板**：先复制分享链接整行，打开 Shadowrocket，App 弹"检测到剪贴板内容"，点**确认导入**
3. 两个节点都导入后，首页列表出现 `Hysteria2-AWS` 和 `Reality-AWS`
4. 点节点右侧圆圈选中，打开顶部开关
5. 首次弹"允许添加 VPN 配置"，点 **允许** 并输入锁屏密码
6. 状态栏出现 `VPN` 图标即连上

---

## 五、测试与切换建议

- 连上后打开 [fast.com](https://fast.com) 或 Speedtest 测速，确认出口 IP 是美国
- **日常主力用 Hysteria2**（快）；晚高峰若被电信 UDP 限速或特殊时期，切 **Reality**（稳）
- 两个客户端都支持一键切换，无需重装

### 常见问题

| 问题 | 解决 |
|---|---|
| v2rayN 里 Hysteria2 节点连不上 | 确认内核已切换为 `sing-box`，且安全组 UDP 8443 / 20000-50000 已放行 |
| 手机扫码后无法连接 | 确认安全组 UDP 端口已放行；Reality 需 TCP 443 |
| 连上了但没网 | 检查是否设为"活动服务器"且开启了系统代理 |
| 想换 IP / 被封 | AWS 控制台解绑旧弹性 IP，重新分配绑定，再跑一次脚本（脚本会重新生成配置） |

---

*本指南仅用于个人合规用途（远程办公、公共 Wi-Fi 防护等），请遵守当地法律法规。*