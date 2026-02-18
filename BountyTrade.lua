local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.BountyTrade = {}
local BountyTrade = GUnit.BountyTrade

-- Trade state
local tradePartnerName = nil
local bothAccepted = false
local playerGold = 0
local targetGold = 0

local function ResetTradeState()
    tradePartnerName = nil
    bothAccepted = false
    playerGold = 0
    targetGold = 0
end

local function FindBountyMatches(partnerName, goldGiven, goldReceived)
    local myName = Utils.NormalizeName(Utils.PlayerName())
    local partner = Utils.NormalizeName(partnerName)
    if not partner then return {} end

    local matches = {}
    local targets = HitList:GetAllForCurrentGuild()

    for _, target in pairs(targets) do
        if not target.bountyClaims then goto continue end

        -- Scenario A: I placed the bounty, I gave gold to the killer
        if goldGiven > 0 and Utils.NormalizeName(target.submitter) == myName then
            local claim = target.bountyClaims[partner]
            if claim then
                local owed = math.max(0, (claim.totalCopper or 0) - (claim.paidCopper or 0))
                if owed > 0 then
                    table.insert(matches, {
                        targetName = target.name,
                        killerName = partner,
                        goldTraded = goldGiven,
                        goldOwed = owed,
                        scenario = "placer",
                    })
                end
            end
        end

        -- Scenario B: Partner placed the bounty, I killed the target, partner gave me gold
        if goldReceived > 0 and Utils.NormalizeName(target.submitter) == partner then
            local claim = target.bountyClaims[myName]
            if claim then
                local owed = math.max(0, (claim.totalCopper or 0) - (claim.paidCopper or 0))
                if owed > 0 then
                    table.insert(matches, {
                        targetName = target.name,
                        killerName = myName,
                        goldTraded = goldReceived,
                        goldOwed = owed,
                        scenario = "killer",
                    })
                end
            end
        end

        ::continue::
    end
    return matches
end

-- Popup queue: process one match at a time
local pendingMatches = {}

local function ShowNextBountyPopup()
    if #pendingMatches == 0 then return end
    local match = table.remove(pendingMatches, 1)

    local tradedStr = Utils.GoldStringFromCopper(match.goldTraded)
    local owedStr = Utils.GoldStringFromCopper(match.goldOwed)

    local promptText
    if match.scenario == "placer" then
        promptText = "You traded " .. tradedStr .. " to " .. match.killerName .. ".\n\n"
            .. "You owe " .. owedStr .. " bounty on " .. match.targetName .. ".\n\n"
            .. "Was this a bounty payment?"
    else
        promptText = match.killerName .. " received " .. tradedStr .. " from trade.\n\n"
            .. "Bounty owed for killing " .. match.targetName .. ": " .. owedStr .. ".\n\n"
            .. "Was this a bounty payment?"
    end

    -- Store match data for the popup callback
    BountyTrade._currentMatch = match
    StaticPopup_Show("GUNIT_BOUNTY_CONFIRM", promptText)
end

StaticPopupDialogs["GUNIT_BOUNTY_CONFIRM"] = {
    text = "%s",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        local match = BountyTrade._currentMatch
        if not match then return end

        if match.scenario == "placer" then
            local updated, err = HitList:RecordBountyPayment(match.targetName, match.killerName, match.goldTraded)
            if updated then
                Comm:BroadcastUpsert(updated)
                GUnit:NotifyDataChanged()
                local remaining = HitList:GetBountyOwed(match.targetName, match.killerName)
                if remaining > 0 then
                    GUnit:Print("Bounty payment recorded. " .. Utils.GoldStringFromCopper(remaining) .. " still owed on " .. match.targetName .. ".")
                else
                    GUnit:Print("Bounty on " .. match.targetName .. " fully paid to " .. match.killerName .. ".")
                end
            else
                GUnit:Print(err or "Failed to record bounty payment.")
            end
        else
            GUnit:Print("Bounty payment from " .. match.killerName .. " noted for " .. match.targetName .. ".")
        end

        BountyTrade._currentMatch = nil
        ShowNextBountyPopup()
    end,
    OnCancel = function()
        BountyTrade._currentMatch = nil
        ShowNextBountyPopup()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OnTradeShow()
    ResetTradeState()
    -- In TBC Classic, trade target is accessible via UnitName("NPC")
    local name = UnitName("NPC")
    if name then
        tradePartnerName = Utils.NormalizeName(name)
    end
end

local function OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
    if playerAccepted and playerAccepted == 1 and targetAccepted and targetAccepted == 1 then
        bothAccepted = true
        -- Capture gold amounts while trade window is still open
        playerGold = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
        targetGold = GetTargetTradeMoney and GetTargetTradeMoney() or 0
    end
end

local function OnTradeClosed()
    if not bothAccepted or not tradePartnerName then
        ResetTradeState()
        return
    end

    local goldGiven = playerGold
    local goldReceived = targetGold
    local partner = tradePartnerName
    ResetTradeState()

    if goldGiven <= 0 and goldReceived <= 0 then return end

    local matches = FindBountyMatches(partner, goldGiven, goldReceived)
    if #matches == 0 then return end

    pendingMatches = matches
    ShowNextBountyPopup()
end

function BountyTrade:Init()
    GUnit:RegisterEvent("TRADE_SHOW", OnTradeShow)
    GUnit:RegisterEvent("TRADE_ACCEPT_UPDATE", OnTradeAcceptUpdate)
    GUnit:RegisterEvent("TRADE_CLOSED", OnTradeClosed)
end
