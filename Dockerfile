# syntax=docker/dockerfile:1
FROM ruby:3.4.2-alpine AS builder

WORKDIR /app

# Install build dependencies for native gems (like json)
RUN apk add --no-cache build-base

# Copy only Gemfile and Gemfile.lock to leverage caching
COPY Gemfile Gemfile.lock ./

# Install gems in deployment mode
RUN bundle config set deployment 'true' \
    && bundle config set without 'development test' \
    && bundle install --path vendor/bundle

# Copy the rest of the app files after installing gems
COPY . .

# Final runtime image
FROM ruby:3.4.2-alpine

COPY --from=builder /app /app

WORKDIR /app

EXPOSE 4567

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "4567"]
