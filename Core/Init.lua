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
--- so the pasted roster, the raid record and the punctuality are filed per guild - realm and guild
--- name - and a character sees and SHARES only its own guild's. (A hunter that is an officer in
--- another guild would otherwise have announced the main's raid nights to that guild.) Settings -
--- logins, map dots, the logs folder - stay the account's.
---
--- The client names your guild a moment after login. Until it has, ns.Books() is an unsaved, empty
--- stand-in: an empty terminal for a second, never another guild's books.
function ns.GuildKey()
    if not (IsInGuild and IsInGuild()) then
        local me = UnitName and UnitName("player")
        return me and ("-|" .. tostring(GetRealmName and GetRealmName() or "") .. "|" .. me) or nil
    end
    local ok, name = pcall(GetGuildInfo, "player")
    if not ok or type(name) ~= "string" or name == "" then return nil end
    return tostring(GetRealmName and GetRealmName() or "") .. "|" .. name
end

ns.unfiled = {}
function ns.Books()
    local key = ns.GuildKey()
    if not key then return ns.unfiled end
    local d = db()
    if type(d.guilds) ~= "table" then d.guilds = {} end
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
  elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
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
