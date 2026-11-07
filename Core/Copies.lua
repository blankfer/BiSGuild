--[[
  BiSGuild :: Core/Copies.lua - is a newer BiS Guild about in the guild?

  WHAT IS LEFT OF THE COPY CHECK (18 Oct 2026). Arn: "can we get rid of the fingerprint thing". From
  16 to 18 Oct this file also checked that every file of the copy had loaded and swapped a SHA-256
  fingerprint with guildmates, to guard the PowerShell script. Raiders read their logs in the notebook
  now (Google's computer, the reader fetched from our GitHub) and the script is the officers' own, so
  that went. What stays is the one part that helps anybody: hearing that a guildmate runs a newer
  version, and saying so once.

  THE CONVERSATION (MOD "GLOG", alongside Core/Share.lua - believed from ANY guildmate, since all it
  says is "this is my version"):

    BUILD |0.2.0|-|?      at login, 20-40 s in: my version - and what is yours?
    BUILD |0.2.0|-|.      an answer.

  The middle field held the fingerprint. It stays, always "-", because 0.1.x copies check its shape and
  would drop a line without it - and they are exactly the copies that need to hear a newer one exists.

  LEAN (standing order, 7 Oct): one line per login, and an ask is answered by at most a few: a copy
  waits 2-10 s and stands down once C.ENOUGH others of ITS version have already answered. A copy that
  spoke in the last C.QUIET seconds does not answer at all.
]]
local ADDON, ns = ...

local C = {}
ns.Copy = C

C.ENOUGH = 3                 -- answers of our version that make ours unnecessary
C.QUIET = 120                -- seconds after we last spoke in which we do not answer again
C.KEEP = 30 * 86400          -- a guildmate's version is remembered this long
C.RECENT = 14 * 86400        -- and counted for this long

local function Now() return GetTime and GetTime() or 0 end
local function After(t, fn) if C_Timer and C_Timer.After then C_Timer.After(t, fn) end end
local function Short(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^%-]+)") or name
end

function C.Book()
    local b = ns.Books()
    if type(b.copies) ~= "table" then b.copies = {} end
    return b.copies
end

local function numbers(v)
    local t = {}
    for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

--- Is version a newer than version b? 0.10.0 is newer than 0.9.3.
function C.Newer(a, b)
    local x, y = numbers(a), numbers(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

function C.Say(ask)
    if not (ns.X and IsInGuild and IsInGuild()) then return false end
    C.lastSent = Now()
    ns.X.Send("BUILD", ns.VERSION, "-", ask and "?" or ".")
    return true
end

function C.AnswerSoon()
    if C.waiting then return end
    if C.lastSent and Now() - C.lastSent < C.QUIET then return end
    C.waiting, C.same = true, 0
    After(2 + math.random() * 8, function()
        C.waiting = nil
        if (C.same or 0) >= C.ENOUGH then return end      -- enough copies of our version have answered
        C.Say(false)
    end)
end

function C.Hear(sender, version, _, flags)
    if type(version) ~= "string" or #version > 24 or not version:match("^[%w%.%-]+$") then return end
    flags = type(flags) == "string" and flags or ""
    local name = Short(sender)
    -- guildmates only; never ourselves
    C.me = C.me or ns.X.Me()                   -- a name does not change in a session; asked once
    if not name or name == C.me or ns.X.Rank(name) == nil then return end
    C.Book()[name] = { v = version, t = time() }
    if C.waiting and version == ns.VERSION then C.same = (C.same or 0) + 1 end
    if flags:find("?", 1, true) then C.AnswerSoon() end
    C.Judge()
end

--- The guild's versions next to ours, over the last C.RECENT seconds: how many run a newer one, and
--- the newest.
function C.Summary()
    local s = { newer = 0 }
    local now, book = time(), C.Book()
    for name, e in pairs(book) do
        if type(e) ~= "table" or type(e.t) ~= "number" or now - e.t > C.KEEP then
            book[name] = nil
        elseif now - e.t <= C.RECENT and C.Newer(e.v, ns.VERSION) then
            s.newer = s.newer + 1
            if not s.newest or C.Newer(e.v, s.newest) then s.newest = e.v end
        end
    end
    return s
end

--- THE NOTE HAS A SWITCH (Forever 1.0, 7 Nov 2026): `versionNote`, OFF for a new install - the shared lib's
--- `/biscomm ver` lists every BiS version about and speaks up only for a critical one, so a line in chat for every
--- newer copy is a nag to a new player. An existing save was frozen ON (it always spoke). Versions are still heard
--- and written down either way; only the chat line waits for the switch.
function C.NoteOn() return ns.DB().versionNote == true end

--- Say it once a session, and only when it is worth saying.
function C.Judge()
    if C.toldOld or not C.NoteOn() then return end
    local s = C.Summary()
    if s.newer >= 1 then
        C.toldOld = true
        ns.Print("%d guildmate(s) run BiS Guild %s - you have %s. %s", s.newer, tostring(s.newest), ns.VERSION,
            ns.T.text("muted", "Update it from CurseForge."))
    end
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

if ns.X then ns.X.handlers.BUILD = C.Hear end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, _, a, b)
    if a or b then After(20 + math.random() * 20, function() C.Say(true) end) end
end)
