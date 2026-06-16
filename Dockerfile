# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────
# Stage 1 · build the React/TypeScript frontend
# ─────────────────────────────────────────────
FROM node:20-alpine AS web
WORKDIR /app/web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# ─────────────────────────────────────────────
# Stage 2 · build the TypeScript backend
# ─────────────────────────────────────────────
FROM node:20-alpine AS server
WORKDIR /app/server
COPY server/package*.json ./
RUN npm ci
COPY server/ ./
# Generate the Prisma client (needed for the TypeScript build)
RUN npx prisma generate
RUN npm run build

# ─────────────────────────────────────────────
# Stage 3 · lean production runtime
# ─────────────────────────────────────────────
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app/server

# production dependencies + Prisma schema/migrations
COPY server/package*.json ./
COPY server/prisma ./prisma
RUN npm ci --omit=dev && npx prisma generate && npm cache clean --force

# compiled backend + built frontend (served statically by the API)
COPY --from=server /app/server/dist ./dist
COPY --from=web /app/web/dist /app/web/dist

# entrypoint: applies migrations + seed when DATABASE_URL is set, else legacy mode
COPY server/docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# non-root user
RUN addgroup -S soc && adduser -S soc -G soc && chown -R soc:soc /app
USER soc

EXPOSE 4000
# Recetor de syslog das firewalls (UDP/TCP). Mapeie 514→5514 no host se quiser.
EXPOSE 5514/udp
EXPOSE 5514/tcp
HEALTHCHECK --interval=30s --timeout=4s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:4000/api/health || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/index.js"]
