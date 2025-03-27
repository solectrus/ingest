FROM ruby:3.4.2-alpine AS builder

WORKDIR /app

# Install build dependencies for native gems (like json)
RUN apk add --no-cache build-base

# Copy only Gemfile and Gemfile.lock to leverage caching
COPY Gemfile* /app/

# Install gems
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle install -j4 --retry 3 && \
    bundle clean --force

# Copy the rest of the app files after installing gems
COPY . .

# Final runtime image
FROM ruby:3.4.2-alpine
LABEL maintainer="georg@ledermann.dev"

# Add tzdata to get correct timezone
RUN apk add --no-cache tzdata

# Decrease memory usage
ENV MALLOC_ARENA_MAX=2

ENV APP_ENV=production
ENV RACK_ENV=production

WORKDIR /app

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/
COPY --from=builder /app /app

EXPOSE 4567

ENTRYPOINT ["bundle", "exec"]
CMD ["rackup", "--host", "0.0.0.0", "--port", "4567"]
