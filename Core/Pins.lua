--[[
  BiSGuild :: Core/Pins.lua - guildmates on the game's own world map, as RADAR TRACKS.

  Arn, 16 Oct 2026: guildmates on the world map, and "the problem is not everyone is going to install
  OpenMap". So the marks go on Blizzard's world map through HereBeDragons-Pins - the library Questie
  and BiS Tools' farm pins draw with - and any map addon that shows that library's pins shows them
  too (OpenMap's changelog says it does). Nobody needs anything but BiS Guild.

  RADAR TRACKS (8 Nov 2026, Arn: "IF we want ours to not step aside we should make them better think combat jet
  fighter" ... "Build it"; mockup https://claude.ai/artifact/7JWzapTVKpsNUnR8Zv6iAi). Each guildmate is a TRACK:
    the friendly symbol  a half-circle over a base line (the radar sign for a friendly aircraft) in their class
                         colour - Lines painted WHITE8X8 + a tint
    the speed line       from the symbol the way they are heading, as long as they are fast (M.SPEEDS): worked out
                         from their last two spots (M.Motion; yards by HereBeDragons' zone size), none standing still
    the callsign         "FRANK 26" beside it - on their own zone's map only (M.TagFor), never on the continent's
    lock-on              hover: four green brackets close round it, and the card (name, class, level, heading and
                         speed, where, how old the spot is); a click opens their card in the terminal, as ever
    old spots fade       a spot older than M.STALE goes hollow and grey, its age on the tag, until the lib drops it
    groups merge         tracks within M.MERGE of each other on one map are ONE box with a count (M.Clusters);
                         hover it for the names, click for the terminal's WHERE page
  It is redrawn when a spot arrives (at most once a second) and every M.SWEEP; nothing runs while nothing changes.

  WHERE THE SPOTS COME FROM: LibBiSComm's shared spots (minor 12) - every BiS addon sends its player's
  spot on the guild channel while they move, outside instances. A guildmate without a BiS addon has
  no track; the terminal's WHERE list still shows their zone from the roster. Your own position is the
  game's arrow.

  ON THE ZONE MAP AND ONE LEVEL UP (HBD_PINS_WORLDMAP_SHOW_PARENT), as BiS Tools' farm pins, which
  Arn has seen land right. Not the whole world: OpenMap's notes (16 Oct) say this library's continent
  and world positions come out wrong on Forever.

  ONE FRAME PER PIN, never shared with the minimap (BiS Tools learned it 6 Oct: the library re-parents
  a pin into whichever map draws it, and a frame on two maps shows on neither).

  NOT YOUR GROUP (Arn, 22 Oct, two marks on one cousin: "both of these blue marks are frank how about they only
  show up if we are not in a party or raid"): the game already draws your party and raid on its map, so a
  guildmate in your group gets no track; the moment he leaves it, it comes back (GROUP_ROSTER_UPDATE).

  `/bisg dots off` takes them all away; `/bisg dots on` brings them back.
]]
local ADDON, ns = ...

local M = {}
ns.Pins = M

M.SIZE = 26             -- a track's frame (the symbol in the middle, room for its speed line)
M.ARC_R = 6             -- the half-circle's radius
M.ARC_SEG = 6           -- lines that make the half-circle
M.SWEEP = 30            -- seconds: stale spots are dropped by the lib; this notices they went
M.STALE = 130           -- seconds: a spot older than this missed its resend (the lib's 120) - hollow, grey
M.AGED = 60             -- seconds: past this the tag says how old the spot is
M.MOTION_GAP = 120      -- seconds: two spots further apart than this say nothing about speed
M.MERGE = 0.02          -- of a map's width: tracks this close on one map are one box
-- yards a second -> the speed word and the speed line's length (run 7, a mount 11-14, a flight ~26)
M.SPEEDS = { { 0.6, "STILL", 0 }, { 9, "ON FOOT", 7 }, { 17, "FAST", 12 }, { math.huge, "VERY FAST", 17 } }
M.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
M.WHITE = "Interface\\Buttons\\WHITE8X8"
M.LOCK = { 0.30, 1, 0.60 }        -- the lock-on green
M.pins = {}             -- key (a sender, or "#map:n" for a box) -> { frame }
M.pool = {}
M.motion = {}           -- sender -> { map, x, y, at, hdg (radians from north), speed (yards/s) }

local function HBD() return LibStub and LibStub("HereBeDragons-Pins-2.0", true) end
local function HBDCore() return LibStub and LibStub("HereBeDragons-2.0", true) end
local function Lib() return _G.LibBiSComm end
local function Now() return GetTime and GetTime() or 0 end

--[[ OPENMAP SHOWS THE GUILD TOO (8 Nov 2026, Arn: "open maps does the same thing now"). First answer: we stepped
  aside. Arn's answer to that: make ours better - so the tracks STAY ON beside OpenMap, and one line at the first login
  with it says that OpenMap's own "Friends and guild" switch is the one to turn off if two marks are too many. Our switch
  is in OpenMap's menu too (OpenMapAPI.RegisterMenuToggle, its public "add your own"). OpenMap is known by its API's
  table, asked late (it loads after us). BiSGuildAPI.MapDots() lets it (or anyone) ask us. ]]
M.TOGGLE_ID = "bisguild_dots"

function M.Neighbour() return type(_G.OpenMapAPI) == "table" end

function M.On() return ns.DB().mapDots ~= false end

--- Once, the first login with OpenMap: both draw the guild; which switch is whose.
function M.Tell()
    local d = ns.DB()
    if not (M.On() and M.Neighbour()) or d.toldOpenMap then return false end
    d.toldOpenMap = true
    ns.Print("OpenMap draws your guild too. BiS Guild's radar tracks stay on; two marks each too many? Turn off "
        .. "OpenMap's \"Friends and guild\", or ours: %s (also in OpenMap's menu).", ns.T.text("muted", "/bisg dots off"))
    return true
end

--- Our switch in OpenMap's menu (its API's "add your own"), once.
function M.Hook()
    local api = _G.OpenMapAPI
    if M.hooked or type(api) ~= "table" or type(api.RegisterMenuToggle) ~= "function" then return false end
    local ok = pcall(api.RegisterMenuToggle, "BiSGuild", {
        id = M.TOGGLE_ID, label = "BiS Guild radar tracks",
        get = function() return M.On() end,
        set = function(v) if ns.Opt and ns.Opt.SetDots then ns.Opt.SetDots(v) end end,
    })
    M.hooked = ok
    return ok
end

--- Where a track stands, by its own map (the roster's zone lags: Arn's screenshot, a dot in Tirisfal said "Durotar").
function M.ZoneOf(map)
    return ns.Where and ns.Where.MapName and ns.Where.MapName(map) or nil
end

--- Who is in your party or raid, by whole name (Forever: "Name Surname", the name the shared spots carry).
function M.Grouped()
    local set = {}
    local okN, n = pcall(GetNumGroupMembers)
    n = okN and type(n) == "number" and n or 0
    if n == 0 then return set end
    local raid = IsInRaid and IsInRaid() == true
    for i = 1, raid and n or n - 1 do
        local ok, name = pcall(GetUnitName, (raid and "raid" or "party") .. i, false)
        if ok and type(name) == "string" and name ~= "" then set[(name:gsub("%-.*$", ""))] = true end
    end
    return set
end

-- ------------------------------------------------------------------ motion

--- The speed word and the line's length for yards a second (nil = unknown: no line, no word).
function M.SpeedOf(yps)
    if type(yps) ~= "number" then return nil, 0 end
    for _, s in ipairs(M.SPEEDS) do if yps < s[1] then return s[2], s[3] end end
end

function M.Compass(hdg)
    if type(hdg) ~= "number" then return nil end
    local i = math.floor(((hdg % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8 + 1
    return M.COMPASS[i]
end

--- A new spot against the last one: heading (radians clockwise from north) and speed (yards a second). Same map,
--- a few seconds to two minutes apart; the zone's size in yards from HereBeDragons (unknown size: no speed, no line).
function M.Motion(sender, s)
    local was = M.motion[sender]
    local now = { map = s.map, x = s.x, y = s.y, at = s.at }
    if was and was.at == s.at and was.x == s.x and was.y == s.y then return was end   -- nothing new
    if was and was.map == s.map and type(s.at) == "number" and type(was.at) == "number" then
        local dt = s.at - was.at
        if dt > 0.5 and dt <= M.MOTION_GAP then
            local core = HBDCore()
            local w, h
            if core and core.GetZoneSize then
                local ok, a, b = pcall(core.GetZoneSize, core, s.map)
                if ok and type(a) == "number" and type(b) == "number" and a > 0 and b > 0 then w, h = a, b end
            end
            if w then
                local east, north = (s.x - was.x) * w, (was.y - s.y) * h
                local dist = math.sqrt(east * east + north * north)
                now.speed = dist / dt
                if dist > 0.5 then now.hdg = math.atan2(east, north) % (2 * math.pi) else now.hdg = was.hdg end
            end
        elseif dt <= 0.5 then
            now.hdg, now.speed = was.hdg, was.speed
        end
    end
    M.motion[sender] = now
    return now
end

-- ------------------------------------------------------------------ the pin

local function line(b, layer)
    local l = b:CreateLine(nil, layer or "OVERLAY")
    l:SetTexture(M.WHITE)
    l:SetThickness(2)
    return l
end

local function tint(l, r, g, bl, a) l:SetVertexColor(r, g, bl, a or 1) end

local function NewPin()
    local b = table.remove(M.pool)
    if b then return b end
    b = CreateFrame("Button", nil, UIParent)
    b:SetSize(M.SIZE, M.SIZE)
    -- the friendly symbol: a half-circle (M.ARC_SEG lines) over its base
    b.arc = {}
    local r, cy = M.ARC_R, -2
    for i = 1, M.ARC_SEG do
        local a0 = math.pi * (i - 1) / M.ARC_SEG
        local a1 = math.pi * i / M.ARC_SEG
        local l = line(b)
        l:SetStartPoint("CENTER", b, -math.cos(a0) * r, cy + math.sin(a0) * r)
        l:SetEndPoint("CENTER", b, -math.cos(a1) * r, cy + math.sin(a1) * r)
        b.arc[i] = l
    end
    b.base = line(b)
    b.base:SetStartPoint("CENTER", b, -r, cy)
    b.base:SetEndPoint("CENTER", b, r, cy)
    -- the speed line
    b.vec = line(b, "ARTWORK")
    b.vec:SetThickness(1.5)
    -- the box (a group)
    -- the box (a group): four sides, 4 px in from the frame's edge
    b.box = {}
    for i, spec in ipairs({ { "TOPLEFT", 4, -4, "TOPRIGHT", -4, -4, true }, { "BOTTOMLEFT", 4, 4, "BOTTOMRIGHT", -4, 4, true },
                            { "TOPLEFT", 4, -4, "BOTTOMLEFT", 4, 4, false }, { "TOPRIGHT", -4, -4, "BOTTOMRIGHT", -4, 4, false } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(M.LOCK[1], M.LOCK[2], M.LOCK[3], 1)
        t:SetPoint(spec[1], spec[2], spec[3])
        t:SetPoint(spec[4], spec[5], spec[6])
        if spec[7] then t:SetHeight(2) else t:SetWidth(2) end
        b.box[i] = t
    end
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.count:SetPoint("CENTER", 0, 0)
    b.count:SetTextColor(M.LOCK[1], M.LOCK[2], M.LOCK[3])
    -- the callsign
    b.tag = b:CreateFontString(nil, "OVERLAY")
    b.tag:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.tag:SetPoint("LEFT", b, "RIGHT", -2, 4)
    -- lock-on: four corners, shown under the mouse
    b.lock = {}
    for i, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local h = b:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(M.LOCK[1], M.LOCK[2], M.LOCK[3], 1)
        h:SetPoint(c[1], 0, 0) h:SetSize(7, 2)
        local v = b:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(M.LOCK[1], M.LOCK[2], M.LOCK[3], 1)
        v:SetPoint(c[1], 0, 0) v:SetSize(2, 7)
        h:Hide() v:Hide()
        b.lock[i * 2 - 1], b.lock[i * 2] = h, v
    end
    function b:Locked(on)
        for _, t in ipairs(self.lock) do if on then t:Show() else t:Hide() end end
    end
    b:SetScript("OnEnter", function(self)
        self:Locked(true)
        local tip = _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        for _, l in ipairs(M.CardLines(self)) do tip:AddLine(l[1], l[2], l[3], l[4]) end
        tip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Locked(false) if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self)
        if not (ns.K and ns.K.Show) then return end
        if self.members then ns.K.Show("where") elseif self.who then ns.K.Show(self.who .. " <raider>") end
    end)
    -- the callsign only on the track's own zone map: the map's id is asked each time the map draws it
    b:SetScript("OnShow", function(self) M.TagFor(self) end)
    return b
end

--- The callsign shows on the track's own zone, never one level up (the continent would be a wall of names).
function M.TagFor(b)
    local wm = _G.WorldMapFrame
    local shown
    if wm and wm.GetMapID then
        local ok, id = pcall(wm.GetMapID, wm)
        shown = ok and id or nil
    end
    local on = b.who ~= nil and b.members == nil and (shown == nil or shown == b.map)
    if on then b.tag:Show() else b.tag:Hide() end
    return on
end

--- The HUD card under the mouse: { text, r, g, b } a line.
function M.CardLines(b)
    local L, g = {}, M.LOCK
    if b.members then
        L[#L + 1] = { ("%d GUILDMATES HERE"):format(#b.members), g[1], g[2], g[3] }
        for _, who in ipairs(b.members) do L[#L + 1] = { who, 1, 1, 1 } end
        local zone = M.ZoneOf(b.map)
        if zone then L[#L + 1] = { zone, 0.6, 0.65, 0.62 } end
        L[#L + 1] = { "click: the terminal's WHERE page", 0.6, 0.65, 0.62 }
        return L
    end
    if not b.who then return L end
    L[#L + 1] = { "LOCK  " .. b.who:upper(), g[1], g[2], g[3] }
    local m = ns.K and ns.K.Member(b.who)
    if m then L[#L + 1] = { ("%s  LVL %s  %s"):format(tostring(m.class or ""):upper(), tostring(m.level or "?"),
        tostring(m.rank or "")), 1, 1, 1 } end
    local mo = M.motion[b.who]
    local word = mo and M.SpeedOf(mo.speed)
    if word then
        local dir = word ~= "STILL" and M.Compass(mo.hdg) or nil
        L[#L + 1] = { (dir and ("HDG " .. dir .. "  ") or "") .. word, 1, 1, 1 }
    end
    local zone = M.ZoneOf(b.map) or (m and m.zone)
    local age = b.at and math.max(0, math.floor(Now() - b.at)) or nil
    local spot = (zone or "?") .. ((b.x and b.y) and ("  %d,%d"):format(math.floor(b.x * 100), math.floor(b.y * 100)) or "")
    L[#L + 1] = { spot .. (age and ("  %ds ago"):format(age) or ""), 0.6, 0.65, 0.62 }
    L[#L + 1] = { "BiS Guild", 0.73, 0.5, 1 }
    return L
end

--- Dress a pin as one guildmate's track.
local function dressTrack(b, sender, s, colour)
    local stale = type(s.at) == "number" and (Now() - s.at) > M.STALE
    local age = type(s.at) == "number" and (Now() - s.at) or 0
    local r, g, bl = colour.r, colour.g, colour.b
    if stale then r, g, bl = 0.75, 0.75, 0.75 end
    local a = stale and 0.45 or 1
    b.who, b.members, b.map, b.x, b.y, b.at, b.stale = sender, nil, s.map, s.x, s.y, s.at, stale
    for _, l in ipairs(b.arc) do tint(l, r, g, bl, a) l:Show() end
    tint(b.base, r, g, bl, a) b.base:Show()
    for _, t in ipairs(b.box) do t:Hide() end
    b.count:Hide()
    -- the speed line: from the middle of the base, the way they head, as long as they are fast
    local mo = M.motion[sender]
    local _, len = M.SpeedOf(mo and mo.speed)
    if mo and mo.hdg and len and len > 0 and not stale then
        b.vec:SetStartPoint("CENTER", b, 0, -2)
        b.vec:SetEndPoint("CENTER", b, math.sin(mo.hdg) * (M.ARC_R + len), -2 + math.cos(mo.hdg) * (M.ARC_R + len))
        tint(b.vec, r, g, bl, 1)
        b.vec:Show()
    else
        b.vec:Hide()
    end
    local first = (sender:match("^(%S+)") or sender):upper()
    local m = ns.K and ns.K.Member(sender)
    local tag = first .. ((m and m.level) and (" " .. tostring(m.level)) or "")
    if age > M.AGED then tag = tag .. ("  %ds"):format(math.floor(age)) end
    b.tag:SetText(tag)
    b.tag:SetTextColor(1, 1, 1, stale and 0.45 or 0.95)
    M.TagFor(b)
end

--- Dress a pin as a box of several.
local function dressBox(b, members, map, x, y)
    b.who, b.members, b.map, b.x, b.y, b.at, b.stale = nil, members, map, x, y, nil, false
    for _, l in ipairs(b.arc) do l:Hide() end
    b.base:Hide()
    b.vec:Hide()
    for _, t in ipairs(b.box) do t:Show() end
    b.count:SetText(tostring(#members))
    b.count:Show()
    b.tag:Hide()
end

-- ------------------------------------------------------------------ drawing

local function Release(H, key)
    local p = M.pins[key]
    if not p then return end
    if H then H:RemoveWorldMapIcon(M, p.frame) end
    p.frame.who, p.frame.members = nil, nil
    p.frame:Locked(false)
    p.frame:Hide()
    M.pool[#M.pool + 1] = p.frame
    M.pins[key] = nil
end

function M.Clear()
    local H = HBD()
    for key in pairs(M.pins) do Release(H, key) end
end

--- Tracks close together on one map, as groups: { { members = { senders }, map, x, y } } (alone = one member).
--- Greedy and in name order, so the same spots always make the same groups.
function M.Clusters(spots)
    local names = {}
    for sender in pairs(spots) do names[#names + 1] = sender end
    table.sort(names)
    local groups = {}
    for _, sender in ipairs(names) do
        local s = spots[sender]
        local home
        for _, g in ipairs(groups) do
            if g.map == s.map and math.abs(g.x - s.x) <= M.MERGE and math.abs(g.y - s.y) <= M.MERGE then home = g break end
        end
        if home then
            home.members[#home.members + 1] = sender
            local n = #home.members
            home.x = home.x + (s.x - home.x) / n
            home.y = home.y + (s.y - home.y) / n
        else
            groups[#groups + 1] = { members = { sender }, map = s.map, x = s.x, y = s.y }
        end
    end
    return groups
end

--- Draw what the lib knows now. Answers how many marks are up (tracks and boxes), for the suite and `/bisg dots`.
function M.Update()
    local H, lib = HBD(), Lib()
    if not (H and lib and lib.Spots) or not M.On() then M.Clear() return 0 end
    local grouped = M.Grouped()
    local spots = {}
    for sender, s in pairs(lib:Spots()) do
        if type(sender) == "string" and type(s) == "table" and s.map and s.x and s.y and not grouped[sender] then
            spots[sender] = s
            M.Motion(sender, s)
        end
    end
    for sender in pairs(M.motion) do if not spots[sender] then M.motion[sender] = nil end end
    -- redrawn whole: a spot is a few seconds apart at most, and a group may form or part with any of them
    M.Clear()
    local colours = _G.RAID_CLASS_COLORS
    local n = 0
    for i, grp in ipairs(M.Clusters(spots)) do
        local b = NewPin()
        local key
        if #grp.members == 1 then
            local sender = grp.members[1]
            local m = ns.K and ns.K.Member(sender)
            local cc = m and m.class and colours and colours[m.class] or { r = 0.93, g = 0.91, b = 0.96 }
            key = sender
            dressTrack(b, sender, spots[sender], cc)
        else
            table.sort(grp.members)
            key = "#" .. grp.map .. ":" .. i
            dressBox(b, grp.members, grp.map, grp.x, grp.y)
        end
        M.pins[key] = { frame = b }
        if H:AddWorldMapIconMap(M, b, grp.map, grp.x, grp.y, _G.HBD_PINS_WORLDMAP_SHOW_PARENT) then n = n + 1 end
    end
    M.count = n
    return n
end

--- A spot arrived: draw within the second, not once per message (a guild moving together sends many).
function M.Soon()
    if M._armed then return end
    M._armed = true
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() M._armed = false M.Update() end)
    else
        M._armed = false
        M.Update()
    end
end

function M.Boot()
    local lib = Lib()
    if not lib or M._booted then return end
    M._booted = true
    if lib.RegisterCallback then lib:RegisterCallback("SPOT", function() M.Soon() end) end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(M.SWEEP, function() M.Update() end) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then M.Soon() return end     -- joined or left: tracks on or off
    M.Boot() M.Hook() M.Tell() M.Update()
end)
