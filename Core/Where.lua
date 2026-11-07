--[[
  BiSGuild :: Core/Where.lua - the terminal's WHERE page: the map, and who is where.

  Arn, 16 Oct 2026: "It'll have a map too showing where all the raiders are at".

  TWO SOURCES, SAID APART ON THE PAGE:
    * the DOTS are guildmates whose BiS addon shares their spot (LibBiSComm minor 12: every BiS
      addon sends it on the guild channel while you move, outside instances; `/biscomm share off`
      stops it). Exact, but only for people running a BiS addon with sharing on.
    * the LIST is the guild roster: every online member and the zone the game says they are in -
      everybody, BiS addon or not, but a zone name and no more.
  A row that also has a dot says "on map"; clicking it shows their map.

  The map is drawn the way BiS Tools' overlay draws it (Tools/Overlay.lua there): the zone's base
  layer, the explored pieces over it, the torn paper edge trimmed off. The base layer always shows
  here - this is a page about where OTHER people are, and your own fog of war would hide them.

  Redrawn every K.WHERE_EVERY seconds while the page shows (Terminal.lua's OnUpdate), never hidden.
]]
local ADDON, ns = ...
local K = ns.K

local W = {}
ns.Where = W

W.TILE = 256
W.EDGE = { 0.03, 0, 0.045 }     -- the paper's edge, left/right, top, bottom (BiS Tools' O.EDGE)
W.MAP_W = 520                    -- the map panel's width; the list takes the rest
--- THE CAPITALS' BOXES, measured by eye with Arn on 14 Oct for BiS Tools' overlay (O.CROP there): a
--- capital is one painted picture, parchment and city in the same pixels, so the edge trim cannot find
--- the city - this box replaces it. left, top, right, bottom as shares of the map.
W.CROP = {
    [1454] = { 0.08, 0.015, 0.88, 0.985 },   -- Orgrimmar
    [1456] = { 0.10, 0.03, 0.88, 0.96 },     -- Thunder Bluff
    [1458] = { 0.03, 0.01, 0.91, 0.975 },    -- Undercity
    [1453] = { 0.03, 0.05, 0.92, 0.97 },     -- Stormwind
    [1455] = { 0.08, 0.005, 0.915, 0.98 },   -- Ironforge
    [1457] = { 0.05, 0.005, 0.93, 0.98 },    -- Darnassus
}

local function hidden(v)
    if v == nil or not issecretvalue then return false end
    local ok, yes = pcall(issecretvalue, v)
    return (not ok) or yes == true
end
local function num(v) if hidden(v) or type(v) ~= "number" then return nil end return v end
local function fileSize(px)
    local f = 16
    while f < px do f = f * 2 end
    return f
end
local function Lib() return _G.LibBiSComm end

--------------------------------------------------------------------
-- the words (the suite drives these)
--------------------------------------------------------------------

--- A map's art: its size in the art's pixels and the pieces that cover it, or nil.
--- piece = { file, x, y, w, h, fileW, fileH }
function W.Pieces(mapID)
    if not (mapID and C_Map and C_Map.GetMapArtLayers) then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local L = ok and type(layers) == "table" and layers[1] or nil
    if not L then return nil end
    local lw = num(L.layerWidth)
    local lh = num(L.layerHeight)
    if not (lw and lh and lw > 0 and lh > 0) then return nil end
    local pieces = {}
    local tw, th = num(L.tileWidth) or W.TILE, num(L.tileHeight) or W.TILE
    local okF, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    files = okF and type(files) == "table" and files or {}
    local cols = math.ceil(lw / tw)
    for i, file in ipairs(files) do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        pieces[#pieces + 1] = { file, c * tw, r * th, tw, th, tw, th, "BORDER" }
    end
    -- what this map gave, for `/bisg mapwhy`
    W.why = { map = mapID, base = #pieces, explored = 0, records = 0, hidden = false }
    -- the explored pieces over it, cut the way the client cuts them (BiS Tools' overlay, 14 Oct)
    local info = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
    local okE, explored = false, nil
    if info then okE, explored = pcall(info, mapID) end
    W.why.hidden = okE and hidden(explored) or false
    W.why.call = info and (okE and "answered" or "errored") or "missing"
    if okE and type(explored) == "table" and not hidden(explored) then
        W.why.records = #explored
        for _, e in ipairs(explored) do
            local tw2, th2 = num(e.textureWidth), num(e.textureHeight)
            local ox, oy = num(e.offsetX) or 0, num(e.offsetY) or 0
            if tw2 and th2 and type(e.fileDataIDs) == "table" then
                local wide, tall = math.ceil(tw2 / W.TILE), math.ceil(th2 / W.TILE)
                for j = 1, tall do
                    local ph = (j < tall) and W.TILE or (th2 - W.TILE * (tall - 1))
                    for k = 1, wide do
                        local pw = (k < wide) and W.TILE or (tw2 - W.TILE * (wide - 1))
                        local file = e.fileDataIDs[(j - 1) * wide + k]
                        if file then
                            -- ARTWORK, over the base's BORDER (Arn, 16 Oct, Zephras Isle: "it shows fog of
                            -- war, I've explored some of that map" - one shared layer let the fog draw last)
                            pieces[#pieces + 1] = { file, ox + W.TILE * (k - 1), oy + W.TILE * (j - 1), pw, ph,
                                (k < wide) and W.TILE or fileSize(pw), (j < tall) and W.TILE or fileSize(ph), "ARTWORK" }
                            W.why.explored = W.why.explored + 1
                        end
                    end
                end
            end
        end
    end
    return lw, lh, pieces
end

function W.MapName(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    local name = ok and type(info) == "table" and info.name or nil
    return type(name) == "string" and not hidden(name) and name or nil
end

--- Every spot we know: guildmates' from the lib, and our own. { name, key, map, x, y, me }
function W.Spots()
    local out = {}
    local lib = Lib()
    if lib and lib.Spots then
        for sender, s in pairs(lib:Spots()) do
            if type(sender) == "string" and type(s) == "table" and s.map then
                out[#out + 1] = { name = sender, key = K.NameKey(sender), map = s.map, x = s.x, y = s.y }
            end
        end
    end
    if lib and lib.MySpot then
        local ok, map, x, y = pcall(lib.MySpot, lib)
        if ok and map then
            local me = UnitName and UnitName("player") or "you"
            out[#out + 1] = { name = me, key = K.NameKey(me), map = map, x = x, y = y, me = true }
        end
    end
    return out
end

--- THE WORLD VIEW (Arn, 16 Oct: "world view"). Azeroth's map, with every zone's spots placed on it by
--- the client's own C_Map.GetMapRectOnMap - where a zone sits on another map - and not by a library's
--- arithmetic: OpenMap's notes (16 Oct) say HereBeDragons' world positions come out wrong on Forever.
W.WORLD = 947
W.rects = {}                    -- "from>to" -> { minX, maxX, minY, maxY } or false
function W.OnMap(from, x, y, to)
    if from == to then return x, y end
    if not (from and to and C_Map and C_Map.GetMapRectOnMap) then return nil end
    local k = from .. ">" .. to
    local r = W.rects[k]
    if r == nil then
        local ok, a, b, c, d = pcall(C_Map.GetMapRectOnMap, from, to)
        if ok then
            a, b, c, d = num(a), num(b), num(c), num(d)
        else
            a = nil
        end
        r = (a and b and c and d and b > a and d > c) and { a, b, c, d } or false
        W.rects[k] = r
    end
    if not r then return nil end
    return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
end

--- The map's kind (0 cosmic, 1 world, 2 continent, 3 zone...), or nil.
function W.MapInfoType(map)
    if not (map and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    return ok and type(info) == "table" and num(info.mapType) or nil
end

--- Can the world view be drawn: its art, and the client placing zones on it.
function W.WorldReady()
    return C_Map and C_Map.GetMapRectOnMap ~= nil and W.Pieces(W.WORLD) ~= nil
end

--- Which map to show when nobody picked one: the world, when it can be drawn; else where most dots
--- are; else where I am.
function W.AutoMap(spots)
    if W.WorldReady() then return W.WORLD end
    local count, best = {}, nil
    for _, s in ipairs(spots) do
        count[s.map] = (count[s.map] or 0) + 1
        if not best or count[s.map] > count[best] or (count[s.map] == count[best] and s.map < best) then best = s.map end
    end
    if best then return best end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        return ok and num(m) or nil
    end
    return nil
end

--- The list: online guild members grouped by zone, the busiest zone first, alphabetical inside.
--- rows = { { header = true, zone = name, n = count } | { person, with its zone } }
function W.Rows(spots)
    local bySpot = {}
    for _, s in ipairs(spots) do local mm = K.Member(s.name) if mm then bySpot[mm.key] = s end end
    local zones, order = {}, {}
    for key, m in pairs(K.Guild().members) do
        if m.online then
            local z = m.zone or "?"
            if not zones[z] then zones[z] = {} order[#order + 1] = z end
            table.insert(zones[z], { name = m.name or key, key = key, class = m.class, level = m.level, zone = z,
                                     rank = m.rank, spot = bySpot[key] })
        end
    end
    table.sort(order, function(a, b)
        if #zones[a] ~= #zones[b] then return #zones[a] > #zones[b] end
        return a < b
    end)
    local rows = {}
    for _, z in ipairs(order) do
        rows[#rows + 1] = { header = true, zone = z, n = #zones[z] }
        table.sort(zones[z], function(a, b) return a.name < b.name end)
        for _, p in ipairs(zones[z]) do rows[#rows + 1] = p end
    end
    return rows
end

--- THE CLOSE-UP LIVES IN OPENMAP (Arn, 16 Oct: OpenMap zooms down to the ground; "if the addon is
--- installed"). Its API (OpenMapAPI, major 1) does not lend its terrain to other windows, but it moves
--- its own map: WorldFromMap turns a zone spot into its stitched world, ShowWorld glides there. So the
--- button opens the world map and, with OpenMap, glides in on whoever was clicked (else the middle of
--- the zone shown). Without OpenMap: the game's map on that zone. Our dots are on both (Pins.lua).
---
--- NEVER IN COMBAT: OpenMap's own notes - opening the map in a fight drew "action blocked".
W.ZOOM = 40              -- OpenMap's zoom: 1 is the whole world; this is a few hundred yards across
function W.OpenMapHere() return type(_G.OpenMapAPI) == "table" and _G.OpenMapAPI.WorldFromMap ~= nil end

function W.OpenBig()
    if InCombatLockdown and InCombatLockdown() then
        K.Say("not in combat - the map cannot be opened in a fight", "warn")
        return false
    end
    local map = W.shown
    if not map then K.Say("no map to open", "warn") return false end
    local x, y = 0.5, 0.5
    if W.focus and W.focus.map == map then x, y = W.focus.x, W.focus.y end
    -- the terminal STAYS OPEN (Arn: "it closes our window"): it shares the map's layer now, and the
    -- map, opened last, comes up in front
    if OpenWorldMap then pcall(OpenWorldMap, map) elseif ToggleWorldMap then pcall(ToggleWorldMap) end
    local api = W.OpenMapHere() and _G.OpenMapAPI
    if api then
        -- a moment for the map to come up and switch to the stitched view, then glide
        local function glide()
            local ok, u, v = pcall(api.WorldFromMap, map, x, y)
            if ok and u and api.IsStitched and api.IsStitched() then pcall(api.ShowWorld, u, v, W.ZOOM) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.2, glide) else glide() end
    elseif WorldMapFrame and WorldMapFrame.SetMapID then
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, map)
    end
    return true
end

--- Somebody without a dot was clicked: their raider card if they have one, else say plainly why
--- there is nothing to show (Arn, 16 Oct: "no raider or boss called Fistfull Ofpills <raider>").
--- The roster gives Forever's whole name and the log the first one, so the first word is tried too.
---
--- THEIR ZONE, EVEN WITHOUT A BIS ADDON (Arn, 16 Oct: "if i click on people that dont have our
--- addon can it still read where they are at and open to that map?"). The roster says which ZONE
--- every online member is in; only a BiS addon says where in it. So the click opens that zone's map
--- and says "somewhere in" - never a dot we would have to invent.
W.ROOTS = { 947, 946 }          -- Azeroth, then the cosmic map: every zone hangs under one of them
W.zoneMaps = nil                -- zone name, lowercased -> uiMapID, filled on first need
function W.MapForZone(zone)
    if type(zone) ~= "string" or zone == "" or zone == "?" then return nil end
    if not W.zoneMaps then
        W.zoneMaps = {}
        if C_Map and C_Map.GetMapChildrenInfo then
            for _, root in ipairs(W.ROOTS) do
                local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
                for _, info in ipairs(ok and type(list) == "table" and list or {}) do
                    local name, id = info.name, num(info.mapID)
                    if type(name) == "string" and id and not hidden(name) then
                        local key = name:lower()
                        -- a zone or a city beats a dungeon floor of the same name
                        local t = num(info.mapType) or 9
                        local have = W.zoneMaps[key]
                        if not have or t < have.t then W.zoneMaps[key] = { id = id, t = t } end
                    end
                end
            end
        end
    end
    local hit = W.zoneMaps[zone:lower()]
    return hit and hit.id or nil
end

--- IN AN INSTANCE (Arn, 19 Oct: "darth is online can we have a check that says this person is in an
--- instance"): the roster names the zone - "Shadowfang Keep" - and no BiS addon shares a spot inside
--- one, so there is never a dot. The kind, from the client's map types when it lists the place (4 =
--- Enum.UIMapType.Dungeon), else from the Classic names below (UNVERIFIED on Forever: its own new
--- instances will be missing until seen). Answers "dungeon", "raid", "battleground", or nil.
W.INSTANCES = {}
for kind, names in pairs({
    dungeon = { "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Deadmines", "Shadowfang Keep",
        "Blackfathom Deeps", "The Stockade", "Stormwind Stockade", "Gnomeregan", "Razorfen Kraul",
        "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon",
        "The Temple of Atal'Hakkar", "Sunken Temple", "Blackrock Depths", "Blackrock Spire",
        "Lower Blackrock Spire", "Upper Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance" },
    raid = { "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj",
        "Temple of Ahn'Qiraj", "Ahn'Qiraj Temple", "Naxxramas" },
    battleground = { "Warsong Gulch", "Arathi Basin", "Alterac Valley" },
}) do
    for _, n in ipairs(names) do W.INSTANCES[n:lower()] = kind end
end
--- DOCKED (Arn, 19 Oct: "the idea for the map is how they track the oil tankers out at sea ... a player in
--- an instance should show them but docked in an instance"): where each instance's door is, on its zone
--- map - { uiMapID, x %, y % } - so a guildmate inside is drawn at the door. Classic's entrances, from
--- public game data (Questie's dungeon table, cross-checked against Wowhead Classic; 19 Oct): the four
--- Blackrock instances share the mountain's Searing Gorge door; Ahn'Qiraj's two share the gate; the
--- battlegrounds have a door per faction. UNVERIFIED on Forever: its own instances are not here.
W.DOCK = {
    ["ragefire chasm"] = { 1454, 52.6, 49.0 }, ["wailing caverns"] = { 1413, 46.0, 36.5 },
    ["the deadmines"] = { 1436, 42.5, 71.7 }, ["deadmines"] = { 1436, 42.5, 71.7 },
    ["shadowfang keep"] = { 1421, 44.8, 67.8 }, ["blackfathom deeps"] = { 1440, 14.5, 14.2 },
    ["the stockade"] = { 1453, 42.3, 58.9 }, ["stormwind stockade"] = { 1453, 42.3, 58.9 },
    ["gnomeregan"] = { 1426, 24.3, 39.8 }, ["razorfen kraul"] = { 1413, 42.9, 90.2 },
    ["scarlet monastery"] = { 1420, 82.6, 33.8 }, ["razorfen downs"] = { 1413, 49.0, 93.9 },
    ["uldaman"] = { 1418, 44.6, 12.1 }, ["zul'farrak"] = { 1446, 38.7, 20.1 }, ["maraudon"] = { 1443, 29.1, 62.5 },
    ["the temple of atal'hakkar"] = { 1435, 69.9, 53.5 }, ["sunken temple"] = { 1435, 69.9, 53.5 },
    ["blackrock depths"] = { 1427, 34.8, 85.3 }, ["blackrock spire"] = { 1427, 34.8, 85.3 },
    ["lower blackrock spire"] = { 1427, 34.8, 85.3 }, ["upper blackrock spire"] = { 1427, 34.8, 85.3 },
    ["molten core"] = { 1427, 34.8, 85.3 }, ["blackwing lair"] = { 1427, 34.8, 85.3 },
    ["dire maul"] = { 1444, 59.2, 45.1 }, ["stratholme"] = { 1423, 31.3, 15.7 }, ["scholomance"] = { 1422, 69.7, 73.2 },
    ["onyxia's lair"] = { 1445, 52.6, 76.8 }, ["zul'gurub"] = { 1434, 53.9, 17.6 },
    ["ruins of ahn'qiraj"] = { 1451, 28.6, 92.3 }, ["temple of ahn'qiraj"] = { 1451, 28.6, 92.3 },
    ["ahn'qiraj temple"] = { 1451, 28.6, 92.3 }, ["naxxramas"] = { 1423, 39.9, 25.8 },
    ["warsong gulch"] = { Horde = { 1413, 46.5, 8.6 }, Alliance = { 1440, 61.7, 84.5 } },
    ["arathi basin"] = { Horde = { 1417, 73.5, 29.0 }, Alliance = { 1417, 45.4, 44.4 } },
    ["alterac valley"] = { Horde = { 1416, 63.6, 58.8 }, Alliance = { 1416, 39.5, 80.2 } },
}
--- An instance's door: its zone map and x, y (0-1), for your faction's door where there are two; nil.
function W.Dock(zone)
    if type(zone) ~= "string" then return nil end
    local d = W.DOCK[zone:lower()]
    if not d then return nil end
    if not d[1] then
        local faction
        if UnitFactionGroup then
            local ok, f = pcall(UnitFactionGroup, "player")
            faction = ok and f or nil
        end
        d = d[faction or ""] or d.Horde or d.Alliance
    end
    return d[1], d[2] / 100, d[3] / 100
end

function W.Instance(zone)
    if type(zone) ~= "string" or zone == "" or zone == "?" then return nil end
    local kind = W.INSTANCES[zone:lower()]
    if kind then return kind end
    W.MapForZone(zone)                                     -- fills W.zoneMaps
    local hit = W.zoneMaps and W.zoneMaps[zone:lower()]
    if hit and hit.t == 4 then return "dungeon" end
    return nil
end

function W.Person(row)
    -- in a dungeon, a raid or a battleground: say so - no spot is shared in there, so no map shows them
    local kind = W.Instance(row.zone)
    if kind then
        K.Say(("%s is in a %s - %s, level %s. Inside an instance nobody's spot is shared.")
            :format(row.name, kind, row.zone, tostring(row.level or "?")), "ink2")
        return "instance"
    end
    local map = W.MapForZone(row.zone)
    if map and W.Pieces(map) then
        K.whereMap, W.focus = map, nil
        K.Paint()
        K.Say(("%s is somewhere in %s - no exact spot: no BiS addon is sharing theirs"):format(row.name, row.zone), "ink2")
        return "map"
    end
    local cards = ns.S.Cards()
    for _, name in ipairs({ row.name, (row.name:match("^(%S+)")) }) do
        if K.Parse(name .. " <raider>", cards, {}) == "raider" then return K.Go(name .. " <raider>") end
    end
    K.Say(("%s - %s, level %s: no dot (no BiS addon sharing a spot), no map for that place, no raid nights yet")
        :format(row.name, row.zone or "?", tostring(row.level or "?")), "ink2")
    return nil
end

--------------------------------------------------------------------
-- frames
--------------------------------------------------------------------

function K.BuildWhere(page, bodyH)
    local ui = K.ui
    page.map = ui.Panel(page, "MAP", 8, 0, W.MAP_W, bodyH - 4)
    local canvas = CreateFrame("Frame", nil, page.map)
    canvas:SetPoint("TOPLEFT", 4, -22)
    canvas:SetSize(W.MAP_W - 8, bodyH - 30)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    page.canvas, page.cw, page.ch = canvas, W.MAP_W - 8, bodyH - 30
    -- THE LAND: a frame exactly the size of the land shown, clipping what lies past it - a capital's
    -- trimmed parchment would otherwise show again in the panel's spare room (16 Oct, Orgrimmar)
    page.land = CreateFrame("Frame", nil, canvas)
    if page.land.SetClipsChildren then page.land:SetClipsChildren(true) end
    page.tiles, page.dots, page.labels, page.marks = {}, {}, {}, {}
    page.none = ui.Text(canvas, 13, "ink2")
    page.none:SetPoint("TOPLEFT", 12, -12)
    page.none:SetWidth(W.MAP_W - 40)
    if page.none.SetWordWrap then page.none:SetWordWrap(true) end

    local lx = W.MAP_W + 16
    -- OPEN THE BIG MAP HERE: zoomed right in on OpenMap when it is installed, the game's own map on
    -- this zone when it is not
    local open = CreateFrame("Button", nil, page.map)
    open:SetPoint("TOPRIGHT", -96, -1)
    open:SetSize(120, 16)
    local obg = open:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    ui.Fill(obg, "sunken")
    local ohi = K.Pop(open)
    open.fs = ui.Text(open, 11, "gold", "CENTER")
    open.fs:SetPoint("CENTER", 0, 0)
    open:SetScript("OnClick", function() W.OpenBig() end)
    page.open = open
    -- WORLD: back out to the whole guild after a click zoomed into somebody's zone
    local world = CreateFrame("Button", nil, page.map)
    world:SetPoint("RIGHT", open, "LEFT", -6, 0)
    world:SetSize(60, 16)
    local wbg = world:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    ui.Fill(wbg, "sunken")
    local whi = K.Pop(world)
    world.fs = ui.Text(world, 11, "gold", "CENTER")
    world.fs:SetPoint("CENTER", 0, 0)
    world.fs:SetText("WORLD")
    world:SetScript("OnClick", function() K.whereMap, W.focus = W.WORLD, nil K.Paint() end)
    page.world = world

    page.who = ui.Panel(page, "WHO IS WHERE", lx, 0, K.W - lx - 8, bodyH - 4)
    page.grid = ui.Grid(page.who, { "NAME", "LVL", "RANK", "" },
        { { 120, "LEFT" }, { 30, "RIGHT" }, { 84, "LEFT" }, { 54, "RIGHT" } }, K.LIST_ROWS, 22,
        function(key)
            local row = W.byKey and W.byKey[key]
            if row and row.spot then K.whereMap, W.focus = row.spot.map, row.spot K.Paint()
            elseif row and row.name then W.Person(row) end
        end)
    page.hint = ui.Text(page.who, 12, "ink2")
    page.hint:SetPoint("TOPLEFT", 12, -44)
    page.hint:SetWidth(K.W - lx - 40)
    if page.hint.SetWordWrap then page.hint:SetWordWrap(true) end
    return page
end

local function Tile(p, i)
    local t = p.tiles[i]
    if not t then
        t = p.land:CreateTexture(nil, "BORDER")
        p.tiles[i] = t
    end
    return t
end

--- A zone marker: a purple square on a dark middle (gold on gold parchment was lost - Arn, 16 Oct),
--- and "Zone N" outlined under it.
local function Mark(p, i)
    local m = p.marks[i]
    if not m then
        m = CreateFrame("Frame", nil, p.land)
        m:SetSize(12, 12)
        local mid = m:CreateTexture(nil, "ARTWORK")
        mid:SetPoint("TOPLEFT", -1, 1)
        mid:SetPoint("BOTTOMRIGHT", 1, -1)
        mid:SetColorTexture(0, 0, 0, 0.6)
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
                                { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
            local t = m:CreateTexture(nil, "OVERLAY")
            t:SetPoint(side[1], 0, 0)
            t:SetPoint(side[2], 0, 0)
            if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
            t:SetColorTexture(K.ui.rgb("accent"))
        end
        m.label = W.MapText(p.land, 10, "ink")
        m.label:SetPoint("TOP", m, "BOTTOM", 0, -1)
        p.marks[i] = m
    end
    return m
end

--- MAP WORDS ARE OUTLINED (Arn, 16 Oct: "yellow is getting lost on the yellow background of the map"):
--- black round the letters, as the game draws its own map text, so any colour reads on parchment.
local function MapText(parent, size, colour)
    local fs = K.ui.Text(parent, size, colour)
    if fs.SetFont then pcall(fs.SetFont, fs, K.FONT, size, "OUTLINE") end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    return fs
end
W.MapText = MapText

--- ONE LABEL FOR A CROWD (Arn, 19 Oct, partied with four guildmates: "yeah its crowded" - "you",
--- "Frankadank Sithlord" and "Hillsbrad Foothills 2" printed through each other on one spot). Things
--- whose labels would land within W.CROWD_X / W.CROWD_Y px of each other share ONE label - the first
--- one's, with "+N" for the people folded into it. You lead a crowd you are in, then dots, then zone
--- markers. Every dot still draws; the list beside the map still names everyone.
--- items: { x =, y = (map px), n = people it stands for, me = bool } in placing order. Answers, per
--- item, lead = true and extra = people folded in, or lead = false.
W.CROWD_X, W.CROWD_Y = 44, 12
function W.Crowd(items)
    local order = {}
    for i, it in ipairs(items) do order[#order + 1] = i end
    table.sort(order, function(a, b)
        local A, B = items[a], items[b]
        if (A.me and true or false) ~= (B.me and true or false) then return A.me and true or false end
        if (A.mark and true or false) ~= (B.mark and true or false) then return not A.mark end
        return a < b
    end)
    local out = {}
    for _, i in ipairs(order) do
        if not out[i] then
            local lead = items[i]
            out[i] = { lead = true, extra = 0 }
            for _, j in ipairs(order) do
                local o = items[j]
                if not out[j] and math.abs(o.x - lead.x) <= W.CROWD_X and math.abs(o.y - lead.y) <= W.CROWD_Y then
                    out[j] = { lead = false }
                    out[i].extra = out[i].extra + (o.n or 1)
                end
            end
        end
    end
    return out
end

local function Dot(p, i)
    local d, l = p.dots[i], p.labels[i]
    if not d then
        -- a black edge under every dot: a gold "you" on gold parchment was invisible
        d = p.land:CreateTexture(nil, "OVERLAY", nil, 2)
        d.edge = p.land:CreateTexture(nil, "OVERLAY", nil, 1)
        d.edge:SetColorTexture(0, 0, 0, 1)
        d.edge:SetPoint("TOPLEFT", d, "TOPLEFT", -1, 1)
        d.edge:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, -1)
        l = MapText(p.land, 10, "ink")
        p.dots[i], p.labels[i] = d, l
    end
    return d, l
end

--- THE LITTLE FIGURES (Arn, 18-19 Oct: "actual size so very tiny maybe like 10 pixels max"): a 3D
--- stand-in of each guildmate's race and sex (Core/Looks.lua) standing on their dot, turned the way they
--- last moved. A 3D model is not clipped by its frame, so they are kept small and few.
W.FIG_W, W.FIG_H, W.FIG_MAX = 10, 14, 40
W.prev, W.face = {}, {}
local function Fig(p, i)
    p.figs = p.figs or {}
    local m = p.figs[i]
    if not m then
        m = CreateFrame("DressUpModel", nil, p.land)
        m:SetSize(W.FIG_W, W.FIG_H)
        if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
        p.figs[i] = m
    end
    return m
end

--- Which way someone faces: toward where they went since their last spot (map y runs down).
function W.Heading(key, map, x, y)
    local was = W.prev[key]
    W.prev[key] = { map = map, x = x, y = y }
    if was and was.map == map then
        local dx, dy = x - was.x, y - was.y
        if math.abs(dx) + math.abs(dy) > 0.002 then W.face[key] = math.atan2(dx, dy) end
    end
    return W.face[key] or 0
end

function K.PaintWhere(p)
    local ui = K.ui
    local spots = W.Spots()
    local map = K.whereMap or W.AutoMap(spots)
    W.shown = map
    if W.focus and W.focus.map ~= map then W.focus = nil end
    -- the button says where it goes: OpenMap's close-up when it is here, the game's map when not
    p.open.fs:SetText(W.OpenMapHere() and (W.focus and "ZOOM IN OPENMAP" or "OPEN IN OPENMAP") or "OPEN WORLD MAP")
    if map then p.open:Show() else p.open:Hide() end
    for _, t in ipairs(p.tiles) do t:Hide() end
    -- the edge is its own texture: hiding the dot leaves it drawn (Arn, 5 Nov: black squares on every map)
    for i, d in ipairs(p.dots) do d:Hide() d.edge:Hide() p.labels[i]:Hide() end
    for _, fg in ipairs(p.figs or {}) do fg:Hide() end
    local figs, Lk = 0, ns.Looks

    -- the map
    local lw, lh, pieces = W.Pieces(map)
    local name = W.MapName(map)
    p.map.title:SetText("MAP  " .. ns.T.text("ink", (name or "nowhere known"):upper()))
    if not lw then
        p.none:SetText(map and "No map for this place." or
            "No map yet: nobody is sharing a spot, and the game will not say where you are (inside an instance?).")
        p.none:Show()
        p.map.right:SetText("")
    else
        p.none:Hide()
        local x0, y0 = lw * W.EDGE[1], lh * W.EDGE[2]
        local x1, y1 = lw - lw * W.EDGE[1], lh - lh * W.EDGE[3]
        local box = W.CROP[map]
        if box then x0, y0, x1, y1 = lw * box[1], lh * box[2], lw * box[3], lh * box[4] end
        local s = math.min(p.cw / (x1 - x0), p.ch / (y1 - y0))
        local landW, landH = (x1 - x0) * s, (y1 - y0) * s
        p.land:ClearAllPoints()
        p.land:SetPoint("TOPLEFT", p.canvas, "TOPLEFT", (p.cw - landW) / 2, -(p.ch - landH) / 2)
        p.land:SetSize(landW, landH)
        p.land:Show()
        for i, pc in ipairs(pieces) do
            local t = Tile(p, i)
            t:SetDrawLayer(pc[8] or "BORDER")             -- the fog under, the explored over
            t:SetTexture(pc[1])
            t:SetTexCoord(0, pc[4] / pc[6], 0, pc[5] / pc[7])
            t:SetSize(pc[4] * s, pc[5] * s)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", p.land, "TOPLEFT", (pc[2] - x0) * s, -(pc[3] - y0) * s)
            t:SetVertexColor(0.78, 0.78, 0.78, 1)        -- a shade down, so the dots stand out
            t:Show()
        end
        -- the dots on this map: class colours, me in gold and a size bigger
        local colours = _G.RAID_CLASS_COLORS
        local n = 0
        local crowd = {}                                  -- every label, for W.Crowd
        for _, sp in ipairs(spots) do
            -- a spot on its own zone, or placed onto the map shown (the world view)
            local mx, my = W.OnMap(sp.map, sp.x, sp.y, map)
            if mx then
                local px, py = (mx * lw - x0) * s, (my * lh - y0) * s
                if px >= 0 and py >= 0 and px <= landW and py <= landH then
                    n = n + 1
                    local d, l = Dot(p, n)
                    local m = K.Member(sp.name)
                    local cc = m and m.class and colours and colours[m.class]
                    -- their stand-in, when we know their race and sex: the figure stands on a small dot
                    local display = Lk and figs < W.FIG_MAX and (sp.me and Lk.Mine() or Lk.Display(sp.name))
                    local size = display and 4 or (sp.me and 10 or 8)
                    d:SetSize(size, size)
                    if sp.me then d:SetColorTexture(ui.rgb("gold")) elseif cc then d:SetColorTexture(cc.r, cc.g, cc.b, 1)
                    else d:SetColorTexture(ui.rgb("ink")) end
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", p.land, "TOPLEFT", px, -py)
                    d:Show()
                    d.edge:Show()
                    if display then
                        figs = figs + 1
                        local fg = Fig(p, figs)
                        if fg._display ~= display then                -- a call only when it changes
                            fg._display = display
                            pcall(fg.SetDisplayInfo, fg, display)
                        end
                        local face = W.Heading(sp.key or sp.name, sp.map, sp.x, sp.y)
                        if fg._face ~= face then fg._face = face pcall(fg.SetFacing, fg, face) end
                        fg:ClearAllPoints()
                        fg:SetPoint("BOTTOM", p.land, "TOPLEFT", px, -py)
                        fg:Show()
                    end
                    -- the forename: "Frankadank", not "Frankadank Sithlord" (the list has the rest)
                    local short = sp.me and "you" or (tostring(sp.name):match("^(%S+)") or sp.name)
                    l:SetTextColor(ui.rgb(sp.me and "gold" or "ink"))
                    l:ClearAllPoints()
                    l:SetPoint("LEFT", d, "RIGHT", 3, 0)
                    crowd[#crowd + 1] = { x = px, y = py, n = 1, me = sp.me, text = short, label = l }
                end
            end
        end
        -- ZONE MARKERS on a map bigger than a zone: guildmates with no dot (no BiS addon sharing),
        -- counted in the middle of the zone the roster says they are in - never a dot we invented
        for _, m in ipairs(p.marks) do m:Hide() m.label:Hide() end
        local marks = 0
        -- DOCKED: a guildmate in an instance, at its door (W.Dock) - on any map that shows the door,
        -- the world or the zone itself (Arn, 19 Oct: "show them but docked in an instance")
        local docked, dockOrder = {}, {}
        for _, r in ipairs(W.Rows(spots)) do
            if not r.header and not r.spot and W.Instance(r.zone) then
                local d = docked[r.zone]
                if not d then d = {} docked[r.zone] = d dockOrder[#dockOrder + 1] = r.zone end
                d[#d + 1] = tostring(r.name):match("^(%S+)") or r.name
            end
        end
        table.sort(dockOrder)
        for _, zone in ipairs(dockOrder) do
            local who = docked[zone]
            local dm, dx, dy = W.Dock(zone)
            local cx, cy
            if dm then cx, cy = W.OnMap(dm, dx, dy, map) end
            if cx then
                local px, py = (cx * lw - x0) * s, (cy * lh - y0) * s
                if px >= 0 and py >= 0 and px <= landW and py <= landH then
                    marks = marks + 1
                    local mk = Mark(p, marks)
                    mk:ClearAllPoints()
                    mk:SetPoint("CENTER", p.land, "TOPLEFT", px, -py)
                    mk:Show()
                    crowd[#crowd + 1] = { x = px, y = py, n = #who, mark = true, label = mk.label,
                        text = #who == 1 and ("%s - docked: %s"):format(who[1], zone)
                            or ("%d docked: %s"):format(#who, zone) }
                end
            end
        end
        if map == W.WORLD or (W.MapInfoType(map) or 9) <= 2 then
            local nodot = {}
            for _, r in ipairs(W.Rows(spots)) do
                if not r.header and not r.spot and r.zone and r.zone ~= "?" and not W.Instance(r.zone) then
                    nodot[r.zone] = (nodot[r.zone] or 0) + 1
                end
            end
            for zone, count in pairs(nodot) do
                local zm = W.MapForZone(zone)
                local cx, cy
                if zm then cx, cy = W.OnMap(zm, 0.5, 0.5, map) end
                if cx then
                    local px, py = (cx * lw - x0) * s, (cy * lh - y0) * s
                    if px >= 0 and py >= 0 and px <= landW and py <= landH then
                        marks = marks + 1
                        local mk = Mark(p, marks)
                        mk:ClearAllPoints()
                        mk:SetPoint("CENTER", p.land, "TOPLEFT", px, -py)
                        mk:Show()
                        crowd[#crowd + 1] = { x = px, y = py, n = count, mark = true,
                                              text = ("%s %d"):format(zone, count), label = mk.label }
                    end
                end
            end
        end
        -- the labels: one per crowd (W.Crowd)
        for i, c in ipairs(W.Crowd(crowd)) do
            local it = crowd[i]
            if c.lead then
                it.label:SetText(c.extra > 0 and ("%s +%d"):format(it.text, c.extra) or it.text)
                it.label:Show()
            else
                it.label:Hide()
            end
        end
        -- short: the title bar is shared with WORLD and OPEN (16 Oct: the long form ran under them)
        p.map.right:SetText(("%d dot%s"):format(n, n == 1 and "" or "s") .. (marks > 0 and ("  +%d zone%s"):format(marks, marks == 1 and "" or "s") or ""))
    end
    if p.world then
        if map == W.WORLD or not W.WorldReady() then p.world:Hide() else p.world:Show() end
    end

    -- the list
    local rows = W.Rows(spots)
    W.byKey = {}
    local off = ui.Scroll(p.grid, #rows)
    local online = 0
    for _, r in ipairs(rows) do if not r.header then online = online + 1 end end
    p.who.right:SetText(("%d online"):format(online) .. ui.Showing(p.grid))
    if #rows == 0 then
        p.hint:SetText(IsInGuild and IsInGuild() and "Nobody in the guild is online - or the roster has not arrived yet."
            or "Not in a guild.")
        p.hint:Show()
    else
        p.hint:Hide()
    end
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if not r then
            ui.SetRow(row, nil, {})
        elseif r.header then
            local kind = W.Instance(r.zone)
            ui.SetRow(row, "#" .. r.zone, { r.zone .. (kind and (" (" .. kind .. ")") or ""), r.n, "", "" },
                { "gold", "gold", "muted", "muted" })
            W.byKey["#" .. r.zone] = r
        else
            local cc = r.class and colours and colours[r.class]
            local kind = not r.spot and W.Instance(r.zone)
            ui.SetRow(row, r.key, { "  " .. r.name, r.level or "", r.rank or "",
                                    r.spot and "on map" or kind and ("in " .. kind) or "" },
                { cc and { cc.r, cc.g, cc.b } or "ink", "ink2", "muted",
                  (r.spot and r.spot.map == map) and "good" or "accent" })
            row.who = r.name
            W.byKey[r.key] = r
        end
    end
end
