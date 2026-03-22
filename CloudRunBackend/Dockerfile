FROM oven/bun:1
WORKDIR /app

# Copy shared prompts (referenced as ../../../shared/prompts from src/routes/)
COPY shared/ ./shared/

# Copy backend dependencies
COPY CloudRunBackend/package.json CloudRunBackend/bun.lock ./CloudRunBackend/
WORKDIR /app/CloudRunBackend
RUN bun install --frozen-lockfile --production

# Copy backend source
COPY CloudRunBackend/src ./src

EXPOSE 8080
ENV PORT=8080

CMD ["bun", "run", "src/index.ts"]
