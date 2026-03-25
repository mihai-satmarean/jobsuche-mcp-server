# Multi-stage build for Jobsuche MCP Server
# Stage 1: Build Rust binary (standard glibc - wolfi-base uses glibc, not musl)
FROM rust:1.88-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy dependency files first (layer caching)
COPY Cargo.toml Cargo.lock ./
COPY jobsuche-mcp-server/Cargo.toml ./jobsuche-mcp-server/

# Copy source code
COPY . .

# Build release binary
RUN cargo build --release --bin jobsuche-mcp-server

# Stage 2: Nanobot wrapper runtime (obot-compatible containerized MCP)
# Nanobot wraps the stdio MCP server and exposes it over HTTP on port 8099
# Note: wolfi-base (chainguard) uses glibc, compatible with standard Rust builds
FROM cgr.dev/chainguard/wolfi-base:latest

USER root

RUN apk add --no-cache glibc-locale-posix

# Copy nanobot binary from the official nanobot image
COPY --from=ghcr.io/nanobot-ai/nanobot:v0.0.58 /usr/local/bin/nanobot /usr/local/bin/nanobot

# Copy nanobot entrypoint script
COPY scripts/nanobot.sh /usr/local/bin/nanobot.sh
RUN chmod +x /usr/local/bin/nanobot.sh

# Copy compiled binary from builder stage
COPY --from=builder /build/target/release/jobsuche-mcp-server /usr/local/bin/jobsuche-mcp-server

# Create user and directories (UID 1000 required by obot security policy)
RUN mkdir -p /home/user/.local/bin /home/user/.config/nanobot && \
    chown -R 1000:0 /home/user && \
    chown -R 1000:0 /usr/local

USER 1000

ENV HOME=/home/user
ENV DOCKER_CONTAINER=true
ENV JOBSUCHE_API_URL="" \
    JOBSUCHE_API_KEY="" \
    JOBSUCHE_DEFAULT_PAGE_SIZE="25" \
    JOBSUCHE_MAX_PAGE_SIZE="100" \
    RUST_LOG="info"

# Nanobot listens on 8099 (obot containerized runtime convention)
EXPOSE 8099

WORKDIR /home/user

# nanobot.sh wraps the stdio server and exposes it over HTTP
ENTRYPOINT ["nanobot.sh", "jobsuche-mcp-server"]
