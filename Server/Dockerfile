# Multi-stage production Dockerfile for Liquid Glass Server
ARG NODE_IMAGE=node:22-alpine
FROM ${NODE_IMAGE} AS builder

WORKDIR /app

# Install build dependencies
COPY package*.json tsconfig.json ./
RUN npm ci

# Copy source and compile TypeScript
COPY src/ ./src/
RUN npm run build

# Production runtime stage
FROM ${NODE_IMAGE} AS runner

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
ENV HOST=0.0.0.0

# Copy package descriptors and install only production dependencies
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled JavaScript from builder
COPY --from=builder /app/dist ./dist

# Keep all writable runtime directories available to the unprivileged process.
RUN mkdir -p /app/data /app/uploads /app/logs && chown -R node:node /app

USER node

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "dist/server.js"]
