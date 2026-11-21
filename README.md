# Grain Rot — Rot Lurker Spawner (v0.1.1, test build)

UE4SS Lua mod for Grain Rot / `Helden` (Unreal Engine 5.7). **Host-only.**

## Behavior

- While the active dungeon run is in **Exploring** state, request **one Rotlurker every 1000 ms**.
- Pause automatically in the elevator, outpost, menu, and after the run ends.
- Spawn on the **authoritative host only**; clients should see native replicated enemies if the engine successfully creates them.
- No alive-enemy cap by default (`MaxAlive=0`): this intentionally accumulates enemies and may severely affect FPS after a few minutes.
- Prefer spawning a **runtime-discovered Rotlurker class** (from `HeldenCharacterPreset` or existing Rotlurker actor) at a generated `HeldenDungeonEnemyManager.SpawnLocations` transform; then request a default AI controller. Do not spawn an unrelated generic enemy using a guessed Blueprint path.
- When the exact class is not loaded, request the enemy via the reflected `HeldenCheatManager:DebugSpawnCharacter(InCharacterName)` if a live cheat manager is available. Character data name is resolved from `HeldenDataSingleton.CharacterDataTable` when possible, otherwise it uses `Rotlurker`. **The debug path may be disabled in Shipping builds.**

## Installation

1. Install a working Grain Rot UE4SS (compatible with `Helden/Binaries/Win64`).
2. Go to the [CI workflow](../../actions/workflows/ci.yml), open the latest successful run and download its artifact `GrainRotRotLurkerSpawner-v0.1.1`.
3. Extract the artifact ZIP and then the contained installation ZIP into `Grain Rot/Helden/Binaries/Win64/`.
4. Check `ue4ss/Mods/GrainRotRotLurkerSpawner/Scripts/main.lua` and `ue4ss/Mods/GrainRotRotLurkerSpawner/enabled.txt`.
5. Install the mod **on the host**. Enter a dungeon; check `UE4SS.log` entries prefixed `[GrainRotRotLurkerSpawner]`.

## Testing and troubleshooting

This is a **test build**, not yet proven in a real game session. The included GitHub Actions test checks Lua syntax, timer/gating/authority logic and a simulated native/fallback spawn. It cannot prove Unreal native spawning, AI activation, replication or usable placement.

**Expected diagnostic messages:**

- `loaded ... 1000ms`: the script loaded (not evidence of spawning).
- `dungeon active; enemy manager resolved`: confirmed active generated dungeon context.
- `character data row: ...`: actual runtime character data key was found.
- `native spawn requested`: the game function accepted the call; because its return type is `void`, actual spawning is **not** confirmed by this message.
- `CONFIRMED: Rotlurker actor(s) present in world`: a matching `HeldenCharacter.CharacterDataName`/preset was observed by the 5-second verification poll, but it may also be a naturally spawned one.
- `SPAWN FAILED`: no supported native cheat manager and no known Rotlurker class/spawn point, or actor creation failed.
- `direct fallback actor created; AI/identity need live verification`: an actor was created. This does **not** prove full Rotlurker behavior or AI initialization.
- `WARNING: native spawn calls ... no Rotlurker actor`: likely wrong character key, missing cheat permission or the Shipping build ignores the debug command.

If there is no change in game, send the `UE4SS.log` (host, one session after entering a dungeon) so the actual character key and/or spawn pathway can be established. Keep game and save backups before testing.

## Technical provenance

Reflected in user-supplied Grain Rot build `Helden-5.7.4` from [Grain-Rot-Mod-Data-Base](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base):

- `HeldenDungeonEnemyManager.SpawnLocations` (`TArray<FTransform>`)
- `HeldenDungeonActor.EnemyManager`
- `HeldenGameState.CurrentDungeonRun.State` (`Exploring=2`)
- `HeldenCharacter.CharacterDataName` and `AppliedCharacterPreset`
- `HeldenCharacterData.CharacterPreset`, `CharacterDataName`, `bDungeonEnemy`
- `HeldenCheatManager.DebugSpawnCharacter(FName InCharacterName)` (native void function)
- Rotlurker kill-achievement enum exists. **No loaded Rotlurker Blueprint class name was present in the supplied static ObjectDump.**

[Reflection inspector workflow](../../actions/workflows/inspect-reflection.yml) fetches and inspects the original user-provided mapping/dump without uploading proprietary game assets to this repository.

Change `CFG.IntervalMs` in `main.lua` to adjust cadence; `CFG.MaxAlive=0` is deliberately unlimited.
