-- dev/deckapp.lua - the guild on the phone (Core/DeckApp.lua), run by dev/tests.lua at its end: return function(H, NS).
-- The deck itself is BiSTheme's (its own suites): here it is a stand-in that takes the data in and reads every part of it as the
-- real one's painter does - what it would choke on is an error here.
return function(H, NS)
    local A, I, K, S = NS.DeckApp, NS.Inv, NS.K, NS.S
    H.section("the phone: the guild as an app")
    H.ok(A ~= nil, "Core/DeckApp.lua is loaded")
    local INK = { ink = 1, ink2 = 1, dim = 1, good = 1, gold = 1, warn = 1, accent = 1 }
    local TINT = { uncommon = 1, rare = 1, epic = 1 }
    local function words(v, what) if v ~= nil and type(v) ~= "string" and type(v) ~= "number" then error(what .. " is not words: " .. type(v), 2) end end
    local function button(b, what)
        if type(b) ~= "table" or type(b.word) ~= "string" or b.word == "" then error(what .. ": a button has a word", 2) end
        if not (type(b.fn) == "function" or b.item or b.spell or b.macro) then error(what .. ": a button does something", 2) end
        if b.fn and b.item then error(what .. ": either ours or the game's", 2) end
    end
    local defs = {}
    local D = { defs = defs, page = "home", dirty = 0, pinned = {} }
    function D.Register(d)
        for k in pairs(d.page or {}) do
            if not ({ tour = 1, title = 1, kicker = 1, tabs = 1, find = 1, boxes = 1, rows = 1, text = 1, say = 1, big = 1, keys = 1, hero = 1, tick = 1 })[k] then error("the deck knows no page." .. k, 2) end
        end
        d.id = d.owner .. ":" .. d.key
        defs[d.id] = d
        return { def = d, Dirty = function() D.dirty = D.dirty + 1 end }
    end
    function D.Dirty() D.dirty = D.dirty + 1 end
    function D.Open(id) D.page = id end
    function D.IsPinned(id) return D.pinned[id] end
    --- Everything a paint asks of one tab; answers its rows.
    local function paint(d, tab)
        local p = d.page
        words(p.title(tab), "title") words(p.kicker(tab), "kicker") words(p.say(tab), "say") words(p.text(tab), "text")
        local t = p.tabs()
        local n = 0
        for _, x in ipairs(t) do n = n + #x if #x > 9 then error("a tab is nine letters at most: " .. x) end end
        if #t > 4 then error("four tabs") end
        local f = p.find(tab)
        if f and not (type(f.get) == "function" and type(f.set) == "function") then error("find") end
        local boxes = p.boxes(tab)
        if #boxes > 8 then error("eight boxes") end
        for _, b in ipairs(boxes) do words(b[1], "a box") words(b[2], "a box's value") if b[2] == nil then error("a box says something: " .. b[1]) end if b[3] and not INK[b[3]] then error("no such ink: " .. tostring(b[3])) end end
        local rows = p.rows(tab)
        for _, r in ipairs(rows) do
            words(r.text, "a row") words(r.right, "its right") words(r.sub, "its line") words(r.tip, "its tip") words(r.mark, "its mark")
            if type(r.text) ~= "string" or r.text == "" then error("a row says something") end
            if r.ink and not INK[r.ink] then error("no such ink: " .. tostring(r.ink)) end
            if r.tint and not TINT[r.tint] then error("no such tint: " .. tostring(r.tint)) end
            if r.act then button(r.act, r.text) end
            if r.side then button(r.side, r.text) if r.right then error("a side key and no right: " .. r.text) end end
        end
        local big = p.big(tab)
        if big then button(big, "big") end
        local keys = p.keys(tab)
        if #keys > 4 then error("four keys") end
        for _, b in ipairs(keys) do button(b, "a key") end
        return rows, boxes, big, keys
    end
    local function card(d, out)
        local prio = d.card.prio(out)
        if prio == nil then return nil end
        local l = d.card.lines(out)
        if type(l) ~= "table" or #l < 4 then error("a card has its four words") end
        for i = 1, 4 do words(l[i], "a card") end
        if l[5] and not INK[l[5]] then error("no such ink") end
        if #(l.list or {}) > 3 then error("three lines at most") end
        for _, x in ipairs(l.list or {}) do words(x[1], "a card's line") words(x[2], "its right") end
        local bs = d.card.buttons()
        if #bs > 3 then error("three buttons") end
        for _, b in ipairs(bs) do button(b, "a card's button") end
        return prio, l, bs
    end

    -- no deck: nothing
    local keep = {}
    for _, g in ipairs({ "BiSTheme", "GetNumGuildMembers", "GetGuildRosterInfo", "C_PartyInfo", "C_UnitAuras", "C_Container", "C_Item", "C_Spell", "GetWeaponEnchantInfo", "GetServerTime",
        "ChatFrame_SendTell", "IsInGroup", "UnitName", "GetNumGroupMembers", "IsInRaid", "UnitIsGroupLeader", "date", "issecretvalue", "BiSToolsAPI", "LOCALIZED_CLASS_NAMES_MALE", "C_Timer" }) do keep[g] = rawget(_G, g) end
    local books = NS.Books()
    local rosterWas, loginsWas, recWas = books.roster, _G.BiSGuildDB.logins, books.record
    local theme = {}
    for k, v in pairs(keep.BiSTheme or {}) do theme[k] = v end
    theme.Deck = nil
    _G.BiSTheme = theme
    H.ok(A.Register() == false and not A.handle, "without the deck: nothing is made")
    theme.Deck = D
    -- the world
    local clock = 1795370400                                       -- (Sun 22 Nov 2026)
    _G.GetServerTime = function() return clock end
    _G.date = function(f, t) return os.date("!" .. f, t) end
    _G.LOCALIZED_CLASS_NAMES_MALE = nil
    local ROSTER = { { "Bob", "Raider", "WARRIOR", true }, { "Kio Alpha", "Raider", "MAGE", true }, { "Cara", "Raider", "PRIEST", false }, { "Dax Moss", "Initiate", "SHAMAN", true }, { "Kumlust", "Officer", "SHAMAN", true } }
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] if r then return r[1], r[2], 1, 60, r[3], "Orgrimmar", "", "", r[4], 0, r[3] end end
    K._guildDirty = true
    local group, lead = { "Kumlust" }, true
    _G.IsInGroup = function() return #group > 1 end
    _G.IsInRaid = function() return false end
    _G.GetNumGroupMembers = function() return #group > 1 and #group or 0 end
    _G.UnitName = function(u) if u == "player" then return "Kumlust" end local i = tonumber(tostring(u):match("^party(%d+)$") or "") return i and group[i + 1] or nil end
    _G.UnitIsGroupLeader = function() return lead end
    _G.BiSToolsAPI = nil
    local invited, checks = {}, 0
    _G.C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end, ConvertToRaid = function() end, DoReadyCheck = function() checks = checks + 1 end }
    I.out, I.held, I.queue, I._armed, I.armed = {}, nil, {}, false, nil
    local AURAS, BAG, WEAPON = {}, {}, nil
    _G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter) if unit ~= "player" or filter ~= "HELPFUL" then error("args") end return AURAS[i] end }
    local ITEMS = { [13510] = { "Flask of the Titans", 3, 17626 }, [9088] = { "Gift of Arthas", 2, 11371 }, [13931] = { "Nightfin Soup", 5, 18234, "Restores health. If you spend 10 seconds eating you will become Well Fed." },
        [4540] = { "Tough Hunk of Bread", 5, 433, "Restores 61 health over 18 sec." }, [2589] = { "Linen Cloth", 0, nil, nil, 7 } }
    _G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end, GetContainerItemInfo = function(b, s) local x = b == 0 and BAG[s] if x then return { itemID = x[1], stackCount = x[2] } end end }
    _G.C_Item = { GetItemInfoInstant = function(id) local it = ITEMS[id] return id, "", "", "", 130000 + id, it[5] or 0, it[2] end, GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
        GetItemSpell = function(id) if ITEMS[id][3] then return ITEMS[id][1], ITEMS[id][3] end end, GetItemInfo = function(id) return ITEMS[id] and ITEMS[id][1] end }
    _G.C_Spell = { GetSpellName = function(id) return id == 19705 and "Well Fed" or nil end, GetSpellDescription = function(id) for _, it in pairs(ITEMS) do if it[3] == id then return it[4] end end end }
    _G.GetWeaponEnchantInfo = function() return WEAPON ~= nil, WEAPON end
    local function later(n) H.clock = H.clock + (n or 10) end
    local rec = { nights = {}, gear = {}, archived = {}, restored = {} }
    books.record = rec
    books.roster = nil
    later()
    H.ok(A.Register() == true and defs["BiSGuild:app"] and defs["BiSGuild:login"], "with it: the app, and the log-in card")
    H.ok(A.Register() == false, "once")
    local d = defs["BiSGuild:app"]
    local function has(rows, text) for _, r in ipairs(rows) do if r.text == text then return r end end end

    -- nothing at all yet
    for tab = 1, 4 do H.ok(pcall(paint, d, tab), "an empty record paints, tab " .. tab, select(2, pcall(paint, d, tab))) end
    local rows, boxes, big = paint(d, 1)
    H.ok(d.page.text(1):find("No raid pasted", 1, true) and big.word == "PASTE A RAID" and #boxes == 0, "no raid, no record: it says what to do", big and big.word)
    H.ok(d.page.text(3):find("No boss", 1, true) and d.page.text(2) ~= nil or #d.page.rows(2) > 0, "and on the other tabs")
    H.ok(card(d) == nil, "no card")
    local shows = {}
    local realShow = K.Show
    K.Show = function(page) shows[#shows + 1] = page or "?" end
    big.fn()
    H.eq(shows[1], "roster", "PASTE A RAID opens the terminal's ROSTER page")

    -- your buffs
    H.ok(has(rows, "YOUR BUFFS").right == "3 missing" and has(rows, "Flask or elixir").right == "YOU HAVE NONE" and has(rows, "Food").right == "YOU HAVE NONE" and has(rows, "Weapon").right == "NOTHING ON IT", "nothing carried: said")
    BAG = { { 13510, 2 }, { 13931, 5 }, { 4540, 20 }, { 2589, 20 }, { 9088, 1 } }
    later()
    rows = paint(d, 1)
    H.ok(has(rows, "Flask of the Titans").act.item == 13510 and has(rows, "Flask of the Titans").act.word == "DRINK" and has(rows, "Flask of the Titans").right == "x2", "a flask carried: DRINK, the game's own button")
    H.ok(has(rows, "Nightfin Soup").act.word == "EAT" and not has(rows, "Tough Hunk of Bread") and not has(rows, "Linen Cloth"), "the food that leaves you Well Fed, never bread, never cloth")
    H.ok(has(rows, "Gift of Arthas").act.word == "DRINK" and not has(rows, "Flask or elixir"), "an elixir by the game's own kind")
    AURAS = { { spellId = 17626, name = "Flask of the Titans", expirationTime = H.clock + 3600 }, { spellId = 1249519, name = "Well Fed", expirationTime = H.clock + 600 } }
    WEAPON = 1200000
    later(5)
    rows = paint(d, 1)
    H.ok(has(rows, "Flask or elixir").right == "60 MIN" and has(rows, "Food").right == "10 MIN" and has(rows, "Weapon").right == "20 MIN" and not has(rows, "Nightfin Soup") and has(rows, "YOUR BUFFS").right == "all there",
        "all up: how long", has(rows, "Flask or elixir").right)
    H.ok(not has(rows, "Flask of the Titans"), "a flask you are on is not offered")
    AURAS, WEAPON = {}, nil

    -- a raid pasted
    local start = clock + 5400
    books.roster = '{"date":"22-11-2026","signUps":['
        .. '{"className":"Mage","specName":"Fire","name":"Bloodbow/Kio","position":1},{"className":"Warrior","specName":"Fury","name":"bob09","position":2},{"className":"Priest","specName":"Holy","name":"Cara","position":3},'
        .. '{"className":"Absence","name":"Dax","position":4},{"className":"Tank","specName":"Protection","name":"Figs","position":5},{"className":"Healer","specName":"Restoration","name":"Kumlust","position":6}'
        .. '],"displayTitle":"Molten Core","time":"20:00","startTime":' .. start .. '}'
    later()
    local keys
    rows, boxes, big, keys = paint(d, 1)
    H.ok(boxes[1][2] == "1 / 5" and boxes[2][2] == 3 and boxes[3][2] == 2 and boxes[4][2] == os.date("!%H:%M", start), "in, missing, online, when it starts", boxes[1][2] .. " " .. boxes[2][2])
    H.ok(has(rows, "MISSING").right == "3" and has(rows, "Kio Alpha").act.word == "INVITE" and has(rows, "Kio Alpha").sub == "Mage, signed Fire" and has(rows, "Cara").right == "OFFLINE" and not has(rows, "Cara").act, "missing: INVITE who is online", has(rows, "Kio Alpha").sub)
    H.ok(has(rows, "Figs").right == "NOT IN GUILD" and not has(rows, "Figs").act and has(rows, "Dax Moss").right == "ABSENT", "a stranger is never asked by a guess; who signed off is below")
    H.eq(d.page.kicker(1), "Molten Core", "the raid's name")
    H.eq(big.word, "INVITE THE 2", "the main thing to do")
    has(rows, "Bob").act.fn()
    H.RunTimers()
    H.eq(invited[1], "Bob", "INVITE asks that one")
    H.ok(d.page.say(1):find("invited Bob", 1, true), "and says so", d.page.say(1))
    invited = {}
    later()
    big = select(3, paint(d, 1))
    big.fn()
    H.ok(#invited == 0 and select(3, paint(d, 1)).word == "SURE? INVITE 2", "all of them: asked first", select(3, paint(d, 1)).word)
    select(3, paint(d, 1)).fn()
    H.RunTimers()
    H.ok(#invited == 2, "the second press sends", #invited)
    later(20)
    H.eq(select(3, paint(d, 1)).word, "INVITE THE 2", "and not for ever armed")
    -- through BiS Tools' list, when it is here
    local listed
    _G.BiSToolsAPI = { major = 1, PartyReady = function() return true end, InviteList = function(label, list) listed = list return #list end, InviteOne = function() return 1 end }
    select(3, paint(d, 1)).fn()
    H.ok(listed and #listed == 2, "with BiS Tools: its list, to look over")
    _G.BiSToolsAPI = nil
    -- not yours to invite
    group, lead = { "Kumlust", "Bob" }, false
    later()
    rows, boxes, big, keys = paint(d, 1)
    H.ok(big == nil and has(rows, "Kio Alpha").right == "ONLINE" and not has(rows, "Kio Alpha").act and boxes[1][2] == "2 / 5" and not has(rows, "Bob"), "not the leader: who is online, no button", boxes[1][2])
    H.ok(#keys == 1 and keys[1].word == "ROSTER", "no ready check either")
    lead = true
    later()
    keys = select(4, paint(d, 1))
    H.eq(keys[1].word, "READY CHECK", "the leader's ready check")
    keys[1].fn()
    H.eq(checks, 1, "is the game's own")
    group = { "Kumlust" }

    -- the card: from two hours before
    later()
    local prio, l, bs = card(d)
    H.ok(prio == 4 and l[1] == "RAID NIGHT" and l[3] == "1 of 5 in" and bs[1].word == "INVITE 2" and bs[2].word == "OPEN", "the raid night card", tostring(prio) .. " " .. tostring(l and l[3]))
    H.eq(d.badge(), 2, "and the number on the icon")
    clock = start - 600
    later()
    H.eq((card(d)), 8, "ten minutes before: at the top")
    clock = start - 3 * 3600
    later()
    H.ok(card(d) == nil and card(d, true) == 2 and #paint(d, 1) > 3, "three hours before: not by itself, but the page and a pulled-out card know it")
    clock = start + 5 * 3600
    later()
    H.ok(card(d) == nil and not has(paint(d, 1), "MISSING") and select(4, paint(d, 1))[1].word == "PASTE A RAID", "over: it says nothing more of it")
    clock = start - 5400
    later()

    -- the log-in card
    local w = defs["BiSGuild:login"]
    NS.Login.waiting = {}
    H.ok(card(w) == nil, "nobody came: no card")
    NS.Login.waiting = { { name = "Kio Alpha", key = "kio alpha", signed = "Fire", class = "MAGE", delta = -300 }, { name = "Bob", key = "bob", signed = "Fury", class = "WARRIOR" } }
    prio, l, bs = card(w)
    H.ok(prio == 9 and l[3] == "Kio Alpha" and l[4] == "+1" and l.list[2][2] == "5 min early" and bs[2].word == "ALL 2", "somebody came: who, what they signed, how early", l and l[3])
    local f = CreateFrame("Frame")
    D.frame = f
    f:Show()
    H.ok(A.LoginSeen() == true, "the phone open on home: the pop-up steps aside")
    local pop = NS.Login.frame
    if pop then pop:Hide() end
    local n = D.dirty
    NS.Login.Show()
    H.ok((not pop or not pop:IsShown()) and D.dirty > n, "and the card is painted instead")
    D.page = "BiSGuild:app"
    H.ok(A.LoginSeen() == false, "another page open: the pop-up comes")
    D.page, D.fight = "home", true
    H.ok(A.LoginSeen() == false, "in a fight the phone is dim: the pop-up comes")
    D.fight = nil
    f:Hide()
    NS.Login.Show()
    H.ok(NS.Login.frame:IsShown(), "the phone closed: the pop-up comes")
    invited = {}
    bs[1].fn()
    H.RunTimers()
    H.ok(invited[1] == "Kio Alpha" and #NS.Login.waiting == 1, "INVITE asks and the next one is up")
    select(3, card(w))[2].fn()
    H.ok(card(w) == nil, "NOT NOW: gone")

    -- the record
    local function r(p, flask) return { present = p, pulls = 4, flask = flask or 0, elixir = 0, food = 1, weapon = 0, pots = 2, deaths = 1 } end
    rec.nights["2026-11-15 409"] = { v = 2, i = 409, zone = "Molten Core", kills = 2, by = "x", raiders = { Bob = r(2, 4), ["Kio Alpha"] = r(1), Zed = r(2) },
        bosses = { Lucifron = { pulls = 1, kills = 1, best = 92000, killers = { "Bob", "Kio Alpha" } }, Garr = { pulls = 4, kills = 0, best = 0, killers = {} } } }
    rec.nights["2026-11-18 409"] = { v = 2, i = 409, zone = "Molten Core", kills = 2, by = "x", raiders = { Bob = r(2, 4) }, bosses = { Lucifron = { pulls = 2, kills = 1, best = 80000, killers = { "Bob" } } } }
    rec.gear.Bob = { date = "2026-11-18", gear = { [1] = { 16866, 66, 0 } } }
    books.roster = nil
    later()
    rows, boxes = paint(d, 1)
    H.ok(has(rows, "LAST RAID") and has(rows, "Lucifron").right == "1:20" and boxes[1][2] == 2 and boxes[3][2] == 2, "no raid pasted: the last one, boss by boss", boxes[1] and boxes[1][2])
    has(rows, "Lucifron").act.fn()
    H.ok(d.tab == 3 and has(paint(d, 3), "WHO WAS THERE"), "a press opens its page, on its tab")
    boxes = select(2, paint(d, 3))
    H.ok(boxes[1][2] == 2 and boxes[2][2] == 1 and boxes[3][2] == "1:20" and boxes[4][2] == "67%", "kills, wipes, the best, the rate", boxes[4][2])
    H.eq(has(paint(d, 3), "Bob").right, "2 kills", "who was there")
    has(paint(d, 3), "Bob").act.fn()
    H.ok(d.tab == 2 and has(paint(d, 2), "All raiders"), "and a raider from there")
    rows, boxes, big, keys = paint(d, 2)
    H.ok(boxes[1][2] == "100%" and boxes[2][2] == "2 / 2" and has(rows, "Flask").right == "4 of 4 pulls" and has(rows, "Weapon").ink == "warn" and has(rows, "Now").right == "Orgrimmar", "here, what they used, where they are now", has(rows, "Now").right)
    H.ok(has(rows, "GEAR").right == "seen 2026-11-18", "their gear, when it was seen")
    H.ok(keys[1].word == "INVITE" and keys[2].word == "TERMINAL", "invite, or their wide page")
    keys[2].fn()
    H.eq(shows[#shows], "Bob <raider>", "the terminal's own page")
    local told
    _G.ChatFrame_SendTell = function(n2) told = n2 end
    select(3, paint(d, 2)).fn()
    H.eq(told, "Bob", "WHISPER")
    H.ok(d.page.find(2) == nil, "no search on a page")
    has(paint(d, 2), "All raiders").act.fn()
    rows, boxes = paint(d, 2)
    H.ok(has(rows, "Bob").right == "100%" and has(rows, "Kio Alpha").right == "50%" and has(rows, "Bob").sub == "Warrior, Raider, last 2026-11-18" and boxes[1][2] == 2, "the raiders", has(rows, "Bob").sub)
    H.ok(has(rows, "Zed").done and has(rows, "3 members with no raids yet") and not has(rows, "Cara"), "a pug dim, members without raids folded", #rows)
    has(rows, "3 members with no raids yet").act.fn()
    H.ok(has(paint(d, 2), "Cara") and select(4, paint(d, 2))[2].word == "RAIDERS ONLY", "opened")
    select(4, paint(d, 2))[2].fn()
    local find = d.page.find(2)
    find.set("mage")
    rows = paint(d, 2)
    H.ok(#rows == 1 and rows[1].text == "Kio Alpha", "the search: a class")
    find.set("dax")
    H.ok(has(paint(d, 2), "Dax Moss"), "a member without raids is found too")
    find.enter()
    H.ok(has(paint(d, 2), "All raiders"), "Enter opens the first")
    H.ok(select(2, paint(d, 2))[1][2] == "0%", "with nothing on record: zeros, no error")
    has(paint(d, 2), "All raiders").act.fn()
    find.set("nosuch")
    H.ok(d.page.text(2) == "Nobody by that name.", "nobody by that name")
    find.set("")
    rows = paint(d, 3)
    H.ok(rows[1].text == "Lucifron" and rows[1].sub == "2 kills, 1 wipe" and has(rows, "Garr").right == "ALIVE", "BOSSES", rows[1].sub)
    -- gone from the record while its page is open
    has(rows, "Garr").act.fn()
    rec.nights["2026-11-15 409"] = nil
    later()
    H.ok(has(paint(d, 3), "Lucifron") and not has(paint(d, 3), "All bosses"), "a boss gone from the record: back to the list")

    -- SETTINGS: the options window's own switches
    rows = paint(d, 4)
    local sw = has(rows, "Login pop-up")
    H.ok(sw and (sw.right == "ON") == NS.Login.On(), "the login pop-up's switch")
    local was = NS.Login.On()
    sw.act.fn()
    H.ok(NS.Login.On() == not was and has(paint(d, 4), "Login pop-up").right == (was and "OFF" or "ON"), "flips the same setting")
    has(paint(d, 4), "Login pop-up").act.fn()
    for _, t in ipairs({ "Raid pasted", "The terminal", "Where everyone is", "Recruits" }) do has(rows, t).act.fn() end
    H.ok(shows[#shows] == "recruits" and shows[#shows - 1] == "where", "the doors to the big windows")
    local pasted
    local realPaste = NS.U.ShowPaste
    NS.U.ShowPaste = function() pasted = true end
    has(rows, "A combat log").act.fn()
    H.ok(pasted, "and to the log")
    NS.U.ShowPaste = realPaste

    -- hidden answers: no error, nothing of them said
    local SECRET = setmetatable({}, { __eq = function() error("secret") end, __lt = function() error("secret") end, __concat = function() error("secret") end, __index = function() error("secret") end })
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    AURAS = { { spellId = SECRET, name = SECRET, expirationTime = SECRET } }
    _G.C_Container.GetContainerItemInfo = function() return { itemID = SECRET, stackCount = SECRET } end
    later()
    H.ok(pcall(paint, d, 1), "buffs and bags hidden: no error", select(2, pcall(paint, d, 1)))
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("no") end
    _G.C_Container.GetContainerItemInfo = function() error("no") end
    _G.GetWeaponEnchantInfo = nil
    later()
    H.ok(pcall(paint, d, 1), "the client refuses: no error")

    -- LEAN: a paint of a long list asks the game for it once in A.LOOK seconds
    local asked = 0
    local real = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(i) asked = asked + 1 return real(i) end
    K._guildDirty = true
    later()
    for _ = 1, 4 do paint(d, 2) end
    H.ok(asked <= #ROSTER * 2, "four paints of the raiders: the guild read once", asked)
    H.ok(A.events ~= nil, "it listens to the group, the guild, the bags")
    n = D.dirty
    A.events._scripts.OnEvent(A.events, "GROUP_ROSTER_UPDATE")
    H.eq(D.dirty, n + 1, "and only flags the deck")

    K.Show = realShow
    if NS.Login.frame then NS.Login.frame:Hide() end
    NS.Login.waiting = {}
    books.roster, _G.BiSGuildDB.logins, books.record = rosterWas, loginsWas, recWas
    for g, v in pairs(keep) do _G[g] = v end
    for _, g in ipairs({ "BiSTheme", "GetNumGuildMembers", "GetGuildRosterInfo", "C_PartyInfo", "C_UnitAuras", "C_Container", "C_Item", "C_Spell", "GetWeaponEnchantInfo", "GetServerTime", "ChatFrame_SendTell", "IsInGroup",
        "UnitName", "GetNumGroupMembers", "IsInRaid", "UnitIsGroupLeader", "date", "issecretvalue", "BiSToolsAPI", "LOCALIZED_CLASS_NAMES_MALE", "C_Timer" }) do if keep[g] == nil then _G[g] = nil end end
    I.out, I.held, I.queue, I._armed, I.armed = {}, nil, {}, false, nil
    K._guildDirty = true
    A.Drop()
end
