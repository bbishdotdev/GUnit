local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.Sync = {}
local Sync = GUnit.Sync

local CHUNK_DELAY_SECONDS = 0.2
local CLAIM_BACKOFF_MAX_SECONDS = 3
local SYNC_RETRY_DELAY_SECONDS = 8

-- State
local pendingRequestId = nil
local claimedRequests = {}
local isSyncing = false
local hasRetried = false

local function GenerateRequestId()
    return Utils.PlayerName() .. "-" .. Utils.Now() .. "-" .. math.random(1000, 9999)
end

local function SerializeTarget(target)
    return Comm:EncodeMap({
        name = target.name,
        submitter = target.submitter,
        guildName = target.guildName or "",
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
end

local function SendChunkedData(entries, actionType, requestId, onComplete)
    local index = 0
    local function SendNext()
        index = index + 1
        if index > #entries then
            if onComplete then onComplete() end
            return
        end
        local map = { action = actionType, entry = entries[index] }
        if requestId then map.requestId = requestId end
        local payload = Comm:EncodeMap(map)
        Comm:Send("GUILD", payload)
        C_Timer.After(CHUNK_DELAY_SECONDS, SendNext)
    end
    SendNext()
end

local function CollectGuildEntries()
    local guildName = Utils.GuildName()
    if not guildName then return {} end
    local entries = {}
    for _, target in pairs(GUnit.db.targets) do
        if target.guildName == guildName then
            table.insert(entries, SerializeTarget(target))
        end
    end
    return entries
end

-- Outbound: request sync from online guildmates
function Sync:RequestSync()
    if not Utils.InGuild() then return end
    if isSyncing then return end

    isSyncing = true
    hasRetried = false
    pendingRequestId = GenerateRequestId()
    claimedRequests[pendingRequestId] = false

    local payload = Comm:ActionPayload("SYNC_REQUEST", {
        requestId = pendingRequestId,
    })
    Comm:Send("GUILD", payload)

    -- Timeout: if no claim received, retry once then give up
    local requestId = pendingRequestId
    C_Timer.After(SYNC_RETRY_DELAY_SECONDS, function()
        if pendingRequestId ~= requestId then return end
        if claimedRequests[requestId] then return end

        if not hasRetried then
            hasRetried = true
            local retryPayload = Comm:ActionPayload("SYNC_REQUEST", {
                requestId = requestId,
            })
            Comm:Send("GUILD", retryPayload)
            -- Second timeout: give up after another window
            C_Timer.After(SYNC_RETRY_DELAY_SECONDS, function()
                if pendingRequestId == requestId then
                    Sync:FinishSync()
                end
            end)
        else
            Sync:FinishSync()
        end
    end)
end

function Sync:FinishSync()
    isSyncing = false
    pendingRequestId = nil
    GUnit:NotifyDataChanged()
end

-- Inbound: push our data back after receiving sync
local function PushOwnData()
    local entries = CollectGuildEntries()
    if #entries == 0 then return end

    SendChunkedData(entries, "SYNC_PUSH", nil, function()
        local donePayload = Comm:ActionPayload("SYNC_PUSH_DONE", {})
        Comm:Send("GUILD", donePayload)
    end)
end

-- Message handlers
local function HandleSyncRequest(data, sender)
    if not Utils.InGuild() then return end
    local requestId = data.requestId
    if not requestId then return end

    -- Random backoff before claiming
    local delay = math.random() * CLAIM_BACKOFF_MAX_SECONDS
    C_Timer.After(delay, function()
        -- Check if someone else already claimed
        if claimedRequests[requestId] then return end

        claimedRequests[requestId] = true
        local claimPayload = Comm:ActionPayload("SYNC_CLAIM", {
            requestId = requestId,
            responder = Utils.PlayerName(),
        })
        Comm:Send("GUILD", claimPayload)

        -- Send our guild data to the requester
        local entries = CollectGuildEntries()
        SendChunkedData(entries, "SYNC_DATA", requestId, function()
            local donePayload = Comm:ActionPayload("SYNC_DONE", {
                requestId = requestId,
            })
            Comm:Send("GUILD", donePayload)
        end)
    end)
end

local function HandleSyncClaim(data)
    local requestId = data.requestId
    if not requestId then return end
    -- Mark as claimed so other potential responders stand down
    claimedRequests[requestId] = true
end

local function HandleSyncData(data)
    if not data.entry then return end
    local entryData = Comm:DecodeMap(data.entry)
    if entryData and entryData.name then
        HitList:UpsertFromComm(entryData)
    end
end

local function HandleSyncDone(data)
    local requestId = data.requestId
    if requestId and requestId == pendingRequestId then
        -- We received the full dump, now push our data back
        GUnit:NotifyDataChanged()
        C_Timer.After(1, function()
            PushOwnData()
            Sync:FinishSync()
        end)
    end
end

local function HandleSyncPush(data)
    if not data.entry then return end
    local entryData = Comm:DecodeMap(data.entry)
    if entryData and entryData.name then
        HitList:UpsertFromComm(entryData)
    end
end

local function HandleSyncPushDone()
    GUnit:NotifyDataChanged()
end

function Sync:HandleMessage(action, data, sender)
    if action == "SYNC_REQUEST" then
        HandleSyncRequest(data, sender)
    elseif action == "SYNC_CLAIM" then
        HandleSyncClaim(data)
    elseif action == "SYNC_DATA" then
        HandleSyncData(data)
    elseif action == "SYNC_DONE" then
        HandleSyncDone(data)
    elseif action == "SYNC_PUSH" then
        HandleSyncPush(data)
    elseif action == "SYNC_PUSH_DONE" then
        HandleSyncPushDone()
    end
end
