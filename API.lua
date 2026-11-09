--------------------------------------------------------------------------------
-- BiSGuildAPI: for other addons (16 Oct 2026) - the family's rules are _bisdev/docs/playbook.md 5a.
--
-- Arn: "lets do api calls for the other addons, and going forward our stuff will have open api to
-- call". BiS Guild owns the guild's raid record - attendance, consumes, deaths, gear seen, boss kills,
-- punctuality - kept by every member and shared by the officers. Other addons ask HERE, never
-- BiSGuildDB (which is filed per guild and changes shape) nor ns.
--
-- BiSGuildAPI.version goes up when something is added; nothing is changed or taken away without a new
-- BiSGuildAPI.major. Read-only, plus opening the terminal. Every answer is a COPY. Answers are about
-- the guild of the character playing (each guild has its own books). Safe at any time: before the
-- addon has loaded, nil, "not ready".
--
--   BiSGuildAPI.Ready()            -> true | nil, "not ready"                                  (v1)
--   BiSGuildAPI.Nights()           -> { key, ... } oldest first. A key is a night: a date from
--                                      before 17 Oct 2026 ("YYYY-MM-DD", every raid of it added) or,
--                                      since v2, ONE RAID ("YYYY-MM-DD <instance id>", "-2" after
--                                      it for a second raid of that instance that date). Every key
--                                      starts with its date, so they still sort oldest first.     (v1)
--   BiSGuildAPI.Night(key)         -> { kills, by, raiders = { [name] = { present, pulls, flask,
--                                      elixir, food, weapon, pots, deaths } }, bosses = { [boss] =
--                                      { pulls, kills, best (ms), killers = { names } } } }     (v1)
--                                      a raid also: v = 2, i (instance id), zone (its name),
--                                      start (UTC seconds), pulls = { { t, e, b, k, ms, r =
--                                      { [name] = flags }, d, p } } - see BiSGuild/dev/NIGHTS.md (v2)
--   BiSGuildAPI.Label(key)         -> "2026-10-16 Molten Core" - a key as people read it       (v2)
--   BiSGuildAPI.Raiders()          -> { { name, attend (0-100), nights, last (date), deaths,
--                                      issues (count), geared (bool) }, ... } by name          (v1)
--   BiSGuildAPI.Raider(name)       -> { name, attended = { dates }, attend (0-100), nights,
--                                      last = { date, pulls, flask, elixir, food, weapon, pots,
--                                      deaths } or nil, deaths, pots, gear = { { id, ilvl, enchant,
--                                      temp }, 19 } or nil, gearDate, issues = { { slot, item,
--                                      what } }, punctual = { text, raids, late, noshow, avgLate }
--                                      or nil }  | nil, "no such raider"                       (v1)
--   BiSGuildAPI.Bosses()           -> { [boss] = { kills, wipes, best (ms), first (date) } }   (v1)
--   BiSGuildAPI.Boss(name)         -> { kills, wipes, best, first, nights = { dates },
--                                      killers = { [name] = kills } } | nil, "no such boss"    (v1)
--   BiSGuildAPI.RaidNight()        -> the pasted Raid-Helper event: { title, start (server
--                                      seconds), time, date } | nil, "no raid pasted"          (v1)
--   BiSGuildAPI.Open(what)         -> opens the terminal: "raiders" | "bosses" | "where" |
--                                      "roster" | a raider's or boss's name                    (v1)
--   BiSGuildAPI.MapDots()          -> true when our guildmates' dots are on the world map, else
--                                      false and why: "off" | "beside OpenMap" (we step aside for
--                                      its own guild layer unless the player asked for both)    (v3)
--
-- Callbacks:
--   BiSGuildAPI.RegisterCallback(owner, "BiSGuild_Night", fn)   fn(date) - a raid night entered the
--                                  record, imported from a log or shared by an officer        (v1)
--   BiSGuildAPI.UnregisterCallback(owner, event)                                              (v1)
--------------------------------------------------------------------------------
local _, ns = ...

local API = { major = 1, version = 3 }
BiSGuildAPI = API

local function deep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end

function API.Ready()
    if not (ns.S and ns.K and _G.BiSGuildDB) then return nil, "not ready" end
    return true
end

local function guard(fn)
    return function(...)
        local ok, why = API.Ready()
        if not ok then return nil, why end
        local good, a, b = pcall(fn, ...)
        if not good then return nil, "error" end
        return a, b
    end
end

--- (v3) the courtesy check, the other way round: may another map addon draw the guild without doubling ours?
function API.MapDots()
    local P = ns.Pins
    if not (P and ns.DB) then return nil, "not ready" end
    local ok, on = pcall(P.On)
    if ok and on then return true end
    local okA, aside = pcall(P.Aside)
    return false, (okA and aside) and "beside OpenMap" or "off"
end

API.Nights = guard(function() return deep(ns.S.Dates()) end)

API.Label = guard(function(key) return ns.S.Label(key) end)

API.Night = guard(function(date)
    local n = ns.S.Record().nights[date]
    if not n then return nil, "no such night" end
    return deep(n)
end)

API.Raiders = guard(function()
    local out = {}
    local nights = #ns.S.Dates()
    for name, c in pairs(ns.S.Cards()) do
        out[#out + 1] = { name = name, attend = nights > 0 and math.floor(100 * #c.attended / nights + 0.5) or 0,
                          nights = #c.attended, last = c.last and c.last.date or nil, deaths = c.deaths or 0,
                          issues = #(c.issues or {}), geared = c.gear ~= nil }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)

API.Raider = guard(function(name)
    if type(name) ~= "string" or name == "" then return nil, "no name" end
    local cards = ns.S.Cards()
    local card, key = cards[name], name
    if not card then
        -- any case, a whole Forever name for a first-name card, and the other way round
        local want = name:lower()
        local first = (name:match("^([^%-%s]+)") or name):lower()
        for n, c in pairs(cards) do
            local nl = n:lower()
            if nl == want or nl == first then card, key = c, n break end
        end
    end
    if not card then return nil, "no such raider" end
    local nights = #ns.S.Dates()
    local out = deep(card)
    out.name = key
    out.nights = #card.attended
    out.attend = nights > 0 and math.floor(100 * #card.attended / nights + 0.5) or 0
    if ns.Login and ns.Login.Habit then
        local h = ns.Login.Habit(key)
        if h then
            out.punctual = { text = (ns.Login.HabitText(key)), raids = h.raids, late = h.late, noshow = h.noshow,
                             avgLate = h.avgLate }
        end
    end
    return out
end)

API.Bosses = guard(function()
    local out = {}
    for boss, p in pairs(ns.S.Bosses()) do
        out[boss] = { kills = p.kills, wipes = p.wipes, best = p.best, first = p.first }
    end
    return out
end)

API.Boss = guard(function(name)
    if type(name) ~= "string" or name == "" then return nil, "no name" end
    local want = name:lower()
    for boss, p in pairs(ns.S.Bosses()) do
        if boss:lower() == want then
            local out = deep(p)
            out.name = boss
            return out
        end
    end
    return nil, "no such boss"
end)

API.RaidNight = guard(function()
    local text = ns.Books().roster
    local e = ns.Inv and type(text) == "string" and text ~= "" and ns.Inv.Event(text)
    if not (e and e.title) then return nil, "no raid pasted" end
    return { title = e.title, start = e.start, time = e.time, date = e.date }
end)

API.Open = guard(function(what)
    if not (ns.K and ns.K.Show) then return nil, "no terminal" end
    ns.K.Show(type(what) == "string" and what ~= "" and what or nil)
    return true
end)

--------------------------------------------------------------------------------
-- callbacks
--------------------------------------------------------------------------------

local owners = {}             -- event -> { owner -> fn }

function API.RegisterCallback(owner, event, fn)
    if owner == nil or type(event) ~= "string" or type(fn) ~= "function" then
        error("BiSGuildAPI.RegisterCallback(owner, event, fn)", 2)
    end
    owners[event] = owners[event] or {}
    owners[event][owner] = fn
end

function API.UnregisterCallback(owner, event)
    if owners[event] then owners[event][owner] = nil end
end

local function Fire(event, ...)
    for _, fn in pairs(owners[event] or {}) do pcall(fn, ...) end
end

-- a night that changed the record is news: the store's Put is the one door every night comes through
if ns.S and ns.S.Put then
    local put = ns.S.Put
    ns.S.Put = function(date, night, by)
        local changed = put(date, night, by)
        if changed then Fire("BiSGuild_Night", date) end
        return changed
    end
end
