# Multi-stage build for Jobsuche MCP Server
# Stage 1: Build
FROM rust:1.92-bookworm as builder

WORKDIR /build

# Copy dependency files first (layer caching)
COPY Cargo.toml Cargo.lock ./
COPY jobsuche-mcp-server/Cargo.toml ./jobsuche-mcp-server/

# Copy source code
COPY . .

# Build release binary
RUN cargo build --release --bin jobsuche-mcp-server

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app directory and user with UID 1000 (for Kubernetes securityContext)
RUN mkdir -p /app && \
    groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/sh -d /app appuser && \
    chown -R 1000:1000 /app

# Copy binary from builder
COPY --from=builder /build/target/release/jobsuche-mcp-server /usr/local/bin/jobsuche-mcp-server

# Set environment defaults (can be overridden)
ENV JOBSUCHE_API_URL="" \
    JOBSUCHE_API_KEY="" \
    JOBSUCHE_DEFAULT_PAGE_SIZE="25" \
    JOBSUCHE_MAX_PAGE_SIZE="100"

# MCP runs on stdio, but expose port for health checks
EXPOSE 3000

# Switch to non-root user
USER 1000

# Set working directory
WORKDIR /app

# Run the MCP server
CMD ["jobsuche-mcp-server"]

