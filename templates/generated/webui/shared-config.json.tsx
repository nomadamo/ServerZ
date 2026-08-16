import path from "node:path"
import type { ServerZGeneratedConfig } from "../../../src/config.generated.js"

/**
 * Generates the "shared" slice of the webui's server-manager.json config, sourced
 * directly from ServerZ's own config so the two never drift out of sync. The webui's
 * config loader merges this on top of its own user-owned server-manager.json at
 * load/reload time - fields here always win, since ServerZ is the single source of
 * truth for anything it also uses to run the actual server.
 *
 * Field names/shapes mirror server-manager-template.json exactly (including its
 * legacy 0/1 numeric-boolean convention for the serverCfg block, same as
 * serverDZ.generated.cfg.tsx already does for the same reason: serverCfg mirrors
 * the real serverDZ.cfg file format, not idiomatic TS booleans).
 */
export async function generate(config: ServerZGeneratedConfig) {
  const { meta, server, battleye } = config

  const abs = (p: string) => (path.isAbsolute(p) ? p : path.join(meta.serverDirectory, p))

  const shared = {
    // -- RCon / BattlEye --
    rconPassword: battleye.password ?? "",
    rconPort: battleye.port ? Number(battleye.port) : undefined,
    rconIP: battleye.ip ?? "",

    // -- Paths --
    serverPath: meta.serverDirectory,
    // basename, not meta.dayZBinaryPath's full path - the webui's own
    // getServerExePath() does path.join(serverPath, serverExe) itself, so a full
    // path here doubles up into a garbled, never-matching path (confirmed live:
    // this is why the dashboard reported STOPPED despite the server running -
    // process detection was searching for a path that could never exist).
    serverExe: path.basename(meta.dayZBinaryPath),
    serverPort: meta.port,
    profilesPath: abs(meta.profilesPath),
    battleyePath: abs(meta.bePath),
    serverCfgPath: abs(meta.configPath),

    // -- Server settings (mirrors serverDZ.generated.cfg.tsx's field mapping 1:1) --
    serverCfg: {
      hostname: server.serverName,
      maxPlayers: server.maxPlayers,
      motd: server.motd,
      motdInterval: server.motdInterval,
      password: server.password ?? "",
      passwordAdmin: server.adminPassword ?? "",
      enableWhitelist: NumericBoolean(server.enableWhitelist),
      // ServerZ has no separate BattlEye on/off toggle - it's implicitly active
      // whenever battleye config exists, which it always does here.
      BattlEye: 1,
      verifySignatures: server.verifySignatures,
      forceSameBuild: NumericBoolean(server.forceSameBuild),
      guaranteedUpdates: server.guaranteedUpdates,
      allowFilePatching: NumericBoolean(server.allowFilePatching),
      steamQueryPort: server.steamQueryPort,
      maxPing: server.maxPing,
      speedhackDetection: server.speedhackDetection,
      disableVoN: NumericBoolean(server.disableVon),
      vonCodecQuality: server.vonCodecQuality,
      disable3rdPerson: NumericBoolean(server.disable3rdPerson),
      disableCrosshair: NumericBoolean(server.disableCrosshair),
      disableBaseDamage: NumericBoolean(server.disableBaseDamage),
      disableContainerDamage: NumericBoolean(server.disableContainerDamage),
      disableRespawnDialog: NumericBoolean(server.disableRespawnDialog),
      respawnTime: server.respawnTime,
      enableDebugMonitor: NumericBoolean(server.enableDebugMonitor),
      disablePersonalLight: NumericBoolean(server.disablePersonalLight),
      lightingConfig: server.lightingConfig,
      serverTime: server.serverTime,
      serverTimeAcceleration: server.serverTimeAcceleration,
      serverNightTimeAcceleration: server.serverNightTimeAcceleration,
      serverTimePersistent: NumericBoolean(server.serverTimePersistent),
      loginQueueConcurrentPlayers: server.loginQueueConcurrentPlayers,
      loginQueueMaxPlayers: server.loginQueueMaxPlayers,
      simulatedPlayersBatch: server.simulatedPlayersBatch,
      multithreadedReplication: NumericBoolean(server.multithreadedReplication),
      networkRangeClose: server.networkRangeClose,
      networkRangeNear: server.networkRangeNear,
      networkRangeFar: server.networkRangeFar,
      networkRangeDistantEffect: server.networkRangeDistantEffect,
      defaultVisibility: server.defaultVisibility,
      defaultObjectViewDistance: server.defaultObjectViewDistance,
      instanceId: server.instanceID,
      storageAutoFix: NumericBoolean(server.storageAutoFix),
      timeStampFormat: server.timestampFormat ?? "",
      logAverageFps: server.logAverageFPS,
      logMemory: server.logMemory,
      logPlayers: server.logPlayers,
      logFile: server.logFile ?? "",
      adminLogPlayerHitsOnly: NumericBoolean(server.adminLogPlayerHitsOnly),
      adminLogPlacement: NumericBoolean(server.adminLogPlacement),
      adminLogBuildActions: NumericBoolean(server.adminLogBuildActions),
      adminLogPlayerList: NumericBoolean(server.adminLogPlayerList),
      enableCfgGameplayFile: NumericBoolean(server.enableCfgGameplayFile),
      Missions: {
        DayZ: {
          template: server.template,
        },
      },
    },
  }

  return JSON.stringify(shared, null, 2)
}

function NumericBoolean(value: boolean | undefined | null): number | undefined {
  if (value === undefined || value === null) return undefined
  return value ? 1 : 0
}
