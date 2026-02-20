local _, GUnit = ...

GUnit.Utils = {}
local Utils = GUnit.Utils

local SERIAL_SEP = "\031"

function Utils.NormalizeName(name)
    if not name then return nil end
    name = strtrim(name)
    if name == "" then return nil end

    local simpleName = name:match("^[^%-]+") or name
    simpleName = simpleName:lower()
    return simpleName:gsub("^%l", string.upper)
end

function Utils.PlayerName()
    return UnitName("player") or "Unknown"
end

function Utils.InGuild()
    return IsInGuild and IsInGuild() or (GetGuildInfo("player") ~= nil)
end

function Utils.GuildName()
    if GetGuildInfo then
        return GetGuildInfo("player")
    end
    return nil
end

function Utils.CopperFromGoldString(value)
    local amount = tonumber(value)
    if not amount then return nil end
    if amount < 0 then return nil end
    return math.floor(amount * 10000 + 0.5)
end

function Utils.GoldStringFromCopper(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0g" end
    return string.format("%dg", math.floor(copper / 10000))
end

function Utils.IsSubmitter(target, playerName)
    if not target or not target.submitter then return false end
    return target.submitter == (playerName or Utils.PlayerName())
end

function Utils.IsSubmitterUnknown(target)
    if not target then return true end
    local submitter = target.submitter
    return (not submitter) or submitter == "" or submitter == "Unknown"
end

function Utils.Escape(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub("\029", "%%1D")
    value = value:gsub(SERIAL_SEP, "%%1F")
    return value
end

function Utils.Unescape(value)
    value = tostring(value or "")
    value = value:gsub("%%1F", SERIAL_SEP)
    value = value:gsub("%%1D", "\029")
    value = value:gsub("%%25", "%%")
    return value
end

function Utils.SerializeParts(parts)
    local encoded = {}
    for i = 1, #parts do
        encoded[i] = Utils.Escape(parts[i])
    end
    return table.concat(encoded, SERIAL_SEP)
end

function Utils.DeserializeParts(payload)
    local out = {}
    if not payload or payload == "" then return out end
    for value in string.gmatch(payload, "([^" .. SERIAL_SEP .. "]*)") do
        if value == "" and #out > 0 and #out >= string.len(payload) then
            break
        end
        table.insert(out, Utils.Unescape(value))
    end
    return out
end

local GUILD_MSG_PREFIX = "[G-Unit] "

function Utils.InParty()
    if IsInGroup then return IsInGroup() end
    return GetNumGroupMembers and GetNumGroupMembers() > 0
end

function Utils.SendGuildChat(message)
    if Utils.InGuild() and SendChatMessage then
        SendChatMessage(GUILD_MSG_PREFIX .. message, "GUILD")
    end
end

function Utils.SendPartyChat(message)
    if Utils.InParty() and SendChatMessage then
        SendChatMessage(GUILD_MSG_PREFIX .. message, "PARTY")
    end
end

function Utils.TargetLabel(target)
    if not target then return "Unknown" end
    local name = target.name or "Unknown"
    local parts = {}
    if target.race and target.race ~= "" then table.insert(parts, target.race) end
    if target.classToken and target.classToken ~= "" then table.insert(parts, target.classToken) end
    if #parts > 0 then
        return name .. " (" .. table.concat(parts, " ") .. ")"
    end
    return name
end

function Utils.ZoneName()
    return GetRealZoneText() or "Unknown Zone"
end

function Utils.SubZoneName()
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    if subzone and subzone ~= "" then
        return subzone
    end
    return Utils.ZoneName()
end

local function SafeMapIdForUnit(unit)
    if not C_Map or not C_Map.GetBestMapForUnit then
        return nil
    end
    local ok, mapId = pcall(C_Map.GetBestMapForUnit, unit)
    if not ok then
        return nil
    end
    return tonumber(mapId)
end

local function SafeUnitPosition(mapId, unit)
    if not mapId or not C_Map or not C_Map.GetPlayerMapPosition then
        return nil, nil
    end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapId, unit)
    if not ok or not position then
        return nil, nil
    end

    local x = position.x
    local y = position.y
    if type(position.GetXY) == "function" then
        local okXY, px, py = pcall(position.GetXY, position)
        if okXY then
            x = px
            y = py
        end
    end

    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then
        return nil, nil
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return nil, nil
    end
    return x, y
end

function Utils.BuildLocationPayload(options)
    options = options or {}
    local unit = options.unit or "player"
    local source = options.source or "unknown"
    local approximate = options.approximate == true
    local seenAt = tonumber(options.seenAt) or Utils.Now()
    local confidenceYards = tonumber(options.confidenceYards)
    local fallbackToPlayer = options.fallbackToPlayer ~= false

    local zone = Utils.ZoneName()
    local subzone = Utils.SubZoneName()
    local mapId = SafeMapIdForUnit(unit)
    local x, y = SafeUnitPosition(mapId, unit)

    if fallbackToPlayer and (not mapId or x == nil or y == nil) then
        local playerMapId = SafeMapIdForUnit("player")
        if playerMapId then
            mapId = playerMapId
            x, y = SafeUnitPosition(playerMapId, "player")
            approximate = true
        end
    end

    return {
        zone = zone or "Unknown Zone",
        subzone = (subzone and subzone ~= "") and subzone or (zone or "Unknown Zone"),
        mapId = mapId,
        x = x,
        y = y,
        seenAt = seenAt,
        source = source,
        approximate = approximate,
        confidenceYards = confidenceYards,
    }
end

function Utils.FormatLocation(location)
    if type(location) ~= "table" then
        return "Unknown location"
    end
    local zone = location.zone or "Unknown Zone"
    local subzone = location.subzone
    local label = zone
    if subzone and subzone ~= "" and subzone ~= zone then
        label = subzone .. ", " .. zone
    end

    local x = tonumber(location.x)
    local y = tonumber(location.y)
    if x and y then
        label = string.format("%s (%.1f, %.1f)", label, x * 100, y * 100)
    end
    if location.approximate then
        label = "~" .. label
    end
    return label
end

function Utils.Now()
    return time()
end

function Utils.RelativeTime(timestamp)
    local diff = Utils.Now() - (tonumber(timestamp) or 0)
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

function Utils.ClassColorName(name, classToken)
    if not classToken then return name end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not color then return name end
    return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
end
