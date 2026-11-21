--[[
  BiSGuild :: Core/Init.lua - made by _bisdev/new-addon.sh (the house skeleton).

  What every BiS addon starts with, already wired and tested:
    * ns.T      the palette, resolved PER CALL (BiSTheme loads after us, alphabetically)
    * ns.VERSION the TOC's ## Version and nothing else's
    * ns.Print  one chat line with the addon's name in the accent colour
    * BiSGuildDB SavedVariables with defaults filled on ADDON_LOADED
    * the shared BiS channel (LibBiSComm): registered, booted, its off switch remembered
    * /bisg - says hello: version, comm on/off, peers. Replace it with the real addon.
]]
local ADDON, ns = ...

local HEX = {
  ink = "ece8f6", muted = "968ead", accent = "b980ff", good = "4fd0cf", warn = "f08cb0", gold = "e5c04a",
  edge = "3a3260",   -- BiSTheme/Options.lua's window edge: fixed, never the borrowed accent
}
local T = {}
ns.T = T
T.hex = HEX
function T.rgb(name)
  local real = _G.BiSTheme
  if real and real.hex and real.hex[name] and real.rgb then return real.rgb(name) end
  local hex = HEX[name] or HEX.ink
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
function T.text(name, s)
  local real = _G.BiSTheme
  if real and real.hex and real.hex[name] and real.text then return real.text(name, s) end
  return "|cff" .. (HEX[name] or HEX.ink) .. tostring(s) .. "|r"
end

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "dev"

function ns.Print(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage(T.text("accent", ADDON) .. " " .. msg)
end

ns.DEFAULTS = { comm = true }
local function db()
  if type(BiSGuildDB) ~= "table" then
    BiSGuildDB = {}
    ns.madeHere = BiSGuildDB          -- ours, not the client's: a table made before the saved variables came in
  end
  for k, v in pairs(ns.DEFAULTS) do
    if BiSGuildDB[k] == nil then BiSGuildDB[k] = v end
  end
  return BiSGuildDB
end
ns.DB = db

--- FOREVER 1.0: A NEW INSTALL STARTS QUIET (Arn, 7 Nov 2026: "every new user that we get will have every module
--- turned off ... anything that would make a new user go like okay, this add-on is just making random noises and
--- putting random stuff on my screen" - "all the main functionalities start on"). The core - the terminal, the
--- record, its sharing - has no switch. The extras below start OFF for a new install.
---
--- AND AN EXISTING ONE KEEPS WHAT IT HAD ("everybody that already has the addons installed, I don't wanna change
--- default settings that they have on"). logins and mapDots were read `~= false`, so nil meant ON; the newer-version
--- note had no switch and always spoke. On the first 1.0 load of an existing save each is written as the value it was
--- showing, then the stamp. Either way, once: `forever10` is never cleared.
ns.QUIET = { logins = false, mapDots = false, versionNote = false }
function ns.Forever10(d, isNew)
  if type(d) ~= "table" or d.forever10 then return false end
  if isNew then
    for k, v in pairs(ns.QUIET) do d[k] = v end
  else
    d.logins = d.logins ~= false
    d.mapDots = d.mapDots ~= false
    if d.versionNote == nil then d.versionNote = true end
  end
  d.forever10 = true
  return true
end

--- The saved variables are in (ADDON_LOADED): new or existing is decided HERE, before the defaults are merged -
--- no table, or only the one our own db() made, is a new install. (BiS Guild keeps no per-character mirror, so a
--- client that once handed back no saved variables would read as new and start quiet - the safer side.)
function ns.Settle()
  local isNew = type(BiSGuildDB) ~= "table" or rawequal(BiSGuildDB, ns.madeHere)
  local d = db()
  ns.Forever10(d, isNew)
  return d, isNew
end

--- EACH GUILD ITS OWN BOOKS (Arn, 16 Oct: "some people have alts in other guilds - when I opened it on
--- my hunter it still had the pasted JSON"). BiSGuildDB is the account's, every character shares it,
--- so the pasted roster, the raid record and the punctuality are filed per guild and a character sees
--- and SHARES only its own guild's. (A hunter that is an officer in another guild would otherwise have
--- announced the main's raid nights to that guild.) Settings - logins, map dots, the logs folder - stay
--- the account's.
---
--- THE KEY IS THE GUILD NAME ALONE (21 Nov 2026). It was "<realm>|<guild>" (guildless "-|<realm>|<name>")
--- until Forever 1.60.1 Live Update 2: "APIs that return realm names or IDs now instead return an empty
--- string or zero" - GetRealmName answers "", so every book came up as "|<guild>", empty, beside the real
--- one. No realm can be read any more, so none is used: "<guild>", and guildless "-|<whole name>" (Forever's
--- "Name Surname" - UnitName is the first name only). The old books are folded in once - ns.Fold below.
---
--- The client names your guild a moment after login. Until it has, ns.Books() is an unsaved, empty
--- stand-in: an empty terminal for a second, never another guild's books.
local function WholeName()
    local n
    if GetUnitName then
        local ok, v = pcall(GetUnitName, "player", false)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    if not n and UnitName then
        local ok, v = pcall(UnitName, "player")
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    return n and (n:match("^([^%-]+)") or n) or nil
end
ns.WholeName = WholeName

function ns.GuildKey()
    if not (IsInGuild and IsInGuild()) then
        local me = WholeName()
        return me and ("-|" .. me) or nil
    end
    local ok, name = pcall(GetGuildInfo, "player")
    if not ok or type(name) ~= "string" or name == "" then return nil end
    return name
end

--- Is `old` a book key from before 21 Nov that belongs to `key`? Old guild books were "<realm>|<guild>"
--- (the realm "" since the change), old guildless ones "-|<realm>|<first name>". A guild or a whole name
--- never holds a "|", so the shapes cannot be mistaken for each other or for a new key.
function ns.OldKeyOf(old, key)
    if type(old) ~= "string" or type(key) ~= "string" or old == key then return false end
    local who = key:match("^%-|(.+)$")
    if who then
        local name = old:match("^%-|[^|]*|(.+)$")
        return name ~= nil and (name == who or name == (who:match("^(%S+)") or who))
    end
    if old:sub(1, 2) == "-|" then return false end                    -- somebody's guildless book
    return old:match("^[^|]*|(.+)$") == key
end

--- The stray book the bug made ("|<guild>", "-||<name>"): the newest of the old ones.
local function stray(k) return k:sub(1, 1) == "|" or k:sub(1, 3) == "-||" end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function keys(t, sorted)
    local out = {}
    for k in pairs(type(t) == "table" and t or {}) do out[#out + 1] = k end
    if sorted then table.sort(out, function(a, b) return tostring(a) < tostring(b) end) end
    return out
end

--- HOW ONE OLD BOOK FOLDS INTO THE LIVE ONE, field by field. What is live already wins a tie; the old books
--- come stray first, then by realm name, so "first one in" is the stray, made after the change.
local FOLD = {}
--- The pasted roster is one text: the live one stays; with none, the first old one that has one.
function FOLD.roster(g, v)
    if type(v) == "string" and v ~= "" and (type(g.roster) ~= "string" or g.roster == "") then g.roster = v end
end
--- Punctuality, [name][raid start] = verdict: one verdict per raid start, the first stands (Logins.lua
--- L.Mark), the newest L.KEEP starts kept per person.
function FOLD.punctual(g, v)
    if type(v) ~= "table" then return end
    if type(g.punctual) ~= "table" then g.punctual = {} end
    local keepN = (ns.Login and ns.Login.KEEP) or 8
    for name, starts in pairs(v) do
        if type(starts) == "table" then
            local p = g.punctual[name]
            if type(p) ~= "table" then p = {} g.punctual[name] = p end
            for start, e in pairs(starts) do
                if p[start] == nil then p[start] = e end
            end
            local list = keys(p)
            table.sort(list, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
            for i = 1, #list - keepN do p[list[i]] = nil end
        end
    end
end
--- Guildmates' versions, [name] = { v, t }: the one heard last wins.
function FOLD.copies(g, v)
    if type(v) ~= "table" then return end
    if type(g.copies) ~= "table" then g.copies = {} end
    for name, c in pairs(v) do
        local have = g.copies[name]
        if type(c) == "table" and (type(have) ~= "table" or (tonumber(c.t) or 0) > (tonumber(have.t) or 0)) then
            g.copies[name] = c
        end
    end
end
--- The loot ledger's lines: every line once (the ledger itself sorts duplicates and forks out at load,
--- Loot.lua LT.Ledger); meta per event: the most witnesses, direct if either said so; bad lines kept, the
--- newest LT.BAD_KEEP; BiS Loot's import stamp kept if either has it.
function FOLD.loot(g, v)
    if type(v) ~= "table" then return end
    if type(g.loot) ~= "table" then g.loot = {} end
    local L = g.loot
    if type(L.lines) ~= "table" then L.lines = {} end
    if type(L.meta) ~= "table" then L.meta = {} end
    if type(L.bad) ~= "table" then L.bad = {} end
    local held = {}
    for _, line in ipairs(L.lines) do held[line] = true end
    for _, line in ipairs(type(v.lines) == "table" and v.lines or {}) do
        if not held[line] then held[line] = true L.lines[#L.lines + 1] = line end
    end
    for id, m in pairs(type(v.meta) == "table" and v.meta or {}) do
        if type(m) == "table" then
            local have = L.meta[id]
            if type(have) ~= "table" then
                L.meta[id] = m
            else
                have.w = math.max(tonumber(have.w) or 0, tonumber(m.w) or 0)
                have.direct = (have.direct == true or m.direct == true) or nil
            end
        end
    end
    for _, line in ipairs(type(v.bad) == "table" and v.bad or {}) do L.bad[#L.bad + 1] = line end
    local keepN = (ns.Loot and ns.Loot.BAD_KEEP) or 50
    while #L.bad > keepN do table.remove(L.bad, 1) end
    if v.importedFromBiSLoot then L.importedFromBiSLoot = true end
    for k, x in pairs(v) do
        if L[k] == nil then L[k] = x end
    end
end
--- The raid record, by Store.lua's own rules (S.Record() is this live book - its key is folded already):
--- gear, the newer set wins (S.PutGear); an archive and a restore of one key, the later decision wins; then
--- every night through S.Put - the same raid seen twice merges kill by kill, a copy of an archived raid
--- stays out, a whole-date night never sits beside raids of its date.
function FOLD.record(g, r)
    if type(r) ~= "table" then return end
    local S = ns.S
    if not S then
        if g.record == nil then g.record = r end
        return
    end
    local rec = S.Record()
    for _, name in ipairs(keys(r.gear, true)) do
        local have = r.gear[name]
        if type(have) == "table" then S.PutGear(name, have.date, have.gear) end
    end
    local back = {}                              -- archived raids a later restore brings back
    for _, k in ipairs(keys(r.restored, true)) do
        local t = tonumber(r.restored[k])
        if t and t > (tonumber(rec.restored[k]) or 0) then
            rec.restored[k] = t
            local a = rec.archived[k]
            if type(a) == "table" and t > (tonumber(a.t) or 0) then
                rec.archived[k] = nil
                back[#back + 1] = { k, a.night }
            end
        end
    end
    for _, k in ipairs(keys(r.archived, true)) do
        local a = r.archived[k]
        if type(a) == "table" then
            local t, have = tonumber(a.t) or 0, rec.archived[k]
            if (tonumber(rec.restored[k]) or 0) > t then
                back[#back + 1] = { k, a.night }
            elseif type(have) ~= "table" or t > (tonumber(have.t) or 0) then
                rec.archived[k] = a
                rec.restored[k] = nil
                for _, k2 in ipairs(keys(rec.nights)) do
                    if k2 == k or S.SameRaid(rec.nights[k2], a.night) then rec.nights[k2] = nil end
                end
            end
        end
    end
    for _, k in ipairs(keys(r.nights, true)) do
        local n = r.nights[k]
        if type(n) == "table" then S.Put(k, n, n.by) end
    end
    for _, b in ipairs(back) do
        if type(b[2]) == "table" then S.Put(b[1], b[2], b[2].by) end
    end
    for k, x in pairs(r) do
        if rec[k] == nil then rec[k] = x end
    end
end

--- Fold one old book (a copy - the original is kept aside) into the live one. A field with no rule is taken
--- when the live book has none.
function ns.FoldBook(g, b)
    for _, field in ipairs(keys(b, true)) do
        if FOLD[field] then FOLD[field](g, b[field])
        elseif g[field] == nil then g[field] = b[field] end
    end
end

--- THE FOLD, once per key per session (21 Nov 2026): every old book of this guild - any realm, and the stray
--- "|<guild>" - is folded into "<guild>", then moved to BiSGuildDB.oldRealmBooks under its old key (never
--- deleted; a key already there gets " (2)"). Idempotent: a folded book is no longer in `guilds`, so the next
--- login finds nothing to fold. Two guilds of one name on two realms become one book - the client cannot tell
--- them apart any more. Answers how many books were folded.
ns.folded = {}
function ns.Fold(d, key)
    if not key or ns.folded[key] then return 0 end
    ns.folded[key] = true
    if type(d) ~= "table" or type(d.guilds) ~= "table" then return 0 end
    local olds = {}
    for k in pairs(d.guilds) do
        if ns.OldKeyOf(k, key) then olds[#olds + 1] = k end
    end
    if #olds == 0 then return 0 end
    table.sort(olds, function(a, b)
        local sa, sb = stray(a), stray(b)
        if sa ~= sb then return sa end
        return a < b
    end)
    local g = d.guilds[key]
    if type(g) ~= "table" then g = {} d.guilds[key] = g end
    if type(d.oldRealmBooks) ~= "table" then d.oldRealmBooks = {} end
    for _, k in ipairs(olds) do
        local book = d.guilds[k]
        d.guilds[k] = nil
        if type(book) == "table" then ns.FoldBook(g, copy(book)) end
        local aside, n = k, 1
        while d.oldRealmBooks[aside] ~= nil do
            n = n + 1
            aside = k .. " (" .. n .. ")"
        end
        d.oldRealmBooks[aside] = book
    end
    return #olds
end

--- At login and when the guild is named: fold now, so the books are live before anything asks for them.
function ns.FoldNow()
    local key = ns.GuildKey()
    if key and not ns.folded[key] then ns.Books() end
end

ns.unfiled = {}
function ns.Books()
    local key = ns.GuildKey()
    if not key then return ns.unfiled end
    local d = db()
    if type(d.guilds) ~= "table" then d.guilds = {} end
    ns.Fold(d, key)
    local g = d.guilds[key]
    if not g then
        g = {}
        d.guilds[key] = g
        -- the books kept account-wide before 16 Oct go to the first guild seen after the change
        -- (Arn's main, logged first) - once, and never again
        if not d.filedTo and (d.record or d.roster or d.punctual) then
            g.record, g.roster, g.punctual = d.record, d.roster, d.punctual
            d.record, d.roster, d.punctual = nil, nil, nil
            d.filedTo = key
        end
    end
    return g
end

--- ESC FOR A WINDOW, SAFE IN COMBAT (16 Oct 2026). Arn opened the terminal mid-fight and got
--- ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput is protected in combat. So:
---   * in combat it is never called - the keyboard is switched on when combat ends instead;
---   * ESC still runs `onEscape` in combat; the game may open its menu too (a key cannot be held back
---     in combat), which is harmless;
---   * the "swallow this ESC" is undone a moment later, so the NEXT key never vanishes and a fight
---     starting right after can never leave every key swallowed.
local function locked() return InCombatLockdown and InCombatLockdown() end
function ns.EscKeys(f, onEscape)
    local function arm()
        if locked() then return false end
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        return true
    end
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then
            if not locked() then self:SetPropagateKeyboardInput(true) end
            return
        end
        if not locked() then
            self:SetPropagateKeyboardInput(false)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if not locked() then self:SetPropagateKeyboardInput(true) end end)
            end
        end
        onEscape()
    end)
    if not arm() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self) if arm() then self:UnregisterAllEvents() end end)
    end
end

-- the shared BiS channel: no setting of this addon may gate it; only /biscomm off does,
-- and that choice survives a logout here
ns.Comm = {}
function ns.Comm.Boot()
  local lib = _G.LibBiSComm
  if not lib then return end
  lib:RegisterAddon(ADDON, ns.VERSION)
  if db().comm == false then lib:SetEnabled(false) end
  if db().commShare == false and lib.SetSharing then lib:SetSharing(false) end   -- /biscomm share off (minor 12)
  lib:Boot()
end
function ns.Comm.Save()
  local lib = _G.LibBiSComm
  if lib then db().comm = lib:Enabled() end
  if lib and lib.Sharing then db().commShare = lib:Sharing() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    ns.Settle()
    ns.loaded = true                 -- the saved variables are in: the APIs may answer (API.lua, Loot.lua)
    ns.Comm.Boot()
    -- THE ADDON WATCHES NOTHING NOW (5 Oct 2026). Arn: "we can get rid of the attendence and
    -- consume check lets do logs for that". It used to count boss kills and who was standing
    -- there, which was a SECOND source of truth against the combat log - and when two sources
    -- disagree, the one people believe is the one on the website. One source, or arguments.
    --
    -- The nights it had already written down are dropped rather than left to rot in the saved
    -- variables, where they would outlive every piece of code that could read them.
    local d = db()
    if d.nights ~= nil then d.nights = nil end
    if d.taught ~= nil then d.taught = nil end       -- and the consumables list, gone the same way
    -- THE RECORD (16 Oct): the report file is folded into the guild's record, which every member
    -- keeps and Core/Share.lua shares - so the numbers survive a deploy and a missed night
    -- ...into THIS character's guild's books, once the client has named the guild and its raiders
    -- are in it (16 Oct: an alt in another guild must not take in the main's raids) - Store.lua
    if ns.S then ns.S.ImportWhenReady() end
    if ns.X then ns.X.Boot() end
  elseif event == "PLAYER_LOGIN" then
    ns.FoldNow()                     -- the old realm books, folded before anything asks (21 Nov; a guildless
                                     -- character may never hear PLAYER_GUILD_UPDATE)
  elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    ns.FoldNow()
    if ns.S then ns.S.ImportWhenReady() end
  elseif event == "PLAYER_LOGOUT" then
    ns.Comm.Save()
  end
end)

SLASH_BISGUILD1 = "/bisg"
SlashCmdList.BISGUILD = function(input)
  -- the command is lowercased, the REST is not: a spell id does not care, but this is the shape
  -- that stored "/memories now Killed Baron Silverlaine" as lower case in BiSMemories (0.5.3)
  local raw = tostring(input or "")
  local cmd, rest = raw:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if ns.Say then return ns.Say(cmd, rest) end
  local lib = _G.LibBiSComm
  ns.Print("hello - version %s, BiS comm %s, %d peer(s)", ns.VERSION,
    (lib and lib:Enabled()) and T.text("good", "on") or T.text("warn", "off"), lib and lib:Count() or 0)
end
