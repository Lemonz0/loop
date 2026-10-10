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

# Copy package descriptors and install only production dependencies
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled JavaScript from builder
COPY --from=builder /app/dist ./dist

# Create uploads directory
RUN mkdir -p /app/uploads && chown -R node:node /app

USER node

EXPOSE 8080

CMD ["node", "dist/server.js"]
