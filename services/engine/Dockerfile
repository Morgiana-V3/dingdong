ARG NODE_IMAGE=public.ecr.aws/docker/library/node:22-bookworm-slim
FROM ${NODE_IMAGE}

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY src ./src
COPY web ./web
COPY sdk ./sdk
COPY scripts ./scripts

RUN mkdir -p /app/data /app/plugins && chown -R node:node /app/data /app/plugins
USER node

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=18890
ENV DATA_DIR=/app/data
ENV PLUGINS_DIR=/app/plugins

EXPOSE 18890
CMD ["node", "src/server.ts"]
