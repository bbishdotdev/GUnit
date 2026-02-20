local _, GUnit = ...
local Utils = GUnit.Utils

GUnit.HitList = {}
local HitList = GUnit.HitList

local HIT_MODE_ONE_TIME = "one_time"
local HIT_MODE_KOS = "kos"
local HIT_STATUS_ACTIVE = "active"
local HIT_STATUS_COMPLETED = "completed"
local HIT_STATUS_CLOSED = "closed"
local BOUNTY_MODE_NONE = "none"
local BOUNTY_MODE_FIRST = "first_kill"
local BOUNTY_MODE_INFINITE = "infinite"
local BOUNTY_STATUS_OPEN = "open"
local BOUNTY_STATUS_CLAIMED = "claimed"

local RACE_NAME_TO_ID = {
    Human = 1,
    Orc = 2,
    Dwarf = 3,
    NightElf = 4,
    Undead = 5,
    Tauren = 6,
    Gnome = 7,
    Troll = 8,
    BloodElf = 10,
    Draenei = 11,
}

local function NormalizeRaceNameForId(raceName)
    if not raceName or raceName == "" then
        return nil
    end
    local compact = tostring(raceName):gsub("%s+", "")
    return compact
end

local function InferRaceIdFromRaceName(raceName)
    local key = NormalizeRaceNameForId(raceName)
    return key and RACE_NAME_TO_ID[key] or nil
end

local function NormalizeSexForStorage(sexValue)
    local n = tonumber(sexValue)
    if n == nil then
        return 0 -- default male when unknown
    end
    return n
end

local function SafePlayerLocationForUnit(unit)
    if not PlayerLocation or not PlayerLocation.CreateFromUnit then
        return nil
    end
    local ok, location = pcall(PlayerLocation.CreateFromUnit, PlayerLocation, unit)
    if ok then
        return location
    end
    return nil
end

local function CaptureUnitRaceMetadata(unit)
    local location = SafePlayerLocationForUnit(unit)
    local raceId = nil
    local sex = nil

    if location and C_PlayerInfo then
        if C_PlayerInfo.GetRace then
            local okRace, value = pcall(C_PlayerInfo.GetRace, location)
            if okRace then
                raceId = tonumber(value)
            end
        end
        if C_PlayerInfo.GetSex then
            local okSex, value = pcall(C_PlayerInfo.GetSex, location)
            if okSex then
                sex = tonumber(value)
            end
        end
    end

    return raceId, sex
end

local function CloneEntry(entry)
    local out = {}
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

local function NormalizeLocationPayload(location, defaultSource)
    if type(location) ~= "table" then
        return nil
    end

    local zone = location.zone
    if not zone or zone == "" then
        zone = Utils.ZoneName()
    end
    if not zone or zone == "" then
        zone = "Unknown Zone"
    end

    local subzone = location.subzone
    if not subzone or subzone == "" then
        subzone = zone
    end

    local mapId = tonumber(location.mapId)
    local x = tonumber(location.x)
    local y = tonumber(location.y)
    if x and (x < 0 or x > 1) then x = nil end
    if y and (y < 0 or y > 1) then y = nil end

    local seenAt = tonumber(location.seenAt) or Utils.Now()
    local confidenceYards = tonumber(location.confidenceYards)
    local source = location.source
    if not source or source == "" then
        source = defaultSource or "unknown"
    end

    return {
        zone = zone,
        subzone = subzone,
        mapId = mapId,
        x = x,
        y = y,
        seenAt = seenAt,
        source = source,
        approximate = location.approximate == true or location.approximate == "1",
        confidenceYards = confidenceYards,
    }
end

local function HasIncomingLocationPayload(payload)
    if type(payload) ~= "table" then
        return false
    end
    return payload.lastSeenZone ~= nil
        or payload.lastSeenSubzone ~= nil
        or payload.lastSeenMapId ~= nil
        or payload.lastSeenX ~= nil
        or payload.lastSeenY ~= nil
        or payload.lastSeenAt ~= nil
        or payload.lastSeenSource ~= nil
        or payload.lastSeenApproximate ~= nil
        or payload.lastSeenConfidenceYards ~= nil
end

local function EnsureTarget(name, actorName, ts)
    if not GUnit.db.targets[name] then
        GUnit.db.targets[name] = {
            name = name,
            submitter = actorName,
            guildName = Utils.GuildName(),
            reason = "",
            reasonUpdatedAt = nil,
            reasonClearedAt = nil,
            bountyAmount = 0,
            hitMode = HIT_MODE_ONE_TIME,
            hitStatus = HIT_STATUS_ACTIVE,
            bountyMode = BOUNTY_MODE_NONE,
            bountyStatus = BOUNTY_STATUS_OPEN,
            createdAt = ts,
            updatedAt = ts,
            validated = false,
            classToken = nil,
            race = nil,
            raceId = nil,
            sex = nil,
            faction = nil,
            lastKnownLocation = nil,
            killCount = 0,
            kills = {},
            bountyClaims = {},
        }
    end
    return GUnit.db.targets[name]
end

function HitList:EnsureAndSetReason(name, submitter, guildName, reason, ts, reasonUpdatedAt, reasonClear)
    local normalized = Utils.NormalizeName(name)
    if not normalized then return nil end
    local now = ts or Utils.Now()
    local sub = Utils.NormalizeName(submitter) or submitter or "Unknown"
    local target = EnsureTarget(normalized, sub, now)
    if guildName and guildName ~= "" then
        target.guildName = guildName
    end
    local incomingReason = reason or ""
    local incomingReasonTs = tonumber(reasonUpdatedAt) or tonumber(ts) or Utils.Now()
    local currentReasonTs = tonumber(target.reasonUpdatedAt) or 0
    local shouldClear = (reasonClear == true) or (reasonClear == "1")

    if incomingReasonTs < currentReasonTs then
        return target
    end

    if incomingReason ~= "" then
        target.reason = incomingReason
        target.reasonUpdatedAt = incomingReasonTs
        target.reasonClearedAt = nil
    elseif shouldClear then
        target.reason = ""
        target.reasonUpdatedAt = incomingReasonTs
        target.reasonClearedAt = incomingReasonTs
    end

    target.updatedAt = math.max(now, incomingReasonTs)
    return target
end

function HitList:Constants()
    return {
        HIT_MODE_ONE_TIME = HIT_MODE_ONE_TIME,
        HIT_MODE_KOS = HIT_MODE_KOS,
        HIT_STATUS_ACTIVE = HIT_STATUS_ACTIVE,
        HIT_STATUS_COMPLETED = HIT_STATUS_COMPLETED,
        HIT_STATUS_CLOSED = HIT_STATUS_CLOSED,
        BOUNTY_MODE_NONE = BOUNTY_MODE_NONE,
        BOUNTY_MODE_FIRST = BOUNTY_MODE_FIRST,
        BOUNTY_MODE_INFINITE = BOUNTY_MODE_INFINITE,
        BOUNTY_STATUS_OPEN = BOUNTY_STATUS_OPEN,
        BOUNTY_STATUS_CLAIMED = BOUNTY_STATUS_CLAIMED,
    }
end

function HitList:Get(name)
    local normalized = Utils.NormalizeName(name)
    if not normalized then return nil end
    return GUnit.db.targets[normalized]
end

function HitList:GetAll()
    return GUnit.db.targets
end

function HitList:SortedNames()
    local names = {}
    for name in pairs(GUnit.db.targets) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function HitList:SortedNamesForCurrentGuild()
    local guildName = Utils.GuildName()
    local targets = GUnit.db.targets
    local names = {}
    for name, target in pairs(targets) do
        if target.guildName == guildName then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b)
        local ta = targets[a] and targets[a].createdAt or 0
        local tb = targets[b] and targets[b].createdAt or 0
        if ta == tb then return a < b end
        return ta > tb
    end)
    return names
end

function HitList:GetAllForCurrentGuild()
    local guildName = Utils.GuildName()
    local out = {}
    for name, target in pairs(GUnit.db.targets) do
        if target.guildName == guildName then
            out[name] = target
        end
    end
    return out
end

function HitList:CanMutate(target, actorName)
    return target and Utils.IsSubmitter(target, actorName)
end

function HitList:CreateOrTouch(name, actorName, reason, ts)
    local normalized = Utils.NormalizeName(name)
    if not normalized then
        return nil, "Invalid target name."
    end

    local now = ts or Utils.Now()
    local target = EnsureTarget(normalized, actorName, now)
    target.updatedAt = now

    if reason and reason ~= "" and Utils.IsSubmitter(target, actorName) then
        target.reason = reason
    end

    return target
end

function HitList:Delete(name)
    local normalized = Utils.NormalizeName(name)
    if not normalized then return false end
    if not GUnit.db.targets[normalized] then return false end
    GUnit.db.targets[normalized] = nil
    return true
end

function HitList:SetReason(name, reason, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit this hit." end
    local now = Utils.Now()
    target.reason = reason or ""
    target.reasonUpdatedAt = now
    if target.reason == "" then
        target.reasonClearedAt = now
    else
        target.reasonClearedAt = nil
    end
    target.updatedAt = now
    return target
end

function HitList:SetBountyAmount(name, bountyAmount, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit this hit." end
    target.bountyAmount = math.max(0, tonumber(bountyAmount) or 0)
    if target.bountyAmount <= 0 then
        target.bountyMode = BOUNTY_MODE_NONE
        target.bountyStatus = BOUNTY_STATUS_OPEN
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetHitMode(name, mode, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit hit mode." end
    if mode ~= HIT_MODE_ONE_TIME and mode ~= HIT_MODE_KOS then
        return nil, "Invalid hit mode."
    end

    target.hitMode = mode
    if mode == HIT_MODE_KOS and target.hitStatus == HIT_STATUS_COMPLETED then
        target.hitStatus = HIT_STATUS_ACTIVE
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetBountyMode(name, mode, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit bounty mode." end
    if mode ~= BOUNTY_MODE_NONE and mode ~= BOUNTY_MODE_FIRST and mode ~= BOUNTY_MODE_INFINITE then
        return nil, "Invalid bounty mode."
    end

    target.bountyMode = mode
    if mode == BOUNTY_MODE_FIRST then
        target.bountyStatus = BOUNTY_STATUS_OPEN
    else
        target.bountyStatus = BOUNTY_STATUS_OPEN
    end
    if mode == BOUNTY_MODE_NONE then
        target.bountyAmount = 0
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetHitStatus(name, status, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can change status." end
    if status ~= HIT_STATUS_ACTIVE and status ~= HIT_STATUS_COMPLETED and status ~= HIT_STATUS_CLOSED then
        return nil, "Invalid hit status."
    end
    target.hitStatus = status
    target.updatedAt = Utils.Now()
    return target
end

function HitList:ShouldAnnounceSighting(target)
    if not target then return false end
    return target.hitStatus == HIT_STATUS_ACTIVE
end

function HitList:UpsertFromComm(payload)
    local normalized = Utils.NormalizeName(payload.name)
    if not normalized then return nil end
    local ts = tonumber(payload.updatedAt) or Utils.Now()
    local incomingSubmitter = Utils.NormalizeName(payload.submitter) or payload.submitter
    local submitter = incomingSubmitter or "Unknown"

    local target = EnsureTarget(normalized, submitter, ts)

    -- Guild channel is authoritative — always update guildName
    if payload.guildName and payload.guildName ~= "" then
        target.guildName = payload.guildName
    end

    if target.updatedAt and target.updatedAt > ts then
        return target
    end

    if incomingSubmitter and incomingSubmitter ~= "" then
        target.submitter = incomingSubmitter
    elseif not target.submitter or target.submitter == "" then
        target.submitter = "Unknown"
    end
    if payload.reason ~= nil and payload.reason ~= "" then
        target.reason = payload.reason
    elseif target.reason == nil then
        target.reason = ""
    end
    target.bountyAmount = tonumber(payload.bountyAmount) or target.bountyAmount or 0
    target.hitMode = payload.hitMode or target.hitMode or HIT_MODE_ONE_TIME
    target.hitStatus = payload.hitStatus or target.hitStatus or HIT_STATUS_ACTIVE
    target.bountyMode = payload.bountyMode or target.bountyMode or BOUNTY_MODE_NONE
    target.bountyStatus = payload.bountyStatus or target.bountyStatus or BOUNTY_STATUS_OPEN
    target.validated = payload.validated == "1" or payload.validated == true or target.validated
    target.classToken = payload.classToken or target.classToken
    target.race = payload.race or target.race
    target.faction = payload.faction or target.faction
    target.raceId = tonumber(payload.raceId) or target.raceId or InferRaceIdFromRaceName(target.race)
    target.sex = tonumber(payload.sex) or target.sex or 0
    if HasIncomingLocationPayload(payload) then
        local incomingLocation = NormalizeLocationPayload({
            zone = payload.lastSeenZone,
            subzone = payload.lastSeenSubzone,
            mapId = payload.lastSeenMapId,
            x = payload.lastSeenX,
            y = payload.lastSeenY,
            seenAt = payload.lastSeenAt,
            source = payload.lastSeenSource,
            approximate = payload.lastSeenApproximate,
            confidenceYards = payload.lastSeenConfidenceYards,
        }, "comm")
        if incomingLocation then
            local currentSeenAt = target.lastKnownLocation and tonumber(target.lastKnownLocation.seenAt) or 0
            if incomingLocation.seenAt >= currentSeenAt then
                target.lastKnownLocation = incomingLocation
            end
        end
    end
    target.createdAt = tonumber(payload.createdAt) or target.createdAt
    target.updatedAt = ts
    target.killCount = tonumber(payload.killCount) or target.killCount or 0
    target.kills = target.kills or {}
    target.bountyClaims = target.bountyClaims or {}
    return target
end

function HitList:UpdateValidationFromUnit(name, unit)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil, "Unit invalid." end

    local unitName = Utils.NormalizeName(UnitName(unit))
    if unitName ~= target.name then return nil, "Unit name mismatch." end

    local _, englishClass = UnitClass(unit)
    local raceName = UnitRace(unit)
    local faction = UnitFactionGroup(unit)
    local raceId, sex = CaptureUnitRaceMetadata(unit)
    local myFaction = UnitFactionGroup("player")

    if faction and myFaction and faction == myFaction then
        return nil, "Same faction."
    end

    target.validated = true
    target.classToken = englishClass
    target.race = raceName
    target.raceId = raceId or target.raceId
    target.sex = sex or target.sex
    target.faction = faction
    target.lastKnownLocation = NormalizeLocationPayload(Utils.BuildLocationPayload({
        unit = unit,
        source = "unit",
        approximate = false,
        fallbackToPlayer = true,
    }), "unit") or target.lastKnownLocation
    target.updatedAt = Utils.Now()
    return target
end

function HitList:UpdateLastKnownLocation(name, location)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    local normalized = NormalizeLocationPayload(location)
    if not normalized then return nil, "Invalid location payload." end

    local currentSeenAt = target.lastKnownLocation and tonumber(target.lastKnownLocation.seenAt) or 0
    if normalized.seenAt >= currentSeenAt then
        target.lastKnownLocation = normalized
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:ApplyKill(targetName, killerName, location, ts)
    local target = self:Get(targetName)
    if not target then return nil end

    local now = ts or Utils.Now()
    local killer = Utils.NormalizeName(killerName) or killerName or "Unknown"

    local prevCount = target.killCount or 0
    target.kills = target.kills or {}
    local resolvedLocation = nil
    if type(location) == "table" then
        resolvedLocation = NormalizeLocationPayload(location, "party_kill")
    else
        resolvedLocation = NormalizeLocationPayload({
            zone = location or Utils.ZoneName(),
            subzone = Utils.SubZoneName(),
            seenAt = now,
            source = "party_kill",
            approximate = false,
        }, "party_kill")
    end

    table.insert(target.kills, {
        killer = killer,
        ts = now,
        zone = (resolvedLocation and resolvedLocation.zone) or Utils.ZoneName(),
        location = resolvedLocation,
        submitterAtTime = target.submitter,
        proof = {
            auto = true,
            ts = now,
            zone = (resolvedLocation and resolvedLocation.zone) or Utils.ZoneName(),
            location = resolvedLocation,
        },
    })
    target.killCount = prevCount + 1

    if target.hitMode == HIT_MODE_ONE_TIME and target.hitStatus == HIT_STATUS_ACTIVE then
        target.hitStatus = HIT_STATUS_COMPLETED
    end

    local submitterName = Utils.NormalizeName(target.submitter)
    local killerEligibleForClaim = (submitterName == nil) or (Utils.NormalizeName(killer) ~= submitterName)
    if target.bountyAmount and target.bountyAmount > 0 and killerEligibleForClaim then
        target.bountyClaims = target.bountyClaims or {}
        local existing = target.bountyClaims[killer] or { totalCopper = 0, paidCopper = 0, claimCount = 0, lastClaimAt = 0 }
        existing.paidCopper = existing.paidCopper or 0
        if target.bountyMode == BOUNTY_MODE_FIRST and target.bountyStatus ~= BOUNTY_STATUS_CLAIMED then
            existing.totalCopper = existing.totalCopper + target.bountyAmount
            existing.claimCount = existing.claimCount + 1
            existing.lastClaimAt = now
            target.bountyClaims[killer] = existing
            target.bountyStatus = BOUNTY_STATUS_CLAIMED
        elseif target.bountyMode == BOUNTY_MODE_INFINITE then
            existing.totalCopper = existing.totalCopper + target.bountyAmount
            existing.claimCount = existing.claimCount + 1
            existing.lastClaimAt = now
            target.bountyClaims[killer] = existing
        end
    end

    if resolvedLocation then
        local currentSeenAt = target.lastKnownLocation and tonumber(target.lastKnownLocation.seenAt) or 0
        if resolvedLocation.seenAt >= currentSeenAt then
            target.lastKnownLocation = resolvedLocation
        end
    end
    target.updatedAt = now
    return CloneEntry(target)
end

function HitList:RecordBountyPayment(targetName, killerName, copperPaid)
    local target = self:Get(targetName)
    if not target then return nil, "Target not found." end

    local killer = Utils.NormalizeName(killerName)
    if not killer then return nil, "Invalid killer name." end

    target.bountyClaims = target.bountyClaims or {}
    local claim = target.bountyClaims[killer]
    if not claim then return nil, "No bounty claim found for " .. killer end

    claim.paidCopper = claim.paidCopper or 0
    claim.paidCopper = math.min(claim.totalCopper, claim.paidCopper + copperPaid)
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetBountyPaid(targetName, killerName, paid)
    local target = self:Get(targetName)
    if not target then return nil, "Target not found." end

    local killer = Utils.NormalizeName(killerName)
    if not killer then return nil, "Invalid killer name." end

    target.bountyClaims = target.bountyClaims or {}
    local claim = target.bountyClaims[killer]
    if not claim then return nil, "No bounty claim for " .. killer end

    claim.paidCopper = paid and claim.totalCopper or 0
    target.updatedAt = Utils.Now()
    return target
end

function HitList:GetBountyOwed(targetName, killerName)
    local target = self:Get(targetName)
    if not target then return 0 end

    local killer = Utils.NormalizeName(killerName)
    if not killer then return 0 end

    local claim = target.bountyClaims and target.bountyClaims[killer]
    if not claim then return 0 end

    return math.max(0, (claim.totalCopper or 0) - (claim.paidCopper or 0))
end

local FIELD_SEP = ";"

local function ExportEscape(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub(";", "%%3B")
    value = value:gsub("\n", "%%0A")
    return value
end

local function ExportUnescape(value)
    value = tostring(value or "")
    value = value:gsub("%%0A", "\n")
    value = value:gsub("%%3B", ";")
    value = value:gsub("%%25", "%%")
    return value
end

local EXPORT_FIELDS = {
    "name", "submitter", "guildName", "reason", "bountyAmount",
    "hitMode", "hitStatus", "bountyMode", "bountyStatus",
    "validated", "classToken", "race", "faction",
    "raceId", "sex", "createdAt", "updatedAt", "killCount",
    "lastSeenZone", "lastSeenSubzone", "lastSeenMapId", "lastSeenX", "lastSeenY",
    "lastSeenAt", "lastSeenSource", "lastSeenApproximate", "lastSeenConfidenceYards",
}

local LEGACY_EXPORT_FIELDS = {
    "name", "submitter", "guildName", "reason", "bountyAmount",
    "hitMode", "hitStatus", "bountyMode", "bountyStatus",
    "validated", "classToken", "race", "faction",
    "createdAt", "updatedAt", "killCount",
}

function HitList:ExportCurrentGuild()
    local targets = self:GetAllForCurrentGuild()
    local lines = {}
    for _, target in pairs(targets) do
        local fields = {}
        for _, key in ipairs(EXPORT_FIELDS) do
            local val = target[key]
            if key == "validated" then
                val = val and "1" or "0"
            elseif key == "raceId" then
                val = val or InferRaceIdFromRaceName(target.race) or ""
            elseif key == "sex" then
                val = NormalizeSexForStorage(val)
            elseif key == "lastSeenZone" then
                val = target.lastKnownLocation and target.lastKnownLocation.zone or ""
            elseif key == "lastSeenSubzone" then
                val = target.lastKnownLocation and target.lastKnownLocation.subzone or ""
            elseif key == "lastSeenMapId" then
                val = target.lastKnownLocation and target.lastKnownLocation.mapId or ""
            elseif key == "lastSeenX" then
                val = target.lastKnownLocation and target.lastKnownLocation.x or ""
            elseif key == "lastSeenY" then
                val = target.lastKnownLocation and target.lastKnownLocation.y or ""
            elseif key == "lastSeenAt" then
                val = target.lastKnownLocation and target.lastKnownLocation.seenAt or ""
            elseif key == "lastSeenSource" then
                val = target.lastKnownLocation and target.lastKnownLocation.source or ""
            elseif key == "lastSeenApproximate" then
                val = (target.lastKnownLocation and target.lastKnownLocation.approximate) and "1" or "0"
            elseif key == "lastSeenConfidenceYards" then
                val = target.lastKnownLocation and target.lastKnownLocation.confidenceYards or ""
            end
            table.insert(fields, ExportEscape(val))
        end
        table.insert(lines, table.concat(fields, FIELD_SEP))
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local function SplitFields(line)
    local fields = {}
    local padded = line .. FIELD_SEP
    for field in padded:gmatch("([^" .. FIELD_SEP .. "]*)" .. FIELD_SEP) do
        table.insert(fields, field)
    end
    return fields
end

function HitList:ImportFromString(data)
    if not data or data == "" then return 0 end
    local count = 0
    for line in data:gmatch("[^\n]+") do
        local trimmed = strtrim(line)
        if trimmed ~= "" then
            local fields = SplitFields(trimmed)
            local schema = nil
            if #fields >= #EXPORT_FIELDS then
                schema = EXPORT_FIELDS
            elseif #fields >= #LEGACY_EXPORT_FIELDS then
                schema = LEGACY_EXPORT_FIELDS
            end
            if schema then
                local payload = {}
                for i, key in ipairs(schema) do
                    payload[key] = ExportUnescape(fields[i])
                end
                if payload.name and payload.name ~= "" then
                    self:UpsertFromComm(payload)
                    count = count + 1
                end
            end
        end
    end
    return count
end

