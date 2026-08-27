# Stage 1: Build all gems (incl. dev/test) for cache
FROM ruby:4.0.6-alpine AS bundle-cache

WORKDIR /app
RUN apk add --no-cache build-base linux-headers pkgconf libffi-dev

COPY Gemfile* ./

# Prevent documentation installation
RUN echo 'gem: --no-document' >> /etc/gemrc && \
    bundle config set no-doc 'true'

RUN bundle config set path /usr/local/bundle && \
    bundle install -j4 --retry 3

# Stage 2: Only production gems
FROM ruby:4.0.6-alpine AS builder

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
FROM ruby:4.0.6-alpine
LABEL maintainer="georg@ledermann.dev"

# Add tzdata to get correct timezone, and curl for healthcheck
RUN apk add --no-cache tzdata curl

ENV RUBYOPT=--yjit \
    APP_ENV=production \
    RACK_ENV=production

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME=${BUILDTIME}

ARG VERSION
ENV VERSION=${VERSION}

ARG REVISION
ENV REVISION=${REVISION}

# Git-describe version (e.g. v0.10.1-3-g2d8f177), which - unlike VERSION -
# is a real version on branch builds, too. Used by HELIOS to show the version.
ARG COMMIT_VERSION
ENV COMMIT_VERSION=${COMMIT_VERSION}

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

# Expose Sinatra port
EXPOSE 4567

# Healthcheck using endpoint "/ping".
# During the start period, Docker probes every second. Thus the container gets
# the "healthy" status as soon as Puma listens. Without "start-interval", a
# boot that needs more than 5 seconds keeps the container in "starting" until
# the next regular probe, 30 seconds later. Orchestrators (Docker Swarm) hold
# the task in state "starting" for that time, and a reverse proxy in front of
# it can answer 404 until the task becomes "running".
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --start-interval=1s --retries=3 \
    CMD ["curl", "-fs", "http://localhost:4567/ping"]

ENTRYPOINT ["bundle", "exec"]
CMD ["puma", "--bind", "tcp://0.0.0.0:4567"]
