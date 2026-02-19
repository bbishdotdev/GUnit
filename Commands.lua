local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

local function SaveAndBroadcast(target)
    Comm:BroadcastUpsert(target)
    GUnit:NotifyDataChanged()
end

local function ApplyDefaultsToNewHit(target)
    if not target then return target end
    local settings = GUnit.db and GUnit.db.settings or nil
    if not settings then return target end

    local desiredHitMode = settings.defaultHitMode or "one_time"
    local desiredBountyGold = tonumber(settings.defaultBountyGold) or 0
    local desiredBountyCopper = math.max(0, math.floor(desiredBountyGold * 10000 + 0.5))
    local desiredBountyMode = settings.defaultBountyMode or "none"

    local updated = target
    local actor = Utils.PlayerName()

    if desiredHitMode ~= (updated.hitMode or "one_time") then
        local t = HitList:SetHitMode(updated.name, desiredHitMode, actor)
        if t then updated = t end
    end

    if desiredBountyCopper ~= (updated.bountyAmount or 0) then
        local t = HitList:SetBountyAmount(updated.name, desiredBountyCopper, actor)
        if t then updated = t end
    end

    if desiredBountyCopper > 0 and desiredBountyMode ~= "none" then
        local t = HitList:SetBountyMode(updated.name, desiredBountyMode, actor)
        if t then updated = t end
    end

    return updated
end

local function AddFromTargetUnit()
    if not UnitExists("target") then
        GUnit:Print("No target selected.")
        return
    end
    if not UnitIsPlayer("target") then
        GUnit:Print("Only enemy players can be added.")
        return
    end

    local targetName = Utils.NormalizeName(UnitName("target"))
    if not targetName then
        GUnit:Print("Unable to read target name.")
        return
    end

    local targetFaction = UnitFactionGroup("target")
    local myFaction = UnitFactionGroup("player")
    if targetFaction and myFaction and targetFaction == myFaction then
        GUnit:Print("Cannot add same-faction targets.")
        return
    end

    local wasExisting = HitList:Get(targetName) ~= nil
    local created = HitList:CreateOrTouch(targetName, Utils.PlayerName(), nil, Utils.Now())
    if not wasExisting then
        created = ApplyDefaultsToNewHit(created)
    end
    HitList:UpdateValidationFromUnit(targetName, "target")
    SaveAndBroadcast(created)
    Comm:BroadcastReason(HitList:Get(targetName))
    GUnit:Print("Hit added: " .. targetName .. " (one-time, no bounty).")
    local openedTarget = HitList:Get(targetName)
    local openMsg = "A hit on " .. Utils.TargetLabel(openedTarget) .. " has been opened."
    if openedTarget and (openedTarget.bountyAmount or 0) > 0 then
        openMsg = openMsg .. " Bounty: " .. Utils.GoldStringFromCopper(openedTarget.bountyAmount) .. "."
    end
    Utils.SendGuildChat(openMsg)
end

local function AddByName(name)
    local normalized = Utils.NormalizeName(name)
    local wasExisting = normalized and HitList:Get(normalized) ~= nil
    local target = HitList:CreateOrTouch(name, Utils.PlayerName(), nil, Utils.Now())
    if not target then
        GUnit:Print("Invalid name.")
        return
    end
    if not wasExisting then
        target = ApplyDefaultsToNewHit(target)
    end
    SaveAndBroadcast(target)
    Comm:BroadcastReason(target)
    GUnit:Print("Hit added: " .. target.name .. " (unverified, one-time, no bounty).")
    local openMsg = "A hit on " .. Utils.TargetLabel(target) .. " has been opened."
    if (target.bountyAmount or 0) > 0 then
        openMsg = openMsg .. " Bounty: " .. Utils.GoldStringFromCopper(target.bountyAmount) .. "."
    end
    Utils.SendGuildChat(openMsg)
end

local function DoRemove(name)
    local target = HitList:Get(name)
    if not target then
        GUnit:Print("Target not found.")
        return
    end
    if not HitList:CanMutate(target, Utils.PlayerName()) then
        GUnit:Print("Only submitter can remove this hit.")
        return
    end
    HitList:Delete(name)
    Comm:BroadcastDelete(name)
    GUnit:NotifyDataChanged()
    GUnit:Print("Removed hit: " .. name)
end

local function DoSetReason(name, reason)
    local updated, err = HitList:SetReason(name, reason, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return
    end
    SaveAndBroadcast(updated)
    Comm:BroadcastReason(updated)
    GUnit:Print("Reason updated for " .. updated.name .. ".")
end

local function DoSetBounty(name, value)
    local copper = Utils.CopperFromGoldString(value)
    if not copper then
        GUnit:Print("Invalid bounty amount.")
        return
    end
    local updated, err = HitList:SetBountyAmount(name, copper, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return
    end
    SaveAndBroadcast(updated)
    GUnit:Print("Bounty updated for " .. updated.name .. ": " .. Utils.GoldStringFromCopper(updated.bountyAmount) .. ".")
end

local function DoSetHitMode(name, modeArg)
    local mode = modeArg == "kos" and "kos" or "one_time"
    local updated, err = HitList:SetHitMode(name, mode, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return
    end
    SaveAndBroadcast(updated)
    GUnit:Print("Hit mode updated for " .. updated.name .. ": " .. mode .. ".")
end

local function DoSetBountyMode(name, modeArg)
    local mode = "none"
    if modeArg == "first" or modeArg == "first_kill" then
        mode = "first_kill"
    elseif modeArg == "infinite" then
        mode = "infinite"
    end
    local updated, err = HitList:SetBountyMode(name, mode, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return
    end
    SaveAndBroadcast(updated)
    GUnit:Print("Bounty mode updated for " .. updated.name .. ": " .. mode .. ".")
end

local function DoSetStatus(name, status)
    local updated, err = HitList:SetHitStatus(name, status, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return
    end
    SaveAndBroadcast(updated)
    GUnit:Print("Status updated for " .. updated.name .. ": " .. status .. ".")
end

local function OpenUI()
    if GUnit.UI and GUnit.UI.Toggle then
        GUnit.UI:Toggle()
    else
        GUnit:Print("UI is not loaded.")
    end
end

local function HandleGhitCommand(msg)
    local input = strtrim(msg or "")
    if input == "" then
        AddFromTargetUnit()
        return
    end

    if input == "proof" then
        GUnit:Print("Proof is automatic on kill metadata capture in v1.")
        return
    end

    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "remove" then
        DoRemove(rest)
        return
    end
    if cmd == "reason" then
        local name, reason = rest:match("^(%S+)%s+(.+)$")
        if not name then
            GUnit:Print("Usage: /ghit reason <name> <reason>")
            return
        end
        DoSetReason(name, reason)
        return
    end
    if cmd == "bounty" then
        local name, amount = rest:match("^(%S+)%s+(.+)$")
        if not name then
            GUnit:Print("Usage: /ghit bounty <name> <gold>")
            return
        end
        DoSetBounty(name, amount)
        return
    end
    if cmd == "mode" then
        local name, modeArg = rest:match("^(%S+)%s*(%S*)$")
        if not name then
            GUnit:Print("Usage: /ghit mode <name> <one-time|kos>")
            return
        end
        modeArg = (modeArg or ""):lower()
        if modeArg == "one-time" then
            modeArg = "one_time"
        end
        if modeArg ~= "kos" and modeArg ~= "one_time" then
            GUnit:Print("Usage: /ghit mode <name> <one-time|kos>")
            return
        end
        DoSetHitMode(name, modeArg)
        return
    end
    if cmd == "bounty-mode" then
        local name, modeArg = rest:match("^(%S+)%s*(%S*)$")
        if not name then
            GUnit:Print("Usage: /ghit bounty-mode <name> <none|first|infinite>")
            return
        end
        modeArg = (modeArg or ""):lower()
        if modeArg ~= "none" and modeArg ~= "first" and modeArg ~= "first_kill" and modeArg ~= "infinite" then
            GUnit:Print("Usage: /ghit bounty-mode <name> <none|first|infinite>")
            return
        end
        DoSetBountyMode(name, modeArg)
        return
    end
    if cmd == "complete" then
        DoSetStatus(rest, "completed")
        return
    end
    if cmd == "reopen" then
        DoSetStatus(rest, "active")
        return
    end

    AddByName(input)
end

SLASH_GUNIT1 = "/gunit"
SLASH_GUNIT2 = "/g-unit"
SlashCmdList["GUNIT"] = function(msg)
    local input = strtrim(msg or "")
    if input == "" then
        OpenUI()
        return
    end
    if input == "export" then
        if GUnit.UI and GUnit.UI.ShowExportFrame then
            GUnit.UI:ShowExportFrame()
        end
        return
    end
    if input == "import" then
        if GUnit.UI and GUnit.UI.ShowImportFrame then
            GUnit.UI:ShowImportFrame()
        end
        return
    end
    if input == "sync" then
        if GUnit.Sync and GUnit.Sync.RequestSync then
            GUnit.Sync:RequestSync()
            GUnit:Print("Sync requested.")
        end
        return
    end
    if input == "debug" then
        local s = GUnit.db and GUnit.db.settings
        if s then
            s.debugMode = not s.debugMode
            GUnit:Print("Debug mode: " .. (s.debugMode and "ON" or "OFF"))
        end
        return
    end
    if input == "stats" then
        local s = Comm.stats or {}
        GUnit:Print("Sent: " .. (s.sent or 0) .. "  Dropped: " .. (s.dropped_oversize or 0))
        local parts = {}
        for action, count in pairs(s.received or {}) do
            table.insert(parts, action .. "=" .. count)
        end
        table.sort(parts)
        GUnit:Print("Received: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
        return
    end
    -- Forward all other commands to the hit list handler
    HandleGhitCommand(input)
end

SLASH_GHIT1 = "/ghit"
SlashCmdList["GHIT"] = HandleGhitCommand
