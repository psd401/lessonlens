FROM oven/bun:1 AS base
WORKDIR /app/CloudRunBackend

# Install dependencies
COPY CloudRunBackend/package.json CloudRunBackend/bun.lock* ./
RUN bun install --frozen-lockfile

# Copy source
COPY CloudRunBackend/src ./src

# Copy shared modules (preserves ../../../shared relative import paths)
COPY shared /app/shared

# Set environment
ENV NODE_ENV=production
ENV PORT=8080

# Expose port
EXPOSE 8080

# Run the app
CMD ["bun", "run", "src/index.ts"]
