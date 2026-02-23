local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm
local Theme = GUnit.UITheme
local UIComponents = GUnit.UIComponents

GUnit.UI = {}
local UI = GUnit.UI

local rows = {}
local filteredNames = {}
local SELECTED_ROW_BG = { 1, 0.82, 0.0, 0.2 }
local MAX_KILL_DETAIL_ROWS = 6

local mainFrame, contentArea
local guildInfoRow
local listPane, listScrollFrame, listScrollChild, emptyText
local detailDrawer

local drawerWidth = 0
local drawerTargetWidth = 0
local drawerAnimating = false
local drawerIsOpen = false

local function GetSettings()
    local db = GUnit.db or {}
    db.settings = db.settings or {}
    return db.settings
end

local function ShouldAnnounce()
    local settings = GetSettings()
    return settings.uiGuildAnnouncements == true
end

local function MaybeAnnounce(message)
    if ShouldAnnounce() then
        Utils.SendGuildChat(message)
    end
end

local function MaybeAnnounceParty(message)
    local settings = GetSettings()
    if settings.partyAnnouncements then
        Utils.SendPartyChat(message)
    end
end

local function HitModeValueLabel(target)
    return target.hitMode == "kos" and "Indefinitely" or "One-time"
end

local function FormatStatusLabel(status)
    if status == "completed" then return "Closed" end
    if status == "closed" then return "Closed" end
    return "Open"
end

local function BountyModeValueLabel(mode)
    if mode == "infinite" then return "Indefinitely" end
    if mode == "first_kill" then return "One-Time" end
    return "None"
end

local function ColorizeBountyState(text, token)
    if token == "open" then
        return "|cFFD93333" .. text .. "|r"
    end
    if token == "unpaid" then
        return "|cFFF2A63A" .. text .. "|r"
    end
    if token == "closed" then
        return "|cFF33CC66" .. text .. "|r"
    end
    return text
end

local function GoldPipe()
    return "|cFFFFD100|r"
end

local function LatestClaimSummary(target)
    local claims = target and target.bountyClaims or nil
    if not claims then return nil, nil end

    local latestKiller, latestTs, latestClaim = nil, -1, nil
    for killer, claim in pairs(claims) do
        local ts = tonumber(claim.lastClaimAt) or 0
        if ts > latestTs then
            latestTs = ts
            latestKiller = killer
            latestClaim = claim
        end
    end
    if not latestKiller or not latestClaim then
        return nil, nil
    end

    local total = latestClaim.totalCopper or 0
    local paid = latestClaim.paidCopper or 0
    local payState = (total - paid) > 0 and "Unpaid" or "Paid"
    return latestKiller, payState
end

local function BountySummaryLabel(target)
    local mode = target.bountyMode or "none"
    local bountyAmount = target.bountyAmount or 0
    if mode == "none" or bountyAmount <= 0 then
        return "None"
    end

    local modeLabel = BountyModeValueLabel(mode)
    local status = target.bountyStatus or "open"
    if status == "claimed" then
        local killer, payState = LatestClaimSummary(target)
        if killer then
            local payToken = (payState == "Unpaid") and "unpaid" or "closed"
            return modeLabel .. " " .. GoldPipe() .. " Claimed by " .. killer .. " " .. GoldPipe() .. " " .. ColorizeBountyState(payState, payToken)
        end
        return modeLabel .. " " .. GoldPipe() .. " " .. ColorizeBountyState("Unpaid", "unpaid")
    end
    return modeLabel .. " " .. GoldPipe() .. " " .. ColorizeBountyState("Open", "open")
end

local function BuildClaimsText(target)
    local claims = target.bountyClaims or {}
    local lines = {}
    for killer, data in pairs(claims) do
        local total = data.totalCopper or 0
        local paid = data.paidCopper or 0
        local owed = math.max(0, total - paid)
        local status = owed > 0 and ("owed " .. Utils.GoldStringFromCopper(owed)) or "PAID"
        local line = killer .. ": " .. Utils.GoldStringFromCopper(total) .. " (" .. (data.claimCount or 0) .. " kill) - " .. status
        if paid > 0 and owed > 0 then
            line = line .. " (paid " .. Utils.GoldStringFromCopper(paid) .. ")"
        end
        table.insert(lines, line)
    end
    table.sort(lines)
    if #lines == 0 then return "None" end
    return table.concat(lines, "\n")
end

local function FormatBountyColumn(target)
    local amount = target.bountyAmount or 0
    if amount <= 0 then return "None" end
    local status = target.bountyStatus or "open"
    local allPaid = true
    if target.bountyClaims then
        for _, claim in pairs(target.bountyClaims) do
            if (claim.totalCopper or 0) - (claim.paidCopper or 0) > 0 then
                allPaid = false
                break
            end
        end
    end
    local label
    if status == "claimed" and allPaid then
        label = "Paid"
    elseif status == "claimed" then
        label = "Owed"
    else
        label = "Open"
    end
    return Utils.GoldStringFromCopper(amount) .. " (" .. label .. ")"
end

local function GetEnemyFaction()
    local myFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if myFaction == "Horde" then
        return "Alliance"
    end
    return "Horde"
end

local function GetDisplayFaction(target)
    if target and target.faction and target.faction ~= "" then
        return target.faction
    end
    return GetEnemyFaction()
end

local function BuildLocationDisplayParts(location)
    if type(location) ~= "table" then
        return nil, nil, true, false
    end

    local zone = location.zone
    local subzone = location.subzone
    if not zone or zone == "" then
        return nil, nil, true, false
    end

    local areaText = zone
    if subzone and subzone ~= "" and subzone ~= zone then
        areaText = subzone .. ", " .. zone
    end

    local x = tonumber(location.x)
    local y = tonumber(location.y)
    local coordsText = nil
    if x and y then
        coordsText = string.format("(%.1f, %.1f)", x * 100, y * 100)
    end

    return areaText, coordsText, false, location.approximate == true
end

local function BuildLastSeenListText(target)
    local areaText, coordsText, unknown, approximate = BuildLocationDisplayParts(target and target.lastKnownLocation)
    if unknown then
        return "Last seen location is unknown."
    end

    local prefix = approximate and "Approx. last seen at " or "Last seen at "
    if coordsText then
        return prefix .. areaText .. " " .. coordsText
    end
    return prefix .. areaText
end

local function FormatKillTimestamp(ts)
    local value = tonumber(ts)
    if not value or value <= 0 then
        return "-"
    end
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", value)
    if ok and formatted and formatted ~= "" then
        return formatted
    end
    return tostring(value)
end

local function BuildKillDetailsByKiller(target)
    if not target then
        return {}
    end

    local groups = {}
    local order = {}
    local claims = target.bountyClaims or {}
    local submitter = Utils.NormalizeName(target.submitter)

    for _, kill in ipairs(target.kills or {}) do
        local killer = Utils.NormalizeName(kill.killer) or kill.killer or "Unknown"
        if not groups[killer] then
            groups[killer] = {
                killer = killer,
                killCount = 0,
                lastKillTs = tonumber(kill.ts) or 0,
            }
            table.insert(order, killer)
        end
        local entry = groups[killer]
        entry.killCount = entry.killCount + 1
        local killTs = tonumber(kill.ts) or 0
        if killTs > (entry.lastKillTs or 0) then
            entry.lastKillTs = killTs
        end
    end

    local rowsOut = {}
    for _, killer in ipairs(order) do
        local entry = groups[killer]
        local claim = claims[killer]
        local totalCopper = claim and tonumber(claim.totalCopper) or 0
        local paidCopper = claim and tonumber(claim.paidCopper) or 0
        local ineligible = submitter and killer == submitter
        local claimed = (not ineligible) and totalCopper > 0
        local paid = claimed and paidCopper >= totalCopper

        table.insert(rowsOut, {
            killer = entry.killer,
            lastKillTs = entry.lastKillTs or 0,
            lastKillText = FormatKillTimestamp(entry.lastKillTs),
            killCount = entry.killCount or 0,
            ineligible = ineligible == true,
            claimed = claimed == true,
            paid = paid == true,
        })
    end

    table.sort(rowsOut, function(a, b)
        if (a.lastKillTs or 0) == (b.lastKillTs or 0) then
            if (a.killCount or 0) == (b.killCount or 0) then
                return (a.killer or "") < (b.killer or "")
            end
            return (a.killCount or 0) > (b.killCount or 0)
        end
        return (a.lastKillTs or 0) > (b.lastKillTs or 0)
    end)

    return rowsOut
end

local function SetRaceTexture(texture, target)
    local raceName = target and target.race or nil
    local raceId = target and target.raceId or nil
    local sex = target and target.sex or nil
    if Theme.SetRaceIcon then
        Theme.SetRaceIcon(texture, raceName, raceId, sex)
        return
    end
    texture:SetTexture(Theme.GetRaceIcon(raceName))
    texture:SetTexCoord(0, 1, 0, 1)
end

local function SetClassTexture(texture, classToken)
    if classToken and classToken ~= "" then
        Theme.SetClassIcon(texture, classToken)
    else
        texture:SetTexture(Theme.ICON.fallback)
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local CLASS_PICK_OPTIONS = {
    { text = "Warrior", value = "WARRIOR" },
    { text = "Mage", value = "MAGE" },
    { text = "Rogue", value = "ROGUE" },
    { text = "Druid", value = "DRUID" },
    { text = "Hunter", value = "HUNTER" },
    { text = "Shaman", value = "SHAMAN" },
    { text = "Priest", value = "PRIEST" },
    { text = "Warlock", value = "WARLOCK" },
    { text = "Paladin", value = "PALADIN" },
}

local RACES_BY_FACTION = {
    Alliance = { "Human", "Dwarf", "Night Elf", "Gnome", "Draenei" },
    Horde = { "Orc", "Undead", "Tauren", "Troll", "Blood Elf" },
}

local pickerMenuFrame = CreateFrame("Frame", "GUnitPickerMenuFrame", UIParent, "UIDropDownMenuTemplate")

local function ShowPickerMenu(options, onSelect)
    UIDropDownMenu_Initialize(pickerMenuFrame, function(_, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.func = function()
                onSelect(opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, pickerMenuFrame, "cursor", 0, 0)
end

local function SaveTargetAndBroadcast(target)
    Comm:BroadcastUpsert(target)
    GUnit:NotifyDataChanged()
end

local function ApplySubmitterOverride(targetName, submitterName)
    local updated, err = HitList:SetSubmitter(targetName, submitterName, Utils.PlayerName())
    if not updated then
        GUnit:Print(err)
        return false
    end
    SaveTargetAndBroadcast(updated)
    Comm:BroadcastReason(updated)
    return true
end

local function RequireSelectedTarget()
    if not UI.selectedName then
        GUnit:Print("Select a target first.")
        return nil
    end
    local target = HitList:Get(UI.selectedName)
    if not target then
        GUnit:Print("Target no longer exists.")
        UI.selectedName = nil
        UI:Refresh()
        return nil
    end
    return target
end

local function CommitEditModeFields()
    local target = RequireSelectedTarget()
    if not target then return end
    if not HitList:CanMutate(target, Utils.PlayerName()) then return end

    local latest = target
    local changed = false

    local newReason = (UI.reasonEdit and UI.reasonEdit:GetText()) or ""
    local reasonChanged = newReason ~= (latest.reason or "")
    if reasonChanged then
        local updated = HitList:SetReason(latest.name, newReason, Utils.PlayerName())
        if updated then
            latest = updated
            changed = true
        end
    end

    local gold = UI.bountyEdit and tonumber(UI.bountyEdit:GetText()) or nil
    if gold and gold >= 0 then
        local copper = gold * 10000
        if copper ~= (latest.bountyAmount or 0) then
            local updated = HitList:SetBountyAmount(latest.name, copper, Utils.PlayerName())
            if updated then
                latest = updated
                changed = true
                if copper > 0 then
                    MaybeAnnounce("Bounty on " .. Utils.TargetLabel(updated) .. " updated to " .. Utils.GoldStringFromCopper(copper) .. ".")
                end
            end
        end
    end

    if changed then
        SaveTargetAndBroadcast(latest)
    end
    if reasonChanged then
        Comm:BroadcastReason(latest)
    end
end

local function UpdateListPaneAnchor()
    listPane:ClearAllPoints()
    local topAnchor = guildInfoRow and guildInfoRow or contentArea
    local topPoint = guildInfoRow and "BOTTOMLEFT" or "TOPLEFT"
    listPane:SetPoint("TOPLEFT", topAnchor, topPoint, 0, guildInfoRow and -4 or 0)
    listPane:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT")
    if drawerWidth > 1 or drawerAnimating then
        listPane:SetPoint("RIGHT", contentArea, "RIGHT", -(drawerWidth + Theme.DRAWER_GAP), 0)
    else
        listPane:SetPoint("RIGHT", contentArea, "RIGHT", 0, 0)
    end
end

local function ApplyDrawerWidth(width)
    detailDrawer:ClearAllPoints()
    local topAnchor = guildInfoRow and guildInfoRow or contentArea
    local topPoint = guildInfoRow and "BOTTOMRIGHT" or "TOPRIGHT"
    detailDrawer:SetPoint("TOPRIGHT", topAnchor, topPoint, 0, guildInfoRow and -4 or 0)
    detailDrawer:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
    detailDrawer:SetWidth(Theme.DRAWER_WIDTH)
    local reveal = 0
    if Theme.DRAWER_WIDTH > 0 then
        reveal = math.max(0, math.min(width / Theme.DRAWER_WIDTH, 1))
    end
    detailDrawer:SetAlpha(reveal)
    UpdateListPaneAnchor()
end

local function StartDrawerAnimation(showDrawer)
    drawerIsOpen = showDrawer
    drawerTargetWidth = showDrawer and Theme.DRAWER_WIDTH or 0

    if showDrawer then
        detailDrawer:Show()
    end

    if drawerAnimating or not mainFrame then return end
    drawerAnimating = true

    mainFrame:SetScript("OnUpdate", function(_, elapsed)
        local speed = 14
        local t = math.min(1, elapsed * speed)
        drawerWidth = drawerWidth + (drawerTargetWidth - drawerWidth) * t
        ApplyDrawerWidth(drawerWidth)

        if math.abs(drawerTargetWidth - drawerWidth) < 0.5 then
            drawerWidth = drawerTargetWidth
            ApplyDrawerWidth(drawerWidth)
            drawerAnimating = false
            mainFrame:SetScript("OnUpdate", nil)
            if not drawerIsOpen then
                UpdateListPaneAnchor()
            end
        end
    end)
end

local function SetDrawerOpen(showDrawer)
    local settings = GetSettings()
    if settings.rememberDrawerState then
        settings.drawerOpen = showDrawer
    end
    StartDrawerAnimation(showDrawer)
end

local function CreateListRow(parent)
    local row = UIComponents.CreateRow(parent, 1)
    row:SetScript("OnClick", function(selfRow)
        if UI.reasonEdit and UI.reasonEdit:HasFocus() then
            UI.reasonEdit:ClearFocus()
        end
        UI.detailEditMode = false
        UI.selectedName = selfRow.name
        SetDrawerOpen(true)
        UI:RefreshList()
        UI:RefreshDetails()
    end)

    row.classIcon = UIComponents.CreateIcon(row, 16)
    row.classIcon:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.raceIcon = UIComponents.CreateIcon(row, 14)
    row.raceIcon:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)

    row.factionIcon = UIComponents.CreateIcon(row, 14)
    row.factionIcon:SetPoint("LEFT", row.raceIcon, "RIGHT", 4, 0)
    row.factionIcon:Hide()

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.raceIcon, "RIGHT", 8, 7)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -325, 0)

    row.subText = UIComponents.CreateMutedText(row, "GameFontNormalSmall")
    row.subText:SetPoint("LEFT", row.raceIcon, "RIGHT", 8, -7)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)
    row.subText:SetPoint("RIGHT", row, "RIGHT", -325, 0)

    row.submitterIcon = UIComponents.CreateIcon(row, 14)
    row.submitterIcon:SetTexture(Theme.ICON.submitter)
    row.submitterIcon:SetPoint("RIGHT", row, "RIGHT", -250, 0)

    row.submitterText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.submitterText:SetPoint("LEFT", row.submitterIcon, "RIGHT", 4, 0)
    row.submitterText:SetWidth(72)
    row.submitterText:SetJustifyH("LEFT")

    row.statusIcon = UIComponents.CreateIcon(row, 14)
    row.statusIcon:SetPoint("RIGHT", row, "RIGHT", -178, 0)

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("LEFT", row.statusIcon, "RIGHT", 4, 0)
    row.statusText:SetWidth(56)
    row.statusText:SetJustifyH("LEFT")

    row.bountyIcon = UIComponents.CreateIcon(row, 14)
    row.bountyIcon:SetTexture(Theme.ICON.bounty)
    row.bountyIcon:SetPoint("RIGHT", row, "RIGHT", -108, 0)

    row.bountyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bountyText:SetPoint("LEFT", row.bountyIcon, "RIGHT", 4, 0)
    row.bountyText:SetWidth(56)
    row.bountyText:SetJustifyH("LEFT")

    row.killIcon = UIComponents.CreateIcon(row, 14)
    row.killIcon:SetTexture(Theme.ICON.kill)
    row.killIcon:SetPoint("RIGHT", row, "RIGHT", -44, 0)

    row.killText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.killText:SetPoint("LEFT", row.killIcon, "RIGHT", 4, 0)
    row.killText:SetWidth(24)
    row.killText:SetJustifyH("LEFT")

    row:Hide()
    return row
end

local function EnsureRowCount(count)
    for i = #rows + 1, count do
        rows[i] = CreateListRow(listScrollChild)
    end
end

local function UpdateScrollLimits()
    local childHeight = math.max(1, #filteredNames * Theme.ROW_HEIGHT)
    listScrollChild:SetHeight(childHeight)
    local maxScroll = math.max(0, childHeight - listScrollFrame:GetHeight())
    local cur = listScrollFrame:GetVerticalScroll()
    if cur > maxScroll then
        listScrollFrame:SetVerticalScroll(maxScroll)
    end
end

local function ScrollList(delta)
    local childHeight = listScrollChild:GetHeight()
    local maxScroll = math.max(0, childHeight - listScrollFrame:GetHeight())
    local cur = listScrollFrame:GetVerticalScroll()
    local new = math.max(0, math.min(cur - (delta * Theme.ROW_HEIGHT), maxScroll))
    listScrollFrame:SetVerticalScroll(new)
end

local function BuildFilteredNames()
    local names = HitList:SortedNamesForCurrentGuild()
    local settings = GetSettings()
    filteredNames = {}
    for _, name in ipairs(names) do
        local target = HitList:Get(name)
        if target then
            local isClosed = target.hitStatus == "closed"
            if settings.showClosedHits or not isClosed then
                table.insert(filteredNames, name)
            end
        end
    end
end

local function UpdateGuildStatsLayout(self)
    if not self or not self.guildStatsGroup then return end
    if not self.guildiesIcon or not self.guildiesValueText then return end
    if not self.targetsIcon or not self.targetsValueText then return end
    if not self.bountyStatIcon or not self.bountyValueText then return end

    local iconWidth = 14
    local iconTextGap = 4
    local statGap = 20

    local guildiesValueWidth = math.max(8, self.guildiesValueText:GetStringWidth() or 8)
    local targetsValueWidth = math.max(8, self.targetsValueText:GetStringWidth() or 8)
    local bountyValueWidth = math.max(12, self.bountyValueText:GetStringWidth() or 12)

    local guildiesBlock = iconWidth + iconTextGap + guildiesValueWidth
    local targetsBlock = iconWidth + iconTextGap + targetsValueWidth
    local bountyBlock = iconWidth + iconTextGap + bountyValueWidth
    local totalWidth = guildiesBlock + statGap + targetsBlock + statGap + bountyBlock

    local cursor = -(totalWidth / 2)

    self.guildiesIcon:ClearAllPoints()
    self.guildiesIcon:SetPoint("LEFT", self.guildStatsGroup, "CENTER", cursor, 0)
    self.guildiesValueText:ClearAllPoints()
    self.guildiesValueText:SetPoint("LEFT", self.guildiesIcon, "RIGHT", iconTextGap, 0)
    cursor = cursor + guildiesBlock + statGap

    self.targetsIcon:ClearAllPoints()
    self.targetsIcon:SetPoint("LEFT", self.guildStatsGroup, "CENTER", cursor, 0)
    self.targetsValueText:ClearAllPoints()
    self.targetsValueText:SetPoint("LEFT", self.targetsIcon, "RIGHT", iconTextGap, 0)
    cursor = cursor + targetsBlock + statGap

    self.bountyStatIcon:ClearAllPoints()
    self.bountyStatIcon:SetPoint("LEFT", self.guildStatsGroup, "CENTER", cursor, 0)
    self.bountyValueText:ClearAllPoints()
    self.bountyValueText:SetPoint("LEFT", self.bountyStatIcon, "RIGHT", iconTextGap, 0)
end

local function PopulateListRow(row, target)
    if not row or not target then
        return
    end
    row.name = target.name
    SetClassTexture(row.classIcon, target.classToken)
    SetRaceTexture(row.raceIcon, target)
    row.factionIcon:SetTexture(Theme.GetFactionIcon(GetDisplayFaction(target)))
    row.factionIcon:Hide()

    row.nameText:SetText(Utils.ClassColorName(target.name or "Unknown", target.classToken))
    row.subText:SetText(BuildLastSeenListText(target))
    row.submitterText:SetText(target.submitter or "-")

    local status = target.hitStatus or "active"
    row.statusIcon:SetTexture(Theme.GetStatusIcon(status))
    local sc = Theme.GetStatusColor(status)
    row.statusText:SetTextColor(sc[1], sc[2], sc[3], sc[4])
    row.statusText:SetText(FormatStatusLabel(status))

    row.bountyText:SetText(Utils.GoldStringFromCopper(target.bountyAmount or 0))
    row.killText:SetText(tostring(target.killCount or 0))
end

function UI:RefreshList()
    BuildFilteredNames()

    if mainFrame and mainFrame.TitleText then
        mainFrame.TitleText:SetText("G-Unit")
    end
    if self.guildNameText then
        self.guildNameText:SetText(Utils.GuildName() or "No Guild")

        local guildies = GUnit.KnownAddonUserCountForCurrentGuild and GUnit:KnownAddonUserCountForCurrentGuild() or 0
        local targets = HitList:GetAllForCurrentGuild()
        local targetCount = 0
        local bountyTotal = 0
        for _, target in pairs(targets) do
            targetCount = targetCount + 1
            bountyTotal = bountyTotal + (target.bountyAmount or 0)
        end

        if self.guildiesValueText then
            self.guildiesValueText:SetText(tostring(guildies))
        end
        if self.targetsValueText then
            self.targetsValueText:SetText(tostring(targetCount))
        end
        if self.bountyValueText then
            self.bountyValueText:SetText(Utils.GoldStringFromCopper(bountyTotal))
        end
        UpdateGuildStatsLayout(self)
    end

    EnsureRowCount(#filteredNames)

    for i, row in ipairs(rows) do
        if i <= #filteredNames then
            local target = HitList:Get(filteredNames[i])
            if target then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listScrollChild, "TOPLEFT", 0, -((i - 1) * Theme.ROW_HEIGHT))
                row:SetPoint("RIGHT", listScrollChild, "RIGHT", 0, 0)
                PopulateListRow(row, target)
                local bgColor
                if self.selectedName and target.name == self.selectedName then
                    bgColor = SELECTED_ROW_BG
                else
                    bgColor = (i % 2 == 0) and Theme.COLOR.rowEven or Theme.COLOR.rowOdd
                end
                row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                row:Show()
            else
                row.name = nil
                row:Hide()
            end
        else
            row.name = nil
            row:Hide()
        end
    end

    if #filteredNames == 0 then
        emptyText:Show()
    else
        emptyText:Hide()
    end

    UpdateScrollLimits()
end

function UI:RefreshDetails()
    local target = self.selectedName and HitList:Get(self.selectedName) or nil
    if not target then
        self.detailEditMode = false
        self.detailNameText:SetText("No target selected")
        self.detailMetaText:SetText("")
        self.detailLocationLabel:SetText("Last Seen")
        self.detailLocationText:SetText("Location unknown")
        self.detailLocationCoords:SetText("")
        self.killDetailsSectionLabel:Hide()
        self.killDetailsHeader:Hide()
        self.killDetailsEmptyText:Hide()
        self.killDetailsMoreText:Hide()
        for _, row in ipairs(self.killDetailsRows or {}) do
            row:Hide()
        end
        self.detailModesValue:SetText("Select a target from the list.")
        self.detailBountyStatusValue:SetText("")
        self.detailBountyOwedLabel:Hide()
        self.detailBountyOwedValue:Hide()
        self.detailSummaryPanel:SetHeight(30)
        self.reasonReadOnlyLabel:Hide()
        self.reasonReadOnlyText:Hide()
        self.hitModeReadOnlyText:Hide()
        self.bountyAmountReadOnlyText:Hide()
        self.bountyModeReadOnlyText:Hide()
        self.reasonBg:Show()
        self.reasonScroll:Show()
        self.reasonEdit:Show()
        self.hitModeLabel:Show()
        self.bountyLabel:Show()
        self.bountyAmountIcon:Show()
        self.bountyModeIcon:Show()
        self.hitModeDropdown:Show()
        self.bountyEdit:Show()
        self.bountyModeDropdown:Show()
        if not self.reasonEdit:HasFocus() then
            self.reasonEdit:SetText("")
        end
        if not self.bountyEdit:HasFocus() then
            self.bountyEdit:SetText("")
        end
        UIDropDownMenu_SetText(self.hitModeDropdown, "Kill on Sight")
        UIDropDownMenu_SetText(self.bountyModeDropdown, "None")
        self.callOffButton:Hide()
        self.reopenButton:Hide()
        self.detailEditButton:Hide()
        self.detailClassPickButton:Hide()
        self.detailRacePickButton:Hide()
        self.detailSubmitterFixButton:Hide()
        self.drawerCloseButton:Hide()
        SetDrawerOpen(false)
        return
    end

    self.drawerCloseButton:Show()
    SetDrawerOpen(true)

    SetClassTexture(self.detailClassIcon, target.classToken)
    SetRaceTexture(self.detailRaceIcon, target)
    self.detailFactionIcon:SetTexture(Theme.GetFactionIcon(GetDisplayFaction(target)))
    self.detailNameText:SetText(Utils.ClassColorName(target.name or "Unknown", target.classToken))
    local submitterValue = target.submitter or "Unknown"
    local canMutate = HitList:CanMutate(target, Utils.PlayerName())
    local submitterUnknown = Utils.IsSubmitterUnknown(target)
    if submitterUnknown and canMutate then
        self.detailMetaText:SetText("Requested by " .. submitterValue .. " (click to set)")
        self.detailMetaText:SetTextColor(1.0, 0.85, 0.2, 1)
        self.detailSubmitterFixButton:Show()
    else
        self.detailMetaText:SetText("Requested by " .. submitterValue)
        self.detailMetaText:SetTextColor(unpack(Theme.COLOR.textMuted))
        self.detailSubmitterFixButton:Hide()
    end
    local areaText, coordsText, unknown, approximate = BuildLocationDisplayParts(target.lastKnownLocation)
    if unknown then
        self.detailLocationText:SetText("Location unknown")
        self.detailLocationText:SetTextColor(unpack(Theme.COLOR.textMuted))
        self.detailLocationCoords:SetText("")
    else
        self.detailLocationText:SetText((approximate and "Approx. " or "") .. areaText)
        self.detailLocationText:SetTextColor(0.9, 0.9, 0.9, 1)
        self.detailLocationCoords:SetText(coordsText or "")
        self.detailLocationCoords:SetTextColor(unpack(Theme.COLOR.textMuted))
    end

    self.detailStatusIcon:SetTexture(Theme.GetStatusIcon(target.hitStatus))
    self.detailStatusText:SetText(FormatStatusLabel(target.hitStatus))
    local statusColor = Theme.GetStatusColor(target.hitStatus)
    self.detailStatusText:SetTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4])
    self.detailKillsText:SetText(tostring(target.killCount or 0) .. " kills")
    self.detailBountyText:SetText(Utils.GoldStringFromCopper(target.bountyAmount or 0))
    local hitModeLabel = HitModeValueLabel(target)
    self.detailModesValue:SetText(hitModeLabel)
    self.detailBountyStatusValue:SetText(BountySummaryLabel(target))
    self.detailBountyStatusValue:SetTextColor(0.9, 0.9, 0.9, 1)

    self.detailBountyOwedLabel:Hide()
    self.detailBountyOwedValue:Hide()
    self.detailSummaryPanel:SetHeight(30)

    if not self.reasonEdit:HasFocus() then
        self.reasonEdit:SetText(target.reason or "")
    end
    if not self.bountyEdit:HasFocus() then
        self.bountyEdit:SetText(tostring(math.floor((target.bountyAmount or 0) / 10000)))
    end

    UIDropDownMenu_SetText(self.hitModeDropdown, hitModeLabel)

    local bountyModeLabels = { none = "None", first_kill = "One-time", infinite = "Indefinitely" }
    UIDropDownMenu_SetText(self.bountyModeDropdown, bountyModeLabels[target.bountyMode] or "None")

    if not canMutate then
        self.detailEditMode = false
    end
    local editMode = canMutate and self.detailEditMode == true

    if canMutate then
        self.detailEditButton:Show()
        self.detailEditButton:SetText(editMode and "Save" or "Edit")
    else
        self.detailEditButton:Hide()
    end

    local reasonValue = (target.reason and target.reason ~= "") and target.reason or "No reason provided."
    self.reasonReadOnlyText:SetText(reasonValue)

    if editMode then
        self.detailSummaryPanel:Show()
        self.reasonReadOnlyLabel:Hide()
        self.reasonReadOnlyText:Hide()
        self.reasonBg:Show()
        self.detailModesLabel:Hide()
        self.detailModesValue:Hide()
        self.detailBountyStatusLabel:Hide()
        self.detailBountyStatusValue:Hide()

        -- Edit layout: explicit top-down anchors to avoid circular dependencies.
        self.hitModeLabel:ClearAllPoints()
        self.hitModeLabel:SetPoint("TOPLEFT", self.detailSummaryPanel, "TOPLEFT", 0, 0)
        self.hitModeDropdown:ClearAllPoints()
        self.hitModeDropdown:SetPoint("TOPLEFT", self.hitModeLabel, "BOTTOMLEFT", -16, -2)

        self.bountyLabel:ClearAllPoints()
        self.bountyLabel:SetPoint("TOPLEFT", self.hitModeDropdown, "BOTTOMLEFT", 16, -12)
        self.bountyAmountIcon:ClearAllPoints()
        self.bountyAmountIcon:SetPoint("LEFT", self.bountyLabel, "LEFT", 2, -20)
        self.bountyEdit:ClearAllPoints()
        self.bountyEdit:SetPoint("LEFT", self.bountyAmountIcon, "RIGHT", 12, 0)
        self.bountyModeIcon:ClearAllPoints()
        self.bountyModeIcon:SetPoint("LEFT", self.bountyAmountIcon, "LEFT", 0, -34)
        self.bountyModeDropdown:ClearAllPoints()
        self.bountyModeDropdown:SetPoint("TOPLEFT", self.bountyEdit, "BOTTOMLEFT", -20, -10)

        self.hitModeLabel:Show()
        self.bountyLabel:Show()
        self.reasonLabel:Show()
        self.bountyAmountIcon:Show()
        self.bountyModeIcon:Show()
        self.hitModeDropdown:Show()
        self.bountyEdit:Show()
        self.bountyModeDropdown:Show()
        self.reasonScroll:Show()
        self.reasonEdit:Show()

        self.reasonLabel:ClearAllPoints()
        self.reasonLabel:SetPoint("TOPLEFT", self.bountyLabel, "BOTTOMLEFT", 0, -66)
        self.reasonScroll:ClearAllPoints()
        self.reasonScroll:SetPoint("TOPLEFT", self.reasonLabel, "BOTTOMLEFT", 0, -6)
    else
        self.detailSummaryPanel:Show()
        self.reasonReadOnlyLabel:Hide()
        self.detailModesLabel:Show()
        self.detailModesValue:Show()
        self.detailBountyStatusLabel:Show()
        self.detailBountyStatusValue:Show()
        self.reasonReadOnlyText:Show()

        self.hitModeLabel:Hide()
        self.bountyLabel:Hide()
        self.bountyAmountIcon:Hide()
        self.bountyModeIcon:Hide()
        self.hitModeDropdown:Hide()
        self.bountyEdit:Hide()
        self.bountyModeDropdown:Hide()
        self.reasonBg:Hide()
        self.reasonScroll:Hide()
        self.reasonEdit:Hide()
        self.reasonLabel:Hide()

        -- Restore original anchors for reasonLabel/reasonScroll so the chain
        -- hitModeLabel → reasonScroll → reasonLabel doesn't cycle back through
        -- bountyLabel → hitModeDropdown → hitModeLabel (edit-mode leftovers).
        self.reasonLabel:ClearAllPoints()
        self.reasonLabel:SetPoint("TOPLEFT", self.detailSummaryPanel, "BOTTOMLEFT", 0, -2)
        self.reasonScroll:ClearAllPoints()
        self.reasonScroll:SetPoint("TOPLEFT", self.reasonLabel, "BOTTOMLEFT", 0, -6)

        -- Restore readonly anchors.
        self.hitModeLabel:ClearAllPoints()
        self.hitModeLabel:SetPoint("TOPLEFT", self.reasonScroll, "BOTTOMLEFT", 2, -12)
        self.hitModeDropdown:ClearAllPoints()
        self.hitModeDropdown:SetPoint("TOPLEFT", self.hitModeLabel, "BOTTOMLEFT", -16, -2)
        self.bountyLabel:ClearAllPoints()
        self.bountyLabel:SetPoint("TOPLEFT", self.hitModeDropdown, "BOTTOMLEFT", 16, -12)
        self.bountyAmountIcon:ClearAllPoints()
        self.bountyAmountIcon:SetPoint("LEFT", self.bountyLabel, "LEFT", 2, -20)
        self.bountyEdit:ClearAllPoints()
        self.bountyEdit:SetPoint("LEFT", self.bountyAmountIcon, "RIGHT", 12, 0)
        self.bountyModeIcon:ClearAllPoints()
        self.bountyModeIcon:SetPoint("LEFT", self.bountyAmountIcon, "LEFT", 0, -34)
        self.bountyModeDropdown:ClearAllPoints()
        self.bountyModeDropdown:SetPoint("TOPLEFT", self.bountyEdit, "BOTTOMLEFT", -20, -10)

        -- Ensure readonly reason section is always restored after Save.
        self.reasonReadOnlyText:Show()
        self.reasonReadOnlyText:SetAlpha(1)
        self.reasonReadOnlyText:ClearAllPoints()
        self.reasonReadOnlyText:SetPoint("TOPLEFT", self.detailSummaryPanel, "BOTTOMLEFT", 0, -2)
        self.reasonReadOnlyText:SetPoint("RIGHT", detailDrawer, "RIGHT", -24, 0)
        self.reasonReadOnlyText:SetText("|cFFFFD100Reason|r  " .. reasonValue)
    end

    -- Kill details visible in both modes; anchor depends on layout.
    self.killDetailsSectionLabel:Show()
    self.killDetailsSectionLabel:SetAlpha(1)
    self.killDetailsSectionLabel:ClearAllPoints()
    if editMode then
        self.killDetailsSectionLabel:SetPoint("TOPLEFT", self.reasonScroll, "BOTTOMLEFT", 0, -14)
    else
        self.killDetailsSectionLabel:SetPoint("TOPLEFT", self.reasonReadOnlyText, "BOTTOMLEFT", 0, -14)
    end

    self.killDetailsHeader:ClearAllPoints()
    self.killDetailsHeader:SetPoint("TOPLEFT", self.killDetailsSectionLabel, "BOTTOMLEFT", 0, -6)
    self.killDetailsHeader:Show()
    self.killDetailsHeader:SetAlpha(1)

    local canTogglePaid = editMode and canMutate
    local groupedKills = BuildKillDetailsByKiller(target)
    local shownCount = math.min(#groupedKills, MAX_KILL_DETAIL_ROWS)

    if #groupedKills == 0 then
        self.killDetailsEmptyText:ClearAllPoints()
        self.killDetailsEmptyText:SetPoint("TOPLEFT", self.killDetailsHeader, "BOTTOMLEFT", 0, -6)
        self.killDetailsEmptyText:SetText("No kills recorded for this target yet.")
        self.killDetailsEmptyText:Show()
        self.killDetailsMoreText:Hide()
        for _, row in ipairs(self.killDetailsRows) do
            row:Hide()
        end
    else
        self.killDetailsEmptyText:Hide()
        local lastAnchor = self.killDetailsHeader
        for i, row in ipairs(self.killDetailsRows) do
            if i <= shownCount then
                local item = groupedKills[i]
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -2)
                row:SetPoint("RIGHT", self.killDetailsHeader, "RIGHT", 0, 0)
                row.killerText:SetText(item.killer or "-")
                row.whenText:SetText(item.lastKillText or "-")
                row.killsText:SetText(tostring(item.killCount or 0))

                row._killerName = item.killer

                local claimedIcon = item.ineligible and "✗" or (item.claimed and "✓" or "✗")
                local paidIcon = item.ineligible and "✗" or (item.claimed and (item.paid and "✓" or "✗") or "✗")
                row.claimedText:SetText(claimedIcon)

                if canTogglePaid and item.claimed and not item.ineligible then
                    row.paidText:Hide()
                    row.paidButton.label:SetText(paidIcon)
                    row.paidButton:Show()
                else
                    row.paidButton:Hide()
                    row.paidText:SetText(paidIcon)
                    row.paidText:Show()
                end

                row:Show()
                lastAnchor = row
            else
                row:Hide()
            end
        end

        if #groupedKills > shownCount then
            self.killDetailsMoreText:ClearAllPoints()
            self.killDetailsMoreText:SetPoint("TOPLEFT", self.killDetailsRows[shownCount], "BOTTOMLEFT", 0, -4)
            self.killDetailsMoreText:SetText("+" .. tostring(#groupedKills - shownCount) .. " more killers...")
            self.killDetailsMoreText:Show()
        else
            self.killDetailsMoreText:Hide()
        end
    end

    local isActive = target.hitStatus == "active"
    if canMutate and isActive then
        self.callOffButton:Show()
    else
        self.callOffButton:Hide()
    end
    if canMutate and not isActive then
        self.reopenButton:Show()
    else
        self.reopenButton:Hide()
    end

    local allowManualPick = canMutate and (target.validated ~= true)
    if allowManualPick then
        self.detailClassPickButton:Enable()
        self.detailRacePickButton:Enable()
        self.detailClassPickButton:Show()
        self.detailRacePickButton:Show()
    else
        self.detailClassPickButton:Disable()
        self.detailRacePickButton:Disable()
        self.detailClassPickButton:Hide()
        self.detailRacePickButton:Hide()
    end
end

function UI:Refresh()
    if not self.frame then return end
    self:RefreshList()
    self:RefreshDetails()
end

local optionsTabs = {}
local optionsSelectedTab = "general"

local OPT_TEX_ACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab"
local OPT_TEX_INACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab"
local OPT_TEX_HIGHLIGHT = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"
local OPT_TC_LEFT = { 0, 0.15625, 0, 1.0 }
local OPT_TC_MID = { 0.15625, 0.84375, 0, 1.0 }
local OPT_TC_RIGHT = { 0.84375, 1.0, 0, 1.0 }
local OPT_CAP_WIDTH = 20
local OPTION_TAB_DEFS = {
    { key = "general", label = "General", width = 110 },
    { key = "export", label = "Export", width = 100 },
    { key = "import", label = "Import", width = 100 },
}

local function CreateOptionsTabTexPiece(tab, name, texture, width, anchor, relFrame, relPoint, xOff, yOff, tc)
    local tex = tab:CreateTexture(name, "BORDER")
    tex:SetTexture(texture)
    tex:SetSize(width, 24)
    tex:SetPoint(anchor, relFrame, relPoint, xOff or 0, yOff or 0)
    tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    return tex
end

local function UpdateOptionsTabStyles()
    for _, tab in ipairs(optionsTabs) do
        local isSelected = tab.key == optionsSelectedTab
        if isSelected then
            tab.activeL:Show()
            tab.activeM:Show()
            tab.activeR:Show()
            tab.inactiveL:Hide()
            tab.inactiveM:Hide()
            tab.inactiveR:Hide()
            tab.label:SetTextColor(1.0, 0.82, 0.0)
        else
            tab.activeL:Hide()
            tab.activeM:Hide()
            tab.activeR:Hide()
            tab.inactiveL:Show()
            tab.inactiveM:Show()
            tab.inactiveR:Show()
            tab.label:SetTextColor(0.85, 0.85, 0.85)
        end
    end
end

local function ShowOptionsTab(self, tabKey)
    if not self.optionsGeneralPane or not self.optionsExportPane or not self.optionsImportPane then
        return
    end

    optionsSelectedTab = tabKey or "general"
    self.optionsGeneralPane:Hide()
    self.optionsExportPane:Hide()
    self.optionsImportPane:Hide()

    if optionsSelectedTab == "general" then
        self.optionsGeneralPane:Show()
    elseif optionsSelectedTab == "export" then
        self.optionsExportPane:Show()
        if self.optionsExportEdit then
            local data = HitList:ExportCurrentGuild()
            if not data or data == "" then
                data = "No hits to export for current guild."
            end
            self._optionsExportStaticText = data
            self._optionsExportSyncing = true
            self.optionsExportEdit:SetText(data)
            self._optionsExportSyncing = false
            self.optionsExportEdit:HighlightText()
            self.optionsExportEdit:SetCursorPosition(0)
            self.optionsExportEdit:SetFocus()
        end
    else
        self.optionsImportPane:Show()
        if self.optionsImportEdit then
            self.optionsImportEdit:SetFocus()
        end
    end

    UpdateOptionsTabStyles()
end

local function CreateLabeledCheckButton(parent, label, anchorTo, relPoint, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchorTo, relPoint or "BOTTOMLEFT", x or 0, y or 0)
    cb.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    return cb
end

function UI:ShowOptionsModal()
    if self.optionsFrame then
        self.optionsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        self.optionsFrame:SetFrameLevel(mainFrame and (mainFrame:GetFrameLevel() + 50) or 200)
        self.optionsFrame:Show()
        self.optionsFrame:Raise()
        ShowOptionsTab(self, optionsSelectedTab)
        return
    end

    local frame = CreateFrame("Frame", "GUnitOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(560, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(mainFrame and (mainFrame:GetFrameLevel() + 50) or 200)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    UIComponents.StyleInset(frame)
    frame:SetBackdropColor(0, 0, 0, 0.96)
    self.optionsFrame = frame
    tinsert(UISpecialFrames, "GUnitOptionsFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("G-Unit Options")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -32)
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -32)
    tabBar:SetHeight(24)

    optionsTabs = {}
    local prevTab
    for _, def in ipairs(OPTION_TAB_DEFS) do
        local tab = CreateFrame("Button", nil, tabBar)
        tab:SetSize(def.width, 24)
        tab.key = def.key
        tab:SetFrameLevel(frame:GetFrameLevel() + 4)
        if prevTab then
            tab:SetPoint("LEFT", prevTab, "RIGHT", -10, 0)
        else
            tab:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, 0)
        end

        local midWidth = def.width - (OPT_CAP_WIDTH * 2)
        tab.activeL = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_ACTIVE, OPT_CAP_WIDTH, "BOTTOMLEFT", tab, "BOTTOMLEFT", 0, -3, OPT_TC_LEFT)
        tab.activeM = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_ACTIVE, midWidth, "LEFT", tab.activeL, "RIGHT", 0, 0, OPT_TC_MID)
        tab.activeR = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_ACTIVE, OPT_CAP_WIDTH, "LEFT", tab.activeM, "RIGHT", 0, 0, OPT_TC_RIGHT)
        tab.inactiveL = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_INACTIVE, OPT_CAP_WIDTH, "TOPLEFT", tab, "TOPLEFT", 0, 0, OPT_TC_LEFT)
        tab.inactiveM = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_INACTIVE, midWidth, "LEFT", tab.inactiveL, "RIGHT", 0, 0, OPT_TC_MID)
        tab.inactiveR = CreateOptionsTabTexPiece(tab, nil, OPT_TEX_INACTIVE, OPT_CAP_WIDTH, "LEFT", tab.inactiveM, "RIGHT", 0, 0, OPT_TC_RIGHT)
        tab.activeL:Hide()
        tab.activeM:Hide()
        tab.activeR:Hide()

        tab:SetHighlightTexture(OPT_TEX_HIGHLIGHT, "ADD")
        local hl = tab:GetHighlightTexture()
        hl:ClearAllPoints()
        hl:SetPoint("LEFT", tab, "LEFT", 10, -4)
        hl:SetPoint("RIGHT", tab, "RIGHT", -10, -4)

        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.label:SetPoint("LEFT", 14, -3)
        tab.label:SetPoint("RIGHT", -12, -3)
        tab.label:SetText(def.label)
        tab:SetScript("OnClick", function()
            ShowOptionsTab(self, def.key)
        end)

        table.insert(optionsTabs, tab)
        prevTab = tab
    end

    local generalPane = CreateFrame("Frame", nil, frame)
    generalPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    generalPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    self.optionsGeneralPane = generalPane

    local exportPane = CreateFrame("Frame", nil, frame)
    exportPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    exportPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    exportPane:Hide()
    self.optionsExportPane = exportPane

    local importPane = CreateFrame("Frame", nil, frame)
    importPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    importPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    importPane:Hide()
    self.optionsImportPane = importPane

    local settings = GetSettings()

    local leftCol = CreateFrame("Frame", nil, generalPane)
    leftCol:SetPoint("TOPLEFT", generalPane, "TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", generalPane, "BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(250)

    local rightCol = CreateFrame("Frame", nil, generalPane)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 10, 0)
    rightCol:SetPoint("TOPRIGHT", generalPane, "TOPRIGHT", 0, 0)
    rightCol:SetPoint("BOTTOMRIGHT", generalPane, "BOTTOMRIGHT", 0, 0)

    local modeLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", 8, -10)
    modeLabel:SetText("Default Kill on Sight")

    local modeDD = CreateFrame("Frame", "GUnitDefaultModeDD", leftCol, "UIDropDownMenuTemplate")
    modeDD:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(modeDD, 120)
    UIDropDownMenu_Initialize(modeDD, function(dropdown, level)
        local options = {
            { text = "One-time", value = "one_time" },
            { text = "Indefinitely", value = "kos" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                settings.defaultHitMode = btn.value
                UIDropDownMenu_SetText(dropdown, btn:GetText())
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(modeDD, settings.defaultHitMode == "kos" and "Indefinitely" or "One-time")

    local bountyLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bountyLabel:SetPoint("TOPLEFT", modeDD, "BOTTOMLEFT", 16, -16)
    bountyLabel:SetText("Default Bounty (gold)")

    local bountyEdit = CreateFrame("EditBox", nil, leftCol, "InputBoxTemplate")
    bountyEdit:SetPoint("TOPLEFT", bountyLabel, "BOTTOMLEFT", 0, -8)
    bountyEdit:SetSize(100, 22)
    bountyEdit:SetAutoFocus(false)
    bountyEdit:SetNumeric(true)
    bountyEdit:SetText(tostring(settings.defaultBountyGold or 0))
    bountyEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    bountyEdit:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    bountyEdit:SetScript("OnEditFocusLost", function()
        local val = tonumber(bountyEdit:GetText()) or 0
        settings.defaultBountyGold = math.max(0, val)
        bountyEdit:SetText(tostring(settings.defaultBountyGold))
    end)

    local bountyModeLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bountyModeLabel:SetPoint("TOPLEFT", bountyEdit, "BOTTOMLEFT", 0, -16)
    bountyModeLabel:SetText("Default Bounty Mode")

    local bountyModeDD = CreateFrame("Frame", "GUnitDefaultBountyModeDD", leftCol, "UIDropDownMenuTemplate")
    bountyModeDD:SetPoint("TOPLEFT", bountyModeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(bountyModeDD, 120)
    UIDropDownMenu_Initialize(bountyModeDD, function(dropdown, level)
        local options = {
            { text = "None", value = "none" },
            { text = "One-time", value = "first_kill" },
            { text = "Indefinitely", value = "infinite" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                settings.defaultBountyMode = btn.value
                UIDropDownMenu_SetText(dropdown, btn:GetText())
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local modeLabels = { none = "None", first_kill = "One-time", infinite = "Indefinitely" }
    UIDropDownMenu_SetText(bountyModeDD, modeLabels[settings.defaultBountyMode] or "None")

    local showClosed = CreateLabeledCheckButton(
        rightCol,
        "Show closed hits",
        rightCol,
        "TOPLEFT",
        6,
        -12
    )
    showClosed:SetChecked(settings.showClosedHits)
    showClosed:SetScript("OnClick", function(selfBtn)
        settings.showClosedHits = selfBtn:GetChecked() and true or false
        UI:Refresh()
    end)

    local rememberDrawer = CreateLabeledCheckButton(
        rightCol,
        "Remember drawer open/closed",
        showClosed,
        "BOTTOMLEFT",
        0,
        -10
    )
    rememberDrawer:SetChecked(settings.rememberDrawerState)
    rememberDrawer:SetScript("OnClick", function(selfBtn)
        settings.rememberDrawerState = selfBtn:GetChecked() and true or false
    end)

    local announceToggle = CreateLabeledCheckButton(
        rightCol,
        "Guild announcements for UI updates",
        rememberDrawer,
        "BOTTOMLEFT",
        0,
        -10
    )
    announceToggle:SetChecked(settings.uiGuildAnnouncements)
    announceToggle:SetScript("OnClick", function(selfBtn)
        settings.uiGuildAnnouncements = selfBtn:GetChecked() and true or false
    end)

    local partyToggle = CreateLabeledCheckButton(
        rightCol,
        "Party announcements",
        announceToggle,
        "BOTTOMLEFT",
        0,
        -10
    )
    partyToggle:SetChecked(settings.partyAnnouncements)
    partyToggle:SetScript("OnClick", function(selfBtn)
        settings.partyAnnouncements = selfBtn:GetChecked() and true or false
    end)

    local debugToggle = CreateLabeledCheckButton(
        rightCol,
        "Debug logging (sync diagnostics)",
        partyToggle,
        "BOTTOMLEFT",
        0,
        -10
    )
    debugToggle:SetChecked(settings.debugMode)
    debugToggle:SetScript("OnClick", function(selfBtn)
        settings.debugMode = selfBtn:GetChecked() and true or false
        GUnit:Print("Debug mode: " .. (settings.debugMode and "ON" or "OFF"))
    end)

    local exportHelp = exportPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportHelp:SetPoint("TOPLEFT", exportPane, "TOPLEFT", 8, -10)
    exportHelp:SetText("Export data (Ctrl+C).")
    exportHelp:SetTextColor(unpack(Theme.COLOR.textMuted))

    local exportScroll = CreateFrame("ScrollFrame", "GUnitOptionsExportScroll", exportPane, "UIPanelScrollFrameTemplate")
    exportScroll:SetPoint("TOPLEFT", exportPane, "TOPLEFT", 6, -30)
    exportScroll:SetPoint("BOTTOMRIGHT", exportPane, "BOTTOMRIGHT", -24, 10)
    local exportEdit = CreateFrame("EditBox", "GUnitOptionsExportEdit", exportScroll)
    exportEdit:SetMultiLine(true)
    exportEdit:SetFontObject("ChatFontNormal")
    exportEdit:SetWidth(500)
    exportEdit:SetAutoFocus(false)
    exportEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    exportEdit:SetScript("OnEditFocusGained", function(selfEdit)
        selfEdit:HighlightText()
    end)
    exportEdit:SetScript("OnTextChanged", function(selfEdit)
        if UI._optionsExportSyncing then return end
        if UI._optionsExportStaticText and selfEdit:GetText() ~= UI._optionsExportStaticText then
            UI._optionsExportSyncing = true
            selfEdit:SetText(UI._optionsExportStaticText)
            UI._optionsExportSyncing = false
            selfEdit:HighlightText()
        end
    end)
    exportScroll:SetScrollChild(exportEdit)
    self.optionsExportEdit = exportEdit

    local importHelp = importPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importHelp:SetPoint("TOPLEFT", importPane, "TOPLEFT", 8, -10)
    importHelp:SetText("Paste export data below and click Import.")
    importHelp:SetTextColor(unpack(Theme.COLOR.textMuted))

    local importScroll = CreateFrame("ScrollFrame", "GUnitOptionsImportScroll", importPane, "UIPanelScrollFrameTemplate")
    importScroll:SetPoint("TOPLEFT", importPane, "TOPLEFT", 6, -30)
    importScroll:SetPoint("BOTTOMRIGHT", importPane, "BOTTOMRIGHT", -24, 44)
    local importEdit = CreateFrame("EditBox", "GUnitOptionsImportEdit", importScroll)
    importEdit:SetMultiLine(true)
    importEdit:SetFontObject("ChatFontNormal")
    importEdit:SetWidth(500)
    importEdit:SetAutoFocus(false)
    importEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    importScroll:SetScrollChild(importEdit)
    self.optionsImportEdit = importEdit

    local importBtn = UIComponents.CreateButton(importPane, "Import", 100, 24)
    importBtn:SetPoint("BOTTOMRIGHT", importPane, "BOTTOMRIGHT", -4, 10)
    importBtn:SetScript("OnClick", function()
        local text = UI.optionsImportEdit and UI.optionsImportEdit:GetText() or ""
        local count = HitList:ImportFromString(text)
        GUnit:Print("Imported " .. count .. " hit(s).")
        GUnit:NotifyDataChanged()
        if UI.optionsImportEdit then
            UI.optionsImportEdit:SetText("")
            UI.optionsImportEdit:SetFocus()
        end
    end)

    ShowOptionsTab(self, optionsSelectedTab)
end

function UI:Init()
    if self.frame then return end

    mainFrame = CreateFrame("Frame", "GUnitMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(Theme.FRAME_WIDTH, Theme.FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetToplevel(true)
    mainFrame.TitleText:SetText("G-Unit")
    mainFrame:SetScript("OnHide", function()
        UI._ignoreFocusSave = true
        if UI.reasonEdit and UI.reasonEdit:HasFocus() then
            UI.reasonEdit:ClearFocus()
        end
        if UI.bountyEdit and UI.bountyEdit:HasFocus() then
            UI.bountyEdit:ClearFocus()
        end
        if UI.optionsImportEdit and UI.optionsImportEdit:HasFocus() then
            UI.optionsImportEdit:ClearFocus()
        end
        if UI.optionsExportEdit and UI.optionsExportEdit:HasFocus() then
            UI.optionsExportEdit:ClearFocus()
        end
        UI._ignoreFocusSave = false
        UI._reasonEditingName = nil
        UI.detailEditMode = false
        UI.selectedName = nil
        drawerIsOpen = false
        drawerAnimating = false
        drawerTargetWidth = 0
        drawerWidth = 0
        if mainFrame then
            mainFrame:SetScript("OnUpdate", nil)
        end
        if detailDrawer and listPane then
            ApplyDrawerWidth(0)
        end
    end)
    mainFrame:Hide()
    self.frame = mainFrame

    tinsert(UISpecialFrames, "GUnitMainFrame")

    contentArea = CreateFrame("Frame", nil, mainFrame)
    contentArea:SetPoint("TOPLEFT", mainFrame.InsetBg, "TOPLEFT", 6, -6)
    contentArea:SetPoint("BOTTOMRIGHT", mainFrame.InsetBg, "BOTTOMRIGHT", -6, 6)

    guildInfoRow = CreateFrame("Frame", nil, contentArea)
    guildInfoRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT")
    guildInfoRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT")
    guildInfoRow:SetHeight(22)

    self.guildNameText = guildInfoRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.guildNameText:SetPoint("LEFT", guildInfoRow, "LEFT", 2, 0)
    self.guildNameText:SetTextColor(1, 0.82, 0.0, 1)
    self.guildNameText:SetJustifyH("LEFT")

    self.gearButton = CreateFrame("Button", nil, guildInfoRow)
    self.gearButton:SetSize(20, 20)
    self.gearButton:SetPoint("RIGHT", guildInfoRow, "RIGHT", -2, 0)
    self.gearButton:SetFrameLevel(mainFrame:GetFrameLevel() + 15)
    self.gearButton:EnableMouse(true)
    self.gearButton.tex = self.gearButton:CreateTexture(nil, "ARTWORK")
    self.gearButton.tex:SetAllPoints()
    self.gearButton.tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    self.gearButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    self.gearButton:SetScript("OnClick", function()
        UI:ShowOptionsModal()
    end)

    self.guildStatsGroup = CreateFrame("Frame", nil, guildInfoRow)
    self.guildStatsGroup:SetSize(320, 20)
    self.guildStatsGroup:SetPoint("CENTER", guildInfoRow, "CENTER", 0, 0)

    self.guildiesIcon = self.guildStatsGroup:CreateTexture(nil, "ARTWORK")
    self.guildiesIcon:SetSize(14, 14)
    self.guildiesIcon:SetPoint("LEFT", self.guildStatsGroup, "LEFT", 0, 0)
    self.guildiesIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")

    self.guildiesValueText = self.guildStatsGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.guildiesValueText:SetPoint("LEFT", self.guildiesIcon, "RIGHT", 4, 0)
    self.guildiesValueText:SetTextColor(1, 0.82, 0.0, 1)
    self.guildiesValueText:SetText("0")

    self.targetsIcon = self.guildStatsGroup:CreateTexture(nil, "ARTWORK")
    self.targetsIcon:SetSize(14, 14)
    self.targetsIcon:SetPoint("LEFT", self.guildiesValueText, "RIGHT", 24, 0)
    self.targetsIcon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")

    self.targetsValueText = self.guildStatsGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.targetsValueText:SetPoint("LEFT", self.targetsIcon, "RIGHT", 4, 0)
    self.targetsValueText:SetTextColor(1, 0.82, 0.0, 1)
    self.targetsValueText:SetText("0")

    self.bountyStatIcon = self.guildStatsGroup:CreateTexture(nil, "ARTWORK")
    self.bountyStatIcon:SetSize(14, 14)
    self.bountyStatIcon:SetPoint("LEFT", self.targetsValueText, "RIGHT", 24, 0)
    self.bountyStatIcon:SetTexture(Theme.ICON.bounty)

    self.bountyValueText = self.guildStatsGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.bountyValueText:SetPoint("LEFT", self.bountyStatIcon, "RIGHT", 4, 0)
    self.bountyValueText:SetTextColor(1, 0.82, 0.0, 1)
    self.bountyValueText:SetText("0g")

    self.guildNameText:SetPoint("RIGHT", self.guildStatsGroup, "LEFT", -16, 0)

    listPane = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    UIComponents.StylePanel(listPane)

    local listHeader = UIComponents.CreateHeader(listPane, "Kill Targets")
    listHeader:SetPoint("TOPLEFT")
    listHeader:SetPoint("TOPRIGHT")

    listScrollFrame = CreateFrame("ScrollFrame", nil, listPane)
    listScrollFrame:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 6, -6)
    listScrollFrame:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -6, 6)
    listScrollFrame:EnableMouseWheel(true)
    listScrollFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollList(delta)
    end)

    listScrollChild = CreateFrame("Frame")
    listScrollChild:SetWidth(math.max(1, listScrollFrame:GetWidth()))
    listScrollChild:SetHeight(1)
    listScrollFrame:SetScrollChild(listScrollChild)
    listScrollFrame:SetScript("OnSizeChanged", function(selfFrame, w)
        listScrollChild:SetWidth(math.max(1, w))
        UpdateScrollLimits()
    end)

    emptyText = UIComponents.CreateMutedText(listScrollChild, "GameFontNormal")
    emptyText:SetPoint("TOP", listScrollChild, "TOP", 0, -40)
    emptyText:SetText("No hit targets for current guild.")
    emptyText:Hide()

    detailDrawer = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    UIComponents.StylePanel(detailDrawer)
    detailDrawer:Show()
    detailDrawer:SetFrameLevel(contentArea:GetFrameLevel() + 1)
    listPane:SetFrameLevel(detailDrawer:GetFrameLevel() + 2)

    local drawerHeader = UIComponents.CreateHeader(detailDrawer, "Target Details")
    drawerHeader:SetPoint("TOPLEFT")
    drawerHeader:SetPoint("TOPRIGHT")

    self.drawerCloseButton = UIComponents.CreateButton(drawerHeader, "X", 30, 20)
    self.drawerCloseButton:SetPoint("RIGHT", drawerHeader, "RIGHT", -6, 0)
    self.drawerCloseButton:SetScript("OnClick", function()
        if UI.reasonEdit and UI.reasonEdit:HasFocus() then
            UI.reasonEdit:ClearFocus()
        end
        UI.selectedName = nil
        UI:RefreshList()
        UI:RefreshDetails()
    end)
    self.drawerCloseButton:Hide()

    self.detailClassIcon = UIComponents.CreateIcon(detailDrawer, 20)
    self.detailClassIcon:SetPoint("TOPLEFT", drawerHeader, "BOTTOMLEFT", 10, -10)

    self.detailClassPickButton = CreateFrame("Button", nil, detailDrawer)
    self.detailClassPickButton:SetSize(20, 20)
    self.detailClassPickButton:SetPoint("TOPLEFT", drawerHeader, "BOTTOMLEFT", 10, -10)
    self.detailClassPickButton:RegisterForClicks("LeftButtonUp")
    self.detailClassPickButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target or target.validated == true or not HitList:CanMutate(target, Utils.PlayerName()) then
            return
        end
        ShowPickerMenu(CLASS_PICK_OPTIONS, function(classToken)
            target.classToken = classToken
            target.updatedAt = Utils.Now()
            SaveTargetAndBroadcast(target)
        end)
    end)

    self.detailRaceIcon = UIComponents.CreateIcon(detailDrawer, 18)
    self.detailRaceIcon:SetPoint("LEFT", self.detailClassIcon, "RIGHT", 4, 0)

    self.detailRacePickButton = CreateFrame("Button", nil, detailDrawer)
    self.detailRacePickButton:SetSize(18, 18)
    self.detailRacePickButton:SetPoint("LEFT", self.detailClassPickButton, "RIGHT", 4, 0)
    self.detailRacePickButton:RegisterForClicks("LeftButtonUp")
    self.detailRacePickButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target or target.validated == true or not HitList:CanMutate(target, Utils.PlayerName()) then
            return
        end

        local enemyFaction = GetEnemyFaction()
        local races = RACES_BY_FACTION[enemyFaction] or {}
        local opts = {}
        for _, race in ipairs(races) do
            table.insert(opts, { text = race, value = race })
        end

        ShowPickerMenu(opts, function(raceName)
            target.race = raceName
            target.faction = enemyFaction
            target.updatedAt = Utils.Now()
            SaveTargetAndBroadcast(target)
        end)
    end)

    self.detailFactionIcon = UIComponents.CreateIcon(detailDrawer, 18)
    self.detailFactionIcon:SetPoint("LEFT", self.detailRaceIcon, "RIGHT", 4, 0)

    self.detailNameText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.detailNameText:SetPoint("LEFT", self.detailFactionIcon, "RIGHT", 8, 0)
    self.detailNameText:SetPoint("RIGHT", detailDrawer, "RIGHT", -70, 0)
    self.detailNameText:SetJustifyH("LEFT")

    self.detailEditButton = UIComponents.CreateButton(detailDrawer, "Edit", 52, 20)
    self.detailEditButton:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailEditButton:SetPoint("TOP", self.detailNameText, "TOP", 0, 2)
    self.detailEditButton:Hide()
    self.detailEditButton:SetScript("OnClick", function()
        local leavingEditMode = UI.detailEditMode == true
        if leavingEditMode then
            CommitEditModeFields()
            UI.detailEditMode = false
        end
        UI._ignoreFocusSave = true
        if UI.reasonEdit and UI.reasonEdit:HasFocus() then
            UI.reasonEdit:ClearFocus()
        end
        if UI.bountyEdit and UI.bountyEdit:HasFocus() then
            UI.bountyEdit:ClearFocus()
        end
        UI._ignoreFocusSave = false
        if not leavingEditMode then
            UI.detailEditMode = true
        end
        UI:RefreshDetails()
        if leavingEditMode and C_Timer and C_Timer.After then
            -- Save triggers intermediate refreshes while transitioning modes.
            -- Run one deferred readonly refresh to stabilize anchors/visibility.
            C_Timer.After(0, function()
                if UI and UI.detailEditMode == false and UI.selectedName then
                    UI:RefreshDetails()
                end
            end)
        end
    end)

    self.detailMetaText = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.detailMetaText:SetPoint("TOPLEFT", self.detailClassIcon, "BOTTOMLEFT", 0, -4)
    self.detailMetaText:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailMetaText:SetJustifyH("LEFT")
    self.detailSubmitterFixButton = CreateFrame("Button", nil, detailDrawer)
    self.detailSubmitterFixButton:SetPoint("TOPLEFT", self.detailMetaText, "TOPLEFT", 0, 2)
    self.detailSubmitterFixButton:SetPoint("BOTTOMRIGHT", self.detailMetaText, "BOTTOMRIGHT", 0, -2)
    self.detailSubmitterFixButton:Hide()
    self.detailSubmitterFixButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        if not Utils.IsSubmitterUnknown(target) then return end
        if not HitList:CanMutate(target, Utils.PlayerName()) then return end
        UI._submitterTargetName = target.name
        local popup = StaticPopup_Show("GUNIT_SUBMITTER_OVERRIDE")
        if popup and popup.editBox then
            popup.editBox:SetText("")
            popup.editBox:SetFocus()
            popup.editBox:HighlightText()
        end
    end)

    self.detailLocationIcon = UIComponents.CreateIcon(detailDrawer, 13)
    self.detailLocationIcon:SetTexture(Theme.ICON.location or Theme.ICON.fallback)
    self.detailLocationIcon:SetPoint("TOPLEFT", self.detailMetaText, "BOTTOMLEFT", 0, -6)

    self.detailLocationLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.detailLocationLabel:SetPoint("LEFT", self.detailLocationIcon, "RIGHT", 4, 0)
    self.detailLocationLabel:SetText("Last Seen")
    self.detailLocationLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.detailLocationText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailLocationText:SetPoint("LEFT", self.detailLocationLabel, "RIGHT", 8, 0)
    self.detailLocationText:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailLocationText:SetJustifyH("LEFT")
    self.detailLocationText:SetText("Location unknown")

    self.detailLocationCoords = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.detailLocationCoords:SetPoint("TOPLEFT", self.detailLocationText, "BOTTOMLEFT", 0, -1)
    self.detailLocationCoords:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailLocationCoords:SetJustifyH("LEFT")
    self.detailLocationCoords:SetText("")

    local statStrip = CreateFrame("Frame", nil, detailDrawer)
    statStrip:SetPoint("TOPLEFT", self.detailMetaText, "BOTTOMLEFT", 0, -8)
    statStrip:SetPoint("TOPRIGHT", detailDrawer, "TOPRIGHT", -10, -68)
    statStrip:SetHeight(20)

    self.detailStatusIcon = UIComponents.CreateIcon(statStrip, 14)
    self.detailStatusIcon:SetPoint("LEFT")
    self.detailStatusText = statStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailStatusText:SetPoint("LEFT", self.detailStatusIcon, "RIGHT", 4, 0)

    self.detailBountyIcon = UIComponents.CreateIcon(statStrip, 14)
    self.detailBountyIcon:SetTexture(Theme.ICON.bounty)
    self.detailBountyIcon:SetPoint("LEFT", self.detailStatusText, "RIGHT", 16, 0)
    self.detailBountyText = statStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailBountyText:SetPoint("LEFT", self.detailBountyIcon, "RIGHT", 4, 0)

    self.detailKillIcon = UIComponents.CreateIcon(statStrip, 14)
    self.detailKillIcon:SetTexture(Theme.ICON.kill)
    self.detailKillIcon:SetPoint("LEFT", self.detailBountyText, "RIGHT", 16, 0)
    self.detailKillsText = statStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailKillsText:SetPoint("LEFT", self.detailKillIcon, "RIGHT", 4, 0)

    -- Keep location below the status strip (Requested by -> stats -> Last Seen).
    self.detailLocationIcon:ClearAllPoints()
    self.detailLocationIcon:SetPoint("TOPLEFT", statStrip, "BOTTOMLEFT", 0, -8)
    self.detailLocationLabel:ClearAllPoints()
    self.detailLocationLabel:SetPoint("LEFT", self.detailLocationIcon, "RIGHT", 4, 0)
    self.detailLocationText:ClearAllPoints()
    self.detailLocationText:SetPoint("LEFT", self.detailLocationLabel, "RIGHT", 8, 0)
    self.detailLocationText:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailLocationCoords:ClearAllPoints()
    self.detailLocationCoords:SetPoint("TOPLEFT", self.detailLocationText, "BOTTOMLEFT", 0, -1)
    self.detailLocationCoords:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)

    self.detailSummaryPanel = CreateFrame("Frame", nil, detailDrawer)
    self.detailSummaryPanel:SetPoint("TOPLEFT", statStrip, "BOTTOMLEFT", 0, -42)
    self.detailSummaryPanel:SetPoint("RIGHT", detailDrawer, "RIGHT", -10, 0)
    self.detailSummaryPanel:SetHeight(30)

    self.detailModesLabel = UIComponents.CreateMutedText(self.detailSummaryPanel, "GameFontNormalSmall")
    self.detailModesLabel:SetPoint("TOPLEFT", self.detailSummaryPanel, "TOPLEFT", 0, 0)
    self.detailModesLabel:SetText("Kill on Sight")
    self.detailModesLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.detailModesValue = self.detailSummaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailModesValue:SetPoint("LEFT", self.detailModesLabel, "RIGHT", 8, 0)
    self.detailModesValue:SetPoint("RIGHT", self.detailSummaryPanel, "RIGHT", 0, 0)
    self.detailModesValue:SetJustifyH("LEFT")
    self.detailModesValue:SetText("Select a target from the list.")

    self.detailBountyStatusLabel = UIComponents.CreateMutedText(self.detailSummaryPanel, "GameFontNormalSmall")
    self.detailBountyStatusLabel:SetPoint("TOPLEFT", self.detailModesLabel, "BOTTOMLEFT", 0, -6)
    self.detailBountyStatusLabel:SetText("Bounty")
    self.detailBountyStatusLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.detailBountyStatusValue = self.detailSummaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailBountyStatusValue:SetPoint("LEFT", self.detailBountyStatusLabel, "RIGHT", 8, 0)
    self.detailBountyStatusValue:SetPoint("RIGHT", self.detailSummaryPanel, "RIGHT", 0, 0)
    self.detailBountyStatusValue:SetJustifyH("LEFT")
    self.detailBountyStatusValue:SetText("")

    self.detailBountyOwedLabel = UIComponents.CreateMutedText(self.detailSummaryPanel, "GameFontNormalSmall")
    self.detailBountyOwedLabel:SetPoint("TOPLEFT", self.detailBountyStatusLabel, "BOTTOMLEFT", 0, -6)
    self.detailBountyOwedLabel:SetText("Bounty Owed")
    self.detailBountyOwedLabel:Hide()

    self.detailBountyOwedValue = self.detailSummaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailBountyOwedValue:SetPoint("LEFT", self.detailBountyOwedLabel, "RIGHT", 8, 0)
    self.detailBountyOwedValue:SetPoint("RIGHT", self.detailSummaryPanel, "RIGHT", 0, 0)
    self.detailBountyOwedValue:SetJustifyH("LEFT")
    self.detailBountyOwedValue:SetText("")
    self.detailBountyOwedValue:Hide()

    self.reasonLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.reasonLabel:SetPoint("TOPLEFT", self.detailSummaryPanel, "BOTTOMLEFT", 0, -2)
    self.reasonLabel:SetText("Reason")
    self.reasonLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.reasonReadOnlyLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.reasonReadOnlyLabel:SetPoint("TOPLEFT", self.detailSummaryPanel, "BOTTOMLEFT", 0, -2)
    self.reasonReadOnlyLabel:SetText("Reason")
    self.reasonReadOnlyLabel:SetTextColor(unpack(Theme.COLOR.textAccent))
    self.reasonReadOnlyLabel:Hide()

    self.reasonScroll = CreateFrame("ScrollFrame", "GUnitReasonScroll", detailDrawer, "UIPanelScrollFrameTemplate")
    self.reasonScroll:SetPoint("TOPLEFT", self.reasonLabel, "BOTTOMLEFT", 0, -6)
    self.reasonScroll:SetSize(286, 52)

    self.reasonBg = CreateFrame("Frame", nil, detailDrawer, "BackdropTemplate")
    UIComponents.StyleInset(self.reasonBg)
    self.reasonBg:SetPoint("TOPLEFT", self.reasonScroll, "TOPLEFT", -2, 2)
    self.reasonBg:SetPoint("BOTTOMRIGHT", self.reasonScroll, "BOTTOMRIGHT", 18, -2)

    self.reasonEdit = CreateFrame("EditBox", "GUnitReasonEdit", self.reasonScroll)
    self.reasonEdit:SetMultiLine(true)
    self.reasonEdit:SetFontObject("ChatFontNormal")
    self.reasonEdit:SetPoint("TOPLEFT", self.reasonScroll, "TOPLEFT", 6, -6)
    self.reasonEdit:SetWidth(262)
    self.reasonEdit:SetAutoFocus(false)
    if self.reasonEdit.SetTextInsets then
        self.reasonEdit:SetTextInsets(6, 6, 4, 4)
    end
    self.reasonEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.reasonEdit:SetScript("OnEditFocusGained", function()
        UI._reasonEditingName = UI.selectedName
    end)
    self.reasonEdit:SetScript("OnEditFocusLost", function()
        UI._reasonEditingName = nil
        if UI._ignoreFocusSave then return end
        -- Explicit save button owns persistence in edit mode.
    end)
    self.reasonScroll:SetScrollChild(self.reasonEdit)

    self.reasonReadOnlyText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.reasonReadOnlyText:SetPoint("TOPLEFT", self.reasonReadOnlyLabel, "BOTTOMLEFT", 0, -6)
    self.reasonReadOnlyText:SetPoint("RIGHT", detailDrawer, "RIGHT", -24, 0)
    self.reasonReadOnlyText:SetJustifyH("LEFT")
    self.reasonReadOnlyText:SetJustifyV("TOP")
    self.reasonReadOnlyText:SetTextColor(0.9, 0.9, 0.9, 1)
    self.reasonReadOnlyText:Hide()

    self.killDetailsSectionLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.killDetailsSectionLabel:SetText("Kill Details")
    self.killDetailsSectionLabel:SetTextColor(unpack(Theme.COLOR.textAccent))
    self.killDetailsSectionLabel:Hide()

    self.killDetailsHeader = CreateFrame("Frame", nil, detailDrawer)
    self.killDetailsHeader:SetSize(300, 14)
    self.killDetailsHeader:Hide()

    self.killDetailsHeader.killer = UIComponents.CreateMutedText(self.killDetailsHeader, "GameFontNormalSmall")
    self.killDetailsHeader.killer:SetPoint("LEFT", self.killDetailsHeader, "LEFT", 0, 0)
    self.killDetailsHeader.killer:SetWidth(76)
    self.killDetailsHeader.killer:SetJustifyH("LEFT")
    self.killDetailsHeader.killer:SetText("Killer")

    self.killDetailsHeader.when = UIComponents.CreateMutedText(self.killDetailsHeader, "GameFontNormalSmall")
    self.killDetailsHeader.when:SetPoint("LEFT", self.killDetailsHeader.killer, "RIGHT", 4, 0)
    self.killDetailsHeader.when:SetWidth(104)
    self.killDetailsHeader.when:SetJustifyH("LEFT")
    self.killDetailsHeader.when:SetText("Last Kill")

    self.killDetailsHeader.kills = UIComponents.CreateMutedText(self.killDetailsHeader, "GameFontNormalSmall")
    self.killDetailsHeader.kills:SetPoint("LEFT", self.killDetailsHeader.when, "RIGHT", 4, 0)
    self.killDetailsHeader.kills:SetWidth(30)
    self.killDetailsHeader.kills:SetJustifyH("LEFT")
    self.killDetailsHeader.kills:SetText("Kills")

    self.killDetailsHeader.claimed = UIComponents.CreateMutedText(self.killDetailsHeader, "GameFontNormalSmall")
    self.killDetailsHeader.claimed:SetPoint("LEFT", self.killDetailsHeader.kills, "RIGHT", 4, 0)
    self.killDetailsHeader.claimed:SetWidth(52)
    self.killDetailsHeader.claimed:SetJustifyH("LEFT")
    self.killDetailsHeader.claimed:SetText("Claimed")

    self.killDetailsHeader.paid = UIComponents.CreateMutedText(self.killDetailsHeader, "GameFontNormalSmall")
    self.killDetailsHeader.paid:SetPoint("LEFT", self.killDetailsHeader.claimed, "RIGHT", 4, 0)
    self.killDetailsHeader.paid:SetWidth(30)
    self.killDetailsHeader.paid:SetJustifyH("LEFT")
    self.killDetailsHeader.paid:SetText("Paid")

    self.killDetailsRows = {}
    for i = 1, MAX_KILL_DETAIL_ROWS do
        local row = CreateFrame("Frame", nil, detailDrawer)
        row:SetHeight(14)
        row:Hide()

        row.killerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.killerText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.killerText:SetWidth(76)
        row.killerText:SetJustifyH("LEFT")

        row.whenText = UIComponents.CreateMutedText(row, "GameFontNormalSmall")
        row.whenText:SetPoint("LEFT", row.killerText, "RIGHT", 4, 0)
        row.whenText:SetWidth(104)
        row.whenText:SetJustifyH("LEFT")

        row.killsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.killsText:SetPoint("LEFT", row.whenText, "RIGHT", 4, 0)
        row.killsText:SetWidth(30)
        row.killsText:SetJustifyH("LEFT")

        row.claimedText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.claimedText:SetPoint("LEFT", row.killsText, "RIGHT", 4, 0)
        row.claimedText:SetWidth(52)
        row.claimedText:SetJustifyH("LEFT")

        row.paidText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.paidText:SetPoint("LEFT", row.claimedText, "RIGHT", 4, 0)
        row.paidText:SetWidth(30)
        row.paidText:SetJustifyH("LEFT")

        row.paidButton = CreateFrame("Button", nil, row)
        row.paidButton:SetSize(30, 14)
        row.paidButton:SetPoint("LEFT", row.claimedText, "RIGHT", 4, 0)
        row.paidButton:RegisterForClicks("LeftButtonUp")
        row.paidButton:Hide()

        row.paidButton.label = row.paidButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.paidButton.label:SetPoint("LEFT", row.paidButton, "LEFT", 0, 0)
        row.paidButton.label:SetWidth(30)
        row.paidButton.label:SetJustifyH("LEFT")

        row.paidButton:SetScript("OnEnter", function(btn)
            btn.label:SetTextColor(1, 1, 0, 1)
        end)
        row.paidButton:SetScript("OnLeave", function(btn)
            btn.label:SetTextColor(0.9, 0.9, 0.9, 1)
        end)
        row.paidButton:SetScript("OnClick", function()
            if not row._killerName or not UI.selectedName then return end
            local target = HitList:Get(UI.selectedName)
            if not target or not HitList:CanMutate(target, Utils.PlayerName()) then return end
            local claim = target.bountyClaims and target.bountyClaims[row._killerName]
            if not claim then return end
            local isPaid = (claim.paidCopper or 0) >= (claim.totalCopper or 0)
            local updated = HitList:SetBountyPaid(UI.selectedName, row._killerName, not isPaid)
            if updated then
                SaveTargetAndBroadcast(updated)
            end
        end)

        self.killDetailsRows[i] = row
    end

    self.killDetailsEmptyText = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.killDetailsEmptyText:SetJustifyH("LEFT")
    self.killDetailsEmptyText:SetText("No kills recorded for this target yet.")
    self.killDetailsEmptyText:Hide()

    self.killDetailsMoreText = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.killDetailsMoreText:SetJustifyH("LEFT")
    self.killDetailsMoreText:Hide()

    self.hitModeLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.hitModeLabel:SetPoint("TOPLEFT", self.reasonScroll, "BOTTOMLEFT", 2, -12)
    self.hitModeLabel:SetText("Kill on Sight")
    self.hitModeLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.hitModeDropdown = CreateFrame("Frame", "GUnitHitModeDropdown", detailDrawer, "UIDropDownMenuTemplate")
    self.hitModeDropdown:SetPoint("TOPLEFT", self.hitModeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(self.hitModeDropdown, 110)
    UIDropDownMenu_Initialize(self.hitModeDropdown, function(dropdown, level)
        local options = {
            { text = "One-time", value = "one_time" },
            { text = "Indefinitely", value = "kos" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                local target = RequireSelectedTarget()
                if not target then return end
                local updated, err = HitList:SetHitMode(target.name, btn.value, Utils.PlayerName())
                if not updated then
                    GUnit:Print(err)
                    return
                end
                UIDropDownMenu_SetText(dropdown, btn:GetText())
                SaveTargetAndBroadcast(updated)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self.hitModeReadOnlyText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.hitModeReadOnlyText:SetPoint("LEFT", self.hitModeDropdown, "LEFT", 16, 0)
    self.hitModeReadOnlyText:SetTextColor(0.9, 0.9, 0.9, 1)
    self.hitModeReadOnlyText:Hide()

    self.bountyLabel = UIComponents.CreateMutedText(detailDrawer, "GameFontNormalSmall")
    self.bountyLabel:SetPoint("TOPLEFT", self.hitModeDropdown, "BOTTOMLEFT", 16, -12)
    self.bountyLabel:SetText("Bounty Details")
    self.bountyLabel:SetTextColor(unpack(Theme.COLOR.textAccent))

    self.bountyEdit = CreateFrame("EditBox", nil, detailDrawer, "InputBoxTemplate")
    self.bountyEdit:SetSize(110, 24)
    self.bountyEdit:SetPoint("TOPLEFT", self.bountyLabel, "BOTTOMLEFT", 24, -8)
    self.bountyEdit:SetAutoFocus(false)
    self.bountyEdit:SetNumeric(true)
    self.bountyEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.bountyEdit:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    self.bountyEdit:SetScript("OnEditFocusLost", function()
        if UI._ignoreFocusSave then return end
        -- Explicit save button owns persistence in edit mode.
    end)

    self.bountyAmountIcon = UIComponents.CreateIcon(detailDrawer, 16)
    self.bountyAmountIcon:SetTexture(Theme.ICON.bounty)
    self.bountyAmountIcon:SetPoint("LEFT", self.bountyLabel, "LEFT", 2, -20)
    self.bountyEdit:ClearAllPoints()
    self.bountyEdit:SetPoint("LEFT", self.bountyAmountIcon, "RIGHT", 12, 0)

    self.bountyAmountReadOnlyText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.bountyAmountReadOnlyText:SetPoint("LEFT", self.bountyEdit, "LEFT", 6, 0)
    self.bountyAmountReadOnlyText:SetTextColor(0.9, 0.9, 0.9, 1)
    self.bountyAmountReadOnlyText:Hide()

    self.bountyModeDropdown = CreateFrame("Frame", "GUnitBountyModeDropdown", detailDrawer, "UIDropDownMenuTemplate")
    self.bountyModeDropdown:SetPoint("TOPLEFT", self.bountyEdit, "BOTTOMLEFT", -20, -10)
    UIDropDownMenu_SetWidth(self.bountyModeDropdown, 110)
    UIDropDownMenu_Initialize(self.bountyModeDropdown, function(dropdown, level)
        local options = {
            { text = "None", value = "none" },
            { text = "One-time", value = "first_kill" },
            { text = "Indefinitely", value = "infinite" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                local target = RequireSelectedTarget()
                if not target then return end
                local updated, err = HitList:SetBountyMode(target.name, btn.value, Utils.PlayerName())
                if not updated then
                    GUnit:Print(err)
                    return
                end
                UIDropDownMenu_SetText(dropdown, btn:GetText())
                SaveTargetAndBroadcast(updated)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self.bountyModeIcon = UIComponents.CreateIcon(detailDrawer, 16)
    self.bountyModeIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    self.bountyModeIcon:SetPoint("LEFT", self.bountyAmountIcon, "LEFT", 0, -34)
    self.bountyModeDropdown:ClearAllPoints()
    self.bountyModeDropdown:SetPoint("TOPLEFT", self.bountyEdit, "BOTTOMLEFT", -20, -10)

    self.bountyModeReadOnlyText = detailDrawer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.bountyModeReadOnlyText:SetPoint("LEFT", self.bountyModeDropdown, "LEFT", 16, 0)
    self.bountyModeReadOnlyText:SetTextColor(0.9, 0.9, 0.9, 1)
    self.bountyModeReadOnlyText:Hide()

    self.callOffButton = UIComponents.CreateButton(detailDrawer, "Call Off", 100, 24)
    self.callOffButton:SetPoint("BOTTOMLEFT", detailDrawer, "BOTTOMLEFT", 10, 10)
    self.callOffButton:Hide()
    self.callOffButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        UI._callOffTargetName = target.name
        StaticPopup_Show("GUNIT_CALL_OFF_CONFIRM", target.name)
    end)

    self.reopenButton = UIComponents.CreateButton(detailDrawer, "Re-open", 100, 24)
    self.reopenButton:SetPoint("LEFT", self.callOffButton, "RIGHT", 8, 0)
    self.reopenButton:Hide()
    self.reopenButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local updated, err = HitList:SetHitStatus(target.name, "active", Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
        local reopenMsg = "The hit on " .. Utils.TargetLabel(updated) .. " has been re-opened."
        if (updated.bountyAmount or 0) > 0 then
            reopenMsg = reopenMsg .. " Bounty: " .. Utils.GoldStringFromCopper(updated.bountyAmount) .. "."
        end
        MaybeAnnounce(reopenMsg)
    end)

    StaticPopupDialogs["GUNIT_CALL_OFF_CONFIRM"] = {
        text = "Are you sure you want to call off the hit on %s?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            local targetName = UI._callOffTargetName
            if not targetName then return end
            local target = HitList:Get(targetName)
            if not target then return end

            local hasKills = (target.killCount or 0) > 0
            if hasKills then
                local updated = HitList:SetHitStatus(targetName, "closed", Utils.PlayerName())
                if updated then
                    Comm:BroadcastUpsert(updated)
                    GUnit:Print("Hit on " .. targetName .. " closed (kill history preserved).")
                    local closeMsg = "The hit on " .. Utils.TargetLabel(updated) .. " has been closed."
                    MaybeAnnounce(closeMsg)
                    MaybeAnnounceParty(closeMsg)
                end
            else
                HitList:Delete(targetName)
                Comm:BroadcastDelete(targetName)
                GUnit:Print("Hit on " .. targetName .. " has been called off.")
                local callOffMsg = "The hit on " .. targetName .. " has been called off."
                MaybeAnnounce(callOffMsg)
                MaybeAnnounceParty(callOffMsg)
            end
            UI.selectedName = nil
            UI._callOffTargetName = nil
            GUnit:NotifyDataChanged()
        end,
        OnCancel = function()
            UI._callOffTargetName = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["GUNIT_SUBMITTER_OVERRIDE"] = {
        text = "Who submitted this kill target?\n\nI did\nOR",
        button1 = "I did",
        button2 = "Update",
        hasEditBox = 1,
        maxLetters = 12,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(selfPopup)
            if selfPopup and selfPopup.editBox then
                selfPopup.editBox:SetFocus()
                selfPopup.editBox:HighlightText()
            end
            if selfPopup and selfPopup.button2 then
                selfPopup.button2:SetScript("OnClick", function(btn)
                    local popup = btn and btn:GetParent() or nil
                    local targetName = UI._submitterTargetName
                    if not popup or not targetName then return end
                    local text = strtrim((popup.editBox and popup.editBox:GetText()) or "")
                    if text == "" then
                        GUnit:Print("Enter a submitter name or use I did.")
                        if popup.editBox then
                            popup.editBox:SetFocus()
                            popup.editBox:HighlightText()
                        end
                        return
                    end
                    if ApplySubmitterOverride(targetName, text) then
                        UI._submitterTargetName = nil
                        popup:Hide()
                    end
                end)
            end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local parent = editBox:GetParent()
            local targetName = UI._submitterTargetName
            if not targetName then
                parent:Hide()
                return
            end
            local text = strtrim(editBox:GetText() or "")
            if text == "" then
                GUnit:Print("Enter a submitter name or use I did.")
                return
            end
            if ApplySubmitterOverride(targetName, text) then
                UI._submitterTargetName = nil
                parent:Hide()
            end
        end,
        OnAccept = function()
            local targetName = UI._submitterTargetName
            if not targetName then return end
            local me = Utils.PlayerName()
            if ApplySubmitterOverride(targetName, me) then
                UI._submitterTargetName = nil
            end
        end,
        OnCancel = function()
            UI._submitterTargetName = nil
        end,
    }

    self.selectedName = nil

    local settings = GetSettings()
    drawerIsOpen = settings.rememberDrawerState and settings.drawerOpen == true or false
    drawerWidth = drawerIsOpen and Theme.DRAWER_WIDTH or 0
    ApplyDrawerWidth(drawerWidth)
    detailDrawer:Show()

    self:Refresh()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
        self.frame:Raise()
    end
end

function UI:ShowExportFrame()
    self:ShowOptionsModal()
    ShowOptionsTab(self, "export")
end

function UI:ShowImportFrame()
    self:ShowOptionsModal()
    ShowOptionsTab(self, "import")
end
