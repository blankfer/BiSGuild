--[[
  BiSGuild :: Core/Terminal.lua - the raider terminal.

  Arn, 16 Oct 2026: "I saw a Bloomberg terminal window and I know that's the layout I want" - "type
  in a raider name, show all the gear they have ... what their attendance is, how much they consume,
  what we used to put into the raider sheet and LC sheet", and "we type in a boss name, it's like its
  own company ticker".

  THE SHAPE IS BLOOMBERG'S, THE LOOK IS OURS (Arn: "i like our bis theme, these pictures are just
  ideas"): a command line you type a name into, function keys along the top, panels of numbers, a
  ticker along the bottom - in BiSTheme's palette, at the family's 1.43:1.

    KUMLUST <RAIDER> GO     the raider card: armory, attendance, consumes, gear issues, loot won
    RAGNAROS <BOSS> GO      the boss ticker: kills, wipes, first kill, fastest, who has downed it
    RAIDERS  BOSSES         tabs: the two lists, every row clickable
    LOG                     tab: the notebook's link and its paste box (Core/Window.lua U.ShowPaste)

  The Bloomberg words are optional: a bare name works, and a start of one does when only one thing
  starts that way. Everything shown is built from the guild's record (Core/Store.lua), so a night that
  arrived over the guild channel is on the card exactly like one imported from a log.

  NO FUNCTION KEYS (Arn, 16 Oct: "those tabs - i have stuff keybound to those keys"). Bloomberg's
  F1/F2 are a raider's keybinds, so the tabs are clicked, and they say only what they are.
]]
local ADDON, ns = ...

local K = {}
ns.K = K

K.W, K.H = 860, 601            -- 1.43:1, the family's shape
K.ROW = 16
K.FONT = "Fonts\\ARIALN.TTF"   -- narrow, closest the client ships to a terminal face
K.LIST_ROWS = 27
K.STRIP = 12                   -- nights in an attendance strip
-- THE HOVER IS A TINT, NOT A COVER (Arn's screenshot, 16 Oct: the hovered row's item went faded).
-- The client draws the HIGHLIGHT layer above the text, so a highlight at 0.8 washes the words out.
-- AND IT POPS (Arn, 6 Nov, the family rule: "if you hover a row it should pop"): the tint up to 0.28 - still a tint -
-- and a bright 2 px bar on the left edge, which covers no words. K.Pop puts both on a button's HIGHLIGHT layer.
K.HOVER = 0.28
K.WHERE_EVERY = 5              -- seconds between redraws of the WHERE page while it shows
K.GLANCE_W = 470               -- the raid-night line on the right of the command bar
-- THE ROSTER, KEPT FRESH (Arn, 16 Oct: "3 guildmates online and it only shows 2 - can the window update
-- when someone comes online"). The client refreshes its copy only when an addon asks; the terminal asked
-- once, on opening. Now: every K.ROSTER_EVERY s while a page that lists people shows, at once on a
-- guildmate's online/offline line, and the page redraws on the answer.
K.ROSTER_EVERY = 15
K.LIVE = { raiders = true, where = true, roster = true }
function K.AskRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
end
K.GLANCE_BEFORE, K.GLANCE_AFTER = 12 * 3600, 6 * 3600

function K.PaintGlance()
    local g = K.frame and K.frame.glance
    if not g then return end
    local s = K.GlanceText()
    if s then g.fs:SetText(s) g:Show() else g:Hide() end
end

--- The raid-night line's words, or nil outside raid time / without a pasted event.
---   RAID NIGHT  Illidan did nothing wrong  20:00  starts in 1 h 0 min  7 of 24 online
function K.GlanceText()
    local I = ns.Inv
    local text = ns.Books().roster
    if not (I and type(text) == "string" and text ~= "") then return nil end
    local e = I.Event(text)
    local now = GetServerTime and GetServerTime()
    if not (e and e.start and now) or now < e.start - K.GLANCE_BEFORE or now > e.start + K.GLANCE_AFTER then return nil end
    local signed, online = 0, 0
    local here = I.Here()
    for _, r in ipairs(I.Read(text)) do
        if not (r.standing and I.OUT[r.standing]) then
            signed = signed + 1
            local s = I.Status(r, here)
            if s == "online" or s == "with you" then online = online + 1 end
        end
    end
    return ("%s  %s  %s  %s  %s"):format(ns.T.text("gold", "RAID NIGHT"), ns.T.text("ink", e.title or "raid"),
        ns.T.text("accent", e.time or ""), ns.T.text("ink2", I.When(e) or ""),
        ns.T.text(online > 0 and "good" or "muted", ("%d of %d online"):format(online, signed)))
end

local function T() return ns.T end
local function S() return ns.S end

--------------------------------------------------------------------
-- the words (no frames: the suite drives these directly)
--------------------------------------------------------------------

function K.Clock(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return "-" end
    local s = math.floor(ms / 1000 + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function lower(s) return tostring(s or ""):lower() end

--- What a typed line asks for. Returns kind, key - kind is "raider", "boss", "raiders", "bosses",
--- "log" - or nil and a list of near names to offer.
---   "kumlust", "KUMLUST <RAIDER> GO", "kum" (if only one name starts so), "rag <boss>", "bosses"
function K.Parse(line, cards, bosses)
    local s = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local want
    s = s:gsub("%s+[Gg][Oo]$", "")          -- a space first: "Margo" is a raider, not "Mar GO"
    local tag = s:match("<%s*(%a+)%s*>%s*$")
    if tag then
        want = lower(tag)
        s = s:gsub("%s*<%s*%a+%s*>%s*$", "")
    end
    local l = lower(s)
    if l == "" then
        if want == "raider" or want == "raiders" then return "raiders" end
        if want == "boss" or want == "bosses" then return "bosses" end
        return nil, {}
    end
    if l == "raiders" then return "raiders" end
    if l == "bosses" then return "bosses" end
    if l == "report" or l == "run report" then return "report" end
    if l == "log" then return "log" end
    if l == "where" or l == "map" then return "where" end
    if l == "roster" or l == "import" then return "roster" end
    if l == "recruits" or l == "recruit" then return "recruits" end
    if want == "raider" or want == "player" then bosses = {} end
    if want == "boss" then cards = {} end

    local starts, near = {}, {}
    local function look(kind, set)
        for name in pairs(set or {}) do
            local n = lower(name)
            if n == l then return kind, name end
            if n:sub(1, #l) == l then starts[#starts + 1] = { kind, name }
            elseif n:find(l, 1, true) then near[#near + 1] = { kind, name } end
        end
    end
    local kind, name = look("raider", cards)
    if kind then return kind, name end
    kind, name = look("boss", bosses)
    if kind then return kind, name end
    if #starts == 1 then return starts[1][1], starts[1][2] end
    local offer = {}
    for _, list in ipairs({ starts, near }) do
        table.sort(list, function(a, b) return a[2] < b[2] end)
        for _, e in ipairs(list) do if #offer < 4 then offer[#offer + 1] = e[2] end end
    end
    return nil, offer
end

--- The last `n` raid dates, each with whether this raider earned it - the attendance strip.
function K.Strip(card, n)
    local dates = S().Dates()
    local earned = {}
    for _, d in ipairs(card and card.attended or {}) do earned[d] = true end
    local out = {}
    for i = math.max(1, #dates - n + 1), #dates do out[#out + 1] = { date = dates[i], earned = earned[dates[i]] or false } end
    return out
end

--- BiS Loot's awards to one raider, newest first. Read straight from its saved ledger (one tab-
--- separated line per event, Core/Ledger.lua over there) - so it works whenever BiS Loot has ever
--- run on this client, and says nothing at all when it has not.
K.LEDGER = { author = 2, t = 5, kind = 6, raid = 7, boss = 8, item = 9, who = 10 }
function K.Loot(name)
    -- BiS LOOT'S API FIRST (16 Oct 2026: "going forward our stuff will have open api to call") - it
    -- owns the ledger and verifies it; reading its saved lines below is only for a BiS Loot from
    -- before it had an API
    local A = _G.BiSLootAPI
    if type(A) == "table" and A.major == 1 and A.AwardsTo then
        local ok, got = pcall(A.AwardsTo, name)
        if ok and type(got) == "table" then
            local out = {}
            for _, a in ipairs(got) do out[#out + 1] = { item = a.itemId or a.item, boss = a.boss, t = a.t or 0 } end
            return out, true
        end
    end
    local db = _G.BiSLootDB
    local out = {}
    if type(db) ~= "table" or type(db.lines) ~= "table" then return out, false end
    local want = lower(name)
    for _, line in pairs(db.lines) do
        if type(line) == "string" then
            local p = {}
            for f in (line .. "\t"):gmatch("(.-)\t") do p[#p + 1] = f end
            if p[K.LEDGER.kind] == "award" and lower(p[K.LEDGER.who]) == want then
                out[#out + 1] = { item = p[K.LEDGER.item], boss = p[K.LEDGER.boss], t = tonumber(p[K.LEDGER.t]) or 0 }
            end
        end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out, true
end

--- An item's name and quality colour, or "item 12345" until the client has it (it asks the server,
--- and GET_ITEM_INFO_RECEIVED repaints).
function K.Item(id)
    local n = tonumber(id)
    if not n then
        local link = tostring(id or "")
        return (link:match("%[(.-)%]") or link), nil
    end
    if n == 0 then return nil end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get then
        local ok, name, _, quality = pcall(get, n)
        if ok and name then return name, quality end
    end
    K.waiting = true
    return "item " .. n, nil
end

--- An item string with the raider's permanent enchant in it - "item:<id>:<enchant>" - so the
--- tooltip shows the enchant line. Gems are left out until a Forever raid log shows whether its gem
--- field holds gem ids or (id, item level) pairs, as TBC's did: a wrong number there would show a
--- gem the raider does not have. The weapon oil is a temporary enchant and has no place in the
--- string; the CONSUMES panel carries it.
function K.ItemString(g)
    local id = type(g) == "table" and tonumber(g[1]) or 0
    if id == 0 then return nil end
    return ("item:%d:%d"):format(id, tonumber(g[3]) or 0)
end

--- The raiders list: name, attendance %, last night, flask on the last night, deaths, issues.
--- STILL IN THE GUILD? (Arn, 16 Oct: "the sheet had a check to see if someone was still in the
--- guild ... group the people that are pugs all the way in the bottom"). The roster gives each
--- member's rank and class. Names are matched on the first word, lowercased: Forever writes "Name
--- Surname" in places and the log writes "Name".
---
--- A PUG IS ONLY CALLED A PUG WHEN THE ROSTER IS WHOLE. If the client handed over fewer members
--- than it says the guild has (offline members hidden, or the roster not arrived yet), somebody
--- missing from it may just be offline - so they read "?" and are not sunk to the bottom.
function K.NameKey(name)
    local s = tostring(name or ""):match("^([^%-%s]+)")
    return s and s:lower() or ""
end

--- One guild member by any name a log, a roster or a player writes: the whole "Name Surname" (any
--- case, realm dropped) exactly; a first name alone when only one member has it - and when several
--- share it, the ONLINE one, since on raid night the Nebeon in your raid is the one logged in.
function K.Member(name)
    if type(name) ~= "string" or name == "" then return nil end
    local g = K.Guild()
    local whole = (name:match("^([^%-]+)") or name):lower()
    if g.members[whole] then return g.members[whole] end
    local list = g.byFirst and g.byFirst[K.NameKey(name)]
    if not list then return nil end
    if #list == 1 then return list[1] end
    for _, m in ipairs(list) do if m.online then return m end end
    return list[1]
end

function K.Guild()
    if K._guild and not K._guildDirty then return K._guild end
    local g = { members = {}, complete = false }
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local total = tonumber((GetNumGuildMembers())) or 0
        local seen = 0
        g.byFirst = {}
        for i = 1, total do
            local name, rank, _, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
            if type(name) == "string" then
                local ok, first = pcall(K.NameKey, name)
                if ok and first ~= "" then
                    seen = seen + 1
                    -- FILED BY THE WHOLE NAME (Arn, 16 Oct: "not sure why the GM Neb is not showing up" -
                    -- the guild has Nebeon Nohealzforu, Nebeon Nohotzforu and Nebeon Nolightforu, and
                    -- filing by first name let an offline alt overwrite the online GM). K.Member finds
                    -- a first name alone.
                    local whole = (name:match("^([^%-]+)") or name)
                    local key = whole:lower()
                    local m = { key = key, rank = rank, class = class, name = whole,
                                zone = type(zone) == "string" and zone or nil, online = online and true or false,
                                level = tonumber(level) }
                    g.members[key] = m
                    local list = g.byFirst[first]
                    if not list then list = {} g.byFirst[first] = list end
                    list[#list + 1] = m
                end
            end
        end
        g.complete = total > 0 and seen == total
    end
    K._guild, K._guildDirty = g, false
    return g
end

--- Warriors first, the way a raid sheet reads - roughly tanks, healers, then damage. Within a class,
--- alphabetical (Arn: "i like the alphabetical"). By class, not by role: neither the roster nor the
--- log says what spec anybody plays, and a sheet that guesses roles is wrong where it matters.
K.CLASS_ORDER = { WARRIOR = 1, PALADIN = 2, DRUID = 3, PRIEST = 4, SHAMAN = 5,
                  ROGUE = 6, HUNTER = 7, MAGE = 8, WARLOCK = 9 }
K.sort = "class"

function K.Sort(rows, mode)
    table.sort(rows, function(a, b)
        if a.pug ~= b.pug then return b.pug end                      -- pugs at the bottom, always
        if (a.none or false) ~= (b.none or false) then return b.none end   -- then members with no raids
        if mode == "attend" and a.att ~= b.att then return a.att > b.att end
        if mode ~= "attend" then
            local ca, cb = K.CLASS_ORDER[a.class or ""] or 99, K.CLASS_ORDER[b.class or ""] or 99
            if ca ~= cb then return ca < cb end
        end
        return a.name < b.name
    end)
    return rows
end

function K.Rows(cards)
    local nights = #S().Dates()
    local guild = K.Guild()
    local out, matched = {}, {}
    for name, c in pairs(cards) do
        local m = K.Member(name)
        -- IN A RAID ON RECORD, OR NOT LISTED (Arn, 18 Oct: "if a raider only apperes in one log and we
        -- archive that log can we hide all those people"). A card can be gear alone - every log brings
        -- everyone's gear, and gear stays when its raid is archived - so somebody seen in no raid on
        -- record is left off; a guild member among them shows as a member with no raids. Their gear is
        -- kept: restore the raid and they are back.
        local seen = c.last ~= nil or #(c.attended or {}) > 0 or (c.deaths or 0) > 0
        if m then matched[m.key] = true end
        if not seen then
            if m then
                out[#out + 1] = { name = name, rank = m.rank or "?", class = m.class, pug = false, none = true,
                                  att = 0, last = "-", flask = false, deaths = 0, issues = 0, geared = false }
            end
        else
            out[#out + 1] = {
                name = name,
                rank = m and m.rank or (guild.complete and "pug" or "?"),
                class = m and m.class or nil,
                pug = (m == nil and guild.complete) or false,
                att = nights > 0 and math.floor(100 * #c.attended / nights + 0.5) or 0,
                last = c.last and S().DateOf(c.last.date) or "-",          -- a column: the date alone
                flask = c.last and ((c.last.flask or 0) + (c.last.elixir or 0) > 0) or false,
                deaths = c.deaths or 0,
                issues = #(c.issues or {}),
                -- "clean" is a claim about gear somebody saw; with none on record it is "no gear seen"
                -- (Arn, 16 Oct: a whole night of raiders read "clean" with empty armories)
                geared = c.gear ~= nil,
            }
        end
    end
    -- EVERY GUILD MEMBER, raided or not (Arn, 18 Oct: "pull all guild memebers from blizzard guild
    -- pane"), straight from the game's guild list - greyed and below the raiders, above the pugs
    for key, m in pairs(guild.members) do
        if not matched[key] then
            out[#out + 1] = { name = m.name, rank = m.rank or "?", class = m.class, pug = false, none = true,
                              att = 0, last = "-", flask = false, deaths = 0, issues = 0, geared = false }
        end
    end
    return K.Sort(out, K.sort)
end

--- Everybody a raider page can open: whoever is on the record, and every guild member (a member with
--- no raids opens a page that says so). Answers a set: name -> true.
function K.People(cards)
    local out, matched = {}, {}
    for name in pairs(cards or {}) do
        out[name] = true
        local m = K.Member(name)
        if m then matched[m.key] = true end
    end
    -- a member already on the record is found by their record name, never twice
    for key, m in pairs(K.Guild().members) do
        if not matched[key] then out[m.name] = true end
    end
    return out
end

function K.BossRows(pages)
    local out = {}
    for name, p in pairs(pages) do
        out[#out + 1] = { name = name, kills = p.kills, wipes = p.wipes, best = p.best,
                          first = p.first and S().DateOf(p.first) or "-" }
    end
    table.sort(out, function(a, b)
        if (a.first == "-") ~= (b.first == "-") then return b.first == "-" end
        if a.first ~= b.first then return a.first < b.first end
        return a.name < b.name
    end)
    return out
end

--- The ticker: the newest night, boss by boss.
function K.TickerText()
    local dates = S().Dates()
    local last = dates[#dates]
    if not last then return "NO RAID NIGHTS ON RECORD" end
    local n = S().Record().nights[last]
    local parts = { ("LAST RAID %s  %d KILLS  %d RAIDERS"):format(S().Label(last):upper(), tonumber(n.kills) or 0, select(1, S().Weight(n))) }
    local names = {}
    for boss in pairs(n.bosses or {}) do names[#names + 1] = boss end
    table.sort(names)
    for _, boss in ipairs(names) do
        local b = n.bosses[boss]
        local up = (tonumber(b.kills) or 0) > 0
        parts[#parts + 1] = ("%s %s %s"):format(boss:upper(), up and "DOWN" or "WIPE",
            up and K.Clock(b.best) or ("x" .. (tonumber(b.pulls) or 0)))
    end
    parts[#parts + 1] = ("%d NIGHTS ON RECORD"):format(#dates)
    return table.concat(parts, "   //   ")
end

--------------------------------------------------------------------
-- frames
--------------------------------------------------------------------

local function rgb(name) return T().rgb(name) end

local function Fill(region, name, a)
    local r, g, b = rgb(name)
    region:SetColorTexture(r, g, b, a or 1)
end

--- A button's hover: the tint over it and the bar on its left, both on the HIGHLIGHT layer (the client shows that
--- layer while the mouse is on the button - no script needed). Returns the tint.
function K.Pop(b)
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    Fill(hi, "accent", K.HOVER)
    local bar = b:CreateTexture(nil, "HIGHLIGHT")
    bar:SetPoint("TOPLEFT") bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    Fill(bar, "accent", 1)
    b.popTint, b.popBar = hi, bar
    return hi
end

local function Text(parent, size, colour, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if fs.SetFont then pcall(fs.SetFont, fs, K.FONT, size or 12, "") end
    fs:SetTextColor(rgb(colour or "ink"))
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

--- A panel: a sunken box with a gold title in its top bar - Bloomberg's amber header, our gold.
local function Panel(parent, title, x, y, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", x, -y)
    p:SetSize(w, h)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, "surface", 0.95)
    local bar = p:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(18)
    Fill(bar, "accentSoft")
    p.title = Text(p, 11, "gold")
    p.title:SetPoint("TOPLEFT", 6, -3)
    p.title:SetText(title)
    p.right = Text(p, 11, "muted", "RIGHT")
    p.right:SetPoint("TOPRIGHT", -6, -3)
    return p
end

--- A table of rows: column heads in muted, `n` clickable rows below. cols = { {w, justify}, ... }
--- THE LISTS SCROLL (Arn's first real report, 16 Oct: 34 raiders, 27 rows - everyone after Rollsy
--- was simply not there). The mouse wheel moves a list three rows at a time; the panel's corner
--- says which rows are showing.
local function Scroll(g, total)
    local most = math.max(0, total - #g.rows)
    g.offset = math.max(0, math.min(g.offset or 0, most))
    g.total = total
    return g.offset
end
local function Showing(g)
    if (g.total or 0) <= #g.rows then return "" end
    return ("   rows %d-%d of %d"):format(g.offset + 1, math.min(g.total, g.offset + #g.rows), g.total)
end

--- onHead: optional { [column] = function } - a column title that sorts the list when clicked.
local function Grid(parent, heads, cols, n, y0, onClick, onHead)
    local g = { rows = {}, offset = 0, heads = {}, headButtons = {} }
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta)
        g.offset = (g.offset or 0) - (delta or 0) * 3
        K.Paint()
    end)
    local x = 6
    for i, c in ipairs(cols) do
        local h = Text(parent, 11, "muted", c[2])
        h:SetPoint("TOPLEFT", x, -y0)
        h:SetWidth(c[1])
        h:SetText(heads[i])
        g.heads[i] = h
        if onHead and onHead[i] then
            local b = CreateFrame("Button", nil, parent)
            b:SetPoint("TOPLEFT", x, -y0 + 2)
            b:SetSize(c[1], K.ROW)
            local hi = K.Pop(b)
            b:SetScript("OnClick", function() g.offset = 0 onHead[i]() end)
            g.headButtons[i] = b
        end
        x = x + c[1] + 6
    end
    for r = 1, n do
        local row = CreateFrame("Button", nil, parent)
        row:SetPoint("TOPLEFT", 2, -(y0 + r * K.ROW))
        row:SetSize(x - 2, K.ROW)
        local hi = K.Pop(row)
        row.cells = {}
        local cx = 4
        for i, c in ipairs(cols) do
            local fs = Text(row, 12, "ink", c[2])
            fs:SetPoint("TOPLEFT", cx, -2)
            fs:SetWidth(c[1])
            row.cells[i] = fs
            cx = cx + c[1] + 6
        end
        -- RIGHT-CLICK: the game's own player menu for the row's person (Arn, 16 Oct: "on the raider
        -- screen can we right click and pull up the blizz menu?") - painters set row.who
        if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.who then K.PlayerMenu(self.who) end
                return
            end
            if onClick and self.key then onClick(self.key) end
        end)
        g.rows[r] = row
    end
    return g
end

--- A small button in a panel's title bar (INVITE, INVITE ONLINE): gold words on the sunken colour.
local function BarButton(parent, label, w, point, x, fn)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint(point, x, -1)
    b:SetSize(w, 16)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, "sunken")
    local hi = K.Pop(b)
    b.fs = Text(b, 11, "gold", "CENTER")
    b.fs:SetPoint("CENTER", 0, 0)
    b.fs:SetText(label)
    b:SetScript("OnClick", fn)
    return b
end

local function SetRow(row, key, values, colours)
    row.key = key
    row.who = nil                                  -- the painter names the person, if the row is one
    for i, fs in ipairs(row.cells) do
        fs:SetText(values[i] ~= nil and tostring(values[i]) or "")
        local c = colours and colours[i] or "ink"
        if type(c) == "table" then fs:SetTextColor(c[1], c[2], c[3]) else fs:SetTextColor(rgb(c)) end
    end
    if key then row:Show() else row:Hide() end
end

--- THE GAME'S OWN PLAYER MENU for a name (Arn, 16 Oct: "right click and pull up the blizz menu"):
--- whisper, invite, add friend, ignore - and BiS Tools' "BiS" lines, which join that menu. The
--- FRIEND menu, not the guild roster's: a guild menu opened by an addon can taint promote and kick
--- (BiS Tools keeps its guild-menu line behind a switch for that reason). Forever's whole name, from
--- the roster, so whisper and invite reach the right person.
function K.PlayerMenu(name)
    local m = K.Member(name)
    local whole = m and m.name or name
    if type(whole) ~= "string" or whole == "" then return false end
    if UnitPopup_OpenMenu then
        local ok = pcall(UnitPopup_OpenMenu, "FRIEND",
            { name = whole, chatTarget = whole, connected = m and m.online or nil })
        if ok then return true end
    end
    if FriendsFrame_ShowDropdown then return (pcall(FriendsFrame_ShowDropdown, whole, m and m.online)) end
    return false
end

-- the kit, for pages built in other files (Core/Where.lua) so they look the same
K.ui = { Fill = Fill, Text = Text, Panel = Panel, Grid = Grid, SetRow = SetRow, Scroll = Scroll,
         Showing = Showing, rgb = rgb }

function K.Build()
    if K.frame then return K.frame end
    if not CreateFrame then return nil end
    local f = CreateFrame("Frame", "BiSGuildTerminal", UIParent)
    K.frame = f
    f:SetSize(K.W, K.H)
    f:SetPoint("CENTER")
    -- THE WORLD MAP'S LAYER, not above it (Arn, 16 Oct: "if i click open on OpenMap, it closes our
    -- window"). On DIALOG the terminal covered the map, so opening the map had to hide it; on HIGH,
    -- with SetToplevel, the two are ordinary windows - the one clicked last is in front.
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, "bg", 0.97)
    -- A HAIRLINE ROUND THE WINDOW, in the options kit's own edge colour (Arn, 16 Oct: "there is a
    -- white line on top of the window ... how come our other addons dont put that white line tho?").
    -- It was a 2 px bar in "accent" along the top only, and the accent is borrowed from EllesmereUI
    -- when it is installed - Arn's is white. BiS Tools' windows draw this, fixed, never borrowed.
    f.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = f:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then
            e:SetPoint(side .. "LEFT", 0, 0)
            e:SetPoint(side .. "RIGHT", 0, 0)
            e:SetHeight(1)
        else
            e:SetPoint("TOP" .. side, 0, 0)
            e:SetPoint("BOTTOM" .. side, 0, 0)
            e:SetWidth(1)
        end
        Fill(e, "edge")
        f.edges[side] = e
    end

    -- the top bar: the console prompt, then the function keys
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", 10, -8)
    f.head:SetText(T().text("accent", "BiS> Terminal"))
    local theme = _G.BiSTheme
    if theme and theme.Console then
        f.con = theme.Console(f.head, { width = 170, size = 9 })
        f.con:Set("name", "Guild Terminal")
    end
    f.keys = {}
    -- CENTRED ON THE WINDOW, however many there are (Arn, 16 Oct: a fourth tab, and "the top tabs
    -- shifted a little to the right" - they started at a fixed x). Six since RECRUITS (21 Oct 2026):
    -- 78 wide, so the row starts clear of the prompt's 180 px.
    local TABS = { { "RAIDERS", "raiders" }, { "BOSSES", "bosses" }, { "WHERE", "where" }, { "ROSTER", "roster" },
                   { "RECRUITS", "recruits" }, { "LOG", "log" } }
    K.TAB_W, K.TAB_GAP = 78, 6
    local keyX = math.floor((K.W - (#TABS * (K.TAB_W + K.TAB_GAP) - K.TAB_GAP)) / 2)
    for _, k in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", keyX, -6)
        b:SetSize(K.TAB_W, 18)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        Fill(b.bg, "sunken")
        local hi = K.Pop(b)
        b.fs = Text(b, 11, "ink", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(k[1])
        b:SetScript("OnClick", function() K.Go(k[2]) end)
        f.keys[k[2]] = b
        keyX = keyX + K.TAB_W + K.TAB_GAP
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() K.Hide() end)

    -- the command line
    local cmdbg = f:CreateTexture(nil, "BORDER")
    cmdbg:SetPoint("TOPLEFT", 8, -30)
    cmdbg:SetSize(K.W - 16, 22)
    Fill(cmdbg, "sunken")
    f.prompt = Text(f, 13, "gold")
    f.prompt:SetPoint("TOPLEFT", 14, -34)
    f.prompt:SetText("BiS>")
    local e = CreateFrame("EditBox", nil, f)
    e:SetPoint("TOPLEFT", 52, -30)
    e:SetSize(K.W - 70 - K.GLANCE_W - 8, 22)   -- a name fits; the raid-night line takes the right of the bar
    e:SetAutoFocus(false)
    e:SetMaxLetters(0)               -- no cap: a roster pasted here goes to the ROSTER tab (K.Go)
    e:SetFontObject("GameFontHighlight")
    if e.SetFont then pcall(e.SetFont, e, K.FONT, 13, "") end
    e:SetTextColor(rgb("ink"))
    e:SetScript("OnEnterPressed", function(self)
        local line = self:GetText()
        self:SetText("")
        K.Go(line)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.cmd = e

    -- RAID NIGHT AT A GLANCE (Arn, 16 Oct: "raid night > raiding <xxx> start time 00:00, any info that
    -- is at a glance"): the pasted Raid-Helper event on the right of the command bar - its name, its
    -- time, how long until it starts, how many of those signed are online. Shown from K.GLANCE_BEFORE
    -- before the start to K.GLANCE_AFTER after; click it for the ROSTER tab.
    local g = CreateFrame("Button", nil, f)
    g:SetPoint("TOPRIGHT", -12, -31)
    g:SetSize(K.GLANCE_W, 20)
    g.fs = Text(g, 12, "ink", "RIGHT")
    g.fs:SetAllPoints()
    local ghi = g:CreateTexture(nil, "ARTWORK")
    ghi:SetAllPoints()
    Fill(ghi, "accent", K.HOVER)
    ghi:Hide()
    g:SetScript("OnEnter", function() ghi:Show() end)
    g:SetScript("OnLeave", function() ghi:Hide() end)
    g:SetScript("OnClick", function() K.Go("roster") end)
    f.glance = g
    f.status = Text(f, 11, "muted")
    f.status:SetPoint("TOPLEFT", 12, -56)
    f.status:SetWidth(K.W - 24)

    -- ESC: the command line takes the first press (it gives the keyboard back), the window the next;
    -- a card steps back, a list closes. Combat-safe: Init.lua's ns.EscKeys.
    ns.EscKeys(f, function() if not K.Back() then K.Hide() end end)

    -- the pages, one shown at a time, between the status line and the ticker
    local top, bottom = 72, 24
    local bodyH = K.H - top - bottom
    local function Page()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 0, -top)
        p:SetSize(K.W, bodyH)
        p:Hide()
        return p
    end
    f.pages = {}

    -- AN EMPTY LIST SAYS WHY (Arn clicked RAIDERS on a fresh install and "nothing" happened: the
    -- tab sent him to the same blank page he was already on). Each list keeps its own page and says
    -- where the nights come from when it has none.
    local EMPTY = "No raid nights on record yet.\n\nAfter a raid, open the LOG tab: its notebook reads your "
        .. "combat log, and you paste what it prints - the night is kept here and shared with the guild.\n\nOr wait: when "
        .. "an officer who has the nights is online, they arrive by themselves."
    local function Hint(panel)
        panel.hint = Text(panel, 13, "ink2")
        panel.hint:SetPoint("TOPLEFT", 16, -44)
        panel.hint:SetWidth(K.W - 64)
        if panel.hint.SetWordWrap then panel.hint:SetWordWrap(true) end
        panel.hint:SetText(EMPTY)
    end

    -- every raider
    local pr = Page()
    local plist = Panel(pr, "RAIDERS", 8, 0, K.W - 16, bodyH - 4)
    Hint(plist)
    -- NAME sorts by class then name, ATTEND by attendance; pugs stay at the bottom either way
    pr.grid = Grid(plist, { "NAME", "RANK", "ATTEND", "LAST RAID", "FLASK/ELIX", "DEATHS", "GEAR ISSUES" },
        { { 170, "LEFT" }, { 110, "LEFT" }, { 60, "RIGHT" }, { 100, "RIGHT" }, { 80, "RIGHT" }, { 60, "RIGHT" }, { 110, "RIGHT" } },
        K.LIST_ROWS, 22, function(name) K.Go(name .. " <raider>") end,
        { [1] = function() K.sort = "class" K.Paint() end, [3] = function() K.sort = "attend" K.Paint() end })
    pr.panel = plist
    -- raid night's one button: every guild member on the record who is online (Core/Invite.lua)
    pr.invite = BarButton(plist, "INVITE ONLINE", 110, "TOPLEFT", 90, function()
        if ns.Inv then ns.Inv.InviteOnline() end
    end)
    -- the team at a glance, by class (K.Report)
    pr.report = BarButton(plist, "RUN REPORT", 100, "TOPLEFT", 206, function() K.Go("report") end)
    f.pages.raiders = pr

    -- the raid team report
    local pt = Page()
    local tlist = Panel(pt, "RAID TEAM REPORT", 8, 0, K.W - 16, bodyH - 4)
    pt.grid = Grid(tlist, { "CLASS", "RAIDING", "IN THE LAST RAIDS", "ON THE ROSTER, NO RAIDS (LEVEL)" },
        { { 100, "LEFT" }, { 60, "RIGHT" }, { 340, "LEFT" }, { 300, "LEFT" } },
        K.LIST_ROWS, 22, function() end)
    pt.panel = tlist
    f.pages.report = pt

    -- every boss
    local pb = Page()
    local blist = Panel(pb, "BOSSES", 8, 0, K.W - 16, bodyH - 4)
    Hint(blist)
    pb.grid = Grid(blist, { "BOSS", "KILLS", "WIPES", "FASTEST", "FIRST KILL" },
        { { 260, "LEFT" }, { 70, "RIGHT" }, { 70, "RIGHT" }, { 90, "RIGHT" }, { 120, "RIGHT" } },
        K.LIST_ROWS, 22, function(name) K.Go(name .. " <boss>") end)
    pb.panel = blist
    f.pages.bosses = pb

    -- the raider card: the armory on the left, the numbers on the right
    local rc = Page()
    local leftW = 470
    rc.armory = Panel(rc, "ARMORY", 8, 0, leftW, bodyH - 4)
    rc.invite = BarButton(rc.armory, "INVITE", 64, "TOPRIGHT", -110, function()
        if ns.Inv and K.key then ns.Inv.One(K.key) end
    end)
    rc.gear = Grid(rc.armory, { "SLOT", "ITEM", "ILVL", "" },
        { { 62, "LEFT" }, { 250, "LEFT" }, { 34, "RIGHT" }, { 84, "RIGHT" } }, #S().SLOTS, 22)
    -- HOVER FOR THE ITEM, ENCHANT INCLUDED (Arn, 16 Oct: "click item and the tooltip come out,
    -- ideally with the enchant"). The game's own tooltip, built from an item string that carries the
    -- raider's enchant, so it reads exactly like inspecting them. Shift-click links it in chat.
    for _, row in ipairs(rc.gear.rows) do
        row:SetScript("OnEnter", function(self)
            local tip = _G.GameTooltip
            if not (self.link and tip) then return end
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:SetHyperlink(self.link)
            tip:Show()
        end)
        row:SetScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if not self.link or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
            local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local ok, _, link = pcall(get, self.link)
            if ok and link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end)
    end
    local rx, rw = leftW + 16, K.W - leftW - 24
    rc.att = Panel(rc, "ATTENDANCE", rx, 0, rw, 92)
    rc.attLine = Text(rc.att, 13, "ink")
    rc.attLine:SetPoint("TOPLEFT", 8, -24)
    rc.strip = {}
    for i = 1, K.STRIP do
        local sq = rc.att:CreateTexture(nil, "ARTWORK")
        sq:SetPoint("TOPLEFT", 8 + (i - 1) * 28, -46)
        sq:SetSize(24, 14)
        rc.strip[i] = sq
    end
    -- PUNCTUAL: on time / late / no-show over their last raids (Core/Logins.lua; Arn, 16 Oct:
    -- "habitually late, or perfect attendance")
    rc.punct = Text(rc.att, 11, "muted")
    rc.punct:SetPoint("TOPLEFT", 8, -68)
    rc.punct:SetWidth(rw - 16)
    rc.cons = Panel(rc, "CONSUMES", rx, 98, rw, 132)
    rc.consLines = {}
    for i = 1, 6 do
        local l = Text(rc.cons, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 18)
        l:SetWidth(rw - 16)
        rc.consLines[i] = l
    end
    rc.loot = Panel(rc, "LOOT WON", rx, 236, rw, bodyH - 240)
    rc.lootLines = {}
    for i = 1, 14 do
        local l = Text(rc.loot, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 17)
        l:SetWidth(rw - 16)
        rc.lootLines[i] = l
    end
    f.pages.raider = rc

    -- the boss ticker: the numbers on the left, who has downed it on the right
    local bp = Page()
    bp.stats = Panel(bp, "BOSS", 8, 0, 400, 200)
    bp.statLines = {}
    for i = 1, 6 do
        local l = Text(bp.stats, 13, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 22)
        l:SetWidth(384)
        bp.statLines[i] = l
    end
    bp.nights = Panel(bp, "NIGHTS IT DIED", 8, 206, 400, bodyH - 210)
    bp.nightLines = {}
    for i = 1, 16 do
        local l = Text(bp.nights, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 17)
        bp.nightLines[i] = l
    end
    bp.killers = Panel(bp, "WHO HAS DOWNED IT", 416, 0, K.W - 424, bodyH - 4)
    bp.grid = Grid(bp.killers, { "RAIDER", "KILLS" }, { { 300, "LEFT" }, { 80, "RIGHT" } }, K.LIST_ROWS, 22,
        function(name) K.Go(name .. " <raider>") end)
    f.pages.boss = bp

    -- WHERE: the map and who is where (Core/Where.lua builds it with the same kit)
    if K.BuildWhere then f.pages.where = K.BuildWhere(Page(), bodyH) end
    -- ROSTER: paste a Discord raid tool's roster, invite who is online (Core/Invite.lua)
    if K.BuildRoster then f.pages.roster = K.BuildRoster(Page(), bodyH) end
    -- RECRUITS: BiS> Nebbinator's guild book, through its API (Core/Recruits.lua)
    if K.BuildRecruits then f.pages.recruits = K.BuildRecruits(Page(), bodyH) end

    -- the ticker along the bottom
    local tbg = f:CreateTexture(nil, "BORDER")
    tbg:SetPoint("BOTTOMLEFT", 0, 0)
    tbg:SetPoint("BOTTOMRIGHT", 0, 0)
    tbg:SetHeight(20)
    Fill(tbg, "sunken")
    f.tickClip = CreateFrame("Frame", nil, f)
    f.tickClip:SetPoint("BOTTOMLEFT", 8, 2)
    f.tickClip:SetSize(K.W - 16, 16)
    if f.tickClip.SetClipsChildren then f.tickClip:SetClipsChildren(true) end
    f.tick = Text(f.tickClip, 12, "gold")
    f.tick:SetPoint("LEFT", f.tickClip, "LEFT", 0, 0)
    f.tickX = 0
    -- THE TICKER MOVES ONLY WHILE THE WINDOW IS OPEN, and it costs one SetPoint a frame (the suite
    -- holds it to that): its OnUpdate lives on the window, which runs nothing while hidden.
    f:SetScript("OnUpdate", function(self, elapsed)
        -- the WHERE page redraws every K.WHERE_EVERY s while it is showing - spots move
        if K.page == "where" then
            self.whereT = (self.whereT or 0) + (elapsed or 0)
            if self.whereT >= K.WHERE_EVERY then self.whereT = 0 K.Paint() end
        end
        -- the raid-night line counts down with the clock, every K.WHERE_EVERY seconds
        -- the roster, asked for again every K.ROSTER_EVERY s while a page that lists people shows
        if K.LIVE[K.page] then
            self.rosterT = (self.rosterT or 0) + (elapsed or 0)
            if self.rosterT >= K.ROSTER_EVERY then self.rosterT = 0 K.AskRoster() end
        end
        self.glanceT = (self.glanceT or 0) + (elapsed or 0)
        if self.glanceT >= K.WHERE_EVERY then self.glanceT = 0 K.PaintGlance() end
        -- THE INVITE BUTTONS PULSE while somebody who just logged in waits (Core/Logins.lua)
        local pulse = ns.Login and ns.Login.Pulsing()
        if pulse or self.pulsed then
            local a = pulse and (0.55 + 0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 3))) or 1
            local pr, ro = self.pages.raiders, self.pages.roster
            if pr and pr.invite then pr.invite:SetAlpha(a) end
            if ro and ro.send then ro.send:SetAlpha(a) end
            self.pulsed = pulse
        end
        local w = self.tickW or 0
        if w <= 0 then return end
        self.tickX = self.tickX - (elapsed or 0) * 40
        if self.tickX < -w then self.tickX = K.W end
        self.tick:ClearAllPoints()
        self.tick:SetPoint("LEFT", self.tickClip, "LEFT", self.tickX, 0)
        if self.con then self.con:Paint() end
    end)

    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, event, msg)
        if event == "CHAT_MSG_SYSTEM" then
            -- a guildmate came online or went off: ask for the roster now, not at the next 15 s look
            -- (Arn, 16 Oct: "3 guildmates online and it only shows 2")
            if f:IsShown() and K.LIVE[K.page] and type(msg) == "string"
               and not (issecretvalue and issecretvalue(msg))
               and (msg:find("online", 1, true) or msg:find("offline", 1, true)) then
                K.AskRoster()
            end
            return
        end
        if event == "GUILD_ROSTER_UPDATE" then
            -- only marked here; the roster is read again the next time the list is drawn
            K._guildDirty = true
            if f:IsShown() and K.LIVE[K.page] and not K._rosterPaintArmed then
                K._rosterPaintArmed = true
                if C_Timer and C_Timer.After then
                    C_Timer.After(1, function() K._rosterPaintArmed = false if f:IsShown() then K.Paint() end end)
                end
            end
        elseif K.waiting and f:IsShown() and K.page == "raider" then
            K.Paint()
        end
    end)
    return f
end

--------------------------------------------------------------------
-- painting
--------------------------------------------------------------------

local function Say(text, colour)
    local f = K.frame
    if not f then return end
    f.status:SetText(text or "")
    f.status:SetTextColor(rgb(colour or "muted"))
end
K.Say = Say

local function PaintRaiders(p)
    local rows = K.Rows(S().Cards())
    local off = Scroll(p.grid, #rows)
    local pugs, none = 0, 0
    for _, r in ipairs(rows) do
        if r.pug then pugs = pugs + 1 elseif r.none then none = none + 1 end
    end
    p.panel.right:SetText(("%d raiders, %s%d pugs, %d nights"):format(#rows - pugs - none,
        none > 0 and (none .. " no raids, ") or "", pugs, #S().Dates()) .. Showing(p.grid))
    -- the hint fills the panel only while the list is EMPTY: over listed rows it printed through the
    -- names (Arn, 5 Nov). With the guild listed and no nights, the status line says where nights come from.
    if #rows == 0 then p.panel.hint:Show() else p.panel.hint:Hide() end
    -- the sort you are on is lit
    p.grid.heads[1]:SetTextColor(rgb(K.sort ~= "attend" and "gold" or "muted"))
    p.grid.heads[3]:SetTextColor(rgb(K.sort == "attend" and "gold" or "muted"))
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r and r.none then
            -- a member with no raids: the name in its class colour, dimmed; nothing to count
            local cc = r.class and colours and colours[r.class]
            SetRow(row, r.name, { r.name, r.rank, "-", "-", "-", "-", "no raids yet" },
                { cc and { cc.r * 0.6, cc.g * 0.6, cc.b * 0.6 } or "muted", "muted", "muted", "muted", "muted", "muted", "muted" })
            row.who = r.name
        elseif r then
            local cc = r.class and colours and colours[r.class]
            local nameColour = r.pug and "muted" or (cc and { cc.r, cc.g, cc.b } or "ink")
            SetRow(row, r.name, { r.name, r.rank, r.att .. "%", r.last, r.flask and "yes" or "no", r.deaths,
                                  not r.geared and "no gear seen" or (r.issues > 0 and (r.issues .. " no enchant") or "clean") },
                { nameColour, r.pug and "muted" or "ink2", r.att >= 75 and "good" or (r.att >= 50 and "gold" or "warn"), "ink2",
                  r.flask and "good" or "warn", r.deaths > 0 and "warn" or "ink2",
                  not r.geared and "muted" or (r.issues > 0 and "warn" or "good") })
            row.who = r.name
        else
            SetRow(row, nil, {})
        end
    end
end

--- THE RAID TEAM, AS IT IS (Arn, 19 Oct: "some bloomberg terminal thing that kinda says run report and
--- itll say what our raid team looks like at the moment ... Druid: raiders by name and how many ... not
--- just in our roster but by looking at the last 2-4 logs who has been consistently raiding" - and "right
--- now nobody will come out since there are no raids out yet"). By class: who EARNED a night in the
--- last K.REPORT_RAIDS raids on record (S.Earned: half the kills), each with how many of them - and,
--- beside them, every guild member of that class with no raid in those, by level. With no raids yet
--- the roster side is the whole team; it fills from the logs as raids are read.
K.REPORT_RAIDS = 4
function K.Report(n)
    n = n or K.REPORT_RAIDS
    local rec, dates = S().Record(), S().Dates()
    local raids = {}
    for i = math.max(1, #dates - n + 1), #dates do raids[#raids + 1] = dates[i] end
    local earned = {}
    for _, key in ipairs(raids) do
        local night = rec.nights[key]
        for name in pairs(night and night.raiders or {}) do
            if S().Earned(night, name) then earned[name] = (earned[name] or 0) + 1 end
        end
    end
    local byClass, logged, total, rosterN = {}, {}, 0, 0
    local function slot(c)
        c = c or "?"
        local b = byClass[c]
        if not b then b = { class = c, raiding = {}, roster = {} } byClass[c] = b end
        return b
    end
    local function first(s) return tostring(s):match("^(%S+)") or tostring(s) end
    for name, k in pairs(earned) do
        local m = K.Member(name)
        if m and m.key then logged[m.key] = true end
        table.insert(slot(m and m.class).raiding, { name = first(name), n = k, pug = m == nil })
        total = total + 1
    end
    for key, m in pairs(K.Guild().members) do
        if not logged[key] then
            table.insert(slot(m.class).roster, { name = first(m.name or key), level = tonumber(m.level) or 0 })
            rosterN = rosterN + 1
        end
    end
    -- in the RAIDERS list's class order (K.CLASS_ORDER), a class it does not list and "?" last
    local classes = {}
    for _, b in pairs(byClass) do classes[#classes + 1] = b end
    table.sort(classes, function(a, b)
        local ra, rb = K.CLASS_ORDER[a.class] or 99, K.CLASS_ORDER[b.class] or 99
        if ra ~= rb then return ra < rb end
        return a.class < b.class
    end)
    for _, b in ipairs(classes) do
        table.sort(b.raiding, function(a, c) if a.n ~= c.n then return a.n > c.n end return a.name < c.name end)
        table.sort(b.roster, function(a, c) if a.level ~= c.level then return a.level > c.level end return a.name < c.name end)
    end
    return { raids = raids, classes = classes, raiding = total, roster = rosterN, of = n }
end

--- The report's rows: a class, then as many lines as its names need (K.REPORT_PER on each side).
K.REPORT_PER = 4
function K.ReportRows(rep)
    local rows = {}
    local function chunk(list, fmt)
        local out, line = {}, {}
        for _, x in ipairs(list) do
            line[#line + 1] = fmt(x)
            if #line == K.REPORT_PER then out[#out + 1] = table.concat(line, ", ") line = {} end
        end
        if #line > 0 then out[#out + 1] = table.concat(line, ", ") end
        return out
    end
    local of = #rep.raids
    for _, b in ipairs(rep.classes) do
        local left = chunk(b.raiding, function(x) return ("%s %d/%d%s"):format(x.name, x.n, of, x.pug and " pug" or "") end)
        local right = chunk(b.roster, function(x) return ("%s %d"):format(x.name, x.level) end)
        for i = 1, math.max(1, #left, #right) do
            rows[#rows + 1] = { class = i == 1 and b.class or nil, n = i == 1 and #b.raiding or nil,
                                left = left[i] or "", right = right[i] or "" }
        end
    end
    rows[#rows + 1] = { total = true, n = rep.raiding, left = "", right = rep.roster .. " on the roster" }
    return rows
end

local function PaintReport(p)
    local rep = K.Report()
    local rows = K.ReportRows(rep)
    local off = Scroll(p.grid, #rows)
    local r1, rN = rep.raids[1], rep.raids[#rep.raids]
    p.panel.right:SetText((#rep.raids == 0 and "no raids logged yet - the roster is the team" or
        ("the last %d raid%s: %s - %s"):format(#rep.raids, #rep.raids == 1 and "" or "s", S().Label(r1), S().Label(rN)))
        .. Showing(p.grid))
    p.grid.heads[3]:SetText(("IN THE LAST %d RAIDS"):format(K.REPORT_RAIDS))
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if not r then
            SetRow(row, nil, {})
        elseif r.total then
            SetRow(row, nil, { "TOTAL", r.n, r.left, r.right }, { "gold", "gold", "ink2", "muted" })
        else
            local cc = r.class and colours and colours[r.class]
            local label = r.class and (r.class == "?" and "unknown" or (r.class:sub(1, 1) .. r.class:sub(2):lower())) or ""
            SetRow(row, nil, { label, r.n or "", r.left, r.right },
                { cc and { cc.r, cc.g, cc.b } or "ink", "gold", "ink", "muted" })
        end
    end
end

local function PaintBosses(p)
    local rows = K.BossRows(S().Bosses())
    local off = Scroll(p.grid, #rows)
    p.panel.right:SetText(("%d bosses"):format(#rows) .. Showing(p.grid))
    if #rows == 0 then p.panel.hint:Show() else p.panel.hint:Hide() end
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r then
            SetRow(row, r.name, { r.name, r.kills, r.wipes, K.Clock(r.best), r.first },
                { "ink", r.kills > 0 and "good" or "muted", r.wipes > 0 and "warn" or "ink2", "gold", "ink2" })
        else
            SetRow(row, nil, {})
        end
    end
end

local QUALITY = { [0] = "muted", [1] = "ink", [2] = "good", [3] = "slate", [4] = "accent", [5] = "gold" }

--- A guild member's empty card, for the page that says they have no raids with us.
local NONE = { deaths = 0, pots = 0, attended = {}, issues = {} }

local function PaintRaider(p, name)
    local card = S().Cards()[name]
    local none = false
    if not card then
        -- A GUILD MEMBER WITH NO RAIDS (Arn, 18 Oct: "just a generic message that this player has no
        -- raids logged with us"): the same page, empty, saying so
        if not K.Member(name) then return false end
        card, none = NONE, true
    end
    K.waiting = false
    local issues = {}
    for _, i in ipairs(card.issues or {}) do issues[i.slot] = i.what end
    p.armory.title:SetText("ARMORY  " .. T().text("ink", name:upper()))
    p.armory.right:SetText(card.gearDate and ("seen " .. card.gearDate) or "no gear seen")
    for i, row in ipairs(p.gear.rows) do
        local slot = S().SLOTS[i]
        local g = card.gear and card.gear[i]
        local id = g and tonumber(g[1]) or 0
        if id ~= 0 then
            local item, q = K.Item(id)
            SetRow(row, slot, { slot, item, g[2], issues[slot] or "" },
                { "muted", QUALITY[q or 1] or "ink", "ink2", "warn" })
            row.link = K.ItemString(g)
        else
            SetRow(row, slot, { slot, card.gear and "-" or "", "", "" }, { "muted", "muted", "muted", "muted" })
            row.link = nil
        end
    end

    local nights = #S().Dates()
    local pct = nights > 0 and math.floor(100 * #card.attended / nights + 0.5) or 0
    p.attLine:SetText(("%d of %d nights   %d%%"):format(#card.attended, nights, pct))
    p.attLine:SetTextColor(rgb(pct >= 75 and "good" or (pct >= 50 and "gold" or "warn")))
    if none then
        p.armory.right:SetText("no raids logged with us yet")
        p.attLine:SetText("no raids logged with us yet")
        p.attLine:SetTextColor(rgb("muted"))
    end
    local strip = K.Strip(card, K.STRIP)
    for i, sq in ipairs(p.strip) do
        local s = strip[i]
        if s then Fill(sq, s.earned and "good" or "line2") sq:Show() else sq:Hide() end
    end
    p.att.right:SetText(strip[1] and (S().DateOf(strip[1].date) .. " ->") or "")
    local habit, habitC
    if ns.Login then habit, habitC = ns.Login.HabitText(name) end
    p.punct:SetText("punctual  " .. (habit or "nothing measured yet - it counts at raid time, from a pasted roster"))
    p.punct:SetTextColor(rgb(habit and habitC or "muted"))

    local l = card.last
    local lines = {}
    if l then
        local pulls = l.pulls or 0
        local function of(n) return ("%d of %d pulls"):format(n or 0, pulls) end
        lines = {
            { "flask      " .. of(l.flask), (l.flask or 0) > 0 and "good" or "warn" },
            { "elixirs    " .. of(l.elixir), (l.elixir or 0) > 0 and "good" or "ink2" },
            { "food       " .. of(l.food), (l.food or 0) > 0 and "good" or "warn" },
            { "weapon     " .. of(l.weapon), (l.weapon or 0) > 0 and "good" or "warn" },
            { ("potions    %d that night, %d on record"):format(l.pots or 0, card.pots or 0), "ink" },
            { ("deaths     %d that night, %d on record"):format(l.deaths or 0, card.deaths or 0),
              (card.deaths or 0) > 0 and "warn" or "good" },
        }
        p.cons.right:SetText(S().DateOf(l.date))
    else
        p.cons.right:SetText("")
        lines = { { "no pulls on record", "muted" } }
    end
    for i, fs in ipairs(p.consLines) do
        local e = lines[i]
        fs:SetText(e and e[1] or "")
        if e then fs:SetTextColor(rgb(e[2])) end
    end

    local loot, have = K.Loot(name)
    p.loot.right:SetText(have and (#loot .. " item(s)") or "")
    for i, fs in ipairs(p.lootLines) do
        local e = loot[i]
        if e then
            local item, q = K.Item(e.item)
            fs:SetText(item .. ((e.boss and e.boss ~= "") and T().text("muted", "  " .. e.boss) or ""))
            fs:SetTextColor(rgb(QUALITY[q or 1] or "ink"))
        elseif i == 1 then
            fs:SetText(have and "nothing awarded yet" or "the loot ledger is not ready yet")
            fs:SetTextColor(rgb("muted"))
        else
            fs:SetText("")
        end
    end
    return true
end

local function PaintBoss(p, name)
    local pg = S().Bosses()[name]
    if not pg then return false end
    p.stats.title:SetText("BOSS  " .. T().text("ink", name:upper()))
    local pulls = pg.kills + pg.wipes
    local lines = {
        { ("kills        %d"):format(pg.kills), pg.kills > 0 and "good" or "muted" },
        { ("wipes        %d"):format(pg.wipes), pg.wipes > 0 and "warn" or "ink2" },
        { ("kill rate    %d%%"):format(pulls > 0 and math.floor(100 * pg.kills / pulls + 0.5) or 0), "ink" },
        { ("fastest      %s"):format(K.Clock(pg.best)), "gold" },
        { ("first kill   %s"):format(pg.first and S().Label(pg.first) or "not yet"), "ink" },
        { ("nights dead  %d"):format(#pg.nights), "ink" },
    }
    for i, fs in ipairs(p.statLines) do
        fs:SetText(lines[i][1])
        fs:SetTextColor(rgb(lines[i][2]))
    end
    for i, fs in ipairs(p.nightLines) do
        local d = pg.nights[#pg.nights - i + 1]
        fs:SetText(d and S().Label(d) or (i == 1 and "never killed" or ""))
        fs:SetTextColor(rgb(d and "ink" or "muted"))
    end
    local who = {}
    for n, c in pairs(pg.killers) do who[#who + 1] = { n, c } end
    table.sort(who, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local off = Scroll(p.grid, #who)
    p.killers.right:SetText(("%d raiders"):format(#who) .. Showing(p.grid))
    for i, row in ipairs(p.grid.rows) do
        local w = who[i + off]
        if w then SetRow(row, w[1], { w[1], w[2] }, { "ink", "good" }) row.who = w[1] else SetRow(row, nil, {}) end
    end
    return true
end

function K.Paint()
    local f = K.frame
    if not f then return end
    for name, p in pairs(f.pages) do if name ~= K.page then p:Hide() end end
    local p = f.pages[K.page]
    if K.page == "raiders" then PaintRaiders(p)
    elseif K.page == "bosses" then PaintBosses(p)
    elseif K.page == "report" then PaintReport(p)
    elseif K.page == "raider" then PaintRaider(p, K.key)
    elseif K.page == "boss" then PaintBoss(p, K.key)
    elseif K.page == "where" and K.PaintWhere then K.PaintWhere(p)
    elseif K.page == "roster" and K.PaintRoster then K.PaintRoster(p)
    elseif K.page == "recruits" and K.PaintRecruits then K.PaintRecruits(p)
    end
    p:Show()
    -- the tab you are on is lit; a card lights the list it belongs to
    local on = (K.page == "raider" and "raiders") or (K.page == "report" and "raiders") or (K.page == "boss" and "bosses") or K.page
    for name, b in pairs(f.keys) do
        Fill(b.bg, name == on and "accentSoft" or "sunken")
        b.fs:SetTextColor(rgb(name == on and "gold" or "ink"))
    end
    K.PaintGlance()
    f.tick:SetText(K.TickerText())
    f.tickW = f.tick:GetStringWidth() or 0
end

--------------------------------------------------------------------
-- commands
--------------------------------------------------------------------

function K.Open(page, key)
    -- a different boss starts its killers list at the top; the two big lists keep their place
    local p = K.frame and K.frame.pages[page]
    if p and p.grid and page == "boss" and key ~= K.key then p.grid.offset = 0 end
    K.page, K.key = page, key
    K.Paint()
end

--- ESC WALKS BACK (Arn, 16 Oct: "if i click on someone its hard to go back to the tab - esc only
--- closes the window from the main page and the other pages go back, so someone can spam esc to get
--- back fast and close the window too"). From a card: the page before it, the way you came. With
--- nothing behind it, the list the card belongs to. From a list: false - the window closes.
K.trail = {}
function K.Back()
    if K.page ~= "raider" and K.page ~= "boss" then return false end
    local prev = table.remove(K.trail)
    K._backing = true
    if not prev then
        K.Go(K.page == "raider" and "raiders" or "bosses")
    elseif prev[1] == "raider" or prev[1] == "boss" then
        K.Go(prev[2] .. " <" .. prev[1] .. ">")
    else
        local trail = K.trail
        K.Go(prev[1])
        K.trail = trail
    end
    K._backing = false
    return true
end

--- Run a typed line (or a key). Returns what it did, for the suite.
function K.Go(line)
    -- A ROSTER PASTED INTO THE BiS> LINE (Arn, 16 Oct: Raid-Helper's JSON landed there - the line
    -- has the cursor when the terminal opens - and came back "no raider or boss called {"date"...").
    -- It is not a name, so it goes where rosters go.
    local raw = tostring(line or "")
    if ns.Inv and (raw:find('"signUps"', 1, true) or (#raw > 60 and raw:find(",", 1, true))) then
        ns.Books().roster = raw
        K.trail = {}
        K.Open("roster")
        Say("roster pasted - read from the BiS> line", "good")
        return "roster"
    end
    local kind, key = K.Parse(line, K.People(S().Cards()), S().Bosses())
    if kind == "log" then
        -- THE NOTEBOOK, NOT THE SCRIPT (Arn, 18 Oct: "in the logs we give them the link to go to the
        -- google code thing"). The PowerShell window is ours alone now: `/bisg window`, unadvertised.
        if ns.U and ns.U.ShowPaste then ns.U.ShowPaste() end
        return "log"
    end
    if kind == "raiders" or kind == "bosses" or kind == "where" or kind == "roster" or kind == "report"
        or kind == "recruits" then
        K.trail = {}                                   -- a list is the top: nothing behind it
        K.Open(kind)
        -- no nights yet and the guild listed: the why goes on the status line, not over the rows
        -- (Arn, 5 Nov screenshot: the hint printed straight through the guild's names)
        Say((kind == "raiders" and #S().Dates() == 0
                and "no raid nights yet - after a raid, the LOG tab reads your combat log   (click a name, or type one)")
            or (kind == "raiders" and "every raider - click one, or type a name   (click NAME or ATTEND to sort)")
            or (kind == "report" and ("the raid team by class: who raided in the last %d raids, and who is on the roster"):format(K.REPORT_RAIDS))
            or (kind == "bosses" and "every boss - click one, or type a name")
            or (kind == "roster" and ("paste a roster, READ IT, INVITE - " .. (ns.Inv and ns.Inv.Tools()
                and "BiS Tools' invite list takes it from there" or "a second click sends")))
            or (kind == "recruits" and "the guild's recruits and needs, from BiS> Nebbinator")
            or "who is where - a dot is a guildmate sharing their spot from a BiS addon; click a row to see their map")
        return kind
    end
    if kind == "raider" or kind == "boss" then
        -- the page we came from, so ESC can walk back the same way
        if not K._backing and K.page and (K.page ~= kind or K.key ~= key) then
            table.insert(K.trail, { K.page, K.key })
            if #K.trail > 20 then table.remove(K.trail, 1) end
        end
        K.Open(kind, key)
        Say(("%s <%s>      esc: back"):format(key:upper(), kind:upper()), "accent")
        if kind == "raider" and ns.X and ns.X.WantGear then ns.X.WantGear(key) end    -- newer armory?
        return kind, key
    end
    local what = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if what ~= "" then
        local offer = key or {}
        Say(#offer > 0 and ("no raider or boss called %s - did you mean %s?"):format(what, table.concat(offer, ", "))
            or ("no raider or boss called %s"):format(what), "warn")
    end
    return nil
end

function K.Show(page, key)
    local f = K.Build()
    if not f then return end
    -- a window opened fresh has nothing behind it: ESC from `/bisg alice` goes to the raiders list,
    -- not to whatever page was showing when the window was last closed
    if not f:IsShown() then K.trail = {} end
    local fresh = not f:IsShown()
    f:Show()
    -- in front, whole, and back in front when clicked (the log window does the same - Window.lua)
    if f.SetToplevel then f:SetToplevel(true) end
    if f.Raise then f:Raise() end
    -- ask the server for a fresh roster: who is still in the guild (its answer repaints the list)
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    if f.con then f.con:Say("guild record", "accent") end
    if page then
        K._backing = fresh            -- not "came from": the page before is from the last opening
        K.Go(page)
        K._backing = false
    elseif not K.page then K.Go("raiders") else K.Paint() end
    f.cmd:SetFocus()
    return f
end

function K.Hide()
    if K.frame then
        K.frame.cmd:ClearFocus()
        K.frame:Hide()
    end
end

function K.Toggle()
    if K.frame and K.frame:IsShown() then K.Hide() else K.Show() end
end
