# Xray REALITY 一键脚本
🚀 **一个AI生成的 Xray 安装脚本。**

本脚本基于 Xray-core，VLESS-TCP-REALITY (without being stolen) 回落机制与路由白名单过滤，彻底杜绝回落流量偷跑。

---

## ✨ 核心特性

* **全自动安装**：一键完成环境检查、Xray 安装及 Systemd 服务配置。
* **智能端口管理**：
    * 自动检测 443 端口占用，支持非 Xray 进程占用时自动分配随机端口。
    * **优先使用 4431** 作为内部回落端口，冲突时自动同步切换。
* **极致防偷跑**：
    * 配置 `dokodemo-door` 内部回落。
    * 仅允许访问设定的伪装域名，阻止恶意扫描器消耗 VPS 流量。
* **动态身份生成**：
* 每次安装均生成全新的 UUID、X25519 密钥对及随机 ShortID。
* **可视化输出**：
    * 清晰的参数对账单（UUID, PublicKey, SNI 等）。
    * 自动生成 `vless://` 链接。
    * 终端直接渲染 **二维码**，手机扫码即连。
* **双栈支持**：强制提取 IPv4 地址，优先保证连接稳定性。

---
🛠️ 功能菜单
脚本运行后将进入交互式菜单：

安装 / 更新：全新部署或更新现有配置（保留 Xray 核心）。

卸载 / 删除：一键停止服务并清理所有二进制文件与配置残留。

退出：安全退出脚本。

---
⚠️ 免责声明

本脚本仅供网络技术研究与学习使用，请遵守当地相关法律法规。

由于 REALITY 协议特性，建议优先确保 443 端口未被占用，以获得最佳伪装效果。

🤝 贡献与感谢

核心协议：[Xray-core](https://github.com/XTLS/Xray-core)

安装脚本：[Xray-install](https://github.com/XTLS/Xray-install)

防偷流量配置：[Xray-examples](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-REALITY%20(without%20being%20stolen))
