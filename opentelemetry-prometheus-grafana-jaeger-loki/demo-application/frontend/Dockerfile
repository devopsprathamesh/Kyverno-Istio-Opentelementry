# Pinned base image — see ../../config/versions.env DEMO_NODE_BASE_IMAGE.
FROM node:22.17.0-slim

RUN groupadd --gid 10001 appuser && \
    useradd --uid 10001 --gid appuser --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev --no-audit --no-fund

COPY server.js .

USER 10001:10001
EXPOSE 3000

ENTRYPOINT ["node", "server.js"]
