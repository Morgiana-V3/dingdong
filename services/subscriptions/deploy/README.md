# 在中转服务器部署 Node 订阅管理台

仓库内的消息中转位于 `services/relay/`，订阅服务位于 `services/subscriptions/`。直接使用仓库部署时，先从 `services/relay/.env.example` 创建 `.env`，配置两把独立密钥，设置 `DINGDONG_BIND=127.0.0.1` 和 `DINGDONG_PORT=18080`。从仓库根目录执行：

```sh
cd services/relay
docker compose up -d --build --wait
cd ../subscriptions
sh deploy.sh
```

订阅服务会引用中转的 `.env` 并连接本机 18080 端口。若中转使用其他端口，在它的 `.env` 中设置对应的 `RELAY_INTERNAL_URL`。已有独立部署可将两套源码分别更新到 `/opt/dingdong` 与 `/opt/dingdong-node`。沿用两个服务各自的 Compose 项目名、环境文件、覆盖配置和数据卷。以下步骤覆盖已有中转接入订阅服务及配置公网 HTTPS。

1. 备份原中转 compose、环境文件和数据库，保留原 Docker 镜像标签。保持原消息卷和凭据。
2. 在中转 compose 中将端口映射改为 `127.0.0.1:18080:8080`。Nginx 接管 80 端口，将原消息及 WebSocket 路由转发到这个端口。不要更换手机消息连接地址，以免产生新的消息 ID 命名空间。
3. 在 Node 项目目录执行 `sh deploy.sh`。首次会复用原中转环境文件或从模板创建本地配置，之后重复运行即可升级。保留现有 Compose 项目名、具名卷和 compose.override.yaml。国内服务器可用 `DEBIAN_MIRROR=mirrors.cloud.tencent.com sh deploy.sh`；仍校验 Debian 仓库签名。Node 使用普通容器用户，数据放在具名卷，默认回环监听，依赖 Cordis 注册平台服务。
4. 安装 Nginx。先只安装 `nginx.conf.template` 的 HTTP 部分；将 `SERVER_HOST` 替换为实际 IP/域名，建立 `/var/www/dingdong-acme/.well-known/acme-challenge`，确认原 `/health`、WebSocket 及 Studio 路由正常。
5. 配置可信 HTTPS。IP 证书需要支持 IP/webroot 的 Certbot 5.4+；可在 `/opt/dingdong-certbot` Python venv 中安装固定部署时验证过的 Certbot（本次 5.10.0）。参考 [Let's Encrypt 官方说明](https://letsencrypt.org/2026/03/11/shorter-certs-certbot/)，执行 `certbot certonly --preferred-profile shortlived --webroot --webroot-path /var/www/dingdong-acme --ip-address SERVER_IP`，根据实际账号选择联系邮箱和服务条款参数。域名证书使用相应域名签发流程。
6. 证书就绪后启用 HTTPS 部分，运行 `nginx -t` 再 reload。Node 对公网提供 `/v1/accounts/` 账号 API 和 `/v1/subscriptions` 订阅 API；Web 管理 `/api/` 仍通过 SSH 转发回环端口访问。公网账号请求由原接收密钥认证，导入使用服务器自动生成的一次性授权码。
7. IP 证书有效期较短，必须开启续期：systemd timer 每日两次运行 `/opt/dingdong-certbot/bin/certbot renew --quiet`，deploy hook 执行 `nginx -t && systemctl reload nginx`。禁用系统旧版本 Certbot 的重复 timer，确认实际命令使用支持 IP 的版本，并运行一次 `renew --dry-run --no-random-sleep-on-renew`。

验收：移除手机的本机 Node `adb reverse`，检查真实公网 HTTPS；账号页应自动显示同一公网主机。手机授权后，服务端须验证真实账号和视频动态，容器重启后从加密卷恢复并重新验证。还应检查原消息健康接口和 Studio 在线状态，不能把单次账号成功等同于整个 Studio 迁移完成。

回滚：停止 Node 服务；恢复备份的 Python compose 和原端口，停用新增 Nginx 入口后重建中转容器，保留消息卷。账号卷不自动删除。恢复前检查端口占用，避免 Nginx 与 Docker 同占 80。

## Studio 插件运行时

构建上下文必须包括 scripts/ 和 vendor/；Docker 内先编译 Studio 源码，再移除开发依赖。升级保留 accounts 数据卷和原 relay 凭据。旧 B 站任务保留原 ID/配置，不自动替换为指定 UP 主任务。X 需要服务器可用的网络出口，可在 Compose environment 中通过外部环境传入 X_PROXY；手机 VPN 不会代理服务器。平台代理不能公开成无认证代理。账号接口路径按 bilibili、x、xiaohongshu 隔离，原 Nginx /v1/accounts/ 前缀规则继续适用。

## 本机 Xray 出口（VLESS + REALITY）

Xray 可作为 Node 的专用出站代理。仅监听 `127.0.0.1:18081` 的 HTTP 代理，不开放公网代理端口。Node 保持 host 网络，使用 `X_PROXY=http://127.0.0.1:18081`；只影响 X 登录浏览器、后台接口与配图，国内平台和中转连接保持原路由。

- 内核：官方 XTLS/Xray-core 发布包；安装前核对官方 SHA-256。
- 可执行文件：`/opt/dingdong-xray/xray`。
- 私密节点配置：`/etc/dingdong-xray/config.json`，root:dingdong-proxy，0640，目录 0750。不要复制到仓库。
- systemd：`dingdong-xray.service`，普通专用用户运行、开机启动、故障重启；模板见同目录服务文件。
- 将 `compose.proxy.yaml` 的内容保存为服务器项目的 `compose.override.yaml`（已有 override 时先合并），再执行 `docker compose up -d accounts`。后续升级保留 override 和私密节点配置。
- 检查：`systemctl is-active dingdong-xray`；确认 18081 仅监听回环；在 Node 容器中通过 ProxyAgent 验证 X、接口元数据与 ClientTransaction 请求签名，再验证官方登录表单。

2026-11-17 已使用官方 v26.11.9（SHA-256：b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82）部署。默认 HeadlessChrome 标识被 X 返回 403，使用与桌面 Studio 一致的普通 Chromium 标识后官方登录表单可加载。此项网络与表单验证不代表真实账号登录或账号内容采集成功。

## 管理台与运行检查

在服务器执行 `docker compose ps` 检查 accounts 为 healthy，默认健康端点为 `http://127.0.0.1:18890/health`。用 `docker compose logs --tail=100 accounts` 查看启动日志。管理台登录步骤见项目 README。要更换端口，在项目 .env 中设置 `DINGDONG_NODE_PORT`，同步调整 SSH 隧道和 Nginx 的上游端口。

升级时在原项目目录替换源码并再次运行 `sh deploy.sh`。如需做一致的离线备份，可先停止 accounts，再备份整个 accounts 卷（含 vault.key、会话、任务和管理密钥）及部署环境配置，再用 `docker compose up -d --wait accounts` 启动。保管好备份，避免在升级时执行 `down -v`。
