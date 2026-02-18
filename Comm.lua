local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList

GUnit.Comm = {}
local Comm = GUnit.Comm

local PREFIX = "GUNIT"
local PAIR_SEP = "\031"
local KV_SEP = "\029"

local function RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end

function Comm:Send(channel, payload)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, channel)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, payload, channel)
    end
end

function Comm:EncodeMap(map)
    local parts = {}
    for key, value in pairs(map) do
        table.insert(parts, Utils.Escape(key) .. KV_SEP .. Utils.Escape(value))
    end
    return table.concat(parts, PAIR_SEP)
end

function Comm:DecodeMap(payload)
    local out = {}
    for part in string.gmatch(payload or "", "([^" .. PAIR_SEP .. "]+)") do
        local key, value = string.match(part, "^(.-)" .. KV_SEP .. "(.*)$")
        if key then
            out[Utils.Unescape(key)] = Utils.Unescape(value or "")
        end
    end
    return out
end

function Comm:ActionPayload(action, map)
    map = map or {}
    map.action = action
    return self:EncodeMap(map)
end

function Comm:BroadcastUpsert(target)
    if not target or not Utils.InGuild() then return end
    local payload = self:ActionPayload("UPSERT", {
        name = target.name,
        submitter = target.submitter,
        guildName = target.guildName or Utils.GuildName() or "",
        reason = target.reason or "",
        bountyAmount = target.bountyAmount or 0,
        hitMode = target.hitMode or "one_time",
        hitStatus = target.hitStatus or "active",
        bountyMode = target.bountyMode or "none",
        bountyStatus = target.bountyStatus or "open",
        validated = target.validated and "1" or "0",
        classToken = target.classToken or "",
        race = target.race or "",
        raceId = target.raceId or "",
        sex = target.sex or "",
        faction = target.faction or "",
        lastSeenMapId = target.lastKnownLocation and target.lastKnownLocation.mapId or "",
        lastSeenZone = target.lastKnownLocation and target.lastKnownLocation.zone or "",
        lastSeenSubzone = target.lastKnownLocation and target.lastKnownLocation.subzone or "",
        lastSeenX = target.lastKnownLocation and target.lastKnownLocation.x or "",
        lastSeenY = target.lastKnownLocation and target.lastKnownLocation.y or "",
        lastSeenApproximate = (target.lastKnownLocation and target.lastKnownLocation.approximate) and "1" or "0",
        lastSeenConfidenceYards = target.lastKnownLocation and target.lastKnownLocation.confidenceYards or "",
        lastSeenAt = target.lastKnownLocation and target.lastKnownLocation.seenAt or "",
        lastSeenSource = target.lastKnownLocation and target.lastKnownLocation.source or "",
        createdAt = target.createdAt or Utils.Now(),
        updatedAt = target.updatedAt or Utils.Now(),
        killCount = target.killCount or 0,
    })
    self:Send("GUILD", payload)
end

function Comm:BroadcastDelete(targetName)
    if not Utils.InGuild() then return end
    local payload = self:ActionPayload("DELETE", {
        name = targetName,
        updatedAt = Utils.Now(),
    })
    self:Send("GUILD", payload)
end

function Comm:BroadcastKill(targetName, killerName, location, ts)
    if not Utils.InGuild() then return end
    local zoneName = nil
    local mapId = ""
    local subzone = ""
    local x = ""
    local y = ""
    local approximate = "0"
    local confidenceYards = ""
    local source = ""

    if type(location) == "table" then
        zoneName = location.zone
        mapId = location.mapId or ""
        subzone = location.subzone or ""
        x = location.x or ""
        y = location.y or ""
        approximate = location.approximate and "1" or "0"
        confidenceYards = location.confidenceYards or ""
        source = location.source or ""
    else
        zoneName = location
    end

    local payload = self:ActionPayload("KILL", {
        name = targetName,
        killer = killerName,
        zone = zoneName or Utils.ZoneName(),
        mapId = mapId,
        subzone = subzone,
        x = x,
        y = y,
        approximate = approximate,
        confidenceYards = confidenceYards,
        source = source,
        ts = ts or Utils.Now(),
    })
    self:Send("GUILD", payload)
end

local function HandleUpsert(data)
    if not data.name then return end
    HitList:UpsertFromComm(data)
    GUnit:NotifyDataChanged()
end

local function HandleDelete(data)
    if not data.name then return end
    HitList:Delete(data.name)
    GUnit:NotifyDataChanged()
end

local function HandleKill(data)
    if not data.name then return end
    local target = HitList:ApplyKill(data.name, data.killer, {
        mapId = data.mapId,
        zone = data.zone,
        subzone = data.subzone,
        x = data.x,
        y = data.y,
        approximate = data.approximate,
        confidenceYards = data.confidenceYards,
        seenAt = tonumber(data.ts),
        source = data.source or "party_kill",
    }, tonumber(data.ts))
    if target then
        GUnit:NotifyDataChanged()
    end
end

local function OnAddonMessage(_, prefix, payload, _, sender)
    if prefix ~= PREFIX then return end
    if Utils.NormalizeName(sender) == Utils.NormalizeName(Utils.PlayerName()) then return end
    if GUnit.RegisterKnownAddonUser then
        GUnit:RegisterKnownAddonUser(sender, Utils.GuildName())
    end
    local data = Comm:DecodeMap(payload)
    local action = data.action
    if action == "UPSERT" then
        HandleUpsert(data)
    elseif action == "DELETE" then
        HandleDelete(data)
    elseif action == "KILL" then
        HandleKill(data)
    elseif GUnit.Sync and GUnit.Sync.HandleMessage then
        GUnit.Sync:HandleMessage(action, data, sender)
    end
end

function Comm:Init()
    RegisterPrefix()
    GUnit:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
end
