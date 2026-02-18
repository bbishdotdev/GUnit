local _, Addon = ...

local Theme = {}
Addon.UITheme = Theme

Theme.FRAME_WIDTH = 882
Theme.FRAME_HEIGHT = 540
Theme.PADDING = 10
Theme.ROW_HEIGHT = 34
Theme.ROWS_PER_PAGE = 11
Theme.DRAWER_WIDTH = 330
Theme.DRAWER_GAP = 8

Theme.COLOR = {
    borderBg = { 0.03, 0.03, 0.03, 0.9 },
    panelBg = { 0.08, 0.08, 0.08, 0.75 },
    headerBg = { 0.12, 0.12, 0.12, 0.85 },
    rowOdd = { 0.2, 0.2, 0.2, 0.12 },
    rowEven = { 0.2, 0.2, 0.2, 0.06 },
    rowHover = { 1, 1, 1, 0.08 },
    textMuted = { 0.6, 0.6, 0.6, 1 },
    textAccent = { 1, 0.82, 0.0, 1 },
    statusActive = { 0.85, 0.2, 0.2, 1 }, -- Open
    statusDone = { 0.2, 0.8, 0.2, 1 }, -- Closed (completed)
    statusClosed = { 0.2, 0.8, 0.2, 1 }, -- Closed
}

Theme.ICON = {
    fallback = "Interface\\Icons\\INV_Misc_QuestionMark",
    bounty = "Interface\\Icons\\INV_Misc_Coin_01",
    kill = "Interface\\Icons\\Ability_FiegnDead",
    location = "Interface\\Icons\\INV_Misc_Map_01",
    submitter = "Interface\\Icons\\INV_Misc_Note_01",
    statusActive = "Interface\\Icons\\Ability_DualWield",
    statusDone = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    statusClosed = "Interface\\Icons\\Spell_Shadow_DeathScream",
    faction = {
        Horde = "Interface\\PVPFrame\\PVP-Currency-Horde",
        Alliance = "Interface\\PVPFrame\\PVP-Currency-Alliance",
    },
    race = {
        Human = "Interface\\Icons\\INV_Misc_Head_Human_01",
        Dwarf = "Interface\\Icons\\INV_Misc_Head_Dwarf_01",
        NightElf = "Interface\\Icons\\INV_Misc_Head_NightElf_01",
        ["Night Elf"] = "Interface\\Icons\\INV_Misc_Head_NightElf_01",
        Gnome = "Interface\\Icons\\INV_Misc_Head_Gnome_01",
        Orc = "Interface\\Icons\\INV_Misc_Head_Orc_01",
        Undead = "Interface\\Icons\\INV_Misc_Head_Undead_01",
        Tauren = "Interface\\Icons\\INV_Misc_Head_Tauren_01",
        Troll = "Interface\\Icons\\INV_Misc_Head_Troll_01",
        BloodElf = "Interface\\Icons\\INV_Misc_Head_Elf_01",
        ["Blood Elf"] = "Interface\\Icons\\INV_Misc_Head_Elf_01",
        Draenei = "Interface\\Icons\\INV_Misc_Head_Draenei_01",
    },
}

Theme.CLASS_ICON_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
Theme.CLASS_ICON_COORDS = {
    WARRIOR = { 0.00, 0.25, 0.00, 0.25 },
    MAGE = { 0.25, 0.50, 0.00, 0.25 },
    ROGUE = { 0.50, 0.75, 0.00, 0.25 },
    DRUID = { 0.75, 1.00, 0.00, 0.25 },
    HUNTER = { 0.00, 0.25, 0.25, 0.50 },
    SHAMAN = { 0.25, 0.50, 0.25, 0.50 },
    PRIEST = { 0.50, 0.75, 0.25, 0.50 },
    WARLOCK = { 0.75, 1.00, 0.25, 0.50 },
    PALADIN = { 0.00, 0.25, 0.50, 0.75 },
}

local RACE_ID_TO_KEY = {
    [1] = "Human",
    [2] = "Orc",
    [3] = "Dwarf",
    [4] = "NightElf",
    [5] = "Undead",
    [6] = "Tauren",
    [7] = "Gnome",
    [8] = "Troll",
    [10] = "BloodElf",
    [11] = "Draenei",
}

local function NormalizeRaceKey(raceName)
    if not raceName or raceName == "" then
        return nil
    end
    local compact = tostring(raceName):gsub("%s+", "")
    return compact
end

local function NormalizeSexToken(sex)
    local n = tonumber(sex)
    if n == 1 or n == 3 then
        return "female"
    end
    return "male"
end

local RACE_GRID_TEXTURE = "Interface\\GLUES\\CharacterCreate\\ui-charactercreate-races"
local RACE_BASE_TILE = { uMin = -0.004, uMax = 0.126, vMin = 0.00, vMax = 0.254 } -- Human male tuned crop
local RACE_STEP_U = 0.127 -- one column to the right
local RACE_STEP_V = 0.25 -- one row down

-- Top-down, left-right grid from validated in-game reference:
-- Col0: HumanM, TaurenM, HumanF, TaurenF
-- Col1: DwarfM, UndeadM, DwarfF, UndeadF
-- Col2: GnomeM, TrollM, GnomeF, TrollF
-- Col3: NightElfM, OrcM, NightElfF, OrcF
-- Col4: DraeneiM, BloodElfM, DraeneiF, BloodElfF
local RACE_GRID_SLOT = {
    Human = { col = 0, maleRow = 0, femaleRow = 2 },
    Tauren = { col = 0, maleRow = 1, femaleRow = 3 },
    Dwarf = { col = 1, maleRow = 0, femaleRow = 2 },
    Undead = { col = 1, maleRow = 1, femaleRow = 3 },
    Gnome = { col = 2, maleRow = 0, femaleRow = 2 },
    Troll = { col = 2, maleRow = 1, femaleRow = 3 },
    NightElf = { col = 3, maleRow = 0, femaleRow = 2 },
    Orc = { col = 3, maleRow = 1, femaleRow = 3 },
    Draenei = { col = 4, maleRow = 0, femaleRow = 2 },
    BloodElf = { col = 4, maleRow = 1, femaleRow = 3 },
}

local function TrySetRaceGrid(texture, raceKey, sexToken)
    if not texture or not raceKey then
        return false
    end

    local slot = RACE_GRID_SLOT[raceKey]
    if not slot then
        return false
    end

    local row = (sexToken == "female") and slot.femaleRow or slot.maleRow
    local uShift = slot.col * RACE_STEP_U
    local vShift = row * RACE_STEP_V

    texture:SetTexture(RACE_GRID_TEXTURE)
    texture:SetTexCoord(
        RACE_BASE_TILE.uMin + uShift,
        RACE_BASE_TILE.uMax + uShift,
        RACE_BASE_TILE.vMin + vShift,
        RACE_BASE_TILE.vMax + vShift
    )
    return true
end

function Theme.SetClassIcon(texture, classToken)
    texture:SetTexture(Theme.CLASS_ICON_ATLAS)
    local coords = Theme.CLASS_ICON_COORDS[classToken]
    if coords then
        texture:SetTexCoord(unpack(coords))
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

function Theme.GetRaceIcon(raceName)
    if not raceName or raceName == "" then
        return Theme.ICON.fallback
    end
    local direct = Theme.ICON.race[raceName]
    if direct then
        return direct
    end
    local compact = tostring(raceName):gsub("%s+", "")
    return Theme.ICON.race[compact] or Theme.ICON.fallback
end

function Theme.SetRaceIcon(texture, raceName, raceId, _sex)
    if not texture then
        return
    end

    local key = NormalizeRaceKey(raceName)
    if not key and raceId then
        key = RACE_ID_TO_KEY[tonumber(raceId)]
    end
    local sexToken = NormalizeSexToken(_sex)
    if TrySetRaceGrid(texture, key, sexToken) then
        return
    end
    texture:SetTexture(Theme.GetRaceIcon(key or raceName))
    texture:SetTexCoord(0, 1, 0, 1)
end

function Theme.GetFactionIcon(factionName)
    return Theme.ICON.faction[factionName] or Theme.ICON.fallback
end

function Theme.GetStatusIcon(status)
    if status == "completed" then
        return Theme.ICON.statusDone
    elseif status == "closed" then
        return Theme.ICON.statusClosed
    end
    return Theme.ICON.statusActive
end

function Theme.GetStatusColor(status)
    if status == "completed" then
        return Theme.COLOR.statusDone
    elseif status == "closed" then
        return Theme.COLOR.statusClosed
    end
    return Theme.COLOR.statusActive
end
