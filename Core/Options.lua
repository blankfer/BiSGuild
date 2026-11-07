--[[
  BiSGuild :: Core/Options.lua - the options window and the BiS> page (Forever 1.0, 7 Nov 2026).

  Until 1.0 every setting was a slash command (`/bisg logins on|off`, `/bisg dots on|off`). Arn, 7 Nov: "when they
  open the options, they go to add-ons ... they'll just see BiS> ... click into that add-on", and every extra a new
  install starts with OFF must have a switch a player can find. So:

    * a small options window, BiSTheme's shared kit (Libs\BiSTheme\Options.lua, canon bytes) - the login pop-up,
      the world-map dots, the newer-version note, the shared channel and sharing your spot;
    * held inside "BiS> Guild" in the game's own options (Esc > Options > AddOns > BiS>), registered at PLAYER_LOGIN;
    * every switch calls the SAME function its slash command does (O.Set*), so the two can never disagree.

  NO MINIMAP BUTTON. BiS Guild never had one; the doors are `/bisg` (the terminal), `/bisg options` and the BiS> page.
]]
local ADDON, ns = ...

local O = {}
ns.Opt = O

O.NAME = "BiSGuildOptions"

local function Lib() return _G.LibBiSComm end

--------------------------------------------------------------------
-- the setters: one road for the slash command and the switch
--------------------------------------------------------------------

--- "X just logged in - invite?" and the punctuality kept at raid time (Core/Logins.lua) - one switch, as it was.
function O.SetLogins(on)
    ns.DB().logins = on and true or false
    local L = ns.Login
    if L and not on then
        L.waiting = {}                       -- whoever was waiting goes with the window
        if L.Paint then L.Paint() end
    end
    return ns.DB().logins
end

--- Guildmates' dots on the world map (Core/Pins.lua). Answers how many dots there are now.
function O.SetDots(on)
    ns.DB().mapDots = on and true or false
    return ns.Pins and ns.Pins.Update() or 0
end

--- "N guildmates run a newer BiS Guild" in chat (Core/Copies.lua).
function O.SetNote(on)
    ns.DB().versionNote = on and true or false
    if on and ns.Copy and ns.Copy.Judge then ns.Copy.Judge() end
    return ns.DB().versionNote
end

--- The shared BiS channel, as `/biscomm on|off` does it - and remembered now, not only at logout.
function O.SetComm(on)
    local lib = Lib()
    if not lib then return nil end
    lib:SetEnabled(on and true or false)
    if on and lib.Hi then pcall(lib.Hi, lib) end
    ns.DB().comm = lib:Enabled()
    return ns.DB().comm
end

--- Your spot on the guild's maps, as `/biscomm share on|off` does it.
function O.SetShare(on)
    local lib = Lib()
    if not (lib and lib.SetSharing) then return nil end
    lib:SetSharing(on and true or false)
    ns.DB().commShare = lib:Sharing()
    return ns.DB().commShare
end

local function CommOn() local lib = Lib() return lib and lib:Enabled() or false end
local function ShareOn() local lib = Lib() return lib and lib.Sharing and lib:Sharing() or false end

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

local function toggle(key, label, help, get, set)
    return { key = key, kind = "toggle", label = label, help = help,
             get = function() return get() and true or false end, set = function(_, v) set(v) end }
end

--- The rows. A function, so `get` is asked every time the window paints.
function O.Sections()
    local secs = {
        { title = "on your screen", options = {
            toggle("logins", "login pop-up", "Raid night, with a roster pasted and you leading: a small window when "
                .. "someone on it logs in, to invite them. Off: no window, and nobody's lateness is written down.",
                function() return ns.Login and ns.Login.On() end, O.SetLogins),
            toggle("mapDots", "world-map dots", "Guildmates who run a BiS addon, as dots on the game's world map "
                .. "(not your own group - the game draws them).",
                function() return ns.Pins and ns.Pins.On() end, O.SetDots),
            toggle("versionNote", "newer-version note", "One line in chat when a guildmate runs a newer BiS Guild. "
                .. "/biscomm ver lists every version either way.",
                function() return ns.Copy and ns.Copy.NoteOn() end, O.SetNote),
        } },
        { title = "the shared channel", options = {
            toggle("comm", "BiS channel", "The hidden addon channel every BiS addon shares - how the raid record "
                .. "reaches your guild. Off: you hear nothing and send nothing (/biscomm off).",
                CommOn, O.SetComm),
        } },
    }
    local lib = Lib()
    if lib and lib.SetSharing then
        table.insert(secs[2].options, toggle("commShare", "share my spot", "Where you are, for guildmates' maps "
            .. "and WHERE page - while you move, outside instances (/biscomm share off).", ShareOn, O.SetShare))
    end
    table.insert(secs[2].options, { key = "terminal", kind = "button", label = "the terminal", button = "open",
        help = "The raider terminal: raiders, bosses, where, roster (/bisg).",
        action = function() if ns.K and ns.K.Show then ns.K.Show() end end })
    return secs
end

--- Every row, flat - what a suite reads back.
function O.Rows()
    local out = {}
    for _, sec in ipairs(O.Sections()) do
        for _, opt in ipairs(sec.options) do out[#out + 1] = opt end
    end
    return out
end

function O.Build()
    if O.frame then return O.frame end
    local T = _G.BiSTheme
    if not (T and T.Options) then
        ns.Print("Libs\\BiSTheme\\Options.lua did not load - reinstall the addon")
        return nil
    end
    local f = T.Options(O.NAME, T.OPTIONS and T.OPTIONS.W or 230, "Guild")
    O.frame = f
    if f.Recenter then f:Recenter(60) end
    for _, sec in ipairs(O.Sections()) do
        f:Section(sec.title)
        for _, opt in ipairs(sec.options) do f:Row(opt, ns.DB()) end
    end
    f:Fit()
    return f
end

function O.Toggle()
    local f = O.Build()
    if not f then return nil end
    f:Toggle()
    if f:IsShown() then f:Paint() end
    return f:IsShown()
end

--------------------------------------------------------------------
-- the BiS> page (Libs\BiSTheme\Settings.lua)
--------------------------------------------------------------------

--- What is on, in a few words - the BiS> front page shows it.
function O.Status()
    local function w(on) return on and "on" or "off" end
    return ("logins %s  -  dots %s  -  note %s"):format(w(ns.Login and ns.Login.On()), w(ns.Pins and ns.Pins.On()),
        w(ns.Copy and ns.Copy.NoteOn()))
end

function O.Register()
    local T = _G.BiSTheme
    if not (T and T.SettingsPage) then return nil end
    O.page = T.SettingsPage(ADDON, {
        title = "Guild",
        about = "The guild's raid record, read from the combat log: who came, consumables, deaths, bosses. "
            .. "The terminal (/bisg) is the main window; the switches below are the extras.",
        status = O.Status,
        window = function() return O.Build() end,
        open = { label = "the terminal", func = function() if ns.K and ns.K.Show then ns.K.Show() end end },
        api = { name = "BiSGuildAPI", about = "the guild's raid record, read-only - nights, raiders, bosses - and "
            .. "opening the terminal" },
    })
    return O.page
end

--- `/bisg options`: the options window on its own, as it always opened (Arn, 7 Nov live: "i liked these old option
--- windows that opened without opening the game option window"). The BiS> page is Esc > Options > AddOns.
function O.Open()
    local f = O.Build()
    if f then f:Toggle(true) f:Paint() end
    return f and "window" or nil
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() O.Register() end)
