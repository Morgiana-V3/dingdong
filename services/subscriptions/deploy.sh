#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker compose version >/dev/null
if [ -z "${DINGDONG_ENV_FILE:-}" ] && [ ! -f .env ]; then
  if [ -r ../relay/.env ]; then
    (umask 077; set -C; printf '%s\n' 'DINGDONG_ENV_FILE=../relay/.env' > .env)
  elif [ -r /opt/dingdong/.env ]; then
    (umask 077; set -C; printf '%s\n' 'DINGDONG_ENV_FILE=/opt/dingdong/.env' > .env)
  else
    (umask 077; set -C; cat .env.example > .env)
    printf '%s\n' '已创建 .env。手机连接与推送需要填写现有中转的两个密钥后再次部署。'
  fi
fi
docker compose up -d --build --wait accounts
docker compose exec -T accounts node -e "console.log('管理台：http://127.0.0.1:' + process.env.PORT)"
printf '%s\n' '首次登录请在服务器执行 docker compose exec accounts cat /app/data/admin.key（使用与部署相同的 Compose 配置）。'
