FROM node:24.15.0-bookworm-slim

# Install zstd + postgresql-client
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl zip bash postgresql-client zstd && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && \
    npm cache clean --force

COPY server.js .
COPY public/ public/
COPY backup.sh backup.sh
COPY scripts/ scripts/
RUN chmod +x backup.sh
RUN chmod +x scripts/*

# Backups stored here - mount a volume to this path in Coolify
RUN mkdir -p /backups && chown -R node:node /backups /app
USER node

EXPOSE 3000
CMD ["npm", "start"]
