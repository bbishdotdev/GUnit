local _, Addon = ...
local Theme = Addon.UITheme

local UIComponents = {}
Addon.UIComponents = UIComponents

local function ApplyBackdrop(frame, bgColor)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
end

function UIComponents.StylePanel(frame)
    ApplyBackdrop(frame, Theme.COLOR.panelBg)
end

function UIComponents.StyleInset(frame)
    ApplyBackdrop(frame, Theme.COLOR.borderBg)
end

function UIComponents.CreateHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24)

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(
        Theme.COLOR.headerBg[1],
        Theme.COLOR.headerBg[2],
        Theme.COLOR.headerBg[3],
        Theme.COLOR.headerBg[4]
    )

    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetTextColor(
        Theme.COLOR.textAccent[1],
        Theme.COLOR.textAccent[2],
        Theme.COLOR.textAccent[3],
        Theme.COLOR.textAccent[4]
    )
    fs:SetText(text or "")

    header.text = fs
    return header
end

function UIComponents.CreateButton(parent, label, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 110, height or 24)
    btn:SetText(label or "Button")
    return btn
end

function UIComponents.CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Theme.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * Theme.ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local bgColor = (index % 2 == 0) and Theme.COLOR.rowEven or Theme.COLOR.rowOdd
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(
        Theme.COLOR.rowHover[1],
        Theme.COLOR.rowHover[2],
        Theme.COLOR.rowHover[3],
        Theme.COLOR.rowHover[4]
    )

    return row
end

function UIComponents.CreateIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(Theme.ICON.fallback)
    return icon
end

function UIComponents.CreateMutedText(parent, fontObject)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormalSmall")
    fs:SetTextColor(
        Theme.COLOR.textMuted[1],
        Theme.COLOR.textMuted[2],
        Theme.COLOR.textMuted[3],
        Theme.COLOR.textMuted[4]
    )
    return fs
end
