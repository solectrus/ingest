# Stage 1: Build Crystal application (multi-arch: amd64 + arm64)
FROM 84codes/crystal:1.18.2-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    openssl-dev \
    openssl-libs-static \
    sqlite-dev \
    sqlite-static

# Copy shard files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY src ./src

# Create bin directory
RUN mkdir -p bin

# Build the application (static linking for minimal runtime dependencies)
RUN crystal build src/ingest.cr \
    --release \
    --static \
    --no-debug \
    -o bin/ingest && \
    strip bin/ingest

# Stage 2: Runtime image
FROM alpine:3.22
LABEL maintainer="georg@ledermann.dev"

# Install runtime dependencies
# Note: sqlite-libs not needed because binary is statically linked
RUN apk add --no-cache wget

ENV APP_ENV=production

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME=${BUILDTIME}

ARG VERSION
ENV VERSION=${VERSION}

ARG REVISION
ENV REVISION=${REVISION}

WORKDIR /app

# Copy compiled binary from builder
COPY --from=builder /app/bin/ingest /app/bin/ingest

# Copy static assets (favicons, manifest, etc.)
COPY public /app/public

# Expose Kemal port
EXPOSE 4567

# Healthcheck using /ping endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["wget", "--quiet", "--tries=1", "--spider", "http://localhost:4567/ping"]

CMD ["/app/bin/ingest"]
