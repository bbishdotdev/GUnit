local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.Tracking = {}
local Tracking = GUnit.Tracking

local FALLBACK_ALERT_COOLDOWN_SECONDS = 120
local PRESENCE_STALE_SECONDS = 30
local GLOBAL_ALERT_FLOOR_SECONDS = 2
local COMBAT_LOG_CONFIDENCE_YARDS = 50
local LOCATION_REFRESH_SECONDS = 5
local presenceByName = {}
local globalLastAlertAt = 0
local COMBAT_SIGHTING_SUBEVENTS = {
    SWING_DAMAGE = true,
    SWING_MISSED = true,
    RANGE_DAMAGE = true,
    RANGE_MISSED = true,
    SPELL_CAST_START = true,
    SPELL_CAST_SUCCESS = true,
    SPELL_DAMAGE = true,
    SPELL_MISSED = true,
    SPELL_HEAL = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REFRESH = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_PERIODIC_MISSED = true,
    SPELL_PERIODIC_HEAL = true,
}

local function SendGuildMessage(message)
    Utils.SendGuildChat(message)
end

local function PlayAlertSound()
    if not PlaySound then
        return
    end
    local soundKitId = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    pcall(PlaySound, soundKitId, "Master")
end

local function LocalAlert(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 0.45, 0.8, 1.0, nil, 5)
    end
    PlayAlertSound()
    GUnit:Print(message)
end

local function ClearStalePresence(now)
    for _, state in pairs(presenceByName) do
        if state.isPresent and now - (state.lastSeenAt or 0) >= PRESENCE_STALE_SECONDS then
            state.isPresent = false
        end
    end
end

local function ShouldAlertForEntry(name, now)
    local state = presenceByName[name]
    if not state then
        state = {
            isPresent = false,
            lastSeenAt = 0,
            lastAlertAt = 0,
        }
        presenceByName[name] = state
    end

    local wasPresent = state.isPresent
    state.isPresent = true
    state.lastSeenAt = now

    if wasPresent then
        return false
    end
    if now - (state.lastAlertAt or 0) < FALLBACK_ALERT_COOLDOWN_SECONDS then
        return false
    end
    if now - globalLastAlertAt < GLOBAL_ALERT_FLOOR_SECONDS then
        return false
    end

    state.lastAlertAt = now
    globalLastAlertAt = now
    return true
end

local function HasFlag(flags, flag)
    if not flags or not flag or not bit or not bit.band then
        return false
    end
    return bit.band(flags, flag) ~= 0
end

local function IsEnemyPlayerFromFlags(flags)
    if not flags then
        return false
    end
    if not HasFlag(flags, COMBATLOG_OBJECT_TYPE_PLAYER) then
        return false
    end
    if HasFlag(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY) then
        return false
    end
    return true
end

local function ValidateTargetUnit(unit, targetName)
    local updated, err = HitList:UpdateValidationFromUnit(targetName, unit)
    if updated then
        Comm:BroadcastUpsert(updated)
        GUnit:NotifyDataChanged()
        return
    end

    if err == "Same faction." then
        HitList:Delete(targetName)
        Comm:BroadcastDelete(targetName)
        GUnit:NotifyDataChanged()
        GUnit:Print("Removed " .. targetName .. " from hit list: same faction.")
    end
end

local function ProcessTargetSighting(targetName, source, hasUnitMetadata)
    local target = HitList:Get(targetName)
    if not target then return end
    if not HitList:ShouldAnnounceSighting(target) then return end

    local now = Utils.Now()
    ClearStalePresence(now)

    if not hasUnitMetadata then
        local shouldRefreshLocation = true
        local previousSeenAt = target.lastKnownLocation and tonumber(target.lastKnownLocation.seenAt) or 0
        if previousSeenAt > 0 and now - previousSeenAt < LOCATION_REFRESH_SECONDS then
            shouldRefreshLocation = false
        end
        if shouldRefreshLocation then
            HitList:UpdateLastKnownLocation(targetName, Utils.BuildLocationPayload({
                unit = "player",
                source = source,
                approximate = true,
                confidenceYards = COMBAT_LOG_CONFIDENCE_YARDS,
                seenAt = now,
                fallbackToPlayer = true,
            }))
            target = HitList:Get(targetName)
            if target then
                Comm:BroadcastUpsert(target)
                GUnit:NotifyDataChanged()
            end
        end
    end

    target = HitList:Get(targetName)
    if not target then return end
    if ShouldAlertForEntry(targetName, now) then
        LocalAlert("G-Unit target found in your area: " .. target.name .. ". Be on the lookout!")
    end
end

local function ProcessSeenUnit(unit, source)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end

    local unitName = Utils.NormalizeName(UnitName(unit))
    if not unitName then return end

    local target = HitList:Get(unitName)
    if not target then return end

    ValidateTargetUnit(unit, unitName)
    target = HitList:Get(unitName)
    if not target then return end
    ProcessTargetSighting(unitName, source or "unit", true)
end

local function ProcessCombatLogSighting(name, flags)
    if not name or not IsEnemyPlayerFromFlags(flags) then return end
    local targetName = Utils.NormalizeName(name)
    if not targetName then return end
    local target = HitList:Get(targetName)
    if not target then return end
    ProcessTargetSighting(targetName, "combat_log", false)
end

local function AnnounceEngageIfNeeded()
    if not UnitExists("target") or not UnitIsPlayer("target") then return end
    local targetName = Utils.NormalizeName(UnitName("target"))
    if not targetName then return end

    local hitTarget = HitList:Get(targetName)
    if not hitTarget then return end
    if not HitList:ShouldAnnounceSighting(hitTarget) then return end

    SendGuildMessage("Attempting to kill " .. Utils.TargetLabel(hitTarget) .. "! Hit was placed by " .. hitTarget.submitter .. ".")
end

local function OnCombatLogEvent()
    local _, subevent, _, _, sourceName, sourceFlags, _, _, destName, destFlags = CombatLogGetCurrentEventInfo()
    if COMBAT_SIGHTING_SUBEVENTS[subevent] then
        ProcessCombatLogSighting(sourceName, sourceFlags)
        ProcessCombatLogSighting(destName, destFlags)
    end

    if subevent ~= "PARTY_KILL" then return end
    if not sourceName or not destName then return end

    local killer = Utils.NormalizeName(sourceName)
    local playerName = Utils.NormalizeName(Utils.PlayerName())
    if killer ~= playerName then return end

    local targetName = Utils.NormalizeName(destName)
    local target = HitList:Get(targetName)
    if not target then return end
    if not HitList:ShouldAnnounceSighting(target) then return end

    local now = Utils.Now()
    local killLocation = Utils.BuildLocationPayload({
        unit = "player",
        source = "party_kill",
        approximate = false,
        confidenceYards = nil,
        seenAt = now,
        fallbackToPlayer = true,
    })
    HitList:ApplyKill(targetName, playerName, killLocation, now)
    Comm:BroadcastKill(targetName, playerName, killLocation, now)

    local updatedTarget = HitList:Get(targetName)
    Comm:BroadcastUpsert(updatedTarget)
    GUnit:NotifyDataChanged()

    SendGuildMessage(Utils.TargetLabel(target) .. " has been killed! Hit placed by " .. target.submitter .. ".")
    SendChatMessage("[G-Unit] " .. target.name .. " has been killed for you.", "WHISPER", nil, target.submitter)
end

function Tracking:Init()
    GUnit:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        ProcessSeenUnit("target", "target")
    end)
    GUnit:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        ProcessSeenUnit("mouseover", "mouseover")
    end)
    GUnit:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unitToken)
        if unitToken then
            ProcessSeenUnit(unitToken, "nameplate")
        end
    end)
    GUnit:RegisterEvent("PLAYER_REGEN_DISABLED", AnnounceEngageIfNeeded)
    GUnit:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLogEvent)
end
