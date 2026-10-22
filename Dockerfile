# The only Dockerfile: cloudbuild.yaml and `gcloud run deploy --source .`
# both build from the repository root with it.
#
# Base image pinned to a version and digest so builds are reproducible. To
# update: pick the new tag, read its digest with
#   docker buildx imagetools inspect oven/bun:<version>
# and replace both below.
FROM oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d
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
