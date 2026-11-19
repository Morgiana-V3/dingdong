# Docker 部署与迁移

## 初次部署

准备 Docker Engine 与 Compose 插件。可在仓库的 `services/relay/` 中直接运行 Compose，也可将该目录内容复制到服务器的独立部署目录，例如 `/opt/dingdong`。如需在同一服务器部署订阅服务，参照 [两套服务的部署说明](../services/subscriptions/deploy/README.md)。

已有实例升级时，沿用原部署目录，或在新目录启动前将原 Compose 项目名写入部署用的 `.env`，例如 `COMPOSE_PROJECT_NAME=dingdong`。通过原目录中的 `docker compose ps` 核对项目，项目名也可从运行容器的 `com.docker.compose.project` 标签读取。项目名决定使用哪个命名卷。

在该目录创建 `.env`（不提交版本库），分别生成两个不同的 32 字符以上随机值：

```sh
python3 -c 'import secrets; print(secrets.token_urlsafe(36))'
```

```dotenv
DINGDONG_SEND_TOKEN=替换为独立随机发送密钥
DINGDONG_READ_TOKEN=替换为独立随机接收密钥
DINGDONG_BIND=0.0.0.0
DINGDONG_PORT=8080
```

将 `.env` 权限设为 600，然后启动：

```sh
chmod 600 .env
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8080/health
```

若使用公网 IP 直连，在云安全组放行所选 TCP 端口。若使用反向代理，设置 `DINGDONG_BIND=127.0.0.1`，代理对外提供 HTTPS 并支持 WebSocket Upgrade。

App 设置填 `服务器IP:8080`（自动按 HTTP 处理）或 `https://你的域名`，再填接收密钥。脚本只持有发送密钥。切换服务器不需要重新打包 APK。

基础镜像来自 Docker 官方发布在 AWS ECR 的 Python 镜像，已固定摘要。公开参考：https://gallery.ecr.aws/docker/library/python 。构建仍需访问 PyPI 下载依赖。

`requirements.txt` 固定直接依赖；`requirements.lock` 记录本次 Linux 镜像内的完整依赖版本，供排查和复现参考。当前 Dockerfile 不读取该快照，因此重新构建时部分间接依赖可能更新。需要完全保持本次运行环境时，使用下面的镜像导入方式。

## 不依赖网络重新构建的镜像迁移

旧服务器：

```sh
docker save dingdong-server:0.1.0 | gzip > dingdong-server-0.1.0.tar.gz
```

新服务器导入镜像、放置 compose.yaml 和 `.env`：

```sh
gzip -dc dingdong-server-0.1.0.tar.gz | docker load
docker compose up -d --no-build
```

镜像只含程序，不含 `.env` 或消息库。源码升级后重新构建；容器重建不会删除命名卷。

## 连同待收消息迁移

1. 暂停电脑发送，让在线手机先完成接收。停止旧容器，避免数据库持续写入。
2. 保留 `.env`、compose.yaml、镜像以及数据卷内容。不要执行 `docker compose down -v`。
3. 导出数据库卷。以下辅助容器复用本项目镜像，不需额外下载：

```sh
docker compose stop
docker compose run --rm --no-deps --user root -v "$PWD:/backup" dingdong python -c "import tarfile; archive=tarfile.open('/backup/dingdong-data.tar.gz','w:gz'); archive.add('/app/data',arcname='data'); archive.close()"
chmod 600 dingdong-data.tar.gz
```

4. 将文件安全复制到新服务器，在新环境恢复（只对新建的空数据卷操作）：

```sh
docker compose run --rm --no-deps --user root -v "$PWD:/backup:ro" dingdong python -c "import tarfile; archive=tarfile.open('/backup/dingdong-data.tar.gz'); archive.extractall('/app',filter='data'); archive.close()"
docker compose run --rm --no-deps --user root dingdong chown -R 10001:10001 /app/data
docker compose up -d --no-build
```

5. 健康检查成功后，修改 App 地址和脚本的 `DINGDONG_URL`。地址变化时 App 要求再次填写接收密钥。

命名卷名称由 Compose 项目名决定。上述命令通过服务挂载操作数据，避免手工猜测卷名。备份包含未送达正文，应按私密资料保管。已送达内容在手机导出，服务器备份不含这些正文。

## 运行边界

- 单实例、单 worker、单接收手机。不要直接扩成多个副本。
- 端口可通过 `.env` 调整；数据库无需对公网开放。
- HTTP 支持测试与个人直连，凭据和正文不加密传输；HTTPS 使用受信任证书，App 不绕过证书校验。
- 不配置 root 密码到容器。SSH 登录资料与应用接口凭据独立。
- 更新前备份数据卷与配置。`docker compose up -d --build` 更新容器，保留消息卷。
