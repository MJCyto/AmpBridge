# Multi-stage Dockerfile for AmpBridge
# This creates a production-ready image with automatic database seeding

# Stage 1: Build stage
FROM elixir:1.14-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    python3 \
    make \
    gcc \
    g++ \
    linux-headers

# Set environment variables
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=your_secret_key_base_here_replace_in_production

# Create app directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./
COPY config ./config

# Install Elixir dependencies
# Set environment variables to handle QEMU emulation issues
ENV ERL_SSL_VERSION="tlsv1.2"
ENV ERL_FLAGS="+JMsingle true"
ENV HEX_HTTP_CONCURRENCY=1
ENV HEX_HTTP_TIMEOUT=120

# Update CA certificates and set SSL options
RUN apk add --no-cache ca-certificates && \
    update-ca-certificates

RUN mix local.hex --force && \
    mix local.rebar --force && \
    ERL_FLAGS="+JMsingle true" mix deps.get --only prod && \
    ERL_FLAGS="+JMsingle true" mix deps.compile

# Copy assets
COPY assets ./assets
COPY priv ./priv

# Install Node.js dependencies and build assets
RUN cd assets && \
    npm install && \
    npm run deploy

# Copy source code
COPY lib ./lib

# Compile the application
RUN mix compile

# Create release
RUN mix release

# Create database (seeding will happen at runtime)
ENV DATABASE_PATH=/app/amp_bridge_prod.db
RUN mix ecto.create && \
    mix ecto.migrate

# Stage 2: Runtime stage
FROM elixir:1.15-alpine AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    sqlite \
    bash \
    mosquitto \
    mosquitto-clients \
    curl

# Create non-root user and add to dialout group for serial device access
RUN adduser -D -s /bin/sh ampbridge && \
    adduser ampbridge dialout

# Create app directory
WORKDIR /app

# Copy the release from builder stage
COPY --from=builder --chown=ampbridge:ampbridge /app/_build/prod/rel/amp_bridge ./

# Database will be created at runtime

# Copy the seeding script
COPY --chown=ampbridge:ampbridge priv/repo/seeds.exs /app/priv/repo/seeds.exs

# Copy startup script and Mosquitto config
COPY --chown=ampbridge:ampbridge docker/start.sh /app/start.sh
COPY --chown=ampbridge:ampbridge docker/mosquitto.conf /app/mosquitto.conf
RUN chmod +x /app/start.sh

# Create data directory for SQLite database and Mosquitto
RUN mkdir -p /app/data/mosquitto && chown -R ampbridge:ampbridge /app/data

# Create a volume mount point for persistent data
# To persist the database, run with: -v /path/to/host/data:/app/data
VOLUME ["/app/data"]

# Switch to non-root user
USER ampbridge

# Expose ports
EXPOSE 4000 1885

# Set environment variables
ENV MIX_ENV=prod
ENV PORT=4000
ENV DATABASE_PATH=/app/data/amp_bridge.db
ENV MQTT_HOST=0.0.0.0
ENV MQTT_PORT=1885
ENV SECRET_KEY_BASE=your_secret_key_base_here_replace_in_production_with_64_byte_random_string

# Use startup script
CMD ["/app/start.sh"]
