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

local function GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or "Realm"
    return name .. "-" .. realm
end

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

local cfg
local entries = {} -- Master list

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

-- 6. Options Panel

-- === Profile Popups ===
StaticPopupDialogs = StaticPopupDialogs or {}

StaticPopupDialogs["FAT_EXPORT_PROFILE"] = {
    text = "Export profile: %s\nCopy the string below:",
    button1 = OKAY,
    hasEditBox = true,
    editBoxWidth = 420,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self.EditBox:SetText(self.data or "")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["FAT_IMPORT_PROFILE"] = {
    text = "Import profile\nPaste an export string:",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 420,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        local s = self.EditBox:GetText() or ""
        local name, prof = ImportProfileString(s)
        if not name or not prof then
        if NS and NS.RefreshUI then NS.RefreshUI() end

            print("|cff00c8ffFAT:|r Import failed (invalid string).")
            return
        end
        local root, charKey = FrameAlphaTweaksDB, (NS._charKey or GetCharKey())
        local unique = MakeUniqueProfileName(name, root.profiles)
        root.profiles[unique] = prof
        root.profileKeys[charKey] = unique
        NS._profileName = unique
        cfg = CopyDefaults(NS.defaults, root.profiles[unique] or {})
        root.profiles[unique] = cfg
        ValidateGroups()
        RebuildEntries()
        print("|cff00c8ffFAT:|r Imported profile as |cffffff00" .. unique .. "|r.")
    end,
    OnShow = function(self)
        self.EditBox:SetText("")
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["FAT_NEW_PROFILE"] = {
    text = "Create new profile\nEnter a name:",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        local name = (self.EditBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        local root, charKey = FrameAlphaTweaksDB, (NS._charKey or GetCharKey())
        name = MakeUniqueProfileName(name, root.profiles)
        root.profiles[name] = CopyDefaults(NS.defaults, {})
        root.profileKeys[charKey] = name
        NS._profileName = name
        cfg = CopyDefaults(NS.defaults, root.profiles[name] or {})
        root.profiles[name] = cfg
        ValidateGroups()
        RebuildEntries()
        if NS and NS.RefreshUI then NS.RefreshUI() end

        print("|cff00c8ffFAT:|r Created profile |cffffff00" .. name .. "|r.")
    end,
    OnShow = function(self) self.EditBox:SetText(""); self.EditBox:SetFocus() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["FAT_RENAME_PROFILE"] = {
    text = "Rename profile: %s\nEnter new name:",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        local base = (self.EditBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if base == "" then return end

        local root = FrameAlphaTweaksDB
        if not root or not root.profiles then return end

        local oldName = data or (NS._profileName or "Default")
        if not root.profiles[oldName] then return end

        -- Can't "rename" to the same name
        if base == oldName then return end

        local newName = MakeUniqueProfileName(base, root.profiles)

        -- Move profile table
        root.profiles[newName] = root.profiles[oldName]
        root.profiles[oldName] = nil

        -- Update any characters mapped to the old profile
        root.profileKeys = root.profileKeys or {}
        for ck, pn in pairs(root.profileKeys) do
            if pn == oldName then
                root.profileKeys[ck] = newName
            end
        end

        -- Ensure current character points to the new profile (belt + suspenders)
        local charKey = (NS._charKey or GetCharKey())
        root.profileKeys[charKey] = newName

        -- Switch runtime to the renamed profile and refresh
        NS._profileName = newName
        cfg = CopyDefaults(NS.defaults, root.profiles[newName] or {})
        root.profiles[newName] = cfg

        ValidateGroups()
        RebuildEntries()
        if NS and NS.RefreshUI then NS.RefreshUI() end

        print("|cff00c8ffFAT:|r Renamed profile |cffffff00" .. oldName .. "|r to |cffffff00" .. newName .. "|r.")
    end,
    OnShow = function(self)
        local current = self.data or (NS._profileName or "Default")
        self.EditBox:SetText(current)
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["FAT_COPY_PROFILE"] = {
    text = "Duplicate profile: %s\nEnter new name:",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        local base = (self.EditBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if base == "" then return end
        local root, charKey = FrameAlphaTweaksDB, (NS._charKey or GetCharKey())
        local from = data or (NS._profileName or "Default")
        local newName = MakeUniqueProfileName(base, root.profiles)
        root.profiles[newName] = DeepCopy(root.profiles[from] or CopyDefaults(NS.defaults, {}))
        root.profileKeys[charKey] = newName
        NS._profileName = newName
        cfg = CopyDefaults(NS.defaults, root.profiles[newName] or {})
        root.profiles[newName] = cfg
        ValidateGroups()
        RebuildEntries()
        if NS and NS.RefreshUI then NS.RefreshUI() end

        print("|cff00c8ffFAT:|r Copied to profile |cffffff00" .. newName .. "|r.")
    end,
    OnShow = function(self) self.EditBox:SetText(""); self.EditBox:SetFocus() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["FAT_DELETE_PROFILE"] = {
    text = "Delete profile: %s ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        local root, charKey = FrameAlphaTweaksDB, (NS._charKey or GetCharKey())
        local name = data or (NS._profileName or "Default")
        local count = 0
        for _ in pairs(root.profiles) do count = count + 1 end
        if count <= 1 then
            print("|cff00c8ffFAT:|r You can't delete the last profile.")
            return
        end
        root.profiles[name] = nil
        local fallback = "Default"
        if not root.profiles[fallback] then
            for n in pairs(root.profiles) do fallback = n; break end
        end
        root.profileKeys[charKey] = fallback
        NS._profileName = fallback
        cfg = CopyDefaults(NS.defaults, root.profiles[fallback] or {})
        root.profiles[fallback] = cfg
        ValidateGroups()
        RebuildEntries()
        if NS and NS.RefreshUI then NS.RefreshUI() end
        print("|cff00c8ffFAT:|r Deleted profile; switched to |cffffff00" .. fallback .. "|r.")
end,
}



-- === AceGUI Config Window (ElvUI will skin Ace3 widgets automatically) ===

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then
    -- If AceGUI isn't available for some reason, keep the addon functional without a UI.
    NS.ToggleConfig = function()
        print("|cff00c8ffFAT:|r AceGUI not found. Please ensure libs are installed.")
    end
else
    local UI = {
        frameWidget = nil,
        selectedGroup = 1,
    }


    local function GetRoot()
        -- Ensure DB/profile is ready
        if not cfg then
            local root, charKey, profName, prof = EnsureProfileSystem()
            FrameAlphaTweaksDB = root
            NS._charKey = charKey
            NS._root = root
            NS._profileName = profName
            cfg = prof
            ValidateGroups()
            RebuildEntries()
        end
        return FrameAlphaTweaksDB, (NS._charKey or GetCharKey()), (NS._profileName or "Default"), cfg
    end

    local function ProfilesList()
        local root = FrameAlphaTweaksDB or {}
        local names = {}
        for n in pairs(root.profiles or {}) do names[#names+1] = n end
        table.sort(names)
        local list = {}
        for _, n in ipairs(names) do list[n] = n end
        return list
    end

    local function EnsureSelectedGroup()
        if not cfg or not cfg.groups then return end
        if UI.selectedGroup < 1 then UI.selectedGroup = 1 end
        if UI.selectedGroup > #cfg.groups then UI.selectedGroup = #cfg.groups end
        if #cfg.groups == 0 then
            ValidateGroups()
            UI.selectedGroup = 1
        end
    end

    local function AnyForceFullChecked(g)
        return g and (g.combat or g.target or g.mouseover or g.groupMouseover)
    end

    local WHITE_TOOLTIP_COLOR = (CreateColor and CreateColor(1, 1, 1)) or nil
local function ShowTooltip(owner, text)
    if not owner or not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    -- Retail: SetText(text, color, alpha, wrap)
    -- Older clients: SetText(text, r, g, b[, a][, wrap])
    local ok = false
    if WHITE_TOOLTIP_COLOR then
        ok = pcall(GameTooltip.SetText, GameTooltip, text, WHITE_TOOLTIP_COLOR, 1, true)
    end
    if not ok then
        ok = pcall(GameTooltip.SetText, GameTooltip, text, 1, 1, 1, 1, true)
    end
    if not ok then
        pcall(GameTooltip.SetText, GameTooltip, text)
    end

    GameTooltip:Show()
end

    local function HideTooltip()
        if GameTooltip:IsShown() then GameTooltip:Hide() end
    end

    -- Frame move helper (middle click on a frame row)
local function EnsureMoveDropDown()
    if UI.moveDropDown and UI.moveDropDown.IsObjectType and UI.moveDropDown:IsObjectType("Frame") then
        return
    end
    -- Use a dropdown menu (more reliable than AceGUI popups for click handling)
    UI.moveDropDown = CreateFrame("Frame", "FAT_MoveDropDown", UIParent, "UIDropDownMenuTemplate")
    UI.moveDropDown:Hide()
end

local function CloseMoveFrameWindow()
    if CloseDropDownMenus then
        CloseDropDownMenus()
    end
end

local function MoveFrameToGroup(frameName, toGroupIndex, fromGroupIndex)
    if not frameName or not cfg or not cfg.groups then return end
    EnsureSelectedGroup()
    local fromIndex = fromGroupIndex or UI.selectedGroup or 1
    if toGroupIndex == fromIndex then return end

    local fromG = cfg.groups[fromIndex]
    local toG = cfg.groups[toGroupIndex]
    if not fromG or not toG then return end

    fromG.frames = fromG.frames or {}
    toG.frames = toG.frames or {}

    -- Remove from source group (first occurrence)
    local removed = false
    for j = #fromG.frames, 1, -1 do
        if fromG.frames[j] == frameName then
            table.remove(fromG.frames, j)
            removed = true
            break
        end
    end
    if not removed then return end

    -- Add to target group (avoid duplicates)
    local exists = false
    for _, v in ipairs(toG.frames) do
        if v == frameName then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(toG.frames, frameName)
    end

    UI.selectedGroup = fromIndex
    RebuildEntries()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() NS.RefreshUI() end)
    else
        NS.RefreshUI()
    end
end

local function OpenMoveFrameWindow(frameName, anchorFrame)
    if not frameName then return end
    EnsureMoveDropDown()

    local current = UI.selectedGroup or 1
    local menu = {}

    menu[#menu + 1] = { text = "Move Frame", isTitle = true, notCheckable = true }
    menu[#menu + 1] = { text = frameName, isTitle = true, notCheckable = true }
    menu[#menu + 1] = { text = " ", notCheckable = true, disabled = true }

    for idx, grp in ipairs(cfg.groups or {}) do
        if idx ~= current then
            local gname = grp.name or ("Group " .. idx)
            menu[#menu + 1] = {
                text = gname,
                notCheckable = true,
                func = function()
                    CloseMoveFrameWindow()
                    MoveFrameToGroup(frameName, idx, current)
                end,
            }
        end
    end

    if #menu <= 3 then
        menu[#menu + 1] = { text = "(No other groups)", notCheckable = true, disabled = true }
    end

    if EasyMenu then
        EasyMenu(menu, UI.moveDropDown, anchorFrame or "cursor", 0, 0, "MENU", 2)
    else
        UIDropDownMenu_Initialize(UI.moveDropDown, function(self, level)
            if level ~= 1 then return end
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                for k, v in pairs(item) do info[k] = v end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, UI.moveDropDown, anchorFrame or "cursor", 0, 0)
    end
end

local function FindIndexFromCursor(rowFrames)
    if not rowFrames or #rowFrames == 0 then return nil end
    local cy = GetCursorY()
    for i, f in ipairs(rowFrames) do
        if f and f.IsShown and f:IsShown() then
            local top, bottom = f:GetTop(), f:GetBottom()
            if top and bottom and cy <= top and cy >= bottom then
                return i
            end
        end
    end
    local first, last = rowFrames[1], rowFrames[#rowFrames]
    if first and first.GetTop and first:GetTop() and cy > first:GetTop() then return 1 end
    if last and last.GetBottom and last:GetBottom() and cy < last:GetBottom() then return #rowFrames end
    return nil
end

local function EnsureDragHelpers()
    if UI._dragUpdater then return end
    UI._dragUpdater = CreateFrame("Frame", nil, UIParent)
    UI._dragUpdater:Hide()

    UI._dragLine = UIParent:CreateTexture(nil, "OVERLAY")
    UI._dragLine:SetColorTexture(0, 0.78, 1, 1)
    UI._dragLine:SetHeight(2)
    UI._dragLine:Hide()
end

local function PositionDragLine(targetFrame)
    if not targetFrame or not UI._dragLine then return end
    UI._dragLine:ClearAllPoints()
    UI._dragLine:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", 2, 1)
    UI._dragLine:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", -2, 1)
    UI._dragLine:Show()
end

local function StartDrag(kind, fromIndex)
    if not kind or not fromIndex then return end
    EnsureDragHelpers()
    UI._dragKind = kind
    UI._dragFrom = fromIndex
    UI._dragTo = fromIndex

    UI._dragUpdater:SetScript("OnUpdate", function()
        local frames = (kind == "group") and UI._groupRowFrames or UI._frameRowFrames
        local idx = FindIndexFromCursor(frames)
        if idx and idx ~= UI._dragTo then
            UI._dragTo = idx
            local tf = frames and frames[idx]
            if tf then PositionDragLine(tf) end
        end
    end)
    UI._dragUpdater:Show()
end

local function MoveItem(t, fromIndex, toIndex)
    if type(t) ~= "table" or fromIndex == toIndex then return end
    local v = table.remove(t, fromIndex)
    if v == nil then return end
    table.insert(t, toIndex, v)
end

local function StopDrag()
    if not UI._dragKind then return end
    local kind, fromIndex, toIndex = UI._dragKind, UI._dragFrom, UI._dragTo

    if UI._dragUpdater then
        UI._dragUpdater:SetScript("OnUpdate", nil)
        UI._dragUpdater:Hide()
    end
    if UI._dragLine then UI._dragLine:Hide() end

    UI._dragKind, UI._dragFrom, UI._dragTo = nil, nil, nil

    if not fromIndex or not toIndex or fromIndex == toIndex then return end

    EnsureSelectedGroup()
    if kind == "group" then
        MoveItem(cfg.groups, fromIndex, toIndex)
        UI.selectedGroup = toIndex
    elseif kind == "frame" then
        local g = cfg.groups[UI.selectedGroup]
        g.frames = g.frames or {}
        MoveItem(g.frames, fromIndex, toIndex)
    end

    RebuildEntries()
    RefreshUI()
end

    local function RefreshUI()
        if not UI.frameWidget then return end
        local root, charKey, profName, prof = GetRoot()
        EnsureSelectedGroup()
        local g = cfg.groups[UI.selectedGroup]

        -- Update header widgets
        if UI.profileDropdown then
            UI.profileDropdown:SetList(ProfilesList())
            UI.profileDropdown:SetValue(profName)
        end
        if UI.enableCheckbox then
            UI.enableCheckbox:SetValue(cfg.enabled and true or false)
        end

        -- GROUPS LIST
        if UI.groupsScroll then
            UI.groupsScroll:ReleaseChildren()
            UI.groupsScroll:SetLayout("List")
            UI._groupRowFrames = {}
            for idx, grp in ipairs(cfg.groups) do
                local name = grp.name or ("Group " .. idx)

                local row = AceGUI:Create("SimpleGroup")
                row:SetFullWidth(true)
                row:SetLayout("Flow")

                local btn = AceGUI:Create("Button")
                btn:SetFullWidth(true)
                btn:SetText(name)
                if btn.frame and btn.frame.RegisterForClicks then
                    btn.frame:RegisterForClicks("AnyUp")
                end

                btn:SetCallback("OnClick", function(_, _, mouseButton)
                    -- Shift-left = move up, Shift-right = move down
                    if IsShiftKeyDown() then
                        local newIndex = idx
                        if mouseButton == "LeftButton" then
                            newIndex = math.max(1, idx - 1)
                        elseif mouseButton == "RightButton" or mouseButton == "RightButtonUp" then
                            newIndex = math.min(#cfg.groups, idx + 1)
                        end
                        if newIndex ~= idx then
                            cfg.groups[idx], cfg.groups[newIndex] = cfg.groups[newIndex], cfg.groups[idx]
                            UI.selectedGroup = newIndex
                            RebuildEntries()
                            RefreshUI()
                            return
                        end
                    end

                    UI.selectedGroup = idx
                    RefreshUI()
                end)

                if idx == UI.selectedGroup then
                    btn:SetText("|cff00c8ff»|r " .. name .. " |cff00c8ff«|r")
                end

                row:AddChild(btn)

                UI._groupRowFrames[idx] = row.frame
                UI.groupsScroll:AddChild(row)
            end
        end

        -- FRAMES LIST
        if UI.framesScroll then
            UI.framesScroll:ReleaseChildren()
            UI.framesScroll:SetLayout("List")
            UI._frameRowFrames = {}
            local frames = g.frames or {}
            for i, fname in ipairs(frames) do
                local row = AceGUI:Create("SimpleGroup")
                row:SetFullWidth(true)
                row:SetLayout("Flow")

                -- Frame name button (Shift-left = move up, Shift-right = move down)
                local nameBtn = AceGUI:Create("Button")
                nameBtn:SetText(fname)
                nameBtn:SetWidth((UI._colW and UI._colW.frames or 580) - 120)
                if nameBtn.frame and nameBtn.frame.RegisterForClicks then
                    nameBtn.frame:RegisterForClicks("AnyUp")
                end
                nameBtn:SetCallback("OnClick", function(_, _, mouseButton)
                    if mouseButton == "MiddleButton" then
                        OpenMoveFrameWindow(fname, nameBtn.frame)
                        return
                    end
                    if IsShiftKeyDown() then
                        local newIndex = i
                        if mouseButton == "LeftButton" then
                            newIndex = math.max(1, i - 1)
                        elseif mouseButton == "RightButton" or mouseButton == "RightButtonUp" then
                            newIndex = math.min(#frames, i + 1)
                        end
                        if newIndex ~= i then
                            frames[i], frames[newIndex] = frames[newIndex], frames[i]
                            RebuildEntries()
                            RefreshUI()
                            return
                        end
                    end
                    -- Normal click: no-op (kept for future selection/highlight if desired)
                end)
                row:AddChild(nameBtn)

                -- Quick delete
                local del = AceGUI:Create("Button")
                del:SetText("Delete")
                del:SetWidth(70)
                del:SetCallback("OnClick", function()
                    table.remove(frames, i)
                    RebuildEntries()
                    RefreshUI()
                end)
                row:AddChild(del)

                UI._frameRowFrames[i] = row.frame

                UI.framesScroll:AddChild(row)
            end
        end

        -- SETTINGS PANEL
        if UI.groupNameEdit then UI.groupNameEdit:SetText(g.name or "") end

        local function UpdateFadeEnabled()
            local enabled = AnyForceFullChecked(g)
            if UI.fadeDelay then UI.fadeDelay:SetDisabled(not enabled) end
            if UI.fadeIn then UI.fadeIn:SetDisabled(not enabled) end
            if UI.fadeOut then UI.fadeOut:SetDisabled(not enabled) end
        end

        if UI.cbCombat then
            UI.cbCombat:SetValue(g.combat and true or false)
        end
        if UI.cbTarget then
            UI.cbTarget:SetValue(g.target and true or false)
        end
        if UI.cbMouseover then
            UI.cbMouseover:SetValue(g.mouseover and true or false)
        end
        if UI.cbLinkedMouseover then
            UI.cbLinkedMouseover:SetValue(g.groupMouseover and true or false)
        end

        if UI.fadeDelay then UI.fadeDelay:SetValue(g.mouseoverDelay or 0) end
        if UI.fadeIn then UI.fadeIn:SetValue(g.fadeInDuration or 0.1) end
        if UI.fadeOut then UI.fadeOut:SetValue(g.fadeOutDuration or 0.5) end
        if UI.alphaSlider then UI.alphaSlider:SetValue(g.alpha or 0.5) end

        UpdateFadeEnabled()
    end

    NS.RefreshUI = RefreshUI

    local function BuildConfigWindow()
        local root, charKey, profName, prof = GetRoot()
        if UI.frameWidget then return end

        local f = AceGUI:Create("Frame")
        UI.frameWidget = f
        f:SetTitle("Frame Alpha Tweaks")
        f:SetStatusText("")
        f:SetWidth(1200)
        f:SetHeight(680)
        f:SetLayout("Flow")
        f:EnableResize(false)
        if f.frame then
            local function HasOtherEscapeWindows(selfFrame)
                if type(UISpecialFrames) ~= "table" then return false end
                for _, name in ipairs(UISpecialFrames) do
                    local other = name and _G[name]
                    if other and other ~= selfFrame and other:IsShown() then
                        return true
                    end
                end
                return false
            end

            f.frame:SetFrameStrata("MEDIUM")
            f.frame:SetFrameLevel(10)
            f.frame:EnableKeyboard(true)
            f.frame:SetPropagateKeyboardInput(false)
            f.frame:SetScript("OnKeyDown", function(frame, key)
                if key ~= "ESCAPE" then return end
                frame.obj:Hide()
                if not HasOtherEscapeWindows(frame) and (not GameMenuFrame or not GameMenuFrame:IsShown()) then
                    ToggleGameMenu()
                end
            end)
        end

        f:SetCallback("OnClose", function(widget)
            -- Close any auxiliary windows
            if UI.presetsWin and UI.presetsWin.frame then
                UI.presetsWin.frame:Hide()
            end
            pcall(function() CloseMoveFrameWindow() end)

            AceGUI:Release(widget)
            UI.frameWidget = nil
        end)

        -- Header: Profile dropdown + buttons
        local headerRow = AceGUI:Create("SimpleGroup")
        headerRow:SetFullWidth(true)
        headerRow:SetHeight(70)
        headerRow:SetLayout("None")
        f:AddChild(headerRow)

        local headerLeft = AceGUI:Create("SimpleGroup")
        headerLeft:SetLayout("Flow")
        headerLeft:SetWidth(740)
        headerLeft:SetHeight(70)
        headerRow:AddChild(headerLeft)
        if headerLeft.frame then
            headerLeft.frame:ClearAllPoints()
            headerLeft.frame:SetPoint("TOPLEFT", headerRow.frame, "TOPLEFT", 0, 0)
        end

        local headerHelp = AceGUI:Create("SimpleGroup")
        headerHelp:SetLayout("List")
        headerHelp:SetWidth(430)
        headerHelp:SetHeight(70)
        headerRow:AddChild(headerHelp)
        if headerHelp.frame then
            headerHelp.frame:ClearAllPoints()
            headerHelp.frame:SetPoint("TOPRIGHT", headerRow.frame, "TOPRIGHT", 0, 0)
        end

        local pLabel = AceGUI:Create("Label")
        pLabel:SetText("Profile:")
        pLabel:SetWidth(60)
        headerLeft:AddChild(pLabel)

        local pDrop = AceGUI:Create("Dropdown")
        UI.profileDropdown = pDrop
        pDrop:SetList(ProfilesList())
        pDrop:SetValue(profName)
        pDrop:SetWidth(220)
        pDrop:SetCallback("OnValueChanged", function(_, _, val)
            local root = FrameAlphaTweaksDB
            local charKey = (NS._charKey or GetCharKey())
            if root and root.profiles and root.profiles[val] then
                root.profileKeys[charKey] = val
                NS._profileName = val
                cfg = CopyDefaults(NS.defaults, root.profiles[val] or {})
                root.profiles[val] = cfg
                ValidateGroups()
                RebuildEntries()
                UI.selectedGroup = 1
                RefreshUI()
            end
        end)
        headerLeft:AddChild(pDrop)

        local function HeaderButton(text, width, onclick)
            local b = AceGUI:Create("Button")
            b:SetText(text)
            b:SetWidth(width or 100)
            b:SetCallback("OnClick", onclick)
            headerLeft:AddChild(b)
            return b
        end

        HeaderButton("New", 60, function() StaticPopup_Show("FAT_NEW_PROFILE") end)
		HeaderButton("Rename", 80, function()
			local active = (NS._profileName or profName or "Default")
			NS._profileName = active
			StaticPopup_Show("FAT_RENAME_PROFILE", active, nil, active)
		end)

        HeaderButton("Duplicate", 90, function()
            local active = (NS._profileName or profName or "Default")
            NS._profileName = active
            StaticPopup_Show("FAT_COPY_PROFILE", active, nil, active)
        end)
        HeaderButton("Delete", 70, function()
            local active = (NS._profileName or profName or "Default")
            NS._profileName = active
            StaticPopup_Show("FAT_DELETE_PROFILE", active, nil, active)
        end)
        HeaderButton("Export", 70, function()
            local root = FrameAlphaTweaksDB
            local active = (NS._profileName or profName or "Default")
            local s = ExportProfileString(active, root.profiles[active])
            StaticPopup_Show("FAT_EXPORT_PROFILE", active, nil, s)
        end)
        HeaderButton("Import", 70, function() StaticPopup_Show("FAT_IMPORT_PROFILE") end)
        

        -- Enable addon checkbox
        local enable = AceGUI:Create("CheckBox")
        UI.enableCheckbox = enable
        enable:SetLabel("Enable Addon (Priority: Top groups override bottom groups)")
        enable:SetFullWidth(true)
        enable:SetValue(cfg.enabled and true or false)
        enable:SetCallback("OnValueChanged", function(_, _, val)
            cfg.enabled = val and true or false
            RebuildEntries()
        end)
        f:AddChild(enable)        -- Columns container (manual anchoring: all columns share the same TOP baseline)
        UI._colH = 534
        UI._colW = { groups = 250, frames = 560, settings = 300 }

        -- Columns container (manual anchoring: all columns share the same TOP baseline)
        local cols = AceGUI:Create("SimpleGroup")
        cols:SetFullWidth(true)
        cols:SetHeight(UI._colH)
        cols:SetLayout("None")
        f:AddChild(cols)

        -- Fixed sizes (leave some slack so skins/padding don't cause wraps/offsets)
        -- Groups column
        local groupsBox = AceGUI:Create("InlineGroup")
        groupsBox:SetTitle("Groups")
        groupsBox:SetWidth(UI._colW.groups)
        groupsBox:SetHeight(UI._colH)
        groupsBox:SetLayout("List")
        cols:AddChild(groupsBox)

        if groupsBox.frame then
            groupsBox.frame:ClearAllPoints()
            groupsBox.frame:SetPoint("TOPLEFT", cols.frame, "TOPLEFT", 0, 0)
        end

        local gScroll = AceGUI:Create("ScrollFrame")
        UI.groupsScroll = gScroll
        gScroll:SetLayout("List")
        gScroll:SetFullWidth(true)
        gScroll:SetHeight(UI._colH - 110)
        groupsBox:AddChild(gScroll)

        local gBtnRow = AceGUI:Create("SimpleGroup")
        gBtnRow:SetFullWidth(true)
        gBtnRow:SetLayout("None")
        gBtnRow:SetHeight(40)
        groupsBox:AddChild(gBtnRow)

        local newG = AceGUI:Create("Button")
        UI.groupNewBtn = newG
        newG:SetText("New")
        newG:SetWidth(110)
        newG:SetCallback("OnClick", function()
            local new = CopyDefaults(NS.defaults.groups[1], { name = "New Group", frames = {} })
            table.insert(cfg.groups, new)
            UI.selectedGroup = #cfg.groups
            RebuildEntries()
            RefreshUI()
        end)
        gBtnRow:AddChild(newG)

        local delG = AceGUI:Create("Button")
        UI.groupDeleteBtn = delG
        delG:SetText("Delete")
        delG:SetWidth(110)
        delG:SetCallback("OnClick", function()
            EnsureSelectedGroup()
            local idx = UI.selectedGroup or 1
            local name = (cfg.groups[idx] and cfg.groups[idx].name) or ("Group " .. idx)

            -- Confirm delete
            NS._pendingDeleteGroup = idx
            if not StaticPopupDialogs["FAT_CONFIRM_DELETE_GROUP"] then
                StaticPopupDialogs["FAT_CONFIRM_DELETE_GROUP"] = {
                    text = "Delete group '%s'?",
                    button1 = "Delete",
                    button2 = "Cancel",
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                    OnAccept = function()
                        local di = NS._pendingDeleteGroup or 1
                        if #cfg.groups <= 1 then
                            local d = CopyDefaults(NS.defaults.groups[1], {})
                            d.name = "Default"
                            d.frames = {}
                            d.alpha = 0.5
                            cfg.groups[1] = d
                            UI.selectedGroup = 1
                        else
                            table.remove(cfg.groups, di)
                            if UI.selectedGroup > #cfg.groups then UI.selectedGroup = #cfg.groups end
                        end
                        NS._pendingDeleteGroup = nil
                        RebuildEntries()
                        RefreshUI()
                    end,
                    OnCancel = function()
                        NS._pendingDeleteGroup = nil
                    end,
                }
            end
            local popup = StaticPopup_Show("FAT_CONFIRM_DELETE_GROUP", name)
            if popup then popup:SetFrameStrata("DIALOG") end
        end)
        gBtnRow:AddChild(delG)

        local function PositionGroupButtons()
            if not (gBtnRow and (gBtnRow.content or gBtnRow.frame) and newG and newG.frame and delG and delG.frame) then return end
            local anchor = gBtnRow.content or gBtnRow.frame
            local gap = 10
            local w = anchor:GetWidth()
            if not w or w == 0 then w = UI._colW.groups end
            local total = newG.frame:GetWidth() + delG.frame:GetWidth() + gap
            local startX = math.floor((w - total) / 2 + 0.5)
            newG.frame:ClearAllPoints()
            newG.frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", startX, -2)
            delG.frame:ClearAllPoints()
            delG.frame:SetPoint("TOPLEFT", newG.frame, "TOPRIGHT", gap, 0)
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, PositionGroupButtons) else PositionGroupButtons() end

        -- Frames column
        local framesBox = AceGUI:Create("InlineGroup")
        framesBox:SetTitle("Frames")
        framesBox:SetWidth(UI._colW.frames)
        framesBox:SetHeight(UI._colH)
        framesBox:SetLayout("List")
        cols:AddChild(framesBox)

        if framesBox.frame then
            framesBox.frame:ClearAllPoints()
            framesBox.frame:SetPoint("TOPLEFT", groupsBox.frame, "TOPRIGHT", 10, 0)
        end

        local addRow = AceGUI:Create("SimpleGroup")
        addRow:SetFullWidth(true)
        addRow:SetLayout("None")
        addRow:SetHeight(40)
        framesBox:AddChild(addRow)

        local infoBtn = AceGUI:Create("Button")
        infoBtn:SetText("Info")
        infoBtn:SetWidth(60)
        addRow:AddChild(infoBtn)
        if infoBtn.frame then
            if infoBtn.frame.HookScript then
                infoBtn.frame:HookScript("OnEnter", function()
		ShowTooltip(infoBtn.frame, "Shift+LMB to move items up.\n\nShift+RMB to move items down.\n\nMMB to move a frame to another group.\n\nType /fstack and hover over frames to find frame names. Enter frame name into box and click 'Add' to add to current group. Frame names are case sensitive.")
			end)
				infoBtn.frame:HookScript("OnLeave", HideTooltip)
			end
        end

        local frameEdit = AceGUI:Create("EditBox")
        frameEdit:SetLabel("")
        frameEdit:SetWidth(250)
        frameEdit:SetText("")
		frameEdit:DisableButton(true)
        addRow:AddChild(frameEdit)

        local addBtn = AceGUI:Create("Button")
        addBtn:SetText("Add")
        addBtn:SetWidth(60)
        addBtn:SetCallback("OnClick", function()
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            local name = (frameEdit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            g.frames = g.frames or {}

-- ERROR if frame does not exist
if not _G[name] then
    print("|cff00c8ffFAT:|r Error: Frame does not exist: " .. name)
    frameEdit:SetText("")
    return
end

-- Prevent duplicates
for _, v in ipairs(g.frames) do
    if v == name then
        frameEdit:SetText("")
        return
    end
end

-- Add frame safely
table.insert(g.frames, name)

frameEdit:SetText("")
RebuildEntries()
RefreshUI()

        end)
        addRow:AddChild(addBtn)

        local presetsBtn = AceGUI:Create("Button")
        presetsBtn:SetText("Presets")
        presetsBtn:SetWidth(80)
        
        local function AddFrameToGroup(frameName)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.frames = g.frames or {}
            for _, v in ipairs(g.frames) do
                if v == frameName then return end
            end
            table.insert(g.frames, frameName)
            RebuildEntries()
            RefreshUI()
        end

        UI.presetExpanded = UI.presetExpanded or { unit_frames = false, action_bars = false, cdm = false }

        local function RefreshPresetsWindow()
            if not UI.presetsWin or not UI.presetsScroll then return end
            UI.presetsScroll:ReleaseChildren()
            UI.presetsScroll:SetLayout("List")

            local cats = {
                { key = "unit_frames", title = "Unit Frames", items = presets.unit_frames },
                { key = "cdm", title = "CDM", items = presets.cdm },
                { key = "action_bars", title = "Action Bars", items = presets.action_bars },
            }

            for _, cat in ipairs(cats) do
                local expanded = UI.presetExpanded[cat.key]

                local headRow = AceGUI:Create("SimpleGroup")
                headRow:SetFullWidth(true)
                headRow:SetLayout("Flow")

                local head = AceGUI:Create("Button")
                head:SetFullWidth(true)
                head:SetText((expanded and "[-] " or "[+] ") .. cat.title)
                head:SetCallback("OnClick", function()
                    UI.presetExpanded[cat.key] = not UI.presetExpanded[cat.key]
                    RefreshPresetsWindow()
                end)

                headRow:AddChild(head)
                UI.presetsScroll:AddChild(headRow)

                if expanded then
                    for _, item in ipairs(cat.items or {}) do
                        local row = AceGUI:Create("SimpleGroup")
                        row:SetFullWidth(true)
                        row:SetLayout("Flow")

                        local b = AceGUI:Create("Button")
                        local txt = item.name
                        if item.tip then txt = txt .. " (" .. item.tip .. ")" end
                        b:SetFullWidth(true)
                        b:SetText("  " .. txt)
                        b:SetCallback("OnClick", function() AddFrameToGroup(item.name) end)

                        row:AddChild(b)
                        UI.presetsScroll:AddChild(row)
                    end
                end
            end
        end

        local function TogglePresetsWindow()
            -- Avoid inline "drawer" with tiny height: ElvUI/WindTools skinning can choke on near-zero backdrops.
            if UI.presetsWin and UI.presetsWin.frame then
                if UI.presetsWin.frame:IsShown() then
                    UI.presetsWin.frame:Hide()
                else
                    UI.presetsWin.frame:Show()
                    UI.presetExpanded = { unit_frames = false, action_bars = false, cdm = false }
                    RefreshPresetsWindow()
                end
                return
            end

            local w = AceGUI:Create("Frame")
            UI.presetsWin = w
            w:SetTitle("Frame Alpha Tweaks - Presets")
            w:SetStatusText("")
            w:SetWidth(380)
            w:SetHeight(520)
            w:SetLayout("Fill")
            w:EnableResize(false)
            if w.frame then w.frame:SetFrameStrata("MEDIUM"); w.frame:SetFrameLevel(20) end

            w:SetCallback("OnClose", function(widget)
                AceGUI:Release(widget)
                UI.presetsWin = nil
                UI.presetsScroll = nil
            end)

            local scroll = AceGUI:Create("ScrollFrame")
            UI.presetsScroll = scroll
            scroll:SetLayout("List")
            scroll:SetFullWidth(true)
            scroll:SetFullHeight(true)
            w:AddChild(scroll)

            UI.presetExpanded = { unit_frames = false, action_bars = false, cdm = false }
            RefreshPresetsWindow()
        end

        presetsBtn:SetCallback("OnClick", TogglePresetsWindow)
        addRow:AddChild(presetsBtn)

        local function PositionFramesAddRow()
            if not (addRow and (addRow.content or addRow.frame) and infoBtn and infoBtn.frame and frameEdit and frameEdit.frame and addBtn and addBtn.frame and presetsBtn and presetsBtn.frame) then return end
            local anchor = addRow.content or addRow.frame
            local gap = 10
            local w = anchor:GetWidth()
            if not w or w == 0 then w = UI._colW.frames end

            local infoW = infoBtn.frame:GetWidth() or 60
            local editW = frameEdit.frame:GetWidth() or 320
            local addW = addBtn.frame:GetWidth() or 80
            local presW = presetsBtn.frame:GetWidth() or 80

            local total = infoW + gap + editW + gap + addW + gap + presW
            local startX = math.floor((w - total) / 2 + 0.5)
            if startX < 0 then startX = 0 end

            infoBtn.frame:ClearAllPoints()
            infoBtn.frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", startX, -2)

            frameEdit.frame:ClearAllPoints()
            frameEdit.frame:SetPoint("TOPLEFT", infoBtn.frame, "TOPRIGHT", gap, 0)

            addBtn.frame:ClearAllPoints()
            addBtn.frame:SetPoint("TOPLEFT", frameEdit.frame, "TOPRIGHT", gap, 0)

            presetsBtn.frame:ClearAllPoints()
            presetsBtn.frame:SetPoint("TOPLEFT", addBtn.frame, "TOPRIGHT", gap, 0)
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, PositionFramesAddRow) else PositionFramesAddRow() end

        local framesScroll = AceGUI:Create("ScrollFrame")
        UI.framesScroll = framesScroll
        framesScroll:SetLayout("List")
        framesScroll:SetFullWidth(true)
        framesScroll:SetHeight(UI._colH - 150)
        framesBox:AddChild(framesScroll)

        -- Settings column
        local settingsBox = AceGUI:Create("InlineGroup")
        settingsBox:SetTitle("Settings")
        settingsBox:SetWidth(UI._colW.settings)
        settingsBox:SetHeight(UI._colH)
        settingsBox:SetLayout("List")
        cols:AddChild(settingsBox)

        if settingsBox.frame then
            settingsBox.frame:ClearAllPoints()
            settingsBox.frame:SetPoint("TOPLEFT", framesBox.frame, "TOPRIGHT", 10, 0)
        end

        local function CenterColumns()
            if not (cols and cols.frame and groupsBox and groupsBox.frame) then return end
            local w = cols.frame:GetWidth()
            if not w or w == 0 then return end
            local total = (UI._colW.groups or 0) + 10 + (UI._colW.frames or 0) + 10 + (UI._colW.settings or 0)
            local x = math.floor((w - total) / 2 + 0.5)
            if x < 0 then x = 0 end
            groupsBox.frame:ClearAllPoints()
            groupsBox.frame:SetPoint("TOPLEFT", cols.frame, "TOPLEFT", x, 0)
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, CenterColumns) else CenterColumns() end


        local nameEdit = AceGUI:Create("EditBox")
        UI.groupNameEdit = nameEdit
        nameEdit:SetLabel("Group name")
        nameEdit:SetFullWidth(true)
        nameEdit:SetText(cfg.groups[UI.selectedGroup] and (cfg.groups[UI.selectedGroup].name or "") or "")
        nameEdit:SetCallback("OnEnterPressed", function(_, _, text)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.name = (text or ""):sub(1, 40)
            RefreshUI()
        end)
        settingsBox:AddChild(nameEdit)

        local topBtns = AceGUI:Create("SimpleGroup")
        topBtns:SetFullWidth(true)
        topBtns:SetLayout("Flow")
        settingsBox:AddChild(topBtns)

        UI.dupGroupBtn = AceGUI:Create("Button")
        UI.dupGroupBtn:SetText("Duplicate Group")
        UI.dupGroupBtn:SetFullWidth(true)
        UI.dupGroupBtn:SetCallback("OnClick", function()
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            local base = g.name or "Group"
            local copy = CopyDefaults(g, {})
            copy.name = base .. " (Copy)"
            table.insert(cfg.groups, UI.selectedGroup + 1, copy)
            UI.selectedGroup = UI.selectedGroup + 1
            RebuildEntries()
            RefreshUI()
        end)
        topBtns:AddChild(UI.dupGroupBtn)

        local heading = AceGUI:Create("Heading")
        heading:SetText("Force 100% Alpha when:")
        heading:SetFullWidth(true)
        settingsBox:AddChild(heading)

        UI.cbCombat = AceGUI:Create("CheckBox")
        UI.cbCombat:SetLabel("In Combat")
        UI.cbCombat:SetFullWidth(true)
        UI.cbCombat:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.combat = val and true or false
            RebuildEntries()
            RefreshUI()
        end)
        settingsBox:AddChild(UI.cbCombat)

        UI.cbTarget = AceGUI:Create("CheckBox")
        UI.cbTarget:SetLabel("Target Exists")
        UI.cbTarget:SetFullWidth(true)
        UI.cbTarget:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.target = val and true or false
            RebuildEntries()
            RefreshUI()
        end)
        settingsBox:AddChild(UI.cbTarget)

        UI.cbMouseover = AceGUI:Create("CheckBox")
        UI.cbMouseover:SetLabel("Mouseover")
        UI.cbMouseover:SetFullWidth(true)
        UI.cbMouseover:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.mouseover = val and true or false
            if g.mouseover then g.groupMouseover = false end
            RebuildEntries()
            RefreshUI()
        end)
        settingsBox:AddChild(UI.cbMouseover)

        UI.cbLinkedMouseover = AceGUI:Create("CheckBox")
        UI.cbLinkedMouseover:SetLabel("Linked Mouseover (Group)")
        UI.cbLinkedMouseover:SetFullWidth(true)
        UI.cbLinkedMouseover:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.groupMouseover = val and true or false
            if g.groupMouseover then g.mouseover = false end
            RebuildEntries()
            RefreshUI()
        end)
        settingsBox:AddChild(UI.cbLinkedMouseover)

        UI.fadeDelay = AceGUI:Create("Slider")
        UI.fadeDelay:SetLabel("Fade Delay (seconds)")
        UI.fadeDelay:SetFullWidth(true)
        UI.fadeDelay:SetSliderValues(0, 5, 0.1)
        UI.fadeDelay:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.mouseoverDelay = tonumber(val) or 0
            RebuildEntries()
        end)
        settingsBox:AddChild(UI.fadeDelay)

        UI.fadeIn = AceGUI:Create("Slider")
        UI.fadeIn:SetLabel("Fade In Duration (seconds)")
        UI.fadeIn:SetFullWidth(true)
        UI.fadeIn:SetSliderValues(0, 5, 0.1)
        UI.fadeIn:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.fadeInDuration = tonumber(val) or 0
            RebuildEntries()
        end)
        settingsBox:AddChild(UI.fadeIn)

        UI.fadeOut = AceGUI:Create("Slider")
        UI.fadeOut:SetLabel("Fade Out Duration (seconds)")
        UI.fadeOut:SetFullWidth(true)
        UI.fadeOut:SetSliderValues(0, 5, 0.1)
        UI.fadeOut:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.fadeOutDuration = tonumber(val) or 0
            RebuildEntries()
        end)
        settingsBox:AddChild(UI.fadeOut)
		
				--spacer/divider
		        local heading = AceGUI:Create("Heading")
        heading:SetFullWidth(true)
        settingsBox:AddChild(heading)


        UI.alphaSlider = AceGUI:Create("Slider")
        UI.alphaSlider:SetLabel("Baseline Alpha")
        UI.alphaSlider:SetFullWidth(true)
        UI.alphaSlider:SetSliderValues(0, 1, 0.01)
        UI.alphaSlider:SetCallback("OnValueChanged", function(_, _, val)
            EnsureSelectedGroup()
            local g = cfg.groups[UI.selectedGroup]
            g.alpha = tonumber(val) or 0.5
            RebuildEntries()
        end)
        settingsBox:AddChild(UI.alphaSlider)

        RefreshUI()
    end

    NS.ToggleConfig = function()
        if InCombatLockdown and InCombatLockdown() then
            print("|cff00c8ffFAT:|r Config cannot be opened in combat.")
            return
        end
        GetRoot()
        if not UI.frameWidget then
            BuildConfigWindow()
            return
        end
        local frame = UI.frameWidget.frame
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
            RefreshUI()
        end
    end

    local function HandleCombatState(inCombat)
        if inCombat then
            if UI.frameWidget and UI.frameWidget.frame:IsShown() then
                UI.reopenAfterCombat = true
                print("|cff00c8ffFAT:|r Config closed due to combat. It will reopen when combat ends.")
                UI.frameWidget.frame:Hide()
            end
            return
        end

        if UI.reopenAfterCombat then
            UI.reopenAfterCombat = nil
            GetRoot()
            if not UI.frameWidget then
                BuildConfigWindow()
                return
            end
            UI.frameWidget.frame:Show()
            RefreshUI()
        end
    end

    NS.HandleCombatState = HandleCombatState
end

-- Optional: keep a tiny entry in Blizzard settings that just opens the standalone window.
local function RegisterBlizzardOptionsStub()
    if not Settings or not Settings.RegisterAddOnCategory then return end
    local panel = CreateFrame("Frame", nil, nil)
    panel.name = "Frame Alpha Tweaks"
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)

    panel:SetScript("OnShow", function(self)
        if self._built then return end
        self._built = true
        local t = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 16, -16)
        t:SetText("Frame Alpha Tweaks")

        local d = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        d:SetPoint("TOPLEFT", 16, -46)
        d:SetJustifyH("LEFT")
        d:SetText("This addon uses a standalone configuration window.\nOpen it with /fat, the minimap button, or the button below.")

        local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        b:SetSize(200, 24)
        b:SetPoint("TOPLEFT", 16, -90)
        b:SetText("Open Config Window")
        b:SetScript("OnClick", function()
            if NS.ToggleConfig then NS.ToggleConfig() end
        end)
    end)
end



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
        cfg = prof
        ValidateGroups()
        print("|cff00c8ffFAT:|r Loaded. Type |cffffff00/fat|r for options.")
        RegisterBlizzardOptionsStub()
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
