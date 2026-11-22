--[[
  BiSGuild :: Core/DeckApp.lua - THE GUILD ON THE PHONE (22 Nov 2026).

  Arn, 22 Nov: "these apps i want them to open in the phone like apps" and, on the mocks, "as you have it, start Guild".
  The phone is BiSTheme's deck (it comes with BiS Tools): an app hands in DATA, never a frame. Without it nothing here runs. All of it
  is this addon's own words: the record (Core/Store.lua), the pasted raid and the invites (Core/Invite.lua), punctuality
  (Core/Logins.lua), the options window's rows (Core/Options.lua). Nothing is kept here and nothing is sent by painting.

   TONIGHT   the pasted raid: who is in, who is missing with INVITE, and the buffs you still need with DRINK / EAT. No raid: the last one.
   RAIDERS   everybody, with a search; one opens to a page: how often here, what they used, what their gear lacks, loot
   BOSSES    each boss and its best time; one opens to its page
   SETTINGS  the options window's own switches, and the doors to the big windows

  THE BIG TERMINAL STAYS (the mock's pick): the map, the recruits and the armory are wide things.
  THE CARDS: RAID NIGHT (from two hours before the start, hot at the start) and LOGGED IN (the pop-up's, with the phone open on its
  home screen the pop-up steps aside: one or the other).
  YOUR BUFFS are read out of a fight only, from your own buffs and bags. What you drank is known by the item's own spell (a flask's buff
  IS its spell); food by the one Well Fed buff. UNVERIFIED on Forever: which subclass its flasks carry, so names help.
]]
local ADDON, ns = ...
local A = {}
ns.DeckApp = A

A.LOOK = 4                     -- seconds a long list is kept
A.BEFORE, A.AFTER = 2 * 3600, 4 * 3600     -- when the raid night card is there (the login pop-up's own hours)
A.WELLFED = { 1249519, 19705 } -- the food buff, by its spell (Forever's; the old one)
A.BAGS = 4
A.DRINKS = 5                   -- flasks and elixirs listed at most

local function plain(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return plain(a), plain(b), plain(c), plain(d), plain(e), plain(f), plain(g) end
end
local function now() return ask(GetTime) or 0 end
local function server() return ask(GetServerTime) or 0 end
local function Deck()
    local T = _G.BiSTheme
    return type(T) == "table" and T.Deck or nil
end
local function low(s) return tostring(s or ""):lower() end
local function cap(s) s = tostring(s or "") return s:sub(1, 1):upper() .. s:sub(2):lower() end
local function class(m)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return m and m.class and (names and names[m.class] or cap(m.class)) or nil
end
local function clock(t) local d = _G.date return t and d and d("%H:%M", t) or "-" end
local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

--- A long answer, kept a few seconds; a press that changes something drops them all (A.Drop).
local kept = {}
local function slow(key, fn)
    local t, e = now(), kept[key]
    if not e or t < e.at or t - e.at > A.LOOK then
        local ok, v = pcall(fn)
        e = { at = t, v = ok and v or nil }
        if not ok and geterrorhandler then geterrorhandler()(v) end
        kept[key] = e
    end
    return e.v
end
function A.Drop() kept = {} end

-- THE RAID THAT IS PASTED ------------------------------------------------------------------------------------------------

--- { e = its event (nil = a plain list), on (the list), lead, signed, with, go = members online and not with you, off, out, odd, live, over }
--- or nil when nothing is pasted.
function A.Raid()
    return slow("raid", function()
        local I = ns.Inv
        local text = ns.Books().roster
        if not I or type(text) ~= "string" or text == "" then return nil end
        local r = { e = I.Event(text), on = {}, go = {}, off = {}, out = {}, odd = {}, signed = 0, with = 0, lead = I.Leads() }
        local here = I.Here()
        for _, row in ipairs(I.Read(text)) do
            local s = I.Status(row, here)
            if I.OUT[s] then r.out[#r.out + 1] = row
            else
                r.signed = r.signed + 1
                if s == "with you" then r.with = r.with + 1
                elseif s == "online" then r.go[#r.go + 1] = row
                elseif s == "offline" then r.off[#r.off + 1] = row
                else r.odd[#r.odd + 1] = row end
            end
        end
        local start, t = r.e and r.e.start, server()
        if start then
            r.live = t >= start - A.BEFORE and t <= start + A.AFTER
            r.over = t > start + A.AFTER
        end
        return r
    end)
end
--- The raid the app is about: what is pasted, unless it is over.
local function raid()
    local r = A.Raid()
    return r and not r.over and r or nil
end
local function missing(r) return #r.go + #r.off end
local function members(rows)
    local out = {}
    for _, row in ipairs(rows) do if row.member then out[#out + 1] = row.member end end
    return out
end
--- Everybody who can be asked now: through BiS Tools' list (it asks there), else a second press.
function A.Invite()
    local r = raid()
    if not r then return end
    ns.Inv.Send(members(r.go), "of tonight's raid")
    A.Drop()
    if C_Timer and C_Timer.After and Deck() then C_Timer.After(ns.Inv.ARM + 0.2, function() Deck().Dirty() end) end
end
local function armed()
    local a = ns.Inv and ns.Inv.armed
    return a and a.label == "of tonight's raid" and now() - a.at <= ns.Inv.ARM or false
end
--- What an invite answered (the terminal's own line), for a few seconds.
local function said()
    local K = ns.K
    if K.said and K.saidAt and now() >= K.saidAt and now() - K.saidAt < 8 then return K.said end
end

-- YOUR BUFFS -----------------------------------------------------------------------------------------------------------

local items = {}               -- item id -> { name, spell, kind = "drink" | "food" | false }
local function wellFed()
    for _, id in ipairs(A.WELLFED) do
        local n = ask(C_Spell and C_Spell.GetSpellName, id)
        if type(n) == "string" and n ~= "" then return n end
    end
    return "Well Fed"
end
--- What an item is to us: a flask or elixir, a food that leaves you Well Fed, or nothing. Asked once (a blank text: asked again).
function A.Item(id)
    local it = items[id]
    if it then return it end
    local _, _, _, _, icon, cls, sub = ask((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, id)
    if cls ~= 0 then
        it = { kind = false }
        items[id] = it
        return it
    end
    local name = ask(C_Item and C_Item.GetItemNameByID, id) or ask((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
    local spellName, spell = ask((C_Item and C_Item.GetItemSpell) or GetItemSpell, id)
    it = { name = name, spell = spell, icon = icon, kind = false }
    if type(name) ~= "string" then return it end                          -- (not here yet: asked again)
    if type(spell) ~= "number" then items[id] = it return it end
    local n = low(name)
    if sub == 2 or sub == 3 or n:find("^flask") or n:find("^elixir") or n:find(" elixir$") then
        it.kind = "drink"
    else
        local text = ask(C_Spell and C_Spell.GetSpellDescription, spell)
        if (type(text) ~= "string" or text == "") and (it.tries or 0) < 3 then
            ask(C_Spell and C_Spell.RequestLoadSpellData, spell)
            it.tries = (it.tries or 0) + 1
            return it
        end
        if type(text) == "string" and low(text):find(low(wellFed()), 1, true) then it.kind = "food" end
    end
    it.spellName = spellName
    items[id] = it
    return it
end
--- { food, drink, weapon = minutes left or true / nil (not up), foods = { { id, name, icon, n } }, drinks = {...} }.
function A.Buffs()
    return slow("buffs", function()
        local out = { foods = {}, drinks = {} }
        local fed, up, names = wellFed(), {}, {}
        for i = 1, 40 do
            local ok, aura = pcall(function() return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL") end)
            if not ok or type(aura) ~= "table" then break end
            local id, name, ends = plain(aura.spellId), plain(aura.name), plain(aura.expirationTime)
            local left = type(ends) == "number" and ends > 0 and math.max(0, math.ceil((ends - now()) / 60)) or true
            if type(id) == "number" then up[id] = left end
            if type(name) == "string" then
                names[name] = left
                if name == fed then out.food = left end
                if low(name):find("^flask") or low(name):find("^elixir") then out.drink = out.drink or left end
            end
        end
        local count = {}
        local C = C_Container or {}
        for bag = 0, A.BAGS do
            for slot = 1, tonumber(ask(C.GetContainerNumSlots, bag)) or 0 do
                local info = ask(C.GetContainerItemInfo, bag, slot)
                local id = type(info) == "table" and plain(info.itemID) or nil
                if type(id) == "number" then count[id] = (count[id] or 0) + (tonumber(plain(info.stackCount)) or 1) end
            end
        end
        for id, n in pairs(count) do
            local it = A.Item(id)
            if it.kind then
                local x = { id = id, name = it.name, icon = it.icon, n = n }
                if it.kind == "food" then out.foods[#out.foods + 1] = x
                else
                    x.up = it.spell and up[it.spell] or it.spellName and names[it.spellName] or nil
                    if x.up then out.drink = out.drink or x.up end
                    out.drinks[#out.drinks + 1] = x
                end
            end
        end
        local function most(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end
        table.sort(out.foods, most)
        table.sort(out.drinks, most)
        local has, ms = ask(GetWeaponEnchantInfo)
        if has then out.weapon = type(ms) == "number" and math.ceil(ms / 60000) or true end
        return out
    end) or { foods = {}, drinks = {} }
end
--- What you lack, in words (the card), most needed first.
function A.Lack()
    local b, out = A.Buffs(), {}
    if not b.drink then out[#out + 1] = #b.drinks > 0 and "no flask or elixir on" or "no flask or elixir" end
    if not b.food then out[#out + 1] = #b.foods > 0 and "not Well Fed" or "no food" end
    if not b.weapon then out[#out + 1] = "nothing on your weapon" end
    return out
end
local function left(v) return type(v) == "number" and v .. " MIN" or "UP" end
function A.BuffRows(out)
    local b = A.Buffs()
    local function again() A.Drop() end
    out[#out + 1] = { head = true, text = "YOUR BUFFS", right = #A.Lack() == 0 and "all there" or #A.Lack() .. " missing" }
    if b.drink then out[#out + 1] = { mark = "v", text = "Flask or elixir", right = left(b.drink), ink = "good" }
    elseif #b.drinks == 0 then out[#out + 1] = { mark = "-", text = "Flask or elixir", right = "YOU HAVE NONE", ink = "warn" } end
    for i, x in ipairs(b.drinks) do
        if i > A.DRINKS then break end
        if not x.up and not (b.drink and i > 2) then
            out[#out + 1] = { pic = x.icon or 134400, text = x.name, right = "x" .. x.n, act = { word = "DRINK", item = x.id, after = again }, tip = "Drink one" }
        end
    end
    if b.food then out[#out + 1] = { mark = "v", text = "Food", right = left(b.food), ink = "good" }
    elseif b.foods[1] then
        local x = b.foods[1]
        out[#out + 1] = { pic = x.icon or 134400, text = x.name, right = "x" .. x.n, act = { word = "EAT", item = x.id, after = again }, tip = "Eat one" }
    else out[#out + 1] = { mark = "-", text = "Food", right = "YOU HAVE NONE", ink = "warn", tip = "Nothing in your bags leaves you " .. wellFed() } end
    out[#out + 1] = b.weapon and { mark = "v", text = "Weapon", right = left(b.weapon), ink = "good" } or { mark = "-", text = "Weapon", right = "NOTHING ON IT", ink = "warn", tip = "Oil, stone or imbue" }
end

-- THE RECORD ------------------------------------------------------------------------------------------------------------

local function dates() return slow("dates", function() return ns.S.Dates() end) or {} end
local function cards() return slow("cards", function() return ns.S.Cards() end) or {} end
local function bosses() return slow("bosses", function() return ns.S.Bosses() end) or {} end
local function lines() return slow("rows", function() return ns.K.Rows(cards()) end) or {} end
--- The last raid on record: its night, key, and { name, b } of its bosses.
local function lastRaid()
    local d = dates()
    local key = d[#d]
    local night = key and ns.S.Record().nights[key]
    if not night then return nil end
    local list = {}
    for name, b in pairs(night.bosses or {}) do list[#list + 1] = { name = name, b = b } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return night, key, list
end
local function ink(pct) return pct >= 75 and "good" or pct >= 50 and "gold" or "warn" end

-- THE PAGES --------------------------------------------------------------------------------------------------------------

local ID = ADDON .. ":app"
local query, everyone = "", false
local pick, pickTab            -- { kind = "raider" | "boss", name }: the page open in a list
local function open(kind, name, tab)
    return { word = "open", peek = true, fn = function()
        pick, pickTab = { kind = kind, name = name }, tab
        local D = Deck()
        local d = D and D.defs[ID]
        if d and tab then d.tab = tab end
        if D then D.skip = 0 end
        if kind == "raider" and ns.X and ns.X.WantGear then pcall(ns.X.WantGear, name) end     -- (as the terminal's page does: newer armory?)
    end }
end
local function back(words)
    return { mark = "<", text = words, act = { word = "back", peek = true, fn = function() pick = nil local D = Deck() if D then D.skip = 0 end end } }
end
--- The page open on this tab, or nil; gone from the record = back to the list.
local function page(tab)
    if not pick or pickTab ~= tab then return nil end
    if pick.kind == "boss" and not bosses()[pick.name] then pick = nil return nil end
    if pick.kind == "raider" and not cards()[pick.name] and not ns.K.Member(pick.name) then pick = nil return nil end
    return pick
end

local function person(row, right, colour, act)
    local m = row.member
    local sub = class(m)
    if row.signed then sub = (sub and sub .. ", " or "") .. "signed " .. row.signed end
    return { mark = (class(m) or "?"):sub(1, 1), text = m and m.name or row.typed, sub = sub or "not in the guild", right = right, ink = colour, done = not act and right == "OFFLINE" or nil,
        act = act, verb = act and "INVITE" or nil, tip = act and "Invite" or nil }
end
local function tonightRows()
    local out, r = {}, raid()
    if r then
        out[1] = { head = true, text = "MISSING", right = tostring(missing(r)) }
        for _, row in ipairs(r.go) do
            local name = row.member.name
            out[#out + 1] = person(row, not r.lead and "ONLINE" or nil, "good", r.lead and { word = "INVITE", fn = function() ns.Inv.One(name) A.Drop() end } or nil)
        end
        for _, row in ipairs(r.off) do out[#out + 1] = person(row, "OFFLINE", "dim") end
        for _, row in ipairs(r.odd) do out[#out + 1] = { mark = "?", text = row.typed, right = "NOT IN GUILD", ink = "warn", tip = "Not found in the guild: invite by hand" } end
        A.BuffRows(out)
        if #r.out > 0 then
            out[#out + 1] = { head = true, text = "NOT COMING", right = tostring(#r.out) }
            for _, row in ipairs(r.out) do out[#out + 1] = { mark = "-", text = row.member and row.member.name or row.typed, right = (row.standing or ""):upper(), ink = "dim", done = true } end
        end
        return out
    end
    local night, key, list = lastRaid()
    if night then
        out[1] = { head = true, text = "LAST RAID", right = ns.S.Label(key) }
        for _, x in ipairs(list) do
            local won = (tonumber(x.b.kills) or 0) > 0
            out[#out + 1] = { mark = won and "v" or "-", text = x.name, right = won and ns.K.Clock(x.b.best) or ((tonumber(x.b.pulls) or 0) == 1 and "1 TRY" or (tonumber(x.b.pulls) or 0) .. " TRIES"), ink = won and "good" or "warn", act = open("boss", x.name, 3) }
        end
    end
    A.BuffRows(out)
    return out
end
local function tonightBoxes()
    local r = raid()
    if r then
        return { { "IN", r.with .. " / " .. r.signed, r.with >= r.signed and "good" or "ink" }, { "MISSING", missing(r), missing(r) > 0 and "warn" or "dim" }, { "ONLINE", #r.go, #r.go > 0 and "gold" or "dim" },
            { "START", clock(r.e and r.e.start), "gold" } }
    end
    local night = lastRaid()
    if not night then return {} end
    local people = 0
    for _ in pairs(night.raiders or {}) do people = people + 1 end
    return { { "KILLS", tonumber(night.kills) or 0, "good" }, { "RAIDERS", people }, { "NIGHTS", #dates(), "gold" } }
end

local function raiderRows()
    local out, more = {}, 0
    local q = low(query)
    for _, r in ipairs(lines()) do
        local m = ns.K.Member(r.name)
        local cls = class(m)
        if q ~= "" and not (low(r.name) .. " " .. low(cls) .. " " .. low(r.rank)):find(q, 1, true) then
            -- not it
        elseif r.none and q == "" and not everyone then
            more = more + 1
        else
            local sub = (cls or "?") .. ", " .. tostring(r.rank) .. (r.none and ", no raids yet" or ", last " .. tostring(r.last) .. (r.flask and "" or ", no flask"))
            out[#out + 1] = { mark = (cls or "?"):sub(1, 1), text = r.name, sub = sub, right = r.none and "" or r.att .. "%", ink = r.none and "dim" or ink(r.att), done = r.none or r.pug or nil,
                act = open("raider", r.name), tip = r.issues > 0 and plural(r.issues, "gear issue") or nil }
        end
    end
    if more > 0 then out[#out + 1] = { mark = "+", text = plural(more, "member") .. " with no raids yet", act = { word = "show", peek = true, fn = function() everyone = true end } } end
    return out
end
local function raiderBoxes()
    local n, good, gear = 0, 0, 0
    for _, r in ipairs(lines()) do
        if not (r.none or r.pug) then
            n = n + 1
            if r.att >= 80 then good = good + 1 end
            if r.issues > 0 then gear = gear + 1 end
        end
    end
    if n == 0 then return {} end
    return { { "RAIDERS", n }, { "HERE 80%+", good, "good" }, { "GEAR ISSUES", gear, gear > 0 and "warn" or "dim" }, { "NIGHTS", #dates(), "gold" } }
end
local QUALITY = { [2] = "uncommon", [3] = "rare", [4] = "epic" }
local function raiderPage(name)
    local c = cards()[name] or { attended = {}, issues = {} }
    local m = ns.K.Member(name)
    local out = { back("All raiders") }
    local function add(text, right, colour, tip) if right and right ~= "" then out[#out + 1] = { mark = "-", text = text, right = tostring(right), ink = colour, tip = tip } end end
    add("Now", m and (m.online and (m.zone or "online") or "offline") or "not in the guild", m and m.online and "good" or "dim")
    add("Rank", m and m.rank, "ink2")
    local l = c.last
    if l then
        out[#out + 1] = { head = true, text = "LAST RAID", right = ns.S.DateOf(l.date) }
        local pulls = l.pulls or 0
        for _, x in ipairs({ { "Flask", l.flask, true }, { "Elixirs", l.elixir }, { "Food", l.food, true }, { "Weapon", l.weapon, true } }) do
            add(x[1], (x[2] or 0) .. " of " .. pulls .. " pulls", (x[2] or 0) > 0 and "good" or x[3] and "warn" or "ink2")
        end
        add("Deaths that night", l.deaths or 0, (l.deaths or 0) > 0 and "warn" or "good")
    end
    local habit, colour = nil, nil
    if ns.Login then habit, colour = ns.Login.HabitText(name) end
    add("On time", habit, colour)
    if c.gear then
        out[#out + 1] = { head = true, text = "GEAR", right = c.gearDate and "seen " .. c.gearDate or "" }
        local bad = {}
        for _, i in ipairs(c.issues or {}) do bad[i.slot] = i.what end
        for i, slot in ipairs(ns.S.SLOTS) do
            local g = c.gear[i]
            local id = type(g) == "table" and tonumber(g[1]) or 0
            if id ~= 0 then
                local item, q = ns.K.Item(id)
                out[#out + 1] = { mark = bad[slot] and "!" or "-", text = item or slot, tint = QUALITY[q or 1], sub = low(slot) .. ", level " .. tostring(g[2] or "?"), right = bad[slot] and bad[slot]:upper() or "", ink = "warn" }
            end
        end
    end
    local loot = ns.K.Loot(name)
    if #loot > 0 then
        out[#out + 1] = { head = true, text = "LOOT", right = plural(#loot, "item") }
        for i = 1, math.min(8, #loot) do
            local item, q = ns.K.Item(loot[i].item)
            out[#out + 1] = { mark = "*", text = item or "an item", tint = QUALITY[q or 1], sub = loot[i].boss or "", right = "" }
        end
    end
    return out
end
local function raiderPageBoxes(name)
    local c = cards()[name] or { attended = {} }
    local n = #dates()
    local pct = n > 0 and math.floor(100 * #(c.attended or {}) / n + 0.5) or 0
    return { { "HERE", pct .. "%", ink(pct) }, { "NIGHTS", #(c.attended or {}) .. " / " .. n }, { "DEATHS", c.deaths or 0 }, { "POTIONS", c.pots or 0 } }
end

local function bossRows()
    local out = {}
    for _, b in ipairs(slow("bossrows", function() return ns.K.BossRows(bosses()) end) or {}) do
        out[#out + 1] = { mark = b.kills > 0 and "v" or "-", text = b.name, sub = plural(b.kills, "kill") .. ", " .. plural(b.wipes, "wipe"), right = b.kills > 0 and ns.K.Clock(b.best) or "ALIVE", ink = b.kills > 0 and "gold" or "warn",
            act = open("boss", b.name) }
    end
    return out
end
local function bossBoxes()
    local k, w, down, all = 0, 0, 0, 0
    for _, b in pairs(bosses()) do k, w, all = k + b.kills, w + b.wipes, all + 1 if b.kills > 0 then down = down + 1 end end
    if all == 0 then return {} end
    return { { "DOWN", down .. " / " .. all, down == all and "good" or "ink" }, { "KILLS", k, "good" }, { "WIPES", w, w > 0 and "warn" or "dim" }, { "NIGHTS", #dates(), "gold" } }
end
local function bossPage(name)
    local b = bosses()[name]
    local out = { back("All bosses"), { mark = "-", text = "First kill", right = b.first and ns.S.Label(b.first) or "not yet", ink = "ink2" } }
    if #b.nights > 0 then out[#out + 1] = { mark = "-", text = "Last kill", right = ns.S.Label(b.nights[#b.nights]), ink = "ink2" } end
    local who = {}
    for n, k in pairs(b.killers) do who[#who + 1] = { n, k } end
    table.sort(who, function(x, y) if x[2] ~= y[2] then return x[2] > y[2] end return x[1] < y[1] end)
    if #who > 0 then out[#out + 1] = { head = true, text = "WHO WAS THERE", right = plural(#who, "raider") } end
    for _, x in ipairs(who) do out[#out + 1] = { mark = "-", text = x[1], right = plural(x[2], "kill"), ink = "good", act = open("raider", x[1], 2) } end
    return out
end
local function bossPageBoxes(name)
    local b = bosses()[name]
    local pulls = b.kills + b.wipes
    return { { "KILLS", b.kills, "good" }, { "WIPES", b.wipes, b.wipes > 0 and "warn" or "dim" }, { "BEST", b.kills > 0 and ns.K.Clock(b.best) or "-", "gold" },
        { "KILL RATE", pulls > 0 and math.floor(100 * b.kills / pulls + 0.5) .. "%" or "-" } }
end

--- The options window's own rows, and the doors to the big windows.
local function settingRows()
    local out, db = {}, ns.DB()
    for _, opt in ipairs(ns.Opt and ns.Opt.Rows() or {}) do
        if opt.kind == "toggle" then
            local is = opt.get(db)
            out[#out + 1] = { text = cap(opt.label), right = is and "ON" or "OFF", ink = is and "good" or "dim", tip = opt.help,
                act = { word = "switch", chip = true, fn = function()
                    opt.set(db, not opt.get(db))
                    if ns.Opt.frame and ns.Opt.frame:IsShown() then ns.Opt.frame:Paint() end
                end } }
        end
    end
    local function door(text, word, fn, right, tip) out[#out + 1] = { text = text, right = right, act = { word = word, peek = true, fn = fn }, verb = word, tip = tip } end
    out[#out + 1] = { head = true, text = "THE BIG WINDOWS", right = "" }
    local r = A.Raid()
    door("Raid pasted", "PASTE", function() ns.K.Show("roster") end, r and r.e and clock(r.e.start) or r and "a list" or "none", "The ROSTER page: paste tonight's raid from Discord")
    door("A combat log", "READ", function() ns.U.ShowPaste() end, plural(#dates(), "night"), "After a raid: the log, read outside the game, pasted here")
    door("The terminal", "OPEN", function() ns.K.Show() end, nil, "Everything, wide")
    door("Where everyone is", "OPEN", function() ns.K.Show("where") end)
    door("Recruits", "OPEN", function() ns.K.Show("recruits") end)
    return out
end

-- THE CARDS -----------------------------------------------------------------------------------------------------------------

function A.CardPrio(out)
    local r = raid()
    if not (r and r.live) then return out and r and 2 or nil end
    local t = r.e.start - server()
    if r.lead and #r.go > 0 and t <= 1800 then return 8 end
    return t <= 1800 and #A.Lack() > 0 and 6 or 4
end
function A.CardLines()
    local r = raid()
    if not r then return nil end
    local lack = A.Lack()
    local list = {}
    if missing(r) > 0 then list[#list + 1] = { "Missing", #r.go > 0 and (missing(r) .. ", " .. #r.go .. " online") or tostring(missing(r)) } end
    if lack[1] then list[#list + 1] = { "You", lack[1] } end
    list[#list + 1] = { r.e and r.e.title or "Raid", r.e and ns.Inv.When(r.e) or "" }
    return { "RAID NIGHT", "", r.with .. " of " .. r.signed .. " in", clock(r.e and r.e.start), "gold", hot = r.lead and #r.go > 0 and r.live or false, list = list }
end
local function inviteKey(r)
    if not (r and r.lead and #r.go > 0) then return nil end
    local all = #r.go
    return { word = armed() and "SURE? INVITE " .. all or all == 1 and "INVITE 1" or "INVITE THE " .. all, tip = ns.Inv.Tools() and "Onto BiS Tools' list: look it over, then send" or "Press twice to send", fn = A.Invite }
end

--- Is the phone open on its home screen (or the card pulled out)? Then LOGGED IN is there, and the pop-up is not needed.
function A.LoginSeen()
    local D = Deck()
    if not (A.login and D and D.IsPinned) or D.fight then return false end
    if D.IsPinned(ADDON .. ":login") or (D.IsOut and D.IsOut(ADDON .. ":login")) then return true end
    local f = D.mainSurf and D.surf ~= D.mainSurf and D.mainSurf.frame or D.frame
    return f and f:IsShown() and (D.page or "home") == "home" or false
end
local function waiting()
    local L = ns.Login
    if not L or #L.waiting == 0 then return nil end
    L.Prune()
    return L.waiting[1], #L.waiting
end

function A.Register()
    local D = Deck()
    if A.handle or not (D and D.Register) then return false end
    A.handle = D.Register{
        owner = ADDON, key = "app", name = "Guild", icon = "Gu", order = 30,
        about = "Raid nights from your own logs: who was there, what they used, what comes next.",
        badge = function() local r = raid() return r and r.live and r.lead and #r.go > 0 and #r.go or nil end,
        card = {
            tick = true,
            prio = A.CardPrio, lines = A.CardLines,
            buttons = function()
                local out, r = {}, raid()
                local k = inviteKey(r)
                if k then out[1] = { word = armed() and "SURE?" or "INVITE " .. #r.go, tip = k.tip, fn = A.Invite } end
                out[#out + 1] = { word = "OPEN", peek = true, fn = function() pick = nil D.defs[ID].tab = 1 D.Open(ID) end }
                return out
            end,
        },
        page = {
            tour = { { text = "TONIGHT is the raid you pasted: who is missing, and the buffs you still need.", note = "Paste it under SETTINGS." },
                { text = "Press a raider or a boss: everything the logs say about them." } },
            title = function() return "Guild" end,
            kicker = function()
                local r = raid()
                return r and r.e and r.e.title or r and "a pasted list" or "the raid record"
            end,
            tabs = function() return { "TONIGHT", "RAIDERS", "BOSSES", "SETTINGS" } end,
            find = function(tab)
                if tab ~= 2 or page(2) then return nil end
                return { hint = "search a raider, a class, a rank", get = function() return query end, set = function(w) query = w or "" end,
                    enter = function()
                        local q = low(query)
                        for _, r in ipairs(lines()) do if q ~= "" and low(r.name):find(q, 1, true) then pick, pickTab = { kind = "raider", name = r.name }, 2 return end end
                    end }
            end,
            boxes = function(tab)
                local p = page(tab)
                if p then return p.kind == "boss" and bossPageBoxes(p.name) or raiderPageBoxes(p.name) end
                if tab == 1 then return tonightBoxes() elseif tab == 2 then return raiderBoxes() elseif tab == 3 then return bossBoxes() end
                return {}
            end,
            rows = function(tab)
                local p = page(tab)
                if p then return p.kind == "boss" and bossPage(p.name) or raiderPage(p.name) end
                if tab == 1 then return tonightRows() elseif tab == 2 then return raiderRows() elseif tab == 3 then return bossRows() end
                return settingRows()
            end,
            text = function(tab)
                if page(tab) then return nil end
                if tab == 1 and not raid() and not lastRaid() then return "No raid pasted and no raid on record yet. PASTE A RAID: copy it from your Discord's raid tool." end
                if tab == 2 and #raiderRows() == 0 then return query ~= "" and "Nobody by that name." or "Nobody yet. The guild's list comes from the game, the rest from your raid logs." end
                if tab == 3 and #bossRows() == 0 then return "No boss on record yet. After a raid, read its combat log: SETTINGS, A combat log." end
            end,
            say = function(tab)
                local s = said()
                if s then return s end
                local p = page(tab)
                if p then return p.name end
                if tab == 1 then
                    local r = raid()
                    if r then return r.e and ns.Inv.When(r.e) or plural(r.signed, "name") .. " on the list" end
                elseif tab == 2 and #dates() > 0 then return "Here = at least half the kills of a night"
                elseif tab == 3 and #bossRows() > 0 then return "The best time of each" end
            end,
            big = function(tab)
                local p = page(tab)
                if p and p.kind == "raider" then
                    local m = ns.K.Member(p.name)
                    if m and m.online and _G.ChatFrame_SendTell then return { word = "WHISPER", peek = true, tip = "Write to " .. m.name, fn = function() pcall(_G.ChatFrame_SendTell, m.name) end } end
                    return nil
                end
                if tab ~= 1 then return nil end
                local r = raid()
                if not A.Raid() then return { word = "PASTE A RAID", peek = true, tip = "The ROSTER page of the terminal", fn = function() ns.K.Show("roster") end } end
                return inviteKey(r)
            end,
            keys = function(tab)
                local p = page(tab)
                if p and p.kind == "raider" then
                    local out, m = {}, ns.K.Member(p.name)
                    if m and m.online and ns.Inv.Leads() and not ns.Inv.IsHere(ns.Inv.Here(), m) then
                        out[1] = { word = "INVITE", fn = function() ns.Inv.One(m.name) A.Drop() end }
                    end
                    out[#out + 1] = { word = "TERMINAL", peek = true, tip = "Their page, wide, with the armory", fn = function() ns.K.Show(p.name .. " <raider>") end }
                    return out
                elseif p then return { { word = "TERMINAL", peek = true, fn = function() ns.K.Show(p.name .. " <boss>") end } } end
                if tab == 1 then
                    local out, r = {}, A.Raid()
                    local check = (C_PartyInfo and C_PartyInfo.DoReadyCheck) or DoReadyCheck
                    if check and ask(IsInGroup) and ns.Inv.Leads() then out[1] = { word = "READY CHECK", fn = function() pcall(check) end } end
                    if r then out[#out + 1] = { word = r.over and "PASTE A RAID" or "ROSTER", peek = true, tip = "The ROSTER page of the terminal", fn = function() ns.K.Show("roster") end } end
                    return out
                elseif tab == 2 then
                    local out = { { word = "ASK AGAIN", peek = true, tip = "The guild's list, asked of the game again", fn = function() ns.K.AskRoster() ns.K._guildDirty = true A.Drop() end } }
                    if everyone then out[2] = { word = "RAIDERS ONLY", peek = true, fn = function() everyone = false end } end
                    return out
                end
                return {}
            end,
        },
    }
    -- somebody of the roster came online (the pop-up's, one or the other)
    A.login = D.Register{
        owner = ADDON, key = "login", name = "Raid log-ins", hidden = true, order = 30.5,
        card = {
            prio = function() return waiting() and 9 or nil end,
            lines = function()
                local w, n = waiting()
                if not w then return nil end
                local L = ns.Login
                local list = {}
                if w.signed then list[1] = { "Signed", w.signed } end
                local d = L.DeltaText(w.delta)
                if d then list[#list + 1] = { "Tonight", d } end
                local h = L.HabitText(w.key)
                if h then list[#list + 1] = { "Before", h } end
                return { "LOGGED IN", "", w.name, n > 1 and "+" .. (n - 1) or "", "gold", hot = true, list = list }
            end,
            buttons = function()
                local w, n = waiting()
                if not w then return {} end
                local out = { { word = "INVITE", fn = function() ns.Inv.One(w.name) ns.Login.Done(w.key) A.Drop() end }, { word = "NOT NOW", peek = true, fn = function() ns.Login.Done(w.key) end } }
                if n > 1 then
                    table.insert(out, 2, { word = "ALL " .. n, fn = function()
                        local names = {}
                        for _, x in ipairs(ns.Login.waiting) do names[#names + 1] = x.name end
                        ns.Inv.Queue(names)
                        ns.Login.waiting = {}
                        ns.Login.Paint()
                        A.Drop()
                    end })
                end
                return out
            end,
        },
    }
    -- what changes it: the group, the guild's list, the roster pasted (read again at the next look). Only a flag while it is not shown.
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, e)
        if e == "GROUP_ROSTER_UPDATE" then kept.raid = nil elseif e == "BAG_UPDATE_DELAYED" or e == "PLAYER_REGEN_ENABLED" then kept.buffs = nil end
        if A.handle.Dirty then A.handle:Dirty() end
    end)
    A.events = f
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() A.Register() end)
A.boot = ev
