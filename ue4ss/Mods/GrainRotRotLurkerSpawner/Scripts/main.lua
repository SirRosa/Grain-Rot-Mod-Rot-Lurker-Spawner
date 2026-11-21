-- Grain Rot / Helden 5.7.4 - Rot Lurker Spawner, v0.1.0 (test)
-- Tested against the supplied USMAP/ObjectDump at compile/reflection level only.
-- Mutates server world on the UE4SS game thread. Never uses os.clock for intervals.
local CFG = {
    IntervalMs = 1000,
    EnemyMatch = "rotlurker",
    FallbackName = "Rotlurker",
    MaxAlive = 0,              -- 0 = unlimited (requested: every second, indefinitely)
    DiscoveryRetryTicks = 15,
    VerifyTicks = 5,
    MissingSpawnWarningTicks = 15,
}
local TAG = "[GrainRotRotLurkerSpawner] "
local function log(message) print(TAG .. tostring(message) .. "\n") end
local function get(obj, key)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[key] end)
    return ok and value or nil
end
local function valid(obj)
    if obj == nil then return false end
    local ok, yes = pcall(function() return obj:IsValid() end)
    return ok and yes == true
end
local function name(obj)
    if not valid(obj) then return "" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value) or tostring(obj)
end
local function nonDefault(obj)
    return valid(obj) and not name(obj):find("Default__", 1, true)
end
local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
local function weak(value)
    if valid(value) then return value end
    local ok, result = pcall(function() return value:Get() end)
    return ok and result or nil
end
local function enum(value)
    if type(value) == "number" then return value end
    if value == nil then return nil end
    local valueString = tostring(value)
    return tonumber(valueString) or (valueString:find("Exploring",1,true) and 2)
        or (valueString:find("ElevatorRideDown",1,true) and 1)
        or (valueString:find("EndScreen",1,true) and 3) or nil
end
local function all(cls)
    local ok, result = pcall(FindAllOf, cls)
    return (ok and type(result) == "table") and result or {}
end
local function first(cls)
    local ok, obj = pcall(FindFirstOf, cls)
    if ok and nonDefault(obj) then return obj end
    for _, candidate in ipairs(all(cls)) do
        if nonDefault(candidate) then return candidate end
    end
    return nil
end
local function vector(value)
    if value == nil then return nil end
    local x, y, z = tonumber(get(value, "X")), tonumber(get(value, "Y")), tonumber(get(value, "Z"))
    if x and y and z then return {X=x, Y=y, Z=z} end
    return nil
end
local function actorPosition(actor)
    local ok, value = pcall(function() return actor:K2_GetActorLocation() end)
    return ok and vector(value) or nil
end
local function matches(value)
    if value == nil then return false end
    local s = tostring(value):lower():gsub("[_%s%-]", "")
    return s:find(CFG.EnemyMatch, 1, true) ~= nil
end
local function isRotLurker(actor)
    if not nonDefault(actor) then return false end
    if matches(get(actor, "CharacterDataName")) then return true end
    local preset = get(actor, "AppliedCharacterPreset") or get(actor, "CharacterPreset")
    return nonDefault(preset) and matches(name(preset))
end
local function isAlive(actor)
    local state = enum(get(actor, "CharacterState"))
    return nonDefault(actor) and state ~= 1
end
local S = {
    tick = 0, manager = nil, dungeon = nil, gm = nil, gs = nil,
    player = nil, cheat = nil, cheatAttempted = nil,
    enemyName = nil, enemyClass = nil, preset = nil,
    lastDiscovery = -CFG.DiscoveryRetryTicks, previousRun = nil,
    requests = 0, directSpawns = 0, observed = 0,
    lastSeen = 0, lastVerify = 0, lastWarn = -CFG.MissingSpawnWarningTicks,
    failures = 0, hooked = false,
}
local function resetWorld()
    S.manager = nil
    S.dungeon = nil
    S.player = nil
    S.cheat = nil
    S.cheatAttempted = nil
    S.lastDiscovery = -CFG.DiscoveryRetryTicks
    S.lastSeen = 0
    S.lastVerify = 0
end
local function context()
    if not nonDefault(S.gm) then
        S.gm = first("HeldenGameMode") or first("GameModeBase")
    end
    if not nonDefault(S.gm) then return nil end -- client must never spawn
    if not nonDefault(S.gs) then S.gs = first("HeldenGameState") end
    if not valid(S.gs) then return nil end
    local run = get(S.gs, "CurrentDungeonRun")
    local state = enum(get(run, "State"))
    if state ~= 2 then
        if S.previousRun == 2 then
            log("left dungeon; spawn timer paused")
            resetWorld()
        end
        S.previousRun = state
        return nil
    end
    local dungeon = get(run, "DungeonActor")
    if not nonDefault(dungeon) then return nil end
    local manager = get(dungeon, "EnemyManager")
    if not nonDefault(manager) then return nil end
    local worldOk, world = pcall(function() return dungeon:GetWorld() end)
    if not worldOk or not valid(world) then return nil end
    if dungeon ~= S.dungeon then
        resetWorld()
        S.dungeon = dungeon
        log("dungeon active; enemy manager resolved")
    end
    S.previousRun = 2
    S.manager = manager
    return {world=world, dungeon=dungeon, manager=manager}
end
local function chooseSpawnPoint(manager)
    local locations = get(manager, "SpawnLocations")
    local ok, count = pcall(function() return #locations end)
    if not ok or type(count) ~= "number" or count < 1 then return nil end
    -- The actual dungeon's generated spawn transforms are preferable to
    -- arbitrary coordinates next to the player (walls, gaps, ceilings).
    local index = math.random(1, math.min(count, 10000))
    local tx = unwrap(locations[index])
    return vector(get(tx, "Translation") or get(tx, "Location") or get(tx, "Position"))
end
local function findNameFromDataTable()
    local singleton = first("HeldenDataSingleton")
    if not valid(singleton) then return nil end
    local tableObj = get(singleton, "CharacterDataTable")
    if not valid(tableObj) then return nil end
    local ok, rows = pcall(function() return tableObj:GetRowNames() end)
    if ok and rows then
        local yes, count = pcall(function() return #rows end)
        if yes and type(count) == "number" then
            for i = 1, math.min(count, 5000) do
                local rowName = unwrap(rows[i])
                if matches(rowName) then return tostring(rowName) end
            end
        end
    end
    -- Some UE4SS versions expose the TMap instead of UDataTable:GetRowNames.
    local success, map = pcall(function() return tableObj:GetRowMap() end)
    if success and type(map) == "table" then
        for rowName, row in pairs(map) do
            if matches(rowName) or matches(get(row, "DataName")) or
                matches(get(row, "FriendlyName")) then
                return tostring(get(row, "DataName") or rowName)
            end
        end
    end
    return nil
end
local function findPresetAndClass()
    -- The static 2026-11-20 ObjectDump does not include a BP_Rotlurker asset;
    -- discover it from runtime loaded presets or living enemies, do not guess.
    for _, actor in ipairs(all("HeldenCharacter")) do
        if isRotLurker(actor) then
            local ok, cls = pcall(function() return actor:GetClass() end)
            if ok and valid(cls) then
                S.enemyClass = cls
                S.preset = get(actor, "AppliedCharacterPreset") or get(actor, "CharacterPreset")
                return true
            end
        end
    end
    for _, preset in ipairs(all("HeldenCharacterPreset")) do
        if matches(name(preset)) then
            local cls = get(preset, "CharacterClass")
            if valid(cls) then
                S.enemyClass, S.preset = cls, preset
                return true
            end
        end
    end
    return false
end
local function discover()
    if S.tick - S.lastDiscovery < CFG.DiscoveryRetryTicks then return end
    S.lastDiscovery = S.tick
    if not S.enemyName then
        S.enemyName = findNameFromDataTable()
        if S.enemyName then log("character data row: " .. S.enemyName) end
    end
    if not valid(S.enemyClass) then
        if findPresetAndClass() then
            log("Rotlurker runtime class resolved: " .. name(S.enemyClass))
        end
    end
end
local function findHostController()
    if nonDefault(S.player) then return S.player end
    local fallback
    for _, pc in ipairs(all("HeldenPlayerController")) do
        if nonDefault(pc) then
            local ok, localController = pcall(function() return pc:IsLocalController() end)
            if ok and localController == true then S.player = pc; return pc end
            fallback = fallback or pc
        end
    end
    S.player = fallback
    return fallback
end
local function cheatFor(pc)
    if not nonDefault(pc) then return nil end
    local cheat = get(pc, "CheatManager")
    if valid(cheat) and nonDefault(cheat) then return cheat end
    if S.cheatAttempted ~= pc then
        S.cheatAttempted = pc
        local ok, err = pcall(function() pc:EnableCheats() end)
        if not ok then log("EnableCheats unavailable: "..tostring(err)) end
        cheat = get(pc, "CheatManager")
        if nonDefault(cheat) then return cheat end
    end
    -- A native cheat manager is per-controller; do not call Default__ objects.
    for _, candidate in ipairs(all("HeldenCheatManager")) do
        if nonDefault(candidate) then return candidate end
    end
    return nil
end
local function nativeSpawn(pc, target)
    local cheat = cheatFor(pc)
    if not nonDefault(cheat) then return false, "no live HeldenCheatManager" end
    S.cheat = cheat
    local enemyName = S.enemyName or CFG.FallbackName
    -- Reflected signature: DebugSpawnCharacter(FName InCharacterName) -> void.
    -- A void return means a REQUEST, not evidence of a new actor.
    local ok, errorMessage = pcall(function()
        cheat:DebugSpawnCharacter(enemyName)
    end)
    if not ok then return false, tostring(errorMessage) end
    S.requests = S.requests + 1
    if S.requests <= 3 or S.requests % 30 == 0 then
        log("native spawn requested: " .. enemyName .. " total=" .. S.requests)
    end
    return true, "requested"
end
local function directSpawn(ctx)
    if not valid(S.enemyClass) then return false, "Rotlurker class not loaded" end
    local where = chooseSpawnPoint(ctx.manager)
    if not where then return false, "no valid generated spawn point" end
    -- SpawnActor is used as a fallback only when there is no callable native
    -- cheat manager. Native game initialization and AI require live verification.
    local ok, actor = pcall(function()
        return ctx.world:SpawnActor(S.enemyClass, where, {Pitch=0,Yaw=0,Roll=0})
    end)
    if not ok or not nonDefault(actor) then
        return false, "SpawnActor: " .. tostring(actor)
    end
    -- Game data already known from the native encounter; avoid guessing
    -- any additional initializer or calling OnCharacterSpawned with an
    -- arbitrary entry index, which may corrupt the manager.
    local row = S.enemyName or CFG.FallbackName
    pcall(function() actor.CharacterDataName = row end)
    if nonDefault(S.preset) then
        pcall(function() actor.CharacterPreset = S.preset end)
        pcall(function() actor.AppliedCharacterPreset = S.preset end)
    end
    pcall(function() actor:SpawnDefaultController() end)
    S.directSpawns = S.directSpawns + 1
    log("direct fallback actor created; AI/identity need live verification: "..name(actor))
    return true, "spawned-unverified"
end
local function verify()
    local observed = 0
    local live = 0
    for _, actor in ipairs(all("HeldenCharacter")) do
        if isRotLurker(actor) then
            observed = observed + 1
            if isAlive(actor) then live = live + 1 end
        end
    end
    if observed > 0 then
        if S.lastSeen == 0 then log("CONFIRMED: Rotlurker actor(s) present in world") end
        S.lastSeen = S.tick
    end
    S.observed = live
    return live
end
local function tick()
    S.tick = S.tick + 1
    local ctx = context()
    if not ctx then return end
    discover()
    if S.tick - S.lastVerify >= CFG.VerifyTicks then
        S.lastVerify = S.tick
        verify()
    end
    if CFG.MaxAlive > 0 and S.observed >= CFG.MaxAlive then return end
    local pc = findHostController()
    local ok, reason = nativeSpawn(pc, ctx)
    if ok then
        if S.tick - S.lastSeen >= CFG.MissingSpawnWarningTicks and
            S.tick - S.lastWarn >= CFG.MissingSpawnWarningTicks then
            S.lastWarn = S.tick
            log("WARNING: native spawn calls were made, but no Rotlurker actor has been observed; check name and UE4SS log")
        end
        return
    end
    local direct, fallbackReason = directSpawn(ctx)
    if not direct then
        S.failures = S.failures + 1
        if S.failures <= 3 or S.failures % 30 == 0 then
            log("SPAWN FAILED: " .. tostring(reason) .. " / " .. tostring(fallbackReason))
        end
    end
end
local function onSpawn(_, param)
    local actor = unwrap(param)
    if isRotLurker(actor) then
        S.lastSeen = S.tick
        if not valid(S.enemyClass) then
            local ok, cls = pcall(function() return actor:GetClass() end)
            if ok and valid(cls) then S.enemyClass = cls end
        end
    end
end
pcall(function()
    RegisterHook("/Script/Helden.HeldenDungeonEnemyManager:OnCharacterSpawned", onSpawn)
    S.hooked = true
end)
math.randomseed(os.time())
if type(LoopInGameThreadWithDelay) ~= "function" then
    log("FATAL: LoopInGameThreadWithDelay unavailable; refusing to spawn from worker thread")
else
    local ok, err = pcall(LoopInGameThreadWithDelay, CFG.IntervalMs, function()
        local worked, why = pcall(tick)
        if not worked then
            S.failures = S.failures + 1
            if S.failures <= 3 or S.failures % 30 == 0 then log("TICK ERROR: "..tostring(why)) end
        end
    end)
    if not ok then log("FATAL: unable to start game-thread timer: " .. tostring(err)) end
end
log("v0.1.0 loaded; 1000ms; host only; exploring only; Rotlurker; maxAlive="..CFG.MaxAlive)
