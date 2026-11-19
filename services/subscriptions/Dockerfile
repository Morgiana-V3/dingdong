FROM public.ecr.aws/docker/library/node:22-bookworm-slim
ARG DEBIAN_MIRROR=deb.debian.org
RUN sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g" /etc/apt/sources.list.d/debian.sources && apt-get -o Acquire::http::Timeout=30 update && apt-get -o Acquire::http::Timeout=30 install -y --no-install-recommends chromium ca-certificates fonts-noto-cjk && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY scripts/build-studio.mjs ./scripts/build-studio.mjs
COPY vendor/studio/examples ./vendor/studio/examples
COPY vendor/studio/src ./vendor/studio/src
COPY vendor/studio/THIRD_PARTY_NOTICES.txt ./vendor/studio/THIRD_PARTY_NOTICES.txt
RUN npm run build && npm prune --omit=dev
COPY src ./src
COPY web ./web
RUN mkdir /app/data && chown node:node /app/data
USER node
ENV DATA_DIR=/app/data CHROMIUM_EXECUTABLE=/usr/bin/chromium
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=4 CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||18890)+'/health',{signal:AbortSignal.timeout(3500)}).then(async r=>{if(!r.ok||(await r.json()).service!=='dingdong-node') process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "src/server.mjs"]
