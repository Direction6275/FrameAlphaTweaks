-- Frame Alpha Tweaks v16.3.0 (Unified) - Midnight 12.0 Compatible
-- Feature: Mouseover Persistence (Delay) & Tooltips.
-- Logic: Zero-Hook Safe Mode.

local ADDON, NS = ...
NS = NS or {}

-- 1. APIs & Locals
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local print = print
local GameTooltip = GameTooltip

-- 2. Defaults & Data Structure
FrameAlphaTweaksDB = FrameAlphaTweaksDB or {}

NS.defaults = {
    enabled = true,
    activeGroupIndex = 1,
    nicknames = {},  -- frame name -> nickname mapping (profile-wide)
    groups = {
        {
            name = "Default Group",
            alpha = 0.5,
            combat = true,
            target = true,
            mouseover = true,
            groupMouseover = false,
            mouseoverDelay = 1.0, -- New Default: 1 second delay
            fadeInDuration = 0.2, -- Fade-in duration (seconds)
            fadeOutDuration = 0.2, -- Fade-out duration (seconds)
            frames = {}}
    }
}

local presets = {
    unit_frames = {
        { name = "PlayerFrame" },
        { name = "TargetFrame" },
		{ name = "UUF_Player" },
		{ name = "UUF_Target" },
		{ name = "ElvUF_Player" },
		{ name = "ElvUF_Target" },
    },
    action_bars = {
        { name = "MainActionBar", tip = "Action Bar 1" },
        { name = "MultiBarBottomLeft", tip = "Action Bar 2" },
        { name = "MultiBarBottomRight", tip = "Action Bar 3" },
        { name = "MultiBarRight", tip = "Action Bar 4" },
        { name = "MultiBarLeft", tip = "Action Bar 5" },
        { name = "MultiBar5", tip = "Action Bar 6" },
        { name = "MultiBar6", tip = "Action Bar 7" },
        { name = "MultiBar7", tip = "Action Bar 8" },
        { name = "StanceBar", tip = "Stance Bar" },
        { name = "MainMenuBar", tip = "Main Menu Bar" },
    },
    cdm = {
        { name = "EssentialCooldownViewer" },
        { name = "UtilityCooldownViewer" },
        { name = "BuffIconCooldownViewer" },
        { name = "BuffBarCooldownViewer" },
    },
}

NS.presets = presets

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

NS.CopyDefaults = CopyDefaults


-- === Profiles & Sharing ===
local function DeepCopy(obj, seen)
    if type(obj) ~= "table" then return obj end
    seen = seen or {}
    if seen[obj] then return seen[obj] end
    local t = {}
    seen[obj] = t
    for k, v in pairs(obj) do
        t[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return t
end

NS.DeepCopy = DeepCopy

local function GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or "Realm"
    return name .. "-" .. realm
end

NS.GetCharKey = GetCharKey

-- Minimal JSON encode/decode (enough for our data)
local function JsonEscape(s)
    return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function IsArray(t)
    local max = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        if k > max then max = k end
    end
    for i = 1, max do
        if t[i] == nil then return false end
    end
    return true
end

local function JsonEncode(v)
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return tostring(v)
    end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "string" then return '"' .. JsonEscape(v) .. '"' end
    if tv ~= "table" then return "null" end

    if IsArray(v) then
        local parts = {}
        for i = 1, #v do parts[#parts+1] = JsonEncode(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        local parts = {}
        for k, val in pairs(v) do
            if type(k) == "string" then
                parts[#parts+1] = '"' .. JsonEscape(k) .. '":' .. JsonEncode(val)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

local function JsonDecode(str)
    local i, n = 1, #str

    local function skip()
        while i <= n do
            local c = str:sub(i,i)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then i = i + 1 else break end
        end
    end

    local function parseString()
        i = i + 1
        local out = {}
        while i <= n do
            local c = str:sub(i,i)
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local d = str:sub(i+1,i+1)
                if d == "n" then out[#out+1] = "\n"
                elseif d == "r" then out[#out+1] = "\r"
                elseif d == "t" then out[#out+1] = "\t"
                elseif d == '"' then out[#out+1] = '"'
                elseif d == "\\" then out[#out+1] = "\\"
                else out[#out+1] = d end
                i = i + 2
            else
                out[#out+1] = c
                i = i + 1
            end
        end
        return nil
    end

    local function parseNumber()
        local s = i
        while i <= n do
            local c = str:sub(i,i)
            if c:match("[%d%+%-%eE%.]") then i = i + 1 else break end
        end
        return tonumber(str:sub(s, i-1))
    end

    local function parseValue()
        skip()
        local c = str:sub(i,i)
        if c == '"' then return parseString() end
        if c == "{" then
            i = i + 1
            local obj = {}
            skip()
            if str:sub(i,i) == "}" then i = i + 1; return obj end
            while i <= n do
                skip()
                local key = parseString()
                skip()
                if str:sub(i,i) ~= ":" then return nil end
                i = i + 1
                local val = parseValue()
                obj[key] = val
                skip()
                local ch = str:sub(i,i)
                if ch == "}" then i = i + 1; break end
                if ch ~= "," then return nil end
                i = i + 1
            end
            return obj
        end
        if c == "[" then
            i = i + 1
            local arr = {}
            skip()
            if str:sub(i,i) == "]" then i = i + 1; return arr end
            while i <= n do
                local val = parseValue()
                arr[#arr+1] = val
                skip()
                local ch = str:sub(i,i)
                if ch == "]" then i = i + 1; break end
                if ch ~= "," then return nil end
                i = i + 1
            end
            return arr
        end
        if str:sub(i,i+3) == "true" then i = i + 4; return true end
        if str:sub(i,i+4) == "false" then i = i + 5; return false end
        if str:sub(i,i+3) == "null" then i = i + 4; return nil end
        return parseNumber()
    end

    return parseValue()
end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64Encode(data)
    return ((data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i2 = 8, 1, -1 do r = r .. ((b % 2^i2 - b % 2^(i2-1) > 0) and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i2 = 1, 6 do c = c + ((x:sub(i2,i2) == "1") and 2^(6-i2) or 0) end
        return b64chars:sub(c+1,c+1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function Base64Decode(data)
    data = data:gsub("[^" .. b64chars .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (b64chars:find(x) - 1)
        for i2 = 6, 1, -1 do r = r .. ((f % 2^i2 - f % 2^(i2-1) > 0) and "1" or "0") end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i2 = 1, 8 do c = c + ((x:sub(i2,i2) == "1") and 2^(8-i2) or 0) end
        return string.char(c)
    end))
end

local function SanitizeProfile(p)
    if type(p) ~= "table" then return nil end
    p = CopyDefaults(NS.defaults, p)
    if type(p.groups) == "table" then
        for _, g in ipairs(p.groups) do
            g.frames = g.frames or {}
            local cleaned = {}
            for _, fn in ipairs(g.frames) do
                if type(fn) == "string" and fn ~= "" then cleaned[#cleaned+1] = fn end
            end
            g.frames = cleaned
        end
    end
    return p
end

local function MakeUniqueProfileName(base, profiles)
    local name = base
    if not profiles[name] then return name end
    local i = 2
    while profiles[name .. " " .. i] do i = i + 1 end
    return name .. " " .. i
end

NS.MakeUniqueProfileName = MakeUniqueProfileName

local function ExportProfileString(name, profileTable)
    local payload = { v = 1, name = name, profile = profileTable }
    local json = JsonEncode(payload)
    return "FAT1:" .. Base64Encode(json)
end

local function ImportProfileString(str)
    if type(str) ~= "string" then return nil end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if not str:match("^FAT1:") then return nil end
    local b64 = str:sub(6)
    local ok, decoded = pcall(Base64Decode, b64)
    if not ok or not decoded or decoded == "" then return nil end
    local payload = JsonDecode(decoded)
    if type(payload) ~= "table" or payload.v ~= 1 then return nil end
    local pname = payload.name
    local prof = SanitizeProfile(payload.profile)
    if type(pname) ~= "string" or pname == "" or not prof then return nil end
    return pname, prof
end

NS.ExportProfileString = ExportProfileString
NS.ImportProfileString = ImportProfileString

NS.RefreshUI = NS.RefreshUI or function() end

local function EnsureProfileSystem()
    FrameAlphaTweaksDB = FrameAlphaTweaksDB or {}
    local root = FrameAlphaTweaksDB
    local charKey = GetCharKey()

    -- Legacy migration: root used to be the profile itself.
    if not root.profiles then
        local legacy = root
        root = { profileKeys = {}, profiles = {} }
        root.profiles["Default"] = CopyDefaults(NS.defaults, legacy)
        root.profileKeys[charKey] = "Default"
        FrameAlphaTweaksDB = root
    end

    root.profileKeys = root.profileKeys or {}
    root.profiles = root.profiles or {}
    if not next(root.profiles) then
        root.profiles["Default"] = CopyDefaults(NS.defaults, {})
    end
    if not root.profileKeys[charKey] then
        root.profileKeys[charKey] = "Default"
    end

    local profName = root.profileKeys[charKey]
    if not root.profiles[profName] then
        profName = "Default"
        root.profileKeys[charKey] = profName
    end
    root.profiles[profName] = CopyDefaults(NS.defaults, root.profiles[profName] or {})

    return root, charKey, profName, root.profiles[profName]
end

NS.EnsureProfileSystem = EnsureProfileSystem

local cfg
local entries = {} -- Master list

local function SetConfig(newCfg)
    cfg = newCfg
    NS.cfg = newCfg
end

local function GetConfig()
    return cfg
end

NS.SetConfig = SetConfig
NS.GetConfig = GetConfig

-- 3. Core Logic
local function RebuildEntries()
    -- Remember what was previously controlled so we can restore removed frames
    local old = {}
    for i = 1, #entries do
        old[i] = entries[i]
    end

    wipe(entries)
    if not (cfg and cfg.groups) then return end

    local seen = {}        -- prevents duplicates in new entries
    local stillUsed = {}   -- tracks which frame names remain in config

    for _, group in ipairs(cfg.groups) do
        local frames = group.frames
        if frames then
            for _, name in ipairs(frames) do
                if type(name) == "string" and name ~= "" and not seen[name] then
                    seen[name] = true
                    stillUsed[name] = true

                    entries[#entries+1] = {
                        name = name,
                        ref = nil,
                        lastAlpha = nil,
                        hoverExpire = 0,
                        targetBase = group.alpha or 1.0,
                        combat = (group.combat == nil and true) or group.combat,
                        target = (group.target == nil and true) or group.target,
                        mouseover = (group.mouseover == nil and true) or group.mouseover,
                        groupMouseover = group.groupMouseover or false,
                        mouseoverDelay = group.mouseoverDelay or 1.0,
                        fadeInDuration = group.fadeInDuration or 0.0,
                        fadeOutDuration = group.fadeOutDuration or 0.0,
                        currentAlpha = nil,
                        desiredAlpha = nil,
                        fadeStartAlpha = nil,
                        fadeStartTime = 0,
                        fadeDuration = 0,
                        parentGroup = group,
                    }
                end
            end
        end
    end

    -- Restore alpha for frames that are no longer in any group
    for _, e in ipairs(old) do
        if e and e.name and not stillUsed[e.name] then
            local f = e.ref or _G[e.name]
            if f and f.SetAlpha then
                pcall(f.SetAlpha, f, 1)
            end
        end
    end
end

NS.RebuildEntries = RebuildEntries

local function ForceSetAlpha(entry, alpha)
    if not entry or not entry.ref then return end
    local f = entry.ref
    if f.SetIgnoreParentAlpha then pcall(f.SetIgnoreParentAlpha, f, true) end
    if entry.lastAlpha ~= alpha then
        pcall(f.SetAlpha, f, alpha)
        entry.lastAlpha = alpha
    end
end

local function UpdateFadedAlpha(entry, desired, now)
    if not entry or not entry.ref then return end
    now = now or GetTime()

    -- initialize current alpha from the frame the first time we see it
    if entry.currentAlpha == nil then
        local ok, a = pcall(entry.ref.GetAlpha, entry.ref)
        entry.currentAlpha = (ok and type(a) == "number" and a) or 1.0
        entry.desiredAlpha = entry.currentAlpha
        entry.fadeDuration = 0
    end

    -- start a new fade whenever desired target changes
    if entry.desiredAlpha ~= desired then
        entry.fadeStartAlpha = entry.currentAlpha
        entry.desiredAlpha = desired
        entry.fadeStartTime = now

        local dur = 0
        if desired > entry.currentAlpha then
            dur = entry.fadeInDuration or 0
        else
            dur = entry.fadeOutDuration or 0
        end
        entry.fadeDuration = dur or 0

        if entry.fadeDuration <= 0 then
            entry.currentAlpha = desired
            ForceSetAlpha(entry, desired)
            return
        end
    end

    -- actively fading
    if entry.fadeDuration and entry.fadeDuration > 0 then
        local t = (now - (entry.fadeStartTime or now)) / entry.fadeDuration
        if t >= 1 then
            entry.currentAlpha = entry.desiredAlpha
            entry.fadeDuration = 0
        elseif t < 0 then
            t = 0
        end

        if entry.fadeDuration > 0 then
            entry.currentAlpha = (entry.fadeStartAlpha or entry.currentAlpha) + ((entry.desiredAlpha - (entry.fadeStartAlpha or entry.currentAlpha)) * t)
        end
    else
        entry.currentAlpha = desired
    end

    ForceSetAlpha(entry, entry.currentAlpha)
end

local function TryResolve(entry)
    local f = _G[entry.name]
    if f then
        entry.ref = f
        return true
    end
    return false
end

-- Helper: Check if any frame in the specific group is hovered
local function IsAnyFrameInGroupHovered(group)
    if not group or not group.frames then return false end
    for _, frameName in ipairs(group.frames) do
        local f = _G[frameName]
        if f and f:IsVisible() and f.IsMouseOver and f:IsMouseOver() then
            return true
        end
    end
    return false
end

local function ApplyAlpha(entry, now, inCombat, hasTarget)
    if not entry.ref then return end

    local target, forceFull = 1, false
    if cfg.enabled then
        if entry.combat and inCombat then
            forceFull = true
        elseif entry.target and hasTarget then
            forceFull = true
        else
            now = now or GetTime()
            local isHovering = false

            if entry.groupMouseover and entry.parentGroup and IsAnyFrameInGroupHovered(entry.parentGroup) then
                isHovering = true
            elseif entry.mouseover and entry.ref.IsMouseOver and entry.ref:IsMouseOver() then
                isHovering = true
            end

            if isHovering then
                forceFull = true
                entry.hoverExpire = now + (entry.mouseoverDelay or 0)
            elseif entry.hoverExpire and now < entry.hoverExpire then
                forceFull = true
            end
        end

        if not forceFull then
            target = entry.targetBase or 0.2
        end
    end

    UpdateFadedAlpha(entry, target, now)
end

-- 4. Main Loop
local mainFrame = CreateFrame("Frame")
local updateAccum = 0
local UPDATE_INTERVAL = 1/30 -- ~30Hz is plenty smooth for fades

mainFrame:SetScript("OnUpdate", function(_, dt)
    if not cfg then return end
    updateAccum = updateAccum + (dt or 0)
    if updateAccum < UPDATE_INTERVAL then return end
    updateAccum = 0

    local now = GetTime()
    local inCombat = InCombatLockdown()
    local hasTarget = UnitExists("target")

    for _, e in ipairs(entries) do
        if not e.ref then TryResolve(e) end
        if e.ref and e.ref:IsVisible() then
            ApplyAlpha(e, now, inCombat, hasTarget)
        end
    end
end)

-- 5. Data Migration & Validation
local function ValidateGroups()
    if not cfg.groups then cfg.groups = {} end
    
    -- Legacy Migration
    if FrameAlphaTweaksDB.frameNames then
        if #cfg.groups == 0 then table.insert(cfg.groups, {name="Migrated Frames", alpha=0.5, frames={}}) end
        for name in string.gmatch(FrameAlphaTweaksDB.frameNames, "[^,%s]+") do
            table.insert(cfg.groups[1].frames, name)
        end
        FrameAlphaTweaksDB.frameNames = nil
    end
    
    if FrameAlphaTweaksDB.forceFullOnCombat ~= nil then
        for _, g in ipairs(cfg.groups) do
            g.combat = FrameAlphaTweaksDB.forceFullOnCombat
            g.target = FrameAlphaTweaksDB.forceFullOnTarget
            g.mouseover = FrameAlphaTweaksDB.forceFullOnMouseover
        end
        FrameAlphaTweaksDB.forceFullOnCombat = nil
        FrameAlphaTweaksDB.forceFullOnTarget = nil
        FrameAlphaTweaksDB.forceFullOnMouseover = nil
    end

    -- Validate new keys
    for _, g in ipairs(cfg.groups) do
        if g.combat == nil then g.combat = true end
        if g.target == nil then g.target = true end
        if g.mouseover == nil then g.mouseover = true end
        if g.groupMouseover == nil then g.groupMouseover = false end
        if g.mouseoverDelay == nil then g.mouseoverDelay = 1.0 end
        if g.fadeInDuration == nil then g.fadeInDuration = 0.2 end
        if g.fadeOutDuration == nil then g.fadeOutDuration = 0.2 end
        -- Enforce binary mouseover mode (prefer linked/group mode if both were enabled)
        if g.groupMouseover then g.mouseover = false end
    end
    
    if #cfg.groups == 0 then
        table.insert(cfg.groups, { name = "Group 1", alpha = 1.0, combat=true, target=true, mouseover=true, groupMouseover=false, mouseoverDelay=1.0, fadeInDuration=0.2, fadeOutDuration=0.2, frames = {} })
    end
    
    if not cfg.activeGroupIndex or cfg.activeGroupIndex > #cfg.groups or cfg.activeGroupIndex < 1 then
        cfg.activeGroupIndex = 1
    end
    
    RebuildEntries()
end
NS.ValidateGroups = ValidateGroups

-- 7. Initialization
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")

ev:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        local root, charKey, profName, prof = EnsureProfileSystem()
        FrameAlphaTweaksDB = root
        NS._charKey = charKey
        NS._root = root
        NS._profileName = profName
        SetConfig(prof)
        ValidateGroups()
        print("|cff00c8ffFAT:|r Loaded. Type |cffffff00/fat|r for options.")
        if NS.RegisterBlizzardOptionsStub then
            NS.RegisterBlizzardOptionsStub()
        end
        RebuildEntries()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if NS.HandleCombatState then
            NS.HandleCombatState(true)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if NS.HandleCombatState then
            NS.HandleCombatState(false)
        end
    end
end)

SLASH_FRAMEALPHATWEAKS1 = "/fat"
SlashCmdList.FRAMEALPHATWEAKS = function(msg)
    if NS.ToggleConfig then NS.ToggleConfig() else print("|cff00c8ffFAT:|r Config failed to load.") end
end
