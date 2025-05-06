# Stage 1: Build all gems (incl. dev/test) for cache
FROM ruby:3.4.3-alpine AS bundle-cache

WORKDIR /app
RUN apk add --no-cache build-base

COPY Gemfile* ./

# Prevent documentation installation
RUN echo 'gem: --no-document' >> /etc/gemrc && \
    bundle config set no-doc 'true'

RUN bundle config set path /usr/local/bundle && \
    bundle install -j4 --retry 3

# Stage 2: Only production gems
FROM ruby:3.4.3-alpine AS builder

WORKDIR /app
RUN apk add --no-cache build-base

COPY Gemfile* ./

# Copy cached gems from previous stage
COPY --from=bundle-cache /usr/local/bundle /usr/local/bundle

# Install only production gems
RUN bundle config set path /usr/local/bundle && \
    bundle config set without 'development test' && \
    bundle install --jobs $(nproc) --retry 3 && \
    bundle clean --force && \
    # Remove unneeded files from installed gems (cache, .git, *.o, *.c)
    rm -rf /usr/local/bundle/ruby/*/cache && \
    rm -rf /usr/local/bundle/ruby/*/gems/*/.git && \
    find /usr/local/bundle -type f \( \
    -name '*.c' -o \
    -name '*.o' -o \
    -name '*.log' -o \
    -name 'gem_make.out' \
    \) -delete && \
    find /usr/local/bundle -name '*.so' -exec strip --strip-unneeded {} +

# Copy the rest of the app files after installing gems
COPY . .

# Final runtime image
FROM ruby:3.4.3-alpine
LABEL maintainer="georg@ledermann.dev"

# Add tzdata to get correct timezone, and curl for healthcheck
RUN apk add --no-cache tzdata curl

ENV MALLOC_ARENA_MAX=2 \
    RUBYOPT=--yjit \
    APP_ENV=production \
    RACK_ENV=production

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME=${BUILDTIME}

ARG VERSION
ENV VERSION=${VERSION}

ARG REVISION
ENV REVISION=${REVISION}

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

# Expose Sinatra port
EXPOSE 4567

# Healthcheck using endpoint "/health"
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["curl", "-fs", "http://localhost:4567/health"]

ENTRYPOINT ["bundle", "exec"]
CMD ["rackup", "--host", "0.0.0.0", "--port", "4567"]
