local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.Sync = {}
local Sync = GUnit.Sync

local CHUNK_DELAY_SECONDS = 0.2
local CLAIM_BACKOFF_MAX_SECONDS = 3
local SYNC_RETRY_DELAY_SECONDS = 8
local SYNC_WATCHDOG_SECONDS = 15

local pendingRequestId = nil
local claimedRequests = {}
local isSyncing = false
local hasRetried = false

local function GenerateRequestId()
    return Utils.Now() .. "-" .. math.random(1000, 9999)
end

local function BuildReasonMap(target)
    return {
        action = "REASON",
        name = target.name,
        submitter = target.submitter,
        guildName = target.guildName or Utils.GuildName() or "",
        reason = target.reason or "",
        updatedAt = target.updatedAt or Utils.Now(),
    }
end

local function SendChunkedMaps(maps, requestId, onComplete)
    local index = 0
    local function SendNext()
        index = index + 1
        if index > #maps then
            if onComplete then onComplete() end
            return
        end

        local map = maps[index]
        if requestId then map.requestId = requestId end
        local payload = Comm:CompactEncode(map)
        Comm:CheckedSend("GUILD", payload, (map.action or "?") .. " " .. (map.name or "?"))

        C_Timer.After(CHUNK_DELAY_SECONDS, SendNext)
    end
    SendNext()
end

local function SendChunkedReasons(targets, onComplete)
    local index = 0
    local function SendNext()
        index = index + 1
        if index > #targets then
            if onComplete then onComplete() end
            return
        end
        local payload = Comm:CompactEncode(BuildReasonMap(targets[index]))
        Comm:CheckedSend("GUILD", payload, "SYNC REASON " .. targets[index].name)
        C_Timer.After(CHUNK_DELAY_SECONDS, SendNext)
    end
    SendNext()
end

local function CollectGuildSyncData(action)
    local guildName = Utils.GuildName()
    if not guildName then return {}, {} end
    local allMaps = {}
    local targets = {}
    for _, target in pairs(GUnit.db.targets) do
        if target.guildName == guildName then
            local maps = Comm:CollectTargetMaps(target, action)
            for _, map in ipairs(maps) do
                table.insert(allMaps, map)
            end
            table.insert(targets, target)
        end
    end
    return allMaps, targets
end

function Sync:RequestSync()
    if not Utils.InGuild() then return end
    if isSyncing then return end

    isSyncing = true
    hasRetried = false
    pendingRequestId = GenerateRequestId()
    claimedRequests[pendingRequestId] = false

    GUnit:Debug("SYNC requested, id=" .. pendingRequestId)

    local payload = Comm:ActionPayload("SYNC_REQUEST", {
        requestId = pendingRequestId,
    })
    Comm:Send("GUILD", payload)

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
    GUnit:Debug("SYNC finished")
    isSyncing = false
    pendingRequestId = nil
    GUnit:NotifyDataChanged()
end

local function PushOwnData()
    local allMaps, targets = CollectGuildSyncData("SYNC_PUSH")
    if #allMaps == 0 then return end

    SendChunkedMaps(allMaps, nil, function()
        SendChunkedReasons(targets, function()
            local donePayload = Comm:ActionPayload("SYNC_PUSH_DONE", {})
            Comm:Send("GUILD", donePayload)
        end)
    end)
end

-- Message handlers

local function HandleSyncRequest(data, sender)
    if not Utils.InGuild() then return end
    local requestId = data.requestId
    if not requestId then return end

    local delay = math.random() * CLAIM_BACKOFF_MAX_SECONDS
    C_Timer.After(delay, function()
        if claimedRequests[requestId] then return end

        claimedRequests[requestId] = true
        local claimPayload = Comm:ActionPayload("SYNC_CLAIM", {
            requestId = requestId,
            responder = Utils.PlayerName(),
        })
        Comm:Send("GUILD", claimPayload)

        local allMaps, targets = CollectGuildSyncData("SYNC_DATA")
        SendChunkedMaps(allMaps, requestId, function()
            SendChunkedReasons(targets, function()
                local donePayload = Comm:ActionPayload("SYNC_DONE", {
                    requestId = requestId,
                })
                Comm:Send("GUILD", donePayload)
            end)
        end)
    end)
end

local function HandleSyncClaim(data)
    local requestId = data.requestId
    if not requestId then return end
    claimedRequests[requestId] = true

    GUnit:Debug("SYNC claimed by " .. (data.responder or "unknown"))

    if requestId == pendingRequestId then
        C_Timer.After(SYNC_WATCHDOG_SECONDS, function()
            if isSyncing and pendingRequestId == requestId then
                GUnit:Debug("SYNC watchdog: no SYNC_DONE, forcing finish")
                Sync:FinishSync()
            end
        end)
    end
end

local function HandleSyncData(data)
    if not data.name then return end
    GUnit:Debug("SYNC entry received: " .. data.name)
    HitList:UpsertFromComm(data)
end

local function HandleSyncDone(data)
    local requestId = data.requestId
    if requestId and requestId == pendingRequestId then
        GUnit:Debug("SYNC done, pushing own data")
        GUnit:NotifyDataChanged()
        C_Timer.After(1, function()
            PushOwnData()
            Sync:FinishSync()
        end)
    end
end

local function HandleSyncPush(data)
    if not data.name then return end
    HitList:UpsertFromComm(data)
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
