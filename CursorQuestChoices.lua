-- Cursor Quest Choices + Auto Quest
-- World of Warcraft 3.3.5a / private-server compatible
-- By Darksolis

local ADDON_NAME = ...
local VERSION = "2.3.7"
local CQC = CreateFrame("Frame", "CursorQuestChoicesController")
local boardSessionActive = false
local boardLastSeen = 0
local boardReleaseArmed = false
local boardNPCGUID = nil

local defaults = {
    enabled = true,
    scale = 1.0,
    offsetX = 20,
    offsetY = -10,
    panelWidth = 400,
    maxVisibleRows = 10,
    hideBlizzardGossip = false,
    showGossip = true,
    showAvailable = true,
    showActive = true,
    moveMerchantFrame = true,
    showMerchantInventory = false,
    hideBlizzardMerchant = false,

    autoQuestEnabled = true,
    skipTrivial = true,
    blockedWords = { "commission" },
    rewardMode = "manual",       -- manual | value | stats
    statFocus = "AUTO",          -- AUTO | STR | AGI | STA | INT | SPI | AP | SP | HIT | CRIT | HASTE | EXP
    statsBehavior = "pick",      -- auto | pick
    debug = false,
}

local function CopyDefaults(source, target)
    if type(target) ~= "table" then target = {} end
    for k,v in pairs(source) do
        if type(v) == "table" then target[k] = CopyDefaults(v, target[k])
        elseif target[k] == nil then target[k] = v end
    end
    return target
end

local function Chat(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

local function Print(msg)
    Chat("|cff58c7ffCursor Quest:|r " .. tostring(msg))
end

local function Debug(...)
    if not CursorQuestChoicesDB or not CursorQuestChoicesDB.debug then return end
    local t = {}
    for i=1,select("#",...) do t[i]=tostring(select(i,...)) end
    Print("|cff999999"..table.concat(t," ").."|r")
end

local function SafeText(text)
    text=tostring(text or "")
    text=text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    return text
end


-- Legacy conflict protection ------------------------------------------------
-- Cursor Quest Choices v2+ includes AutoQuestMaster's functionality. If the
-- old standalone addon is still installed, both addons receive QUEST_DETAIL
-- and both can call AcceptQuest(). Holding Shift pauses both, which can make
-- the problem look like a failed board exclusion. Neutralize the legacy addon
-- at runtime and disable it for future reloads.
local legacyConflictReported = false

local function NeutralizeLegacyAutoQuest(reason)
    local found = false

    if type(AQMDB) == "table" then
        AQMDB.enabled = false
        found = true
    end

    local legacyFrame = _G.AQM_Frame
    if legacyFrame then
        found = true
        if legacyFrame.UnregisterAllEvents then
            pcall(legacyFrame.UnregisterAllEvents, legacyFrame)
        end
        if legacyFrame.SetScript then
            pcall(legacyFrame.SetScript, legacyFrame, "OnEvent", nil)
        end
    end

    if GetNumAddOns and GetAddOnInfo then
        for i = 1, GetNumAddOns() do
            local name, title = GetAddOnInfo(i)
            local probe = ((name or "") .. " " .. (title or "")):lower()
            if probe:find("autoquestmaster", 1, true) then
                found = true
                if DisableAddOn and name then pcall(DisableAddOn, name) end
            end
        end
    elseif DisableAddOn then
        pcall(DisableAddOn, "AutoQuestMaster335")
    end

    if found and not legacyConflictReported then
        legacyConflictReported = true
        Print("|cffffaa00Legacy AutoQuestMaster detected and stopped.|r Cursor Quest Choices now owns quest automation. The old addon has also been disabled for future logins.")
        Debug("Legacy AutoQuestMaster neutralized:", reason or "runtime check")
    end
    return found
end

local function Paused()
    -- Shift is the only temporary pause. Board handling is isolated to the
    -- specific guarded quest APIs so normal private-server NPC events are not
    -- accidentally suppressed.
    return IsShiftKeyDown() or not CursorQuestChoicesDB.autoQuestEnabled
end

-- Automation is intended for normal NPC conversations only. Custom panels
-- such as Hero's Call Board can fire the same quest events without a real NPC.
local function HasRealNPCContext()
    if not UnitExists or not UnitExists("npc") then return false end
    local name = UnitName and UnitName("npc")
    return type(name) == "string" and name ~= ""
end

local HARD_BLOCKED_QUEST_TITLES = {
    ["call to arms: battleground"] = true,
}

local function NormalizeQuestProbe(value)
    if type(value) ~= "string" then return "" end
    return SafeText(value):lower():gsub("[%s%p]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsHardBlockedQuestTitle(title)
    if type(title) ~= "string" then return false end
    local raw = SafeText(title):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if HARD_BLOCKED_QUEST_TITLES[raw] then return true end
    local normalized = NormalizeQuestProbe(title)
    -- Do not require an exact title. Ascension's board can append category,
    -- level, daily, or color text around the title.
    return normalized:find("call to arms", 1, true) ~= nil
       and normalized:find("battleground", 1, true) ~= nil
end

-- Private-server gossip APIs do not always return the quest title in slot 1.
-- Scan every string in the quest record before selecting it. This blocks at
-- the selection stage, which is required for boards that instantly accept a
-- quest when SelectGossipAvailableQuest/SelectAvailableQuest is called.
local function RecordContainsHardBlockedQuest(values, firstIndex, lastIndex)
    local combined = {}
    for i=firstIndex,lastIndex do
        if type(values[i]) == "string" and values[i] ~= "" then
            combined[#combined+1] = NormalizeQuestProbe(values[i])
        end
    end
    local probe = table.concat(combined, " ")
    return probe:find("call to arms", 1, true) ~= nil
       and probe:find("battleground", 1, true) ~= nil
end



-- Forward declarations used by early safety hooks.
-- These must be local before any function that references them is compiled.
local autoFlow
local pendingReward
local FindString
local BoardAutomationBlocked
local HeroCallBoardVisualOpen

-- Blocked quest UI suppression --------------------------------------------
-- The Ascension board can open Blizzard's quest-detail frame even when the
-- selection or AcceptQuest call is rejected. Keep a short suppression window
-- and close only the blocked quest page, leaving the board underneath intact.
local blockedQuestUISuppress = 0
local blockedQuestUIHooked = false

local function HideBlockedQuestPanels()
    local title = GetTitleText and GetTitleText()
    if not IsHardBlockedQuestTitle(title) and blockedQuestUISuppress <= 0 then return end

    if QuestFrameDetailPanel and QuestFrameDetailPanel.Hide then QuestFrameDetailPanel:Hide() end
    if QuestFrameProgressPanel and QuestFrameProgressPanel.Hide then QuestFrameProgressPanel:Hide() end
    if QuestFrameRewardPanel and QuestFrameRewardPanel.Hide then QuestFrameRewardPanel:Hide() end

    if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then
        if HideUIPanel then
            pcall(HideUIPanel, QuestFrame)
        elseif QuestFrame.Hide then
            QuestFrame:Hide()
        end
    end
end

local function SuppressBlockedQuestUI(reason)
    blockedQuestUISuppress = math.max(blockedQuestUISuppress or 0, 1.25)
    if autoFlow then autoFlow.pending = false end
    pendingReward = nil
    HideBlockedQuestPanels()
    if type(CloseQuest) == "function" then pcall(CloseQuest) end
    Debug("Blocked quest UI suppressed:", reason or "board quest")
end

local function InstallBlockedQuestUIHook()
    if blockedQuestUIHooked then return end
    blockedQuestUIHooked = true
    if QuestFrameDetailPanel and QuestFrameDetailPanel.HookScript then
        QuestFrameDetailPanel:HookScript("OnShow", function()
            local title = GetTitleText and GetTitleText()
            if IsHardBlockedQuestTitle(title) or blockedQuestUISuppress > 0 then
                SuppressBlockedQuestUI("detail panel OnShow")
            end
        end)
    end
end

-- Global quest API guard ---------------------------------------------------
-- Ascension's Hero's Call Board (or another UI module) may call Blizzard's
-- quest-selection functions directly. Event-handler checks inside this addon
-- cannot stop those external calls. Wrap the global APIs once and reject the
-- blocked board quest before any caller can select or accept it.
local questAPIGuardInstalled = false
local originalSelectGossipAvailableQuest
local originalSelectAvailableQuest
local originalAcceptQuest

local function GossipRecordIsHardBlocked(index)
    if not GetNumGossipAvailableQuests or not GetGossipAvailableQuests then return false end
    local count = GetNumGossipAvailableQuests() or 0
    if count <= 0 or type(index) ~= "number" or index < 1 or index > count then return false end
    local values = { GetGossipAvailableQuests() }
    local stride = math.floor(#values / count)
    if stride < 1 then return false end
    local first = ((index - 1) * stride) + 1
    return RecordContainsHardBlockedQuest(values, first, first + stride - 1)
end

local function GreetingRecordIsHardBlocked(index)
    if not GetAvailableTitle or type(index) ~= "number" then return false end
    local values = { GetAvailableTitle(index) }
    if RecordContainsHardBlockedQuest(values, 1, #values) then return true end
    -- FindString is forward-declared because this guard is installed before
    -- the general API parsing helpers are defined.
    local title = FindString and FindString(values, 1, #values) or nil
    if not title then
        for i=1,#values do if type(values[i])=="string" then title=values[i]; break end end
    end
    return IsHardBlockedQuestTitle(title)
end

local function InstallQuestAPIGuard()
    if questAPIGuardInstalled then return end
    questAPIGuardInstalled = true

    if type(_G.SelectGossipAvailableQuest) == "function" then
        originalSelectGossipAvailableQuest = _G.SelectGossipAvailableQuest
        _G.SelectGossipAvailableQuest = function(index, ...)
            if BoardAutomationBlocked and BoardAutomationBlocked(true) then
                Debug("BOARD GUARD blocked SelectGossipAvailableQuest", index)
                if autoFlow then autoFlow.pending = false end
                pendingReward = nil
                panel:Hide()
                return
            end
            if GossipRecordIsHardBlocked(index) then
                Debug("GLOBAL GUARD blocked SelectGossipAvailableQuest", index)
                SuppressBlockedQuestUI("global gossip selection guard")
                return
            end
            return originalSelectGossipAvailableQuest(index, ...)
        end
    end

    if type(_G.SelectAvailableQuest) == "function" then
        originalSelectAvailableQuest = _G.SelectAvailableQuest
        _G.SelectAvailableQuest = function(index, ...)
            if BoardAutomationBlocked and BoardAutomationBlocked(true) then
                Debug("BOARD GUARD blocked SelectAvailableQuest", index)
                if autoFlow then autoFlow.pending = false end
                pendingReward = nil
                panel:Hide()
                return
            end
            if GreetingRecordIsHardBlocked(index) then
                Debug("GLOBAL GUARD blocked SelectAvailableQuest", index)
                SuppressBlockedQuestUI("global greeting selection guard")
                return
            end
            return originalSelectAvailableQuest(index, ...)
        end
    end

    if type(_G.AcceptQuest) == "function" then
        originalAcceptQuest = _G.AcceptQuest
        _G.AcceptQuest = function(...)
            local title = GetTitleText and GetTitleText()
            if BoardAutomationBlocked and BoardAutomationBlocked(true) then
                Debug("BOARD GUARD blocked AcceptQuest", title or "?")
                SuppressBlockedQuestUI("board-wide AcceptQuest guard")
                return
            end
            if IsHardBlockedQuestTitle(title) then
                Debug("GLOBAL GUARD blocked AcceptQuest", title or "?")
                SuppressBlockedQuestUI("global AcceptQuest guard")
                return
            end
            return originalAcceptQuest(...)
        end
    end
end

local function StandardQuestDetailVisible()
    -- QUEST_DETAIL from a normal NPC displays Blizzard's actual detail panel.
    -- Custom boards may fire the same event without ever showing this panel.
    if QuestFrameDetailPanel and QuestFrameDetailPanel.IsShown then
        return QuestFrameDetailPanel:IsShown()
    end
    -- Conservative fallback for clients with renamed panel globals.
    if QuestFrame and QuestFrame.IsShown then
        return QuestFrame:IsShown()
    end
    return false
end

-- Hard UI exclusions -------------------------------------------------------
-- Custom private-server panels can expose quest-like APIs/events without
-- behaving like a normal NPC. Cursor Quest must remain completely dormant
-- for the entire Hero's Call Board session, including tab changes.
local excludedFrame = nil
local excludedRoot = nil
local exclusionScanDelay = 0
local EXCLUDED_TITLES = {
    ["hero's call board"] = true,
    ["heros call board"] = true,
}

local function NormalizedLabel(text)
    if type(text) ~= "string" then return nil end
    text = SafeText(text):lower():gsub("[%s%p]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function IsExcludedTitle(text)
    if type(text) ~= "string" then return false end
    local raw = SafeText(text):lower()
    if EXCLUDED_TITLES[raw] then return true end
    local normalized = NormalizedLabel(text)
    return normalized == "hero s call board" or normalized == "heros call board"
end

local function FrameNameLooksExcluded(frame)
    if not frame or not frame.GetName then return false end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" then return false end
    local lower = name:lower()
    return lower:find("heroscallboard", 1, true)
        or lower:find("herocallboard", 1, true)
        or lower:find("callboard", 1, true)
end

local function FrameIsEffectivelyVisible(frame)
    if not frame then return false end
    if frame.IsVisible then
        local ok, visible = pcall(frame.IsVisible, frame)
        if not ok or not visible then return false end
    elseif frame.IsShown then
        local ok, shown = pcall(frame.IsShown, frame)
        if not ok or not shown then return false end
    else
        return false
    end
    if frame.GetEffectiveAlpha then
        local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
        if ok and type(alpha) == "number" and alpha <= 0.01 then return false end
    end
    return true
end

local function FrameContainsExcludedTitle(frame, allowRegionInspection)
    if not FrameIsEffectivelyVisible(frame) then return false end
    if FrameNameLooksExcluded(frame) then return true end

    -- Region inspection is intentionally restricted to a tiny set of known
    -- Call Board candidates. Scanning GetRegions() on every UI frame can recurse
    -- through custom bag buttons (notably AdiBags) and cause a stack overflow.
    if allowRegionInspection and frame.GetRegions then
        local ok, regions = pcall(function() return { frame:GetRegions() } end)
        if ok and type(regions) == "table" then
            for _,region in ipairs(regions) do
                if region and region.GetObjectType and region.GetText then
                    local typeOK, objectType = pcall(region.GetObjectType, region)
                    if typeOK and objectType == "FontString" then
                        local textOK, text = pcall(region.GetText, region)
                        if textOK and IsExcludedTitle(text) then return true end
                    end
                end
            end
        end
    end
    return false
end

local function TopVisibleRoot(frame)
    if not frame then return nil end
    local current = frame
    local lastVisible = frame
    local safety = 0
    while current and current.GetParent and safety < 30 do
        local parent = current:GetParent()
        if not parent or parent == UIParent then break end
        if parent.IsShown and parent:IsShown() then lastVisible = parent end
        current = parent
        safety = safety + 1
    end
    return lastVisible
end

local function FindExcludedFrame()
    local likely = {
        _G.HerosCallBoardFrame, _G.HeroCallBoardFrame, _G.HerosCallBoard,
        _G.HeroCallBoard, _G.CallBoardFrame, _G.CallboardFrame,
    }
    for _,frame in ipairs(likely) do
        if FrameContainsExcludedTitle(frame, true) then return frame end
    end

    -- Search by frame name only. Never call GetRegions() across the global UI
    -- tree: custom inventory frames can implement recursive region access.
    if EnumerateFrames then
        local frame = EnumerateFrames()
        local safety = 0
        while frame and safety < 10000 do
            if FrameIsEffectivelyVisible(frame) and FrameNameLooksExcluded(frame) then return frame end
            frame = EnumerateFrames(frame)
            safety = safety + 1
        end
    end
    return nil
end

local function ActivateBoardSession(frame, reason)
    -- Do not cache a high-level parent frame. On this client, the board can be
    -- parented to a persistent shell that remains shown after the board closes,
    -- which would incorrectly block all later NPC quest interactions.
    boardSessionActive = true
    boardLastSeen = GetTime and GetTime() or 0
    boardReleaseArmed = false
    boardNPCGUID = (UnitGUID and UnitGUID("npc")) or boardNPCGUID
    excludedFrame = frame
    excludedRoot = nil
    Debug("Hero's Call Board detected:", reason or "visible frame")
end

local function VisibleBoardDetected(forceScan)
    -- A cached frame is trusted only while that exact matched frame remains
    -- visible and still contains the board title/name. Never trust its parent.
    if excludedFrame and FrameContainsExcludedTitle(excludedFrame) then
        boardLastSeen = GetTime and GetTime() or boardLastSeen
        return true
    end

    excludedFrame = nil
    excludedRoot = nil

    if forceScan or exclusionScanDelay <= 0 then
        local found = FindExcludedFrame()
        exclusionScanDelay = found and 0.10 or 0.35
        if found then
            ActivateBoardSession(found, "visible board frame")
            return true
        end
    end

    boardSessionActive = false
    return false
end

-- Single source of truth for Hero's Call Board automation blocking. This is
-- deliberately based on the visible board frame, not rotating quest titles.
-- Cached root/frame checks handle tab rebuilds; forced scans catch late-loaded
-- board frames before any selection API is allowed to run.
BoardAutomationBlocked = function(forceScan)
    -- Never retain a board session after the board is no longer truly visible.
    -- This is intentionally stateless: each quest action checks the live UI.
    local visible = VisibleBoardDetected(forceScan and true or false)
    if visible then
        if autoFlow then autoFlow.pending = false end
        pendingReward = nil
        if panel then panel:Hide() end
        return true
    end
    boardSessionActive = false
    boardReleaseArmed = false
    boardNPCGUID = nil
    excludedFrame = nil
    excludedRoot = nil
    return false
end

local function EndBoardSession(reason)
    boardSessionActive = false
    boardReleaseArmed = false
    boardNPCGUID = nil
    excludedFrame = nil
    excludedRoot = nil
    exclusionScanDelay = 0
    Debug("Hero's Call Board automatic Shift-pause released:", reason or "new NPC interaction")
end

local function MayReleaseBoardSession(event)
    if not boardSessionActive then return false end
    if event ~= "GOSSIP_SHOW" and event ~= "QUEST_GREETING" then return false end
    if VisibleBoardDetected(true) then return false end

    local now = GetTime and GetTime() or 0
    -- The board and its children must have been continuously absent. This
    -- prevents tab changes and custom quest transitions from unlocking us.
    if now - (boardLastSeen or 0) < 1.25 then return false end
    if not UnitExists or not UnitExists("npc") then return false end

    local guid = UnitGUID and UnitGUID("npc") or nil
    local name = UnitName and UnitName("npc") or nil
    if IsExcludedTitle(name) then return false end

    -- Require a genuinely new interaction context. The first normal event only
    -- arms release; a second event or changed NPC GUID completes it. This makes
    -- board-generated GOSSIP_SHOW unable to release its own lock.
    if guid and boardNPCGUID and guid ~= boardNPCGUID then
        EndBoardSession("different NPC GUID")
        return true
    end
    if boardReleaseArmed then
        EndBoardSession("confirmed normal NPC interaction")
        return true
    end
    boardReleaseArmed = true
    Debug("Board pause release armed; waiting for confirmation")
    return false
end

local function ExcludedInteractionOpen(forceScan, event)
    local npcName = UnitName and UnitName("npc")
    if IsExcludedTitle(npcName) then
        ActivateBoardSession(nil, "NPC/title match")
        return true
    end

    if VisibleBoardDetected(forceScan) then return true end

    if boardSessionActive then
        if MayReleaseBoardSession(event) then return false end
        return true
    end
    return false
end

FindString = function(values,a,b)
    for i=a,b do if type(values[i])=="string" and values[i]~="" then return values[i] end end
end

local function FindBoolean(values,a,b,preferred)
    if preferred and type(values[preferred])=="boolean" then return values[preferred] end
    for i=a,b do if type(values[i])=="boolean" then return values[i] end end
    return false
end

local function TitleBlocked(title)
    if type(title)~="string" then return false end
    if IsHardBlockedQuestTitle(title) then return true end
    local lower=title:lower()
    for _,word in ipairs(CursorQuestChoicesDB.blockedWords or {}) do
        if type(word)=="string" and word~="" and lower:find(word:lower(),1,true) then return true end
    end
    return false
end

-- Stat scoring -------------------------------------------------------------
local CLASS_WEIGHTS = {
 WARRIOR={STR=3,AP=2,AGI=2,HIT=2,CRIT=2,EXP=2,STA=.5,INT=.1,SPI=.1,SP=.1},
 PALADIN={STR=3,AP=2,AGI=1.5,HIT=2,CRIT=2,EXP=2,STA=.5,INT=1,SPI=.3,SP=1},
 HUNTER={AGI=3,AP=2.5,HIT=2,CRIT=2,STA=.5,INT=.5,STR=.5,SPI=.1,SP=.1},
 ROGUE={AGI=3,AP=2.5,HIT=2,CRIT=2,EXP=2,STA=.4,STR=.5,INT=.1,SPI=.1,SP=.1},
 PRIEST={SP=3,INT=2.5,SPI=1.5,CRIT=1.5,HASTE=1.5,STA=.5,STR=.1,AGI=.1,AP=.1},
 SHAMAN={STR=1,AGI=1.5,AP=2,HIT=1.5,CRIT=1.5,EXP=1,SP=2.5,INT=2,HASTE=1.5,STA=.6,SPI=.5},
 MAGE={SP=3,INT=2.5,HASTE=2,CRIT=1.5,STA=.4,SPI=.5,STR=.1,AGI=.1,AP=.1},
 WARLOCK={SP=3,INT=2.5,HASTE=2,CRIT=1.5,STA=.7,SPI=.6,STR=.1,AGI=.1,AP=.1},
 DRUID={AGI=2.5,AP=2,HIT=1.5,CRIT=1.5,EXP=1,SP=2.5,INT=2,HASTE=1.5,STA=.6,SPI=.7,STR=1},
 DEATHKNIGHT={STR=3,AP=2,HIT=2,CRIT=1.5,EXP=2,STA=.6,AGI=.6,INT=.1,SPI=.1,SP=.1},
}
local TOKEN_TO_KEY={
 ITEM_MOD_STRENGTH_SHORT="STR",ITEM_MOD_AGILITY_SHORT="AGI",ITEM_MOD_STAMINA_SHORT="STA",
 ITEM_MOD_INTELLECT_SHORT="INT",ITEM_MOD_SPIRIT_SHORT="SPI",ITEM_MOD_ATTACK_POWER_SHORT="AP",
 ITEM_MOD_SPELL_POWER_SHORT="SP",ITEM_MOD_HIT_RATING_SHORT="HIT",ITEM_MOD_CRIT_RATING_SHORT="CRIT",
 ITEM_MOD_HASTE_RATING_SHORT="HASTE",ITEM_MOD_EXPERTISE_RATING_SHORT="EXP",
}
local KEY_TO_TOKEN={}; for token,key in pairs(TOKEN_TO_KEY) do KEY_TO_TOKEN[key]=token end

local function VendorScore(link)
    if not link then return 0,false end
    local price=select(11,GetItemInfo(link))
    return tonumber(price) or 0, price~=nil
end

local function StatsScore(index)
    local link=GetQuestItemLink("choice",index)
    if not link then return 0,false end
    local stats=GetItemStats(link)
    if not stats then return 0,false end
    local focus=CursorQuestChoicesDB.statFocus or "AUTO"
    if focus~="AUTO" then
        local token=KEY_TO_TOKEN[focus]
        if token then return tonumber(stats[token]) or 0,true end
    end
    local _,class=UnitClass("player"); local weights=CLASS_WEIGHTS[class or "WARRIOR"] or CLASS_WEIGHTS.WARRIOR
    local score=0
    for token,val in pairs(stats) do local key=TOKEN_TO_KEY[token]; if key and weights[key] then score=score+(tonumber(val) or 0)*weights[key] end end
    return score,true
end

local function RewardScore(index, mode)
    if mode=="stats" then
        local s,ready=StatsScore(index)
        if ready and s>0 then return s,true end
    end
    return VendorScore(GetQuestItemLink("choice",index))
end

local function MoneyText(copper)
    copper=tonumber(copper) or 0
    local g=math.floor(copper/10000); local s=math.floor((copper%10000)/100); local c=copper%100
    if g>0 then return g.."g "..s.."s" elseif s>0 then return s.."s "..c.."c" else return c.."c" end
end

-- Shared cursor panel ------------------------------------------------------
local panel=CreateFrame("Frame","CursorQuestChoicesFrame",UIParent)
panel:SetFrameStrata("DIALOG"); panel:SetToplevel(true); panel:SetClampedToScreen(true)
panel:EnableMouse(true); panel:EnableMouseWheel(true); panel:SetWidth(400); panel:SetHeight(120); panel:Hide()
UISpecialFrames=UISpecialFrames or {}; table.insert(UISpecialFrames,"CursorQuestChoicesFrame")
panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=10,right=10,top=10,bottom=10}})
panel:SetBackdropColor(.035,.045,.065,.98); panel:SetBackdropBorderColor(.45,.60,.82,1)
panel.shadow=panel:CreateTexture(nil,"BACKGROUND"); panel.shadow:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background"); panel.shadow:SetPoint("TOPLEFT",-7,7); panel.shadow:SetPoint("BOTTOMRIGHT",7,-7); panel.shadow:SetVertexColor(0,0,0,.72)
panel.inner=panel:CreateTexture(nil,"BORDER"); panel.inner:SetTexture("Interface\\Buttons\\WHITE8X8"); panel.inner:SetPoint("TOPLEFT",12,-12); panel.inner:SetPoint("BOTTOMRIGHT",-12,12); panel.inner:SetVertexColor(.025,.035,.055,.94)
panel.header=CreateFrame("Frame",nil,panel); panel.header:SetPoint("TOPLEFT",13,-13); panel.header:SetPoint("TOPRIGHT",-13,-13); panel.header:SetHeight(35); panel.header:EnableMouse(true)
panel.headerTex=panel.header:CreateTexture(nil,"BACKGROUND"); panel.headerTex:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight"); panel.headerTex:SetAllPoints(); panel.headerTex:SetBlendMode("ADD"); panel.headerTex:SetVertexColor(.08,.35,.62,.72)
panel.headerLine=panel.header:CreateTexture(nil,"ARTWORK"); panel.headerLine:SetTexture("Interface\\Buttons\\WHITE8X8"); panel.headerLine:SetHeight(1); panel.headerLine:SetPoint("BOTTOMLEFT",5,0); panel.headerLine:SetPoint("BOTTOMRIGHT",-5,0); panel.headerLine:SetVertexColor(.25,.68,1,.75)
panel.emblem=panel.header:CreateTexture(nil,"ARTWORK"); panel.emblem:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon"); panel.emblem:SetSize(25,25); panel.emblem:SetPoint("LEFT",8,0)
panel.title=panel.header:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); panel.title:SetPoint("LEFT",panel.emblem,"RIGHT",8,1); panel.title:SetPoint("RIGHT",-38,1); panel.title:SetJustifyH("LEFT"); panel.title:SetTextColor(.72,.9,1); panel.title:SetShadowColor(0,0,0,1); panel.title:SetShadowOffset(1,-1)
panel.close=CreateFrame("Button",nil,panel.header,"UIPanelCloseButton"); panel.close:SetPoint("RIGHT",4,1); panel.close:SetSize(27,27); panel.close:SetScript("OnClick",function() panel:Hide() end)
panel.hint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); panel.hint:SetPoint("TOPLEFT",panel.header,"BOTTOMLEFT",9,-7); panel.hint:SetPoint("RIGHT",panel,"RIGHT",-22,0); panel.hint:SetJustifyH("LEFT"); panel.hint:SetWordWrap(false); panel.hint:SetTextColor(.56,.63,.72)
panel.footer=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); panel.footer:SetPoint("BOTTOMRIGHT",-21,16); panel.footer:SetText("By Darksolis  •  v"..VERSION); panel.footer:SetTextColor(.35,.43,.54)
panel.scrollUp=CreateFrame("Button",nil,panel); panel.scrollUp:SetSize(20,20); panel.scrollUp:SetPoint("BOTTOMLEFT",20,12); panel.scrollUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up"); panel.scrollUp:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down"); panel.scrollUp:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled"); panel.scrollUp:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight"); panel.scrollUp:Hide()
panel.scrollDown=CreateFrame("Button",nil,panel); panel.scrollDown:SetSize(20,20); panel.scrollDown:SetPoint("LEFT",panel.scrollUp,"RIGHT",3,0); panel.scrollDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"); panel.scrollDown:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down"); panel.scrollDown:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled"); panel.scrollDown:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight"); panel.scrollDown:Hide()

local ROW_HEIGHT,CONTENT_TOP,FOOTER_HEIGHT,ROW_INSET=42,64,38,22
local entries,buttons,scrollOffset,clickLock={}, {},0,0
local panelMode="gossip"

local function FitText(fs,text,maxWidth)
    text=SafeText(text); fs:SetText(text); if fs:GetStringWidth()<=maxWidth then return false end
    local lo,hi,best=0,#text,"..."
    while lo<=hi do
        local mid=math.floor((lo+hi)/2); local prefix=text:sub(1,mid)
        while #prefix>0 do local b=prefix:byte(#prefix); if not b or b<128 or b>=192 then break end; prefix=prefix:sub(1,#prefix-1) end
        local candidate=prefix.."..."; fs:SetText(candidate)
        if fs:GetStringWidth()<=maxWidth then best=candidate; lo=mid+1 else hi=mid-1 end
    end
    fs:SetText(best); return true
end

local function EffectiveRows()
    local scale=CursorQuestChoicesDB.scale or 1
    local usable=(UIParent:GetHeight()/scale)-CONTENT_TOP-FOOTER_HEIGHT-28
    return math.min(CursorQuestChoicesDB.maxVisibleRows or 10, math.max(3,math.floor(usable/ROW_HEIGHT)))
end

local function PositionPanel()
    panel:SetWidth(CursorQuestChoicesDB.panelWidth or 400); panel:ClearAllPoints()
    local x,y=GetCursorPosition(); local ui=UIParent:GetEffectiveScale(); x,y=x/ui,y/ui
    local w,h=panel:GetWidth()*panel:GetScale(),panel:GetHeight()*panel:GetScale(); local sw,sh=UIParent:GetWidth(),UIParent:GetHeight(); local ox,oy=CursorQuestChoicesDB.offsetX or 20,CursorQuestChoicesDB.offsetY or -10
    local point,rel,px="TOPLEFT","BOTTOMLEFT",x+ox
    if px+w>sw then point="TOPRIGHT"; px=x-ox end
    local py=y+oy
    if py-h<0 then point=(point=="TOPLEFT") and "BOTTOMLEFT" or "BOTTOMRIGHT"; py=y-oy end
    panel:SetPoint(point,UIParent,rel,px,py)
end

local function GetButton(i)
    if buttons[i] then return buttons[i] end
    local b=CreateFrame("Button",nil,panel); b:SetHeight(38); b:RegisterForClicks("LeftButtonUp")
    b.bg=b:CreateTexture(nil,"BACKGROUND"); b.bg:SetTexture("Interface\\Buttons\\WHITE8X8"); b.bg:SetAllPoints(); b.bg:SetVertexColor(.075,.095,.135,.92)
    b.edge=b:CreateTexture(nil,"BORDER"); b.edge:SetTexture("Interface\\Buttons\\WHITE8X8"); b.edge:SetWidth(2); b.edge:SetPoint("TOPLEFT"); b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetVertexColor(.2,.52,.8,.85)
    b.iconBG=b:CreateTexture(nil,"BORDER"); b.iconBG:SetTexture("Interface\\Buttons\\WHITE8X8"); b.iconBG:SetSize(32,32); b.iconBG:SetPoint("LEFT",4,0); b.iconBG:SetVertexColor(.02,.025,.04,.95)
    b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(28,28); b.icon:SetPoint("CENTER",b.iconBG)
    b.name=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); b.name:SetPoint("LEFT",b.iconBG,"RIGHT",8,7); b.name:SetPoint("RIGHT",-28,7); b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false); b.name:SetShadowColor(0,0,0,1); b.name:SetShadowOffset(1,-1)
    b.sub=b:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); b.sub:SetPoint("LEFT",b.iconBG,"RIGHT",8,-8); b.sub:SetPoint("RIGHT",-28,-8); b.sub:SetJustifyH("LEFT"); b.sub:SetWordWrap(false); b.sub:SetTextColor(.58,.66,.76)
    b.arrow=b:CreateTexture(nil,"ARTWORK"); b.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"); b.arrow:SetSize(14,14); b.arrow:SetPoint("RIGHT",-7,0); b.arrow:SetAlpha(.55)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
    b:SetScript("OnEnter",function(self)
        self.bg:SetVertexColor(.10,.19,.29,1); self.edge:SetVertexColor(.35,.78,1,1); self.arrow:SetAlpha(1)
        if self.itemIndex then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetQuestItem("choice",self.itemIndex); GameTooltip:Show()
        elseif self.merchantIndex and GameTooltip.SetMerchantItem then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetMerchantItem(self.merchantIndex); GameTooltip:Show()
        elseif self.tooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.tooltip,1,1,1,true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave",function(self) self.bg:SetVertexColor(.075,.095,.135,.92); self.edge:SetVertexColor(.2,.52,.8,.85); self.arrow:SetAlpha(.55); GameTooltip:Hide() end)
    buttons[i]=b; return b
end

local function Refresh()
    local maxRows=EffectiveRows(); local visible=math.min(#entries,maxRows)
    for i=1,maxRows do
        local b=GetButton(i); local e=entries[i+scrollOffset]
        if e then
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",panel,"TOPLEFT",ROW_INSET,-(CONTENT_TOP+(i-1)*ROW_HEIGHT)); b:SetPoint("RIGHT",panel,"RIGHT",-ROW_INSET,0)
            b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark"); b.name:SetTextColor(unpack(e.color or {.82,.9,1}))
            local width=math.max(100,b:GetWidth()-80); local trunc=FitText(b.name,e.text,width); FitText(b.sub,e.subtext or "",width)
            b.tooltip=trunc and (e.text..(e.tooltip and "\n\n"..e.tooltip or "")) or e.tooltip; b.itemIndex=e.itemIndex; b.merchantIndex=e.merchantIndex
            b:SetScript("OnClick",function(self,button)
                if button~="LeftButton" or clickLock>0 then return end; clickLock=.30; self:Disable(); if e.onClick then e.onClick() end
            end)
            b:Enable(); b:Show()
        else b:Hide(); b:SetScript("OnClick",nil); b.tooltip=nil; b.itemIndex=nil; b.merchantIndex=nil end
    end
    for i=maxRows+1,#buttons do buttons[i]:Hide() end
    if #entries>maxRows then
        local first,last=scrollOffset+1,math.min(#entries,scrollOffset+visible); panel.hint:SetText("Mouse wheel  •  "..first.."-"..last.." of "..#entries); panel.scrollUp:Show(); panel.scrollDown:Show()
        if scrollOffset<=0 then panel.scrollUp:Disable() else panel.scrollUp:Enable() end
        if scrollOffset>=#entries-maxRows then panel.scrollDown:Disable() else panel.scrollDown:Enable() end
    else
        if panelMode=="reward" then panel.hint:SetText("Choose a quest reward")
        elseif panelMode=="merchant" then panel.hint:SetText("Click an item to buy one vendor unit")
        else panel.hint:SetText("Choose an interaction") end
        panel.scrollUp:Hide(); panel.scrollDown:Hide()
    end
    panel:SetHeight(CONTENT_TOP+visible*ROW_HEIGHT+FOOTER_HEIGHT)
end

local function ShowPanel(title,mode,emblem,keepPosition)
    if #entries==0 then panel:Hide(); return end
    panelMode=mode or "gossip"; panel.emblem:SetTexture(emblem or "Interface\\GossipFrame\\AvailableQuestIcon"); panel.title:SetText(SafeText(title)); FitText(panel.title,title,math.max(160,panel:GetWidth()-115))
    panel:SetScale(CursorQuestChoicesDB.scale or 1); Refresh(); if not keepPosition or not panel:IsShown() then PositionPanel() end; panel:Show(); panel:Raise()
end
local function ResetEntries() entries={}; scrollOffset=0 end
local function AddEntry(e) table.insert(entries,e) end

panel:SetScript("OnMouseWheel",function(_,delta) local m=math.max(0,#entries-EffectiveRows()); scrollOffset=delta<0 and math.min(m,scrollOffset+1) or math.max(0,scrollOffset-1); Refresh() end)
panel.scrollUp:SetScript("OnClick",function() scrollOffset=math.max(0,scrollOffset-1); Refresh() end)
panel.scrollDown:SetScript("OnClick",function() scrollOffset=math.min(math.max(0,#entries-EffectiveRows()),scrollOffset+1); Refresh() end)
panel:SetScript("OnUpdate",function(_,elapsed) if clickLock>0 then clickLock=math.max(0,clickLock-elapsed); if clickLock==0 then for _,b in ipairs(buttons) do if b:IsShown() then b:Enable() end end end end end)

local gossipIcons={vendor="Interface\\GossipFrame\\VendorGossipIcon",trainer="Interface\\GossipFrame\\TrainerGossipIcon",taxi="Interface\\GossipFrame\\TaxiGossipIcon",banker="Interface\\GossipFrame\\BankerGossipIcon",battlemaster="Interface\\GossipFrame\\BattleMasterGossipIcon",healer="Interface\\GossipFrame\\HealerGossipIcon",binder="Interface\\GossipFrame\\BinderGossipIcon",auctioneer="Interface\\GossipFrame\\AuctioneerGossipIcon",tabard="Interface\\GossipFrame\\TabardGossipIcon",gossip="Interface\\GossipFrame\\GossipGossipIcon"}

HeroCallBoardVisualOpen = function()
    -- Visual-only exclusion. This must not alter normal quest automation state.
    -- The board can expose a gossip option such as "Return" even though it is
    -- not a normal NPC interaction, so suppress only Cursor Quest's popup.
    local npcName = UnitName and UnitName("npc") or nil
    if IsExcludedTitle(npcName) then return true end
    return FindExcludedFrame() ~= nil
end

-- Cursor NPC choices -------------------------------------------------------
-- Some private-server NPC menus publish placeholder texture markup on the
-- first GOSSIP_SHOW, then populate the real option labels a frame or two later.
-- Keep a short, bounded refresh window so the player never has to click away
-- and reopen the NPC to get readable choices.
local gossipRefresh = { active=false, delay=0, elapsed=0, attempts=0 }

local function CancelGossipRefresh()
    gossipRefresh.active=false
    gossipRefresh.delay=0
    gossipRefresh.elapsed=0
    gossipRefresh.attempts=0
end

local function ScheduleGossipRefresh(delay)
    gossipRefresh.active=true
    gossipRefresh.delay=delay or 0.08
    gossipRefresh.elapsed=0
    gossipRefresh.attempts=0
end

local function CleanGossipOptionText(value)
    local text=tostring(value or "")
    text=text:gsub("|T.-|t", "")
    text=text:gsub("|A.-|a", "")
    text=SafeText(text)
    text=text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function GossipTextNeedsRefresh(rawText, cleanText)
    if cleanText=="" then return true end
    local lower=cleanText:lower()
    if lower:find("interface\\icons\\",1,true) or lower:find("interface/icons/",1,true) then return true end
    return false
end

local function GossipInlineIcon(rawText)
    local raw=tostring(rawText or "")
    return raw:match("|T([^:|]+)") or raw:match("|A([^:|]+)")
end

local function GossipContextAvailable()
    local options=GetNumGossipOptions and GetNumGossipOptions() or 0
    local available=GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
    local active=GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
    return (options+available+active)>0
end

local function BuildGossipChoices(keepPosition)
    if HeroCallBoardVisualOpen() then panel:Hide(); return false end
    if not CursorQuestChoicesDB.enabled then return false end
    ResetEntries(); local npc=UnitName("npc") or "NPC"
    if CursorQuestChoicesDB.showActive and GetGossipActiveQuests then
        local data={GetGossipActiveQuests()}; local count=GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0; local stride=count>0 and math.floor(#data/count) or 0
        if stride>=4 then for i=1,count do local index=i; local o=(index-1)*stride; local title=FindString(data,o+1,o+stride); local lvl=tonumber(data[o+2]); local complete=FindBoolean(data,o+1,o+stride,o+4); if title then AddEntry{text=(lvl and lvl>0 and "["..lvl.."] " or "")..title,subtext=complete and "Ready to turn in" or "Quest in progress",icon=complete and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon",color=complete and {.36,1,.5} or {1,.78,.28},onClick=function() SelectGossipActiveQuest(index) end} end end end
    end
    if CursorQuestChoicesDB.showAvailable and GetGossipAvailableQuests then
        local data={GetGossipAvailableQuests()}; local count=GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0; local stride=count>0 and math.floor(#data/count) or 0
        if stride>=3 then for i=1,count do local index=i; local o=(index-1)*stride; local title=FindString(data,o+1,o+stride); local lvl=tonumber(data[o+2]); local trivial=FindBoolean(data,o+1,o+stride,o+3); if title then AddEntry{text=(lvl and lvl>0 and "["..lvl.."] " or "")..title,subtext=trivial and "Low-level available quest" or "Available quest",icon="Interface\\GossipFrame\\AvailableQuestIcon",color=trivial and {.62,.64,.68} or {1,.91,.3},onClick=function() SelectGossipAvailableQuest(index) end} end end end
    end
    local needsRefresh=false
    if CursorQuestChoicesDB.showGossip and GetGossipOptions then
        local data={GetGossipOptions()}
        for i=1,#data,2 do
            local rawText=data[i]
            local text=CleanGossipOptionText(rawText)
            local kind=tostring(data[i+1] or "gossip"):lower()
            local index=math.floor((i-1)/2)+1
            local malformed=GossipTextNeedsRefresh(rawText,text)
            local inlineIcon=GossipInlineIcon(rawText)
            if malformed then needsRefresh=true end
            if text=="" or malformed then text="Loading interaction..." end
            AddEntry{text=text,subtext=malformed and "Loading NPC interaction" or "NPC interaction: "..kind,icon=inlineIcon or gossipIcons[kind] or gossipIcons.gossip,color={.8,.9,1},onClick=function() SelectGossipOption(index) end}
        end
    end
    ShowPanel(npc,"gossip","Interface\\GossipFrame\\GossipGossipIcon",keepPosition)
    if CursorQuestChoicesDB.hideBlizzardGossip and GossipFrame and GossipFrame:IsShown() then GossipFrame:Hide() end
    return needsRefresh
end

local function BuildGreetingChoices()
    if HeroCallBoardVisualOpen() then panel:Hide(); return end
    if not CursorQuestChoicesDB.enabled then return end
    ResetEntries(); local npc=UnitName("npc") or "Quest Choices"
    if CursorQuestChoicesDB.showActive and GetNumActiveQuests and GetActiveTitle then for i=1,GetNumActiveQuests() do local index=i; local vals={GetActiveTitle(index)}; local title=FindString(vals,1,#vals); local complete=FindBoolean(vals,1,#vals,2); if title then AddEntry{text=title,subtext=complete and "Ready to turn in" or "Quest in progress",icon=complete and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon",color=complete and {.36,1,.5} or {1,.78,.28},onClick=function() SelectActiveQuest(index) end} end end end
    if CursorQuestChoicesDB.showAvailable and GetNumAvailableQuests and GetAvailableTitle then for i=1,GetNumAvailableQuests() do local index=i; local vals={GetAvailableTitle(index)}; local title=FindString(vals,1,#vals); local trivial=IsAvailableQuestTrivial and IsAvailableQuestTrivial(index) or false; if title then AddEntry{text=title,subtext=trivial and "Low-level available quest" or "Available quest",icon="Interface\\GossipFrame\\AvailableQuestIcon",color=trivial and {.62,.64,.68} or {1,.91,.3},onClick=function() SelectAvailableQuest(index) end} end end end
    ShowPanel(npc,"gossip","Interface\\GossipFrame\\AvailableQuestIcon")
end



-- Native merchant frame positioning ---------------------------------------
-- Keep Blizzard's real MerchantFrame (repair, buyback, extended costs,
-- stack quantities, currencies, etc.) and move it beside the cursor.
local merchantRepositionUntil = 0
local merchantHookInstalled = false
local merchantAnchorX, merchantAnchorY = nil, nil

local function CaptureMerchantAnchor()
    if not GetCursorPosition or not UIParent then return false end
    local uiScale = UIParent:GetEffectiveScale() or 1
    if uiScale <= 0 then uiScale = 1 end
    local x, y = GetCursorPosition()
    merchantAnchorX, merchantAnchorY = x / uiScale, y / uiScale
    return true
end

local function PositionMerchantFrameAtAnchor()
    if not CursorQuestChoicesDB or not CursorQuestChoicesDB.moveMerchantFrame then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not UIParent then return end
    if not merchantAnchorX or not merchantAnchorY then
        if not CaptureMerchantAnchor() then return end
    end

    local x, y = merchantAnchorX, merchantAnchorY
    local screenW, screenH = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
    local frameW, frameH = MerchantFrame:GetWidth() or 336, MerchantFrame:GetHeight() or 444
    local gap = 18

    MerchantFrame:ClearAllPoints()
    if MerchantFrame.SetClampedToScreen then MerchantFrame:SetClampedToScreen(true) end

    -- Prefer the left side of the cursor so the merchant frame is less likely
    -- to cover bags, which are commonly opened on the right side of the screen.
    local openLeft = (x - gap - frameW) >= 0
    local openDown = (y - gap - frameH) >= 0

    if openLeft and openDown then
        MerchantFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x - gap, y - gap)
    elseif openLeft then
        MerchantFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x - gap, y + gap)
    elseif openDown then
        MerchantFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + gap, y - gap)
    else
        MerchantFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + gap, y + gap)
    end
end

local function BeginMerchantReposition()
    if not CursorQuestChoicesDB or not CursorQuestChoicesDB.moveMerchantFrame then return end
    CaptureMerchantAnchor()
    merchantRepositionUntil = (GetTime and GetTime() or 0) + 0.75
    PositionMerchantFrameAtAnchor()
end

local function InstallMerchantFrameHook()
    if merchantHookInstalled or not MerchantFrame then return end
    merchantHookInstalled = true
    if MerchantFrame.HookScript then
        MerchantFrame:HookScript("OnShow", function() BeginMerchantReposition() end)
    end
end

-- Cursor merchant inventory ------------------------------------------------
-- The normal MerchantFrame stays available for repair, buyback, and quantity
-- purchases. This cursor panel provides a fast, compact one-click storefront.
local function MerchantTitle()
    local npc = UnitName and UnitName("npc")
    if type(npc)=="string" and npc~="" then return npc.." • Store" end
    if MerchantNameText and MerchantNameText.GetText then
        local text=MerchantNameText:GetText(); if type(text)=="string" and text~="" then return text.." • Store" end
    end
    return "Merchant Store"
end

local function BuildMerchantPanel(keepPosition)
    if not CursorQuestChoicesDB.enabled or not CursorQuestChoicesDB.showMerchantInventory then return end
    if not GetMerchantNumItems or not GetMerchantItemInfo then return end
    ResetEntries()
    local total=GetMerchantNumItems() or 0
    for i=1,total do
        local index=i
        local name,texture,price,quantity,numAvailable,isUsable,extendedCost=GetMerchantItemInfo(index)
        local link=GetMerchantItemLink and GetMerchantItemLink(index) or nil
        name=name or (link and link:match("%[(.-)%]")) or ("Vendor Item "..index)
        local quality=link and select(3,GetItemInfo(link)) or nil
        local r,g,b=1,1,1
        if quality and GetItemQualityColor then r,g,b=GetItemQualityColor(quality) end
        local parts={}
        if tonumber(price) and price>0 then parts[#parts+1]=MoneyText(price)
        elseif extendedCost then parts[#parts+1]="Special currency"
        else parts[#parts+1]="No coin cost" end
        if quantity and quantity>1 then parts[#parts+1]="x"..quantity.." per purchase" end
        if numAvailable and numAvailable>=0 then
            if numAvailable==0 then parts[#parts+1]="Sold out" else parts[#parts+1]=numAvailable.." available" end
        end
        if isUsable==false then parts[#parts+1]="Not currently usable" end
        AddEntry{
            text=name, subtext=table.concat(parts,"  •  "), icon=texture or "Interface\\Icons\\INV_Misc_Coin_01",
            color={r,g,b}, merchantIndex=index, tooltip="Left-click buys one vendor unit. Use the normal merchant window for repair, buyback, or larger quantities.",
            onClick=function()
                local _,_,_,_,available=GetMerchantItemInfo(index)
                if available==0 then return end
                if BuyMerchantItem then BuyMerchantItem(index,1) end
            end
        }
    end
    ShowPanel(MerchantTitle(),"merchant","Interface\\GossipFrame\\VendorGossipIcon",keepPosition)
    if CursorQuestChoicesDB.hideBlizzardMerchant and MerchantFrame and MerchantFrame:IsShown() then MerchantFrame:Hide() end
end

-- Reward UI ---------------------------------------------------------------
pendingReward = nil
local function BuildRewardPanel(showScores)
    ResetEntries(); local num=GetNumQuestChoices() or 0; local best,bestScore=1,-1; local scores={}
    for i=1,num do local score=RewardScore(i,CursorQuestChoicesDB.rewardMode); scores[i]=score or 0; if scores[i]>bestScore then bestScore=scores[i]; best=i end end
    for i=1,num do
        local index=i
        local name,texture,count,quality=GetQuestItemInfo("choice",index); local link=GetQuestItemLink("choice",index); name=name or (link and link:match("%[(.-)%]")) or ("Reward "..i)
        local r,g,b=1,1,1; if quality and GetItemQualityColor then r,g,b=GetItemQualityColor(quality) end
        local sub="Click to choose"; if showScores then sub=((index==best) and "★ Recommended  •  " or "")..((CursorQuestChoicesDB.rewardMode=="value") and MoneyText(scores[index]) or ("Score "..string.format("%.1f",scores[index]))) end
        if count and count>1 then sub=sub.."  •  x"..count end
        AddEntry{text=name,subtext=sub,icon=texture or "Interface\\Icons\\INV_Misc_QuestionMark",color={r,g,b},itemIndex=index,onClick=function() GetQuestReward(index); panel:Hide() end}
    end
    ShowPanel("Choose Your Reward","reward","Interface\\Icons\\INV_Misc_Gift_01")
end

local function ChooseBestReward()
    local num=GetNumQuestChoices() or 0; if num<=0 then GetQuestReward(0); return true end
    local best,bestScore,allReady=1,-1,true
    for i=1,num do local score,ready=RewardScore(i,CursorQuestChoicesDB.rewardMode); if not ready then allReady=false end; if (score or 0)>bestScore then bestScore=score or 0; best=i end end
    if allReady then GetQuestReward(best); return true end
    return false
end

-- Auto quest flow ----------------------------------------------------------
-- Some 3.3.5/private-server clients do not reliably fire GOSSIP_SHOW again
-- after accepting or turning in one quest. Keep a small event-driven retry
-- state so multi-quest NPCs continue without spamming selection functions.
autoFlow = { pending=false, delay=0, elapsed=0, attempts=0, lock=0 }
local legacyConflictCheck = 0

local function ScheduleAutoResume(reason, delay)
    if not CursorQuestChoicesDB or Paused() then return end
    autoFlow.pending=true
    autoFlow.delay=delay or 0.12
    autoFlow.elapsed=0
    autoFlow.attempts=0
    Debug("Auto resume scheduled:", reason or "unknown")
end

local function LockAutoAction()
    autoFlow.lock=0.35
end

local function SelectNextGossipAutoAction()
    local activeCount=GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
    if activeCount>0 then
        local data={GetGossipActiveQuests()}; local stride=math.floor(#data/activeCount)
        if stride>=4 then for i=1,activeCount do local o=(i-1)*stride; if FindBoolean(data,o+1,o+stride,o+4) then Debug("Selecting completed gossip quest",i); SelectGossipActiveQuest(i); LockAutoAction(); return true end end end
    end
    local availableCount=GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
    if availableCount>0 then
        local data={GetGossipAvailableQuests()}; local stride=math.floor(#data/availableCount)
        if stride>=1 then
            for i=1,availableCount do
                local o=(i-1)*stride
                local first,last=o+1,o+stride
                local title=FindString(data,first,last)
                local trivial=FindBoolean(data,first,last,o+3)
                if RecordContainsHardBlockedQuest(data,first,last) then
                    Debug("Blocked gossip quest before selection",i,title or "Call to Arms: Battleground")
                elseif not (CursorQuestChoicesDB.skipTrivial and trivial) and not TitleBlocked(title) then
                    Debug("Selecting available gossip quest",i,title or "?")
                    SelectGossipAvailableQuest(i)
                    LockAutoAction()
                    return true
                end
            end
        end
    end
    return false
end

local function SelectNextGreetingAutoAction()
    if GetNumActiveQuests and GetActiveTitle then
        for i=1,GetNumActiveQuests() do local vals={GetActiveTitle(i)}; if FindBoolean(vals,1,#vals,2) then SelectActiveQuest(i); LockAutoAction(); return true end end
    end
    if GetNumAvailableQuests and GetAvailableTitle then
        for i=1,GetNumAvailableQuests() do
            local vals={GetAvailableTitle(i)}
            local title=FindString(vals,1,#vals)
            local trivial=IsAvailableQuestTrivial and IsAvailableQuestTrivial(i) or false
            if RecordContainsHardBlockedQuest(vals,1,#vals) then
                Debug("Blocked greeting quest before selection",i,title or "Call to Arms: Battleground")
            elseif not (CursorQuestChoicesDB.skipTrivial and trivial) and not TitleBlocked(title) then
                SelectAvailableQuest(i)
                LockAutoAction()
                return true
            end
        end
    end
    return false
end

local function TryResumeAutoFlow()
    if Paused() then autoFlow.pending=false; return false end
    if autoFlow.lock>0 then return false end
    -- QuestFrame itself can remain shown while the gossip list is active on 3.3.5.
    -- Only block while an actual quest detail/progress/reward panel is visible.
    if (QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown())
        or (QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown())
        or (QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown()) then return false end

    local gossipTotal=(GetNumGossipOptions and GetNumGossipOptions() or 0)
        +(GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0)
        +(GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0)
    if gossipTotal>0 and SelectNextGossipAutoAction() then
        panel:Hide(); return true
    end

    local greetingTotal=(GetNumAvailableQuests and GetNumAvailableQuests() or 0)
        +(GetNumActiveQuests and GetNumActiveQuests() or 0)
    if greetingTotal>0 and SelectNextGreetingAutoAction() then
        panel:Hide(); return true
    end
    return false
end

-- Options -----------------------------------------------------------------
local MODES={{"manual","Manual: choose at cursor"},{"value","Auto: highest vendor value"},{"stats","Stats-based"}}
local FOCUS={{"AUTO","Auto class weights"},{"STR","Strength"},{"AGI","Agility"},{"INT","Intellect"},{"STA","Stamina"},{"SPI","Spirit"},{"AP","Attack Power"},{"SP","Spell Power"},{"HIT","Hit"},{"CRIT","Crit"},{"HASTE","Haste"},{"EXP","Expertise"}}
local function BuildOptions()
    local p=CreateFrame("Frame","CQCOptionsPanel",UIParent); p.name="Cursor Quest Choices"
    local title=p:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-16); title:SetText("Cursor Quest Choices")
    local sub=p:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-6); sub:SetText("Cursor-based NPC choices, quest automation, and reward selection. Hold Shift to pause automation.")
    local function Check(name,label,y,key)
        local c=CreateFrame("CheckButton",name,p,"InterfaceOptionsCheckButtonTemplate"); c:SetPoint("TOPLEFT",16,y); _G[name.."Text"]:SetText(label); c:SetScript("OnClick",function(self) CursorQuestChoicesDB[key]=self:GetChecked() and true or false end); return c
    end
    local enabled=Check("CQCEnabledCB","Enable cursor panels",-72,"enabled")
    local auto=Check("CQCAutoCB","Enable Auto Quest Master",-102,"autoQuestEnabled")
    local trivial=Check("CQCSkipTrivialCB","Skip trivial (grey) quests",-132,"skipTrivial")
    local moveMerchant=Check("CQCMoveMerchantCB","Move the real merchant window beside the cursor",-162,"moveMerchantFrame")
    local compactMerchant=Check("CQCCompactMerchantCB","Also show the compact cursor store list",-192,"showMerchantInventory")
    local modeLabel=p:CreateFontString(nil,"ARTWORK","GameFontNormal"); modeLabel:SetPoint("TOPLEFT",20,-238); modeLabel:SetText("Reward mode")
    local dd=CreateFrame("Frame","CQCRewardModeDrop",p,"UIDropDownMenuTemplate"); dd:SetPoint("TOPLEFT",4,-253)
    UIDropDownMenu_Initialize(dd,function(_,level) for _,e in ipairs(MODES) do local info=UIDropDownMenu_CreateInfo(); info.text=e[2]; info.value=e[1]; info.checked=CursorQuestChoicesDB.rewardMode==e[1]; info.func=function() CursorQuestChoicesDB.rewardMode=e[1]; UIDropDownMenu_SetSelectedValue(dd,e[1]); UIDropDownMenu_SetText(dd,e[2]) end; UIDropDownMenu_AddButton(info,level) end end)
    local focusLabel=p:CreateFontString(nil,"ARTWORK","GameFontNormal"); focusLabel:SetPoint("TOPLEFT",20,-308); focusLabel:SetText("Stats focus")
    local fd=CreateFrame("Frame","CQCStatsFocusDrop",p,"UIDropDownMenuTemplate"); fd:SetPoint("TOPLEFT",4,-323)
    UIDropDownMenu_Initialize(fd,function(_,level) for _,e in ipairs(FOCUS) do local info=UIDropDownMenu_CreateInfo(); info.text=e[2]; info.value=e[1]; info.checked=CursorQuestChoicesDB.statFocus==e[1]; info.func=function() CursorQuestChoicesDB.statFocus=e[1]; UIDropDownMenu_SetSelectedValue(fd,e[1]); UIDropDownMenu_SetText(fd,e[2]) end; UIDropDownMenu_AddButton(info,level) end end)
    local pick=Check("CQCStatsPickCB","Stats mode: show scores and let me pick",-385,"statsPickProxy")
    pick:SetScript("OnClick",function(self) CursorQuestChoicesDB.statsBehavior=self:GetChecked() and "pick" or "auto" end)
    local hint=p:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); hint:SetPoint("TOPLEFT",20,-430); hint:SetText("Blocked words: commission  •  Use /cqc block add <word> to add more.")
    p.refresh=function()
                enabled:SetChecked(CursorQuestChoicesDB.enabled); auto:SetChecked(CursorQuestChoicesDB.autoQuestEnabled); trivial:SetChecked(CursorQuestChoicesDB.skipTrivial); moveMerchant:SetChecked(CursorQuestChoicesDB.moveMerchantFrame); compactMerchant:SetChecked(CursorQuestChoicesDB.showMerchantInventory); pick:SetChecked(CursorQuestChoicesDB.statsBehavior=="pick")
        for _,e in ipairs(MODES) do if e[1]==CursorQuestChoicesDB.rewardMode then UIDropDownMenu_SetSelectedValue(dd,e[1]); UIDropDownMenu_SetText(dd,e[2]) end end
        for _,e in ipairs(FOCUS) do if e[1]==CursorQuestChoicesDB.statFocus then UIDropDownMenu_SetSelectedValue(fd,e[1]); UIDropDownMenu_SetText(fd,e[2]) end end
    end
    p.default=function() CursorQuestChoicesDB=CopyDefaults(defaults,{}) end
    InterfaceOptions_AddCategory(p); CQC.options=p
end
local function OpenOptions() InterfaceOptionsFrame_OpenToCategory("Cursor Quest Choices"); InterfaceOptionsFrame_OpenToCategory("Cursor Quest Choices") end

local function RestoreGossip()
    if GossipFrame and UnitExists("npc") then local n=(GetNumGossipOptions and GetNumGossipOptions() or 0)+(GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0)+(GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0); if n>0 then GossipFrame:Show() end end
end

local function Help()
    Print("/cqc on|off • /cqc options • /cqc scale 0.8-1.5 • /cqc rows 5-15 • /cqc width 320-520")
    Print("/cqc auto on|off • /cqc mode manual|value|stats • /cqc stats auto|pick • /cqc focus <AUTO|STR|...>")
    Print("/cqc hideblizzard • /cqc block add|remove <word> • /cqc reset")
end
SLASH_CURSORQUESTCHOICES1="/cqc"; SLASH_CURSORQUESTCHOICES2="/aq"; SLASH_CURSORQUESTCHOICES3="/aqm"
SlashCmdList.CURSORQUESTCHOICES=function(msg)
    msg=(msg or ""):lower():gsub("^%s+",""):gsub("%s+$",""); local cmd,val=msg:match("^(%S+)%s*(.-)$")
    if cmd=="on" then CursorQuestChoicesDB.enabled=true; Print("enabled")
    elseif cmd=="off" then CursorQuestChoicesDB.enabled=false; panel:Hide(); RestoreGossip(); Print("disabled")
    elseif cmd=="options" or cmd=="opts" then OpenOptions()
    elseif cmd=="auto" and (val=="on" or val=="off") then CursorQuestChoicesDB.autoQuestEnabled=val=="on"; Print("Auto Quest "..val)
    elseif cmd=="mode" and (val=="manual" or val=="value" or val=="stats") then CursorQuestChoicesDB.rewardMode=val; Print("reward mode: "..val)
    elseif cmd=="stats" and (val=="auto" or val=="pick") then CursorQuestChoicesDB.statsBehavior=val; Print("stats behavior: "..val)
    elseif cmd=="focus" then val=val:upper(); if val=="AUTO" or KEY_TO_TOKEN[val] then CursorQuestChoicesDB.statFocus=val; Print("stats focus: "..val) else Print("unknown focus") end
    elseif cmd=="scale" then local n=tonumber(val); if n and n>=.8 and n<=1.5 then CursorQuestChoicesDB.scale=n; panel:SetScale(n); Print("scale: "..n) else Print("use 0.8-1.5") end
    elseif cmd=="rows" then local n=tonumber(val); if n and n>=5 and n<=15 and n==math.floor(n) then CursorQuestChoicesDB.maxVisibleRows=n; Print("rows: "..n) else Print("use 5-15") end
    elseif cmd=="width" then local n=tonumber(val); if n and n>=320 and n<=520 then CursorQuestChoicesDB.panelWidth=math.floor(n); panel:SetWidth(n); Print("width: "..math.floor(n)) else Print("use 320-520") end
    elseif cmd=="hideblizzard" then CursorQuestChoicesDB.hideBlizzardGossip=not CursorQuestChoicesDB.hideBlizzardGossip; if not CursorQuestChoicesDB.hideBlizzardGossip then RestoreGossip() end; Print("Blizzard gossip "..(CursorQuestChoicesDB.hideBlizzardGossip and "hidden" or "shown"))
    elseif cmd=="block" then local action,word=val:match("^(add|remove)%s+(.+)$"); if action and word~="" then if action=="add" then table.insert(CursorQuestChoicesDB.blockedWords,word); Print("blocked: "..word) else for i=#CursorQuestChoicesDB.blockedWords,1,-1 do if CursorQuestChoicesDB.blockedWords[i]:lower()==word:lower() then table.remove(CursorQuestChoicesDB.blockedWords,i) end end; Print("unblocked: "..word) end else Print("use /cqc block add|remove <word>") end
    elseif cmd=="reset" then CursorQuestChoicesDB=CopyDefaults(defaults,{}); panel:SetScale(1); panel:SetWidth(400); RestoreGossip(); Print("settings reset")
    else Help() end
end

-- Events ------------------------------------------------------------------
CQC:RegisterEvent("ADDON_LOADED"); CQC:RegisterEvent("PLAYER_LOGIN"); CQC:RegisterEvent("GOSSIP_SHOW"); CQC:RegisterEvent("GOSSIP_CLOSED"); CQC:RegisterEvent("MERCHANT_SHOW"); CQC:RegisterEvent("MERCHANT_UPDATE"); CQC:RegisterEvent("MERCHANT_CLOSED"); CQC:RegisterEvent("QUEST_GREETING"); CQC:RegisterEvent("QUEST_DETAIL"); CQC:RegisterEvent("QUEST_PROGRESS"); CQC:RegisterEvent("QUEST_COMPLETE"); CQC:RegisterEvent("QUEST_ACCEPT_CONFIRM"); CQC:RegisterEvent("QUEST_FINISHED"); CQC:RegisterEvent("PLAYER_REGEN_DISABLED"); CQC:RegisterEvent("PLAYER_TARGET_CHANGED")
CQC:SetScript("OnUpdate",function(_,elapsed)
    if blockedQuestUISuppress>0 then
        blockedQuestUISuppress=math.max(0,blockedQuestUISuppress-elapsed)
        HideBlockedQuestPanels()
    end
    if merchantRepositionUntil>0 then
        local now=GetTime and GetTime() or 0
        if now<=merchantRepositionUntil and MerchantFrame and MerchantFrame:IsShown() then
            PositionMerchantFrameAtAnchor()
        else
            merchantRepositionUntil=0
        end
    end
    legacyConflictCheck=legacyConflictCheck-elapsed
    if legacyConflictCheck<=0 then
        legacyConflictCheck=2.0
        if _G.AQM_Frame or type(AQMDB)=="table" then NeutralizeLegacyAutoQuest("periodic runtime verification") end
    end
    exclusionScanDelay=math.max(0,(exclusionScanDelay or 0)-elapsed)
    if gossipRefresh.active then
        gossipRefresh.elapsed=gossipRefresh.elapsed+elapsed
        gossipRefresh.delay=gossipRefresh.delay-elapsed
        if gossipRefresh.delay<=0 then
            gossipRefresh.attempts=gossipRefresh.attempts+1
            if not GossipContextAvailable() then
                CancelGossipRefresh()
            else
                local stillWaiting=BuildGossipChoices(true)
                if not stillWaiting or gossipRefresh.elapsed>=1.0 or gossipRefresh.attempts>=6 then
                    CancelGossipRefresh()
                else
                    gossipRefresh.delay=0.12
                end
            end
        end
    end
    if autoFlow.lock>0 then autoFlow.lock=math.max(0,autoFlow.lock-elapsed) end
    if autoFlow.pending then
        autoFlow.elapsed=autoFlow.elapsed+elapsed
        autoFlow.delay=autoFlow.delay-elapsed
        if autoFlow.delay<=0 then
            autoFlow.attempts=autoFlow.attempts+1
            if TryResumeAutoFlow() then
                -- The selected quest will transition through detail/progress and
                -- schedule the next resume when that action finishes.
                autoFlow.pending=false
            elseif autoFlow.elapsed>=2.5 or autoFlow.attempts>=12 then
                Debug("Auto resume ended: no additional eligible quest action")
                autoFlow.pending=false
            else
                autoFlow.delay=0.20
            end
        end
    end
    if pendingReward then pendingReward.elapsed=pendingReward.elapsed+elapsed; pendingReward.retry=pendingReward.retry-elapsed; if pendingReward.retry<=0 then pendingReward.retry=.15; if ChooseBestReward() then pendingReward=nil elseif pendingReward.elapsed>=1.5 then Debug("Reward cache timeout; showing picker"); pendingReward=nil; BuildRewardPanel(true) end end end
end)
CQC:SetScript("OnEvent",function(self,event,arg1)
    if event=="GOSSIP_CLOSED" or event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE" or event=="QUEST_FINISHED" or event=="PLAYER_TARGET_CHANGED" then
        CancelGossipRefresh()
    end
    if event=="ADDON_LOADED" then
        if arg1==ADDON_NAME then
            CursorQuestChoicesDB=CopyDefaults(defaults,CursorQuestChoicesDB or {})
            -- Migrate legacy settings before disabling the old runtime.
            if type(AQMDB)=="table" and not CursorQuestChoicesDB._aqmMigrated then
                for _,k in ipairs({"enabled","rewardMode","statFocus","statsBehavior","debug"}) do
                    if AQMDB[k]~=nil then
                        if k=="enabled" then CursorQuestChoicesDB.autoQuestEnabled=AQMDB[k] else CursorQuestChoicesDB[k]=AQMDB[k] end
                    end
                end
                CursorQuestChoicesDB._aqmMigrated=true
            end
            NeutralizeLegacyAutoQuest("Cursor Quest loaded")
            InstallQuestAPIGuard()
            InstallBlockedQuestUIHook()
            if CursorQuestChoicesDB.merchantLayoutMigratedV222 == nil then
                CursorQuestChoicesDB.moveMerchantFrame = true
                CursorQuestChoicesDB.showMerchantInventory = false
                CursorQuestChoicesDB.merchantLayoutMigratedV222 = true
            end
            panel:SetScale(CursorQuestChoicesDB.scale); panel:SetWidth(CursorQuestChoicesDB.panelWidth); BuildOptions(); InstallMerchantFrameHook(); Print("v"..VERSION.." loaded. /cqc options")
        else
            -- Catch the old addon regardless of load order.
            local loadedName=tostring(arg1 or ""):lower()
            if loadedName:find("autoquestmaster",1,true) then NeutralizeLegacyAutoQuest("legacy addon loaded after Cursor Quest") end
        end
        return
    elseif event=="PLAYER_LOGIN" then
        InstallQuestAPIGuard()
        InstallBlockedQuestUIHook()
        NeutralizeLegacyAutoQuest("PLAYER_LOGIN verification")
        return
    elseif event=="GOSSIP_SHOW" then
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then panel:Hide(); return end
        if autoFlow.lock<=0 and not Paused() and SelectNextGossipAutoAction() then panel:Hide(); return end
        -- Visual gossip data is valid even when this private server does not
        -- preserve the npc unit token. Board interactions were excluded above.
        local needsRefresh=BuildGossipChoices(false)
        if needsRefresh then ScheduleGossipRefresh(0.06) else CancelGossipRefresh() end
    elseif event=="MERCHANT_SHOW" then
        CancelGossipRefresh()
        InstallMerchantFrameHook()
        BeginMerchantReposition()
        if CursorQuestChoicesDB.showMerchantInventory then BuildMerchantPanel(false)
        elseif panelMode=="merchant" then panel:Hide() end
    elseif event=="MERCHANT_UPDATE" then
        if MerchantFrame and MerchantFrame:IsShown() then
            if CursorQuestChoicesDB.showMerchantInventory then BuildMerchantPanel(true) end
            PositionMerchantFrameAtAnchor()
        end
    elseif event=="MERCHANT_CLOSED" then
        merchantAnchorX, merchantAnchorY = nil, nil
        merchantRepositionUntil = 0
        if panelMode=="merchant" then panel:Hide() end
    elseif event=="QUEST_GREETING" then
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then panel:Hide(); return end
        if autoFlow.lock<=0 and not Paused() and SelectNextGreetingAutoAction() then panel:Hide(); return end
        BuildGreetingChoices()
    elseif event=="QUEST_DETAIL" then
        panel:Hide()
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then
            SuppressBlockedQuestUI("Hero's Call Board QUEST_DETAIL")
            return
        end
        local title=GetTitleText and GetTitleText()
        if IsHardBlockedQuestTitle(title) then
            autoFlow.pending=false
            Debug("QUEST_DETAIL hard-blocked by quest title:", title or "?")
            SuppressBlockedQuestUI("QUEST_DETAIL hard block")
            return
        end
        -- A normal quest detail event is sufficient on 3.3.5 private servers.
        -- Do not require an npc unit token or a specific Blizzard panel global;
        -- both are unreliable on custom clients.
        blockedQuestUISuppress=0
        if not Paused() then
            if not TitleBlocked(title) then
                AcceptQuest(); LockAutoAction(); ScheduleAutoResume("quest accepted",0.10)
            else
                Debug("Quest auto-accept blocked:", title or "?")
            end
        end
    elseif event=="QUEST_PROGRESS" then
        panel:Hide()
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then return end
        if not Paused() then if IsQuestCompletable() then CompleteQuest(); LockAutoAction() elseif QuestFrame and QuestFrame:IsShown() then CloseQuest(); ScheduleAutoResume("incomplete quest closed",0.15) end end
    elseif event=="QUEST_COMPLETE" then
        panel:Hide()
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then pendingReward=nil; return end
        local n=GetNumQuestChoices() or 0
        if Paused() then if CursorQuestChoicesDB.enabled and n>1 then BuildRewardPanel(false) end; return end
        if n<=1 then GetQuestReward(n==0 and 0 or 1)
        elseif CursorQuestChoicesDB.rewardMode=="manual" or (CursorQuestChoicesDB.rewardMode=="stats" and CursorQuestChoicesDB.statsBehavior=="pick") then BuildRewardPanel(CursorQuestChoicesDB.rewardMode~="manual")
        elseif not ChooseBestReward() then pendingReward={elapsed=0,retry=0} end
    elseif event=="QUEST_ACCEPT_CONFIRM" then
        if BoardAutomationBlocked and BoardAutomationBlocked(true) then return end
        if not Paused() then ConfirmAcceptQuest(); StaticPopup_Hide("QUEST_ACCEPT_CONFIRM"); LockAutoAction(); ScheduleAutoResume("shared quest confirmed",0.15) end
    elseif event=="QUEST_FINISHED" then
        panel:Hide(); pendingReward=nil
        if not (BoardAutomationBlocked and BoardAutomationBlocked(true)) then ScheduleAutoResume("quest finished",0.12) end
    elseif event=="GOSSIP_CLOSED" or event=="PLAYER_REGEN_DISABLED" then
        if not (event=="GOSSIP_CLOSED" and MerchantFrame and MerchantFrame:IsShown() and panelMode=="merchant") then panel:Hide() end
        pendingReward=nil; if event=="PLAYER_REGEN_DISABLED" then autoFlow.pending=false end
    elseif event=="PLAYER_TARGET_CHANGED" and not UnitExists("npc") then
        if not (MerchantFrame and MerchantFrame:IsShown() and panelMode=="merchant") then panel:Hide() end
    end
end)
