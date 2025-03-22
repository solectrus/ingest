# syntax=docker/dockerfile:1
FROM ruby:3.4.2-alpine AS builder

WORKDIR /app
COPY . .

# Install build dependencies for native gems (like json)
RUN apk add --no-cache build-base

# Install gems in deployment mode
RUN bundle config set deployment 'true' \
    && bundle config set without 'development test' \
    && bundle install

# Final runtime image
FROM ruby:3.4.2-alpine

WORKDIR /app
COPY --from=builder /app /app

EXPOSE 4567
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "4567"]
