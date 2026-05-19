FROM node:24.15.0-bookworm-slim

ARG SUPABASE_CLI_VERSION=2.100.1
ARG TARGETARCH

# Install Supabase CLI + zip + postgresql-client
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl zip bash postgresql-client && \
    rm -rf /var/lib/apt/lists/* && \
    BUILD_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    case "$BUILD_ARCH" in \
      amd64|x86_64) SUPABASE_ARCH=amd64 ;; \
      arm64|aarch64) SUPABASE_ARCH=arm64 ;; \
      *) echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_${SUPABASE_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/supabase /usr/local/bin/supabase-go && \
    supabase --version

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && \
    npm cache clean --force

COPY server.js .
COPY public/ public/
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Backups stored here - mount a volume to this path in Coolify
RUN mkdir -p /backups && chown -R node:node /backups /app
USER node

EXPOSE 3000
CMD ["npm", "start"]
