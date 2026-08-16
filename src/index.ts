import { config } from "#config"
import { logger } from "#lib/logger"
import { createSteamAPI } from "#lib/steamapi"
import { hang } from "#lib/hang"
import { Server } from "./server.js"
import { overlay } from "./overlay.js"
import { wipe } from "./wipe.js"
import { installDirectSignalShutdownHandlers, installFatalShutdownHandlers } from "./shutdown.js"
import qrcode from "qrcode-terminal"
import type { QrChallenge } from "depot-client/src/types.js"

installFatalShutdownHandlers()

async function main() {
  const removeDirectSignalShutdownHandlers = installDirectSignalShutdownHandlers()
  const steam = createSteamAPI({
    adapter: config.steam.steamApiAdapter,
    dataDir: config.steam.configDirectory,
    credentialsCacheDir: `${config.steam.configDirectory}/auth`,
    machineName: "serverz",
    loginTimeout: config.steam.steamContentTimeoutMs,
    onQRChallenge,
    remote: {
      transport: config.steam.steamContentTransport,
      socketPath: config.steam.steamContentSocket,
      url: config.steam.steamContentUrl,
      socketIoPath: config.steam.steamContentSocketIoPath,
      timeoutMs: config.steam.steamContentTimeoutMs,
    },
  })
  if (config.steam.echoMinorRemoteSteamDetails || config.steam.steamApiAdapter === "local") steam.on("debug", logger.scrub().debug)
  const server = new Server(steam)

  if (config.meta.wipe === true || config.meta.wipe === "dry-run") {
    await wipe()
    await hang({ handleSignals: false })
  }

  await overlay.configure()

  const steamNeeded = !config.meta.skipUpdate || !config.meta.skipMods
  if (steamNeeded) await server.doSteamLogin()

  if (!config.meta.skipUpdate) await server.updateServer()
  if (!config.meta.skipMods) await server.updateMods()
  await server.loadMods()
  if (config.meta.cleanMods) await server.cleanMods()
  if (!config.meta.skipMap) await server.updateMap()
  await server.applyTemplates()

  // Started after applyTemplates() generates shared-config.json, deliberately - the
  // webui's config-watcher is supposed to pick up that file's later appearance via a
  // live reload, but that doesn't reliably fire in this environment (untraced, maybe
  // an overlay.fs/inotify interaction) - starting after it already exists sidesteps
  // needing that to work at all, so the RCON password/paths are correct from the
  // webui's very first config read, not "eventually, if the watcher cooperates".
  // Trade-off: the webui is no longer reachable during Steam login/update/mod install,
  // only from here through the actual server starting - still independent of
  // START_DAYZ_SERVER/whether the server itself boots successfully, though.
  await server.startWebUI()

  if (config.meta.startDayZServer) {
    removeDirectSignalShutdownHandlers()
    await server.start()
  } else {
    logger.warn("Server start disabled. START_DAYZ_SERVER may be set to false")
    await hang({ handleSignals: false }) // prevent boot-loop on containers with restart=unless-stopped
  }
}

void main()

function onQRChallenge(challenge: QrChallenge) {
  logger.info("QR code challenge received. Please scan the following QR code with your Steam mobile app to log in:")
  logger.info(`QR Challenge URL: ${challenge.qrChallengeUrl}`)
  qrcode.generate(challenge.qrChallengeUrl, { small: true })
}
