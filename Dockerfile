### Stage: build the webui (dayz-server-manager) ###
# This fork's own CI (.github/workflows/build.yml) targets Node 16, but that's EOL and
# the runtime stage's `apt install nodejs` pulls whatever Debian currently ships (20.x
# at time of writing) - native modules (better-sqlite3, node-pty) are ABI-specific, so
# this must match the runtime's actual Node version, not the older CI target.
FROM node:20-bullseye AS webui-build

WORKDIR /webui-src

# System deps for compiling native modules (in case no prebuilt binary matches this
# platform/ABI and npm falls back to building from source), plus mikero-tools'
# (makepbo) runtime library dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    python3 \
    build-essential \
    curl \
    liblzo2-2 \
    libvorbis0a \
    libvorbisfile3 \
    libvorbisenc2 \
    libogg0 \
    libuchardet0 \
    && rm -rf /var/lib/apt/lists/*

# mikero-tools (makepbo) - compiles watcher_mod/* into the .pbo files the
# player/vehicle-map feature's companion mod needs. The exact filename below can go
# stale (it already had once - this repo doesn't do GitHub releases, just publishes
# whatever's current under the "latest" branch/path), so if this 404s, check
# https://github.com/arma-actions/mikero-tools/tree/latest/linux for the current name.
RUN curl -fsSL "https://raw.githubusercontent.com/arma-actions/mikero-tools/latest/linux/depbo-tools-0.9.62-linux-amd64.tar" -o /tmp/depbo.tar \
    && mkdir -p /opt/mikero-tools \
    && tar -xf /tmp/depbo.tar --strip-components=1 -C /opt/mikero-tools \
    && rm /tmp/depbo.tar
ENV PATH="/opt/mikero-tools/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/mikero-tools/lib"

COPY dayz-server-manager/package*.json ./
COPY dayz-server-manager/ui/package*.json ./ui/
# ui/package-lock.json has drifted from ui/package.json in this fork (missing
# jquery/popper.js) - npm ci enforces an exact match and fails, npm install doesn't.
# Patching the postinstall hook (which runs "cd ui && npm ci") to use npm install
# instead, rather than passing --ignore-scripts globally - that would also skip
# native modules' (node-pty, better-sqlite3) own postinstall build/prebuild-fetch
# scripts, which are required, not just this one broken one.
RUN sed -i 's#cd ui && npm ci#cd ui \&\& npm install#' package.json
RUN npm install

COPY dayz-server-manager/ ./

# Full pipeline now, including build:pbos (mikero-tools is on PATH above) - this
# fork's build-pbos.js already handles a missing makepbo gracefully (placeholder
# dirs instead of failing), so this would have degraded safely even without the
# toolchain; now it actually compiles watcher_mod/* into real .pbo files.
RUN npm run build

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
