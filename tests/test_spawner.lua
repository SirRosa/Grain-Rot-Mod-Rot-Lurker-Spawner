-- Mock tests for the scheduling, host authority and fallback branches.
-- These tests do NOT execute Unreal Engine's native spawn/AI/replication code.
local path = "ue4ss/Mods/GrainRotRotLurkerSpawner/Scripts/main.lua"
local passed = 0
local function check(value, msg)
    assert(value, msg)
    passed = passed + 1
end
local function obj(id, fields)
    local o = fields or {}
    o.IsValid = function() return true end
    o.GetFullName = function() return id end
    return o
end
local function setup(options)
    options = options or {}
    local logs, hooks, scheduled, nativeCalls, directCalls = {}, {}, {}, {}, {}
    local world = obj("World", {})
    world.SpawnActor = function(_, cls, position, rotation)
        directCalls[#directCalls+1] = {cls=cls,position=position,rotation=rotation}
        if options.directFails then return nil end
        return obj("HeldenCharacter spawned Rotlurker", {
            CharacterDataName = "Rotlurker",
            SpawnDefaultController = function() end,
        })
    end
    local manager = obj("HeldenDungeonEnemyManager current", {
        SpawnLocations = {
            {Translation={X=10,Y=20,Z=30}},
            {Translation={X=100,Y=200,Z=300}},
        }
    })
    local dungeon = obj("HeldenDungeonActor current", {EnemyManager=manager})
    dungeon.GetWorld = function() return world end
    local gs = obj("HeldenGameState current", {
        CurrentDungeonRun={State=options.runState or 2, DungeonActor=dungeon}
    })
    local gm = obj("HeldenGameMode current")
    local cheat = obj("HeldenCheatManager current")
    cheat.DebugSpawnCharacter = function(_, creature)
        nativeCalls[#nativeCalls+1] = creature
    end
    local pc = obj("HeldenPlayerController host",{
        IsLocalController=function() return true end,
        CheatManager=options.noCheat and nil or cheat,
        EnableCheats=function() end
    })
    local preset = obj("HeldenCharacterPreset ROTLURKER", {
        CharacterClass=obj("BP_Rotlurker Class")
    })
    local classes = {
        HeldenGameMode=options.client and {} or {gm},
        GameModeBase=options.client and {} or {gm},
        HeldenGameState={gs},
        HeldenPlayerController={pc},
        HeldenCheatManager=options.noCheat and {} or {cheat},
        HeldenCharacter={},
        HeldenCharacterPreset=options.preset and {preset} or {},
        HeldenDataSingleton={},
    }
    local env = setmetatable({
        print=function(line) logs[#logs+1]=line end,
        FindFirstOf=function(cls) return classes[cls] and classes[cls][1] end,
        FindAllOf=function(cls) return classes[cls] or {} end,
        RegisterHook=function(key,callback) hooks[key]=callback end,
        LoopInGameThreadWithDelay=function(ms,callback)
            scheduled.ms, scheduled.callback = ms, callback
            return true
        end,
    }, {__index=_G})
    local chunk, err = loadfile(path, "t", env)
    assert(chunk, err)
    chunk()
    local function tick(n)
        for _=1,(n or 1) do scheduled.callback() end
    end
    return {
        tick=tick,gs=gs,classes=classes,pc=pc,manager=manager,
        nativeCalls=nativeCalls,directCalls=directCalls,logs=logs,
        scheduled=scheduled,hooks=hooks
    }
end

do
    local s=setup()
    check(s.scheduled.ms==1000, "interval should be exactly 1000ms")
    check(s.scheduled.callback~=nil, "game thread timer registered")
    s.tick(3)
    check(#s.nativeCalls==3, "one native request for each dungeon second")
    check(s.nativeCalls[1]=="Rotlurker", "fallback name must be Rotlurker")
    check(#s.directCalls==0, "no unnecessary direct actor spawn after native request")
end
do
    local s=setup({client=true})
    s.tick(5)
    check(#s.nativeCalls==0, "client must not spawn enemies")
    check(#s.directCalls==0, "client must not bypass host check")
end
do
    local s=setup({runState=1})
    s.tick(2)
    check(#s.nativeCalls==0, "elevator ride must not spawn")
    s.gs.CurrentDungeonRun.State=2
    s.tick(2)
    check(#s.nativeCalls==2, "dungeon should start spawning after transition")
    s.gs.CurrentDungeonRun.State=3
    s.tick(2)
    check(#s.nativeCalls==2, "run end must stop spawning")
end
do
    local s=setup({noCheat=true,preset=true})
    s.tick(2)
    check(#s.nativeCalls==0, "no cheat manager, no debug invocation")
    check(#s.directCalls==2, "fallback must spawn one actor per second")
    local d=s.directCalls[1]
    check(d.position.Z==30 or d.position.Z==300, "fallback uses dungeon spawn transforms")
    check(d.cls:GetFullName()=="BP_Rotlurker Class", "fallback uses resolved preset class")
end
do
    local s=setup({noCheat=true})
    s.tick(5)
    check(#s.directCalls==0, "unresolved Rotlurker class must never spawn generic enemy")
    check(#s.nativeCalls==0, "missing manager must not be faked")
    check(table.concat(s.logs):find("SPAWN FAILED",1,true)~=nil, "failed spawn logged")
end
do
    local s=setup()
    s.gs.CurrentDungeonRun.DungeonActor=nil
    s.tick(2)
    check(#s.nativeCalls==0, "missing dungeon actor must fail closed")
end
do
    local s=setup()
    s.manager.SpawnLocations={}
    s.pc.CheatManager=nil
    s.classes.HeldenCheatManager={}
    s.classes.HeldenCharacterPreset={
        obj("HeldenCharacterPreset Rotlurker",{CharacterClass=obj("BP_Rotlurker Class")})
    }
    s.tick(2)
    check(#s.directCalls==0, "no fabricated spawn coordinates without generated locations")
end
do
    local s=setup()
    s.classes.HeldenGameMode={}
    s.classes.GameModeBase={}
    s.tick(1)
    check(#s.nativeCalls==0, "default/no-authority state should not request spawn")
end

print(string.format("PASS: %d mock assertions (not a game-runtime test)",passed))
