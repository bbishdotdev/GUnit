local ADDON_NAME, GUnit = ...

GUnit.VERSION = "0.6.0"
GUnit.PRINT_PREFIX = "|cffff5555[G-Unit]|r "

local DB_DEFAULTS = {
    version = 1,
    targets = {},
    knownAddonUsers = {},
    settings = {
        defaultHitMode = "one_time",
        defaultBountyGold = 0,
        defaultBountyMode = "none",
        showClosedHits = true,
        rememberDrawerState = true,
        drawerOpen = true,
        uiGuildAnnouncements = true,
        partyAnnouncements = true,
        debugMode = false,
    },
}

local eventFrame = CreateFrame("Frame")
local handlersByEvent = {}

local function CopyDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            CopyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

function GUnit:Print(message)
    print(self.PRINT_PREFIX .. tostring(message))
end

function GUnit:Debug(message)
    if not self.db or not self.db.settings or not self.db.settings.debugMode then return end
    print("|cff888888[G-Unit DBG]|r " .. tostring(message))
end

function GUnit:NotifyDataChanged()
    if self.UI and self.UI.Refresh then
        self.UI:Refresh()
    end
end

function GUnit:RegisterKnownAddonUser(name, guildName)
    if not self.db then return end
    local normalized = self.Utils and self.Utils.NormalizeName and self.Utils.NormalizeName(name) or nil
    if not normalized then return end

    self.db.knownAddonUsers = self.db.knownAddonUsers or {}
    local entry = self.db.knownAddonUsers[normalized] or { name = normalized }
    entry.guildName = guildName or (self.Utils and self.Utils.GuildName and self.Utils.GuildName()) or entry.guildName
    entry.lastSeen = self.Utils and self.Utils.Now and self.Utils.Now() or 0
    self.db.knownAddonUsers[normalized] = entry
end

function GUnit:BuildGuildRosterSet()
    local roster = {}
    local numMembers = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            local normalized = self.Utils and self.Utils.NormalizeName and self.Utils.NormalizeName(name) or nil
            if normalized then
                roster[normalized] = true
            end
        end
    end
    return roster, numMembers
end

function GUnit:KnownAddonUserCountForCurrentGuild()
    if not self.db then return 0 end
    local guildName = self.Utils and self.Utils.GuildName and self.Utils.GuildName() or nil
    if not guildName then return 0 end

    local roster, rosterSize = self:BuildGuildRosterSet()
    local users = self.db.knownAddonUsers or {}
    local count = 0
    for key, entry in pairs(users) do
        if entry.guildName == guildName then
            if rosterSize > 0 and not roster[key] then
                users[key] = nil
            else
                count = count + 1
            end
        end
    end
    return count
end

function GUnit:RegisterEvent(eventName, callback)
    if not handlersByEvent[eventName] then
        handlersByEvent[eventName] = {}
        eventFrame:RegisterEvent(eventName)
    end
    table.insert(handlersByEvent[eventName], callback)
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    local handlers = handlersByEvent[eventName]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](eventName, ...)
    end
end)

local function OnPlayerLogin()
    if not GUnitDB then
        GUnitDB = {}
    end

    CopyDefaults(GUnitDB, DB_DEFAULTS)
    GUnit.db = GUnitDB
    -- Normalize legacy/non-boolean values so debug is only enabled when explicitly true.
    GUnit.db.settings.debugMode = (GUnit.db.settings.debugMode == true)
    GUnit:RegisterKnownAddonUser(GUnit.Utils.PlayerName(), GUnit.Utils.GuildName())

    -- Migration: backfill guildName on entries created before guild-scoping
    local guildName = GUnit.Utils.GuildName()
    if guildName and GUnit.db.targets then
        for _, target in pairs(GUnit.db.targets) do
            if not target.guildName then
                target.guildName = guildName
            end
        end
    end

    if GUnit.Comm and GUnit.Comm.Init then
        GUnit.Comm:Init()
    end
    if GUnit.BountyTrade and GUnit.BountyTrade.Init then
        GUnit.BountyTrade:Init()
    end
    if GUnit.Tracking and GUnit.Tracking.Init then
        GUnit.Tracking:Init()
    end
    if GUnit.Tooltip and GUnit.Tooltip.Init then
        GUnit.Tooltip:Init()
    end
    if GUnit.UI and GUnit.UI.Init then
        GUnit.UI:Init()
    end

    if GUnit.Utils.InGuild() and GuildRoster then
        pcall(GuildRoster)
    end

    -- Auto-sync guild data after a short delay (guild roster needs time to load)
    if GUnit.Sync and GUnit.Utils.InGuild() then
        C_Timer.After(3, function()
            GUnit.Sync:RequestSync()
        end)
    end

    GUnit:Print("v" .. GUnit.VERSION .. " loaded. Use /ghit and /g-unit.")
end

GUnit:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)

GUnit:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    if not GUnit.db then return end
    local guildName = GUnit.Utils and GUnit.Utils.GuildName and GUnit.Utils.GuildName()
    if not guildName then return end
    GUnit:RegisterKnownAddonUser(GUnit.Utils.PlayerName(), guildName)
end)
