-- Frame Alpha Tweaks - Config Panel

local ADDON, NS = ...
NS = NS or {}

local CopyDefaults = NS.CopyDefaults
local DeepCopy = NS.DeepCopy
local EnsureProfileSystem = NS.EnsureProfileSystem
local ValidateGroups = NS.ValidateGroups
local RebuildEntries = NS.RebuildEntries
local ExportProfileString = NS.ExportProfileString
local ImportProfileString = NS.ImportProfileString
local MakeUniqueProfileName = NS.MakeUniqueProfileName
local GetCharKey = NS.GetCharKey
local presets = NS.presets or {}

local cfg

local function SyncConfig()
    cfg = NS.GetConfig and NS.GetConfig() or cfg
end

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
        NS.SetConfig(cfg)
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
        NS.SetConfig(cfg)
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
        NS.SetConfig(cfg)

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
        NS.SetConfig(cfg)
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
        NS.SetConfig(cfg)
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
        SyncConfig()
        if not cfg then
            local root, charKey, profName, prof = EnsureProfileSystem()
            FrameAlphaTweaksDB = root
            NS._charKey = charKey
            NS._root = root
            NS._profileName = profName
            NS.SetConfig(prof)
            SyncConfig()
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
    -- Custom popup menu to avoid taint from UIDropDownMenuTemplate
    local function EnsureMovePopup()
        if UI.movePopup and UI.movePopup.IsObjectType and UI.movePopup:IsObjectType("Frame") then
            return
        end
        local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetClampedToScreen(true)
        popup:Hide()
        popup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        popup.buttons = {}

        -- Close when clicking outside
        popup:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(s)
                if not MouseIsOver(s) and IsMouseButtonDown("LeftButton") then
                    s:Hide()
                end
            end)
        end)
        popup:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        UI.movePopup = popup
    end

    local function CloseMoveFrameWindow()
        if UI.movePopup then
            UI.movePopup:Hide()
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
        EnsureMovePopup()

        local popup = UI.movePopup
        local current = UI.selectedGroup or 1

        -- Clear existing buttons
        for _, btn in ipairs(popup.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(popup.buttons)

        -- Build menu items
        local items = {}
        items[#items + 1] = { text = "Move Frame", isTitle = true }
        items[#items + 1] = { text = frameName, isTitle = true, highlight = true }

        local hasTargets = false
        for idx, grp in ipairs(cfg.groups or {}) do
            if idx ~= current then
                hasTargets = true
                local gname = grp.name or ("Group " .. idx)
                items[#items + 1] = {
                    text = gname,
                    func = function()
                        CloseMoveFrameWindow()
                        MoveFrameToGroup(frameName, idx, current)
                    end,
                }
            end
        end

        if not hasTargets then
            items[#items + 1] = { text = "(No other groups)", disabled = true }
        end

        -- Create buttons
        local BUTTON_HEIGHT = 20
        local BUTTON_WIDTH = 180
        local PADDING = 8
        local yOffset = -PADDING

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, popup)
            btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", PADDING, yOffset)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", 8, 0)
            text:SetPoint("RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            text:SetText(item.text)

            if item.isTitle then
                text:SetFontObject(item.highlight and "GameFontHighlightSmall" or "GameFontNormalSmall")
                btn:Disable()
            elseif item.disabled then
                text:SetTextColor(0.5, 0.5, 0.5)
                btn:Disable()
            else
                text:SetTextColor(1, 1, 1)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                btn:SetScript("OnClick", item.func)
            end

            popup.buttons[#popup.buttons + 1] = btn
            yOffset = yOffset - BUTTON_HEIGHT
        end

        -- Size and position popup
        popup:SetSize(BUTTON_WIDTH + PADDING * 2, (#items * BUTTON_HEIGHT) + PADDING * 2)

        if anchorFrame and anchorFrame.GetCenter then
            local x, y = anchorFrame:GetCenter()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        else
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end

        popup:Show()
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
    f.frame:SetFrameStrata("MEDIUM")
    f.frame:SetFrameLevel(10)
    -- ESC-to-close is handled by AceGUI's Frame widget natively.
    -- We avoid SetPropagateKeyboardInput and HookScript to prevent taint
    -- issues with Blizzard panels in WoW 12.0.
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
                NS.SetConfig(cfg)
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
        infoBtn:SetCallback("OnEnter", function(widget)
            ShowTooltip(widget.frame, "Shift+LMB to move items up.\n\nShift+RMB to move items down.\n\nMMB to move a frame to another group.\n\nType /fstack and hover over frames to find frame names. Enter frame name into box and click 'Add' to add to current group. Frame names are case sensitive.")
        end)
        infoBtn:SetCallback("OnLeave", function()
            HideTooltip()
        end)

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
        local spacer = AceGUI:Create("Heading")
        spacer:SetFullWidth(true)
        settingsBox:AddChild(spacer)

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

-- Settings API integration disabled to prevent taint errors in WoW 12.0
-- The Settings.RegisterCanvasLayoutCategory and UIPanelButtonTemplate can cause
-- taint when Blizzard UI panels (Talents, Character, etc.) are opened.
-- Users can access configuration via /fat or the minimap button.
NS.RegisterBlizzardOptionsStub = function()
    -- Intentionally disabled - see comment above
end
