local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList

GUnit.Tooltip = {}
local Tooltip = GUnit.Tooltip

local MARKER_TEXT = "G-Unit: Kill target"
local REQUESTER_PREFIX = "Requested by "
local TARGET_ICON = "Interface\\Icons\\Ability_FiegnDead"

local function TooltipHasMarker(tooltip)
    local lineCount = tooltip:NumLines() or 0
    for i = 1, lineCount do
        local leftLine = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = leftLine and leftLine:GetText() or nil
        if text and string.find(text, MARKER_TEXT, 1, true) then
            return true
        end
    end
    return false
end

local function AppendHitTargetLines(tooltip, target)
    if not target or TooltipHasMarker(tooltip) then
        return
    end

    local submitter = target.submitter or "Unknown"
    local lineOne = string.format("|T%s:12|t %s", TARGET_ICON, MARKER_TEXT)
    local lineTwo = REQUESTER_PREFIX .. submitter

    tooltip:AddLine(lineOne, 0.45, 0.8, 1.0, true)
    tooltip:AddLine(lineTwo, 1.0, 1.0, 1.0, true)
    tooltip:Show()
end

local function OnTooltipSetUnit(tooltip)
    if not tooltip or not tooltip.GetUnit then
        return
    end

    local unitName = tooltip:GetUnit()
    if not unitName then
        return
    end

    local normalized = Utils.NormalizeName(unitName)
    if not normalized then
        return
    end

    local target = HitList:Get(normalized)
    if not target then
        return
    end
    if not HitList:ShouldAnnounceSighting(target) then
        return
    end

    AppendHitTargetLines(tooltip, target)
end

function Tooltip:Init()
    if not GameTooltip or not GameTooltip.HookScript then
        return
    end
    GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
end
