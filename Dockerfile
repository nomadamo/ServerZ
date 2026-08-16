### Stage: build the webui (dayz-server-manager) ###
# Node 16 matches this fork's own CI (.github/workflows/build.yml) - kept in sync
# to minimize native-module ABI surprises (better-sqlite3, node-pty).
FROM node:16-bullseye AS webui-build

WORKDIR /webui-src

# System deps for compiling native modules, in case no prebuilt binary matches
# this platform/ABI and npm falls back to building from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    python3 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY dayz-server-manager/package*.json ./
COPY dayz-server-manager/ui/package*.json ./ui/
# npm ci (both the root install and its own install:ui postinstall hook) fails here -
# this fork's ui/package-lock.json has drifted out of sync with ui/package.json
# (missing jquery/popper.js). npm install tolerates that; npm ci doesn't.
RUN npm install --ignore-scripts && cd ui && npm install

COPY dayz-server-manager/ ./

# Deliberately skips build:pbos here (npm run build's full pipeline) - that step
# needs a separate PBO-compiler toolchain (mikero-tools) just to build the bundled
# companion mod used by the player/vehicle-map feature. Everything else (dashboard,
# RCON, Discord bot, config editor, log viewer, restart control) doesn't need it.
# dist/mods is created empty so IngameReport.installMod()'s readdir doesn't fail on
# a missing directory; the map feature simply won't have a mod to install yet.
RUN npm run generator && npm run build:tsc && npm run build:ui
RUN mkdir -p dist/mods

# Drop devDependencies for the runtime image - keeps native modules that were just
# built/fetched for this exact platform, without carrying the whole toolchain forward.
RUN npm prune --omit=dev


### Stage: ServerZ runtime (+ Node, to run the webui) ###
FROM docker.io/oven/bun:1.3.14-debian AS runtime-base

LABEL org.opencontainers.image.title="ServerZ" \
      org.opencontainers.image.authors="GodBleak <meow@godbleak.dev>" \
      org.opencontainers.image.description="DayZ in a box! — ServerZ: A modern, container-ready DayZ server manager. Configuration so easy an infected could do it." \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://gitlab.godbleak.dev/GodBleak/ServerZ" \
      org.opencontainers.image.url="https://gitlab.godbleak.dev/GodBleak/ServerZ" \
      org.opencontainers.image.documentation="https://gitlab.godbleak.dev/GodBleak/ServerZ" \
      com.getarcaneapp.arcane.icon="https://gitlab.godbleak.dev/uploads/-/system/project/avatar/42/ServerZ_EZ.png"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt -y install --no-install-recommends \
    git \
    ca-certificates \
    libsdl2-2.0-0 \
    libcap2 \
    rsync \
    fuse-overlayfs \
    util-linux \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /serverz /dayz /install /overrides /data /root/.steam

WORKDIR /serverz

# Copy lockfile and package.json first for better layer caching
COPY serverz/package.json serverz/bun.lock* ./
COPY serverz/src/lib/steamapi/depot-client/package.json ./src/lib/steamapi/depot-client/

RUN bun install --frozen-lockfile --production

# Copy source after deps so source changes don't bust the install layer
COPY serverz/healthcheck.sh ./
COPY serverz/jsx-runtime.ts ./
COPY serverz/tsconfig.json ./
COPY serverz/templates/ templates/
COPY serverz/config/ config/
COPY serverz/src/ src/

RUN chmod +x healthcheck.sh

# The webui, built in the stage above - matches WEBUI_DIRECTORY/WEBUI_EXECUTABLE's
# defaults (/webui, node dist/index.js).
COPY --from=webui-build /webui-src/dist /webui/dist
COPY --from=webui-build /webui-src/node_modules /webui/node_modules
COPY --from=webui-build /webui-src/package.json /webui/package.json

# Default Game port
EXPOSE 2302/udp
# Default BattlEye port
EXPOSE 2304/udp
# Default RCon port
EXPOSE 2305/udp
# Default Steam query port
EXPOSE 27015/udp
# Webui default (serverport + 11, see server-manager-template.json)
EXPOSE 2313/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=20m --retries=3 CMD [ "/serverz/healthcheck.sh" ]

ENV ALLOW_CONFIG_MUTATIONS=true
ENV USE_USERXATTR=false
ENV NODE_CONFIG_PARSER=/serverz/src/config/node-config-parser.js


FROM runtime-base AS rootful

CMD ["bun", "src/index.ts"]


FROM runtime-base AS rootless

ENV USE_USERXATTR=true

CMD ["unshare", "--user", "--map-root-user", "--mount", "bun", "src/index.ts"]
