local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList

GUnit.Comm = {}
local Comm = GUnit.Comm

local PREFIX = "GUNIT"
local PAIR_SEP = "\031"
local KV_SEP = "\029"

local PROTOCOL_VERSION = "1"
local MAX_PAYLOAD_BYTES = 245

local WIRE_KEY = {
    action = "a",    version = "v",
    name = "n",      submitter = "s",
    guildName = "g", updatedAt = "ua",  createdAt = "ca",

    reason = "r",       reasonUpdatedAt = "ru",
    reasonClear = "rx", bountyAmount = "ba",
    hitMode = "hm",     hitStatus = "hs",
    bountyMode = "bm",  bountyStatus = "bs",
    validated = "vl",   classToken = "ct",
    race = "rc",        raceId = "ri",
    sex = "sx",         faction = "f",
    killCount = "kc",

    lastSeenMapId = "lm",   lastSeenZone = "lz",
    lastSeenSubzone = "ls", lastSeenX = "lx",
    lastSeenY = "ly",       lastSeenApproximate = "la",
    lastSeenConfidenceYards = "lc", lastSeenAt = "lt",
    lastSeenSource = "lo",

    killer = "kl",  zone = "kz",    ts = "kt",
    mapId = "km",   subzone = "ks",
    approximate = "ka", confidenceYards = "ky",
    source = "kr",

    requestId = "rq", responder = "rp",
}

local WIRE_KEY_REV = {}
for full, short in pairs(WIRE_KEY) do
    WIRE_KEY_REV[short] = full
end

local OMIT_IF_EMPTY = {
    lastSeenMapId = true,   lastSeenZone = true,
    lastSeenSubzone = true, lastSeenX = true,
    lastSeenY = true,
    lastSeenConfidenceYards = true, lastSeenAt = true,
    lastSeenSource = true,
    classToken = true, race = true, raceId = true,
    sex = true, faction = true,
}

Comm.stats = {
    sent = 0,
    dropped_oversize = 0,
    received = {},
}

-- Raw transport

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

-- Encoding

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

function Comm:CompactEncode(map)
    map.version = PROTOCOL_VERSION
    local parts = {}
    for key, value in pairs(map) do
        local strVal = tostring(value or "")
        if not (OMIT_IF_EMPTY[key] and (strVal == "" or strVal == "0")) then
            local wireKey = WIRE_KEY[key] or key
            table.insert(parts, Utils.Escape(wireKey) .. KV_SEP .. Utils.Escape(strVal))
        end
    end
    return table.concat(parts, PAIR_SEP)
end

function Comm:CompactDecode(payload)
    local raw = self:DecodeMap(payload)
    local out = {}
    for key, value in pairs(raw) do
        local fullKey = WIRE_KEY_REV[key] or key
        out[fullKey] = value
    end
    return out
end

-- Preflight send helpers

function Comm:CheckedSend(channel, payload, label)
    local tag = label or "?"
    if #payload <= MAX_PAYLOAD_BYTES then
        self:Send(channel, payload)
        self.stats.sent = self.stats.sent + 1
        GUnit:Debug("SENT " .. tag .. " (" .. #payload .. "b)")
        return true
    end

    self.stats.dropped_oversize = self.stats.dropped_oversize + 1
    GUnit:Debug("DROPPED " .. tag .. " (" .. #payload .. "b) — oversize")
    GUnit:Print("Oversize message dropped: " .. tag .. " (" .. #payload .. "b)")
    return false
end

-- Action payload helper (used for small sync control messages)

function Comm:ActionPayload(action, map)
    map = map or {}
    map.action = action
    map.version = PROTOCOL_VERSION
    return self:EncodeMap(map)
end

-- Field group builders

local function BuildCoreMap(target, action)
    return {
        action = action or "UPSERT",
        name = target.name,
        submitter = target.submitter,
        guildName = target.guildName or Utils.GuildName() or "",
        bountyAmount = target.bountyAmount or 0,
        hitMode = target.hitMode or "one_time",
        hitStatus = target.hitStatus or "active",
        bountyMode = target.bountyMode or "none",
        bountyStatus = target.bountyStatus or "open",
        validated = target.validated and "1" or "0",
        killCount = target.killCount or 0,
        createdAt = target.createdAt or Utils.Now(),
        updatedAt = target.updatedAt or Utils.Now(),
    }
end

local function HasMeta(target)
    return (target.classToken and target.classToken ~= "")
        or (target.race and target.race ~= "")
        or (target.faction and target.faction ~= "")
end

local function BuildMetaMap(target, action)
    return {
        action = action or "UPSERT",
        name = target.name,
        classToken = target.classToken or "",
        race = target.race or "",
        raceId = target.raceId or "",
        sex = target.sex or "",
        faction = target.faction or "",
        updatedAt = target.updatedAt or Utils.Now(),
    }
end

local function HasLocation(target)
    return target.lastKnownLocation
        and target.lastKnownLocation.zone
        and target.lastKnownLocation.zone ~= ""
end

local function BuildLocationMap(target, action)
    local loc = target.lastKnownLocation
    if not loc then return nil end
    return {
        action = action or "UPSERT",
        name = target.name,
        lastSeenMapId = loc.mapId or "",
        lastSeenZone = loc.zone or "",
        lastSeenSubzone = loc.subzone or "",
        lastSeenX = loc.x or "",
        lastSeenY = loc.y or "",
        lastSeenApproximate = loc.approximate and "1" or "0",
        lastSeenConfidenceYards = loc.confidenceYards or "",
        lastSeenAt = loc.seenAt or "",
        lastSeenSource = loc.source or "",
        updatedAt = target.updatedAt or Utils.Now(),
    }
end

local function BuildReasonMap(target)
    local reason = target.reason or ""
    local reasonTs = tonumber(target.reasonUpdatedAt) or target.updatedAt or Utils.Now()
    local isExplicitClear = (reason == "") and (tonumber(target.reasonClearedAt) == reasonTs)
    return {
        action = "REASON",
        name = target.name,
        submitter = target.submitter,
        guildName = target.guildName or Utils.GuildName() or "",
        reason = reason,
        reasonUpdatedAt = reasonTs,
        reasonClear = isExplicitClear and "1" or "0",
        updatedAt = target.updatedAt or Utils.Now(),
    }
end

-- Broadcast functions

function Comm:BroadcastUpsert(target)
    if not target or not Utils.InGuild() then return end
    local label = "UPSERT " .. target.name

    local core = self:CompactEncode(BuildCoreMap(target))
    self:CheckedSend("GUILD", core, label .. " core")

    if HasMeta(target) then
        local meta = self:CompactEncode(BuildMetaMap(target))
        self:CheckedSend("GUILD", meta, label .. " meta")
    end

    if HasLocation(target) then
        local loc = BuildLocationMap(target)
        if loc then
            local locPayload = self:CompactEncode(loc)
            self:CheckedSend("GUILD", locPayload, label .. " location")
        end
    end
end

function Comm:BroadcastReason(target)
    if not target or not Utils.InGuild() then return end
    local payload = self:CompactEncode(BuildReasonMap(target))
    self:CheckedSend("GUILD", payload, "REASON " .. target.name)
end

function Comm:BroadcastDelete(targetName)
    if not Utils.InGuild() then return end
    local map = {
        action = "DELETE",
        name = targetName,
        updatedAt = Utils.Now(),
    }
    local payload = self:CompactEncode(map)
    self:CheckedSend("GUILD", payload, "DELETE " .. targetName)
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

    local map = {
        action = "KILL",
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
    }
    local payload = self:CompactEncode(map)
    self:CheckedSend("GUILD", payload, "KILL " .. targetName)
end

-- Collect all field group maps for a target (for sync)

function Comm:CollectTargetMaps(target, action)
    local maps = {}
    table.insert(maps, BuildCoreMap(target, action))
    if HasMeta(target) then
        table.insert(maps, BuildMetaMap(target, action))
    end
    if HasLocation(target) then
        local loc = BuildLocationMap(target, action)
        if loc then table.insert(maps, loc) end
    end
    return maps
end

-- Receive handlers

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

local function HandleReason(data)
    if not data.name then return end
    GUnit:Debug("RX REASON for " .. data.name .. " (" .. string.len(data.reason or "") .. " chars)")
    HitList:EnsureAndSetReason(
        data.name,
        data.submitter,
        data.guildName,
        data.reason,
        tonumber(data.updatedAt),
        tonumber(data.reasonUpdatedAt),
        data.reasonClear
    )
    GUnit:NotifyDataChanged()
end

local function OnAddonMessage(_, prefix, payload, _, sender)
    if prefix ~= PREFIX then return end
    if Utils.NormalizeName(sender) == Utils.NormalizeName(Utils.PlayerName()) then return end
    if GUnit.RegisterKnownAddonUser then
        GUnit:RegisterKnownAddonUser(sender, Utils.GuildName())
    end

    local data = Comm:CompactDecode(payload)
    local action = data.action

    GUnit:Debug("RECV " .. (action or "nil") .. " from " .. sender .. " (" .. #payload .. "b)" .. (data.name and (" [" .. data.name .. "]") or ""))

    local stats = Comm.stats.received
    stats[action or "unknown"] = (stats[action or "unknown"] or 0) + 1

    if action == "UPSERT" then
        HandleUpsert(data)
    elseif action == "DELETE" then
        HandleDelete(data)
    elseif action == "KILL" then
        HandleKill(data)
    elseif action == "REASON" then
        HandleReason(data)
    elseif GUnit.Sync and GUnit.Sync.HandleMessage then
        GUnit.Sync:HandleMessage(action, data, sender)
    end
end

function Comm:Init()
    RegisterPrefix()
    GUnit:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
end
