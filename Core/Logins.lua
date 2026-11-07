--[[
  BiSGuild :: Core/Logins.lua - "X just logged in - invite?"

  Arn, 16 Oct 2026: "if the addons can see if someone logged in and they are on the roster, makes the
  invite button pulse or a window pop up that says invite this <raider name> that just logged in?"

  WHO COUNTS: somebody on the pasted roster (Core/Invite.lua), in the guild, not signed Absence or
  Bench. WHEN: only while it can help - a roster is pasted, and you lead or assist your group (or are
  on your own, about to form one). Otherwise nothing happens: no pop-up on a random Wednesday.

  HOW IT KNOWS: the client's own "X has come online." (ERR_FRIEND_ONLINE_SS, the guild's login line),
  and the guild roster's online flags compared update to update - the backup for a player who turned
  that chat line off. One person is announced once a minute at most, whichever source is first.

  WHAT IT SHOWS: one small window, 1.43:1, stacking whoever logged in - a row each with Invite, then
  Invite all and Not now - and the terminal's INVITE ONLINE buttons pulse while anyone waits. No
  sound. `/bisg logins off` stops all of it.
]]
local ADDON, ns = ...
local K = ns.K

local L = {}
ns.Login = L

L.W, L.H = 280, 196          -- 1.43:1
L.ROWS = 4                   -- two lines each: the name, and how punctual they are
L.AGAIN = 60                 -- seconds before the same person is announced again
L.waiting = {}               -- { { name, signed, at } } in the order they came online
L.told = {}                  -- key -> GetTime() last announced

local function Now() return GetTime and GetTime() or 0 end
local function hidden(v)
    if v == nil or not issecretvalue then return false end
    local ok, yes = pcall(issecretvalue, v)
    return (not ok) or yes == true
end

function L.On() return ns.DB().logins ~= false end

--- Is now a time to offer invites? A roster to compare with, the say over the group - and, when the
--- roster is a Raid-Helper event with a start time, raid time: from L.BEFORE before the start to
--- L.AFTER after it (Arn, 16 Oct: "does the json say what time the raid is supposed to start?"), so
--- last week's roster left pasted never pops up on the wrong night.
L.BEFORE, L.AFTER = 2 * 3600, 4 * 3600
function L.Armed()
    if not L.On() or not ns.Inv then return false end
    local text = ns.Books().roster
    if type(text) ~= "string" or text == "" then return false end
    local e = ns.Inv.Event(text)                    -- read once per paste, then only looked up
    local now = GetServerTime and GetServerTime()
    if e and e.start and now and (now < e.start - L.BEFORE or now > e.start + L.AFTER) then return false end
    return ns.Inv.Leads()
end

--- This person's roster row, if they are one we would invite (in the guild, not absent or bench).
function L.OnRoster(name)
    local m = K.Member(name)                   -- the whole name: three Nebeons are three people
    local key = m and m.key
    if not key then return nil end
    for _, r in ipairs(ns.Inv.Read(ns.Books().roster)) do
        if r.key == key and r.member and not (r.standing and ns.Inv.OUT[r.standing]) then return r end
    end
    return nil
end

--- Somebody came online. True when they were announced.
function L.CameOnline(name)
    if type(name) ~= "string" or hidden(name) or not L.Armed() then return false end
    local r = L.OnRoster(name)
    if not r then return false end
    local last = L.told[r.key]
    if last and Now() - last < L.AGAIN then return false end
    L.told[r.key] = Now()
    -- the punctuality record first, whether or not there is an invite to offer
    local delta = L.Logged(r.key)
    if ns.Inv.IsHere(ns.Inv.Here(), r.member) then return false end
    for _, w in ipairs(L.waiting) do if w.key == r.key then return false end end
    L.waiting[#L.waiting + 1] = { name = r.member.name, key = r.key, signed = r.signed, class = r.member.class,
                                  delta = delta }
    L.Show()
    return true
end

--------------------------------------------------------------------
-- punctuality
--------------------------------------------------------------------

--[[ ON TIME, LATE, NO-SHOW (Arn, 16 Oct: "how close they were and if the invite went out after,
  meaning they were late. Have to account for server time, real time and their time zone. Maybe we
  even keep a record - habitually late, or perfect attendance").

  ONE CLOCK: Raid-Helper's startTime and GetServerTime() are both seconds since 1970 in UTC, so
  "how long after the start" is a subtraction no time zone can bend. Only showing a clock time needs
  a zone, and date() uses the reader's own. (The export's "time":"20:00" is the event creator's zone
  - never used for arithmetic.)

  WHAT COUNTS IS BEING ONLINE, not being invited: online at the start is on time, whenever the leader
  got round to the invite - a late invite is the leader's, not the raider's. Logged in after the start
  is late, by that much. Signed (not Absence or Bench), never online until the window closes: a
  no-show. Measured on the leader's client, while it holds the roster.

  Kept in BiSGuildDB.punctual[nameKey][startTime] = { d = seconds after the start (negative: early,
  nil: online before we could see the login), late = bool, noshow = bool }; L.KEEP raids per person. ]]
L.KEEP = 8
L.loggedAt = {}               -- key -> GetServerTime() we saw them come online this session

function L.Book()
    local d = ns.Books()                         -- this guild's books (Init.lua; alts in other guilds)
    if type(d.punctual) ~= "table" then d.punctual = {} end
    return d.punctual
end

local function ServerNow() return GetServerTime and GetServerTime() or nil end

--- Write one raid's verdict for one person - the first verdict stands (a relog does not undo late).
function L.Mark(key, start, entry)
    local book = L.Book()
    local p = book[key]
    if not p then p = {} book[key] = p end
    if p[start] then return false end
    p[start] = entry
    -- keep the newest L.KEEP raids
    local starts = {}
    for s in pairs(p) do starts[#starts + 1] = s end
    table.sort(starts)
    for i = 1, #starts - L.KEEP do p[starts[i]] = nil end
    return true
end

--- ANOTHER OFFICER'S VERDICT (Arn, 16 Oct: "share the punctuality with the other officers too").
--- Merged person by person, because each officer's client saw different logins: on time beats late
--- (one officer saw them online at the start; a relog another caught is not lateness), late beats
--- no-show (they came), and of two lates the smaller stands. True when it changed ours.
local function Rank(v) if v.noshow then return 1 elseif v.late then return 2 end return 3 end
function L.Merge(key, start, entry)
    local book = L.Book()
    local p = book[key]
    local have = p and p[start]
    if not have then return L.Mark(key, start, entry) end
    local a, b = Rank(entry), Rank(have)
    if a > b or (a == 2 and b == 2 and (entry.d or 0) < (have.d or 0))
       or (a == 3 and b == 3 and have.d == nil and entry.d ~= nil) then
        p[start] = entry
        return true
    end
    return false
end

--- The raids on record and how many people each: start -> count.
function L.Starts()
    local out = {}
    for _, p in pairs(L.Book()) do
        for s in pairs(p) do out[s] = (out[s] or 0) + 1 end
    end
    return out
end

--- Seen logging in now: remember when, and if the raid has started, they are late by that much.
--- Answers the seconds after the start (negative = early), or nil without a start time.
function L.Logged(key)
    local now = ServerNow()
    if now then L.loggedAt[key] = now end
    local e = ns.Inv and ns.Inv.Event(ns.Books().roster)
    if not (e and e.start and now) then return nil end
    local d = now - e.start
    if d > 0 then L.Mark(key, e.start, { d = d, late = true }) end
    return d
end

--- The start has passed: whoever on the roster is online is on time (early by what we saw, if we
--- saw it). Once per raid.
function L.AtStart(e)
    local I = ns.Inv
    local here = I.Here()
    for _, r in ipairs(I.Read(ns.Books().roster)) do
        if r.member and not (r.standing and I.OUT[r.standing]) then
            local s = I.Status(r, here)
            if s == "online" or s == "with you" then
                local at = L.loggedAt[r.key]
                L.Mark(r.key, e.start, { d = at and (at - e.start) or nil, late = false })
            end
        end
    end
end

--- The window has closed: whoever signed and never came is a no-show. Once per raid.
function L.AtEnd(e)
    local I = ns.Inv
    for _, r in ipairs(I.Read(ns.Books().roster)) do
        if r.member and not (r.standing and I.OUT[r.standing]) then
            L.Mark(r.key, e.start, { noshow = true })
        end
    end
end

--- The clock's two moments, checked every L.TICK seconds - a comparison of two numbers, nothing more
--- until a moment arrives.
L.TICK = 30
L.done = {}                   -- "start:<t>" / "end:<t>" already handled
function L.Tick()
    local e = ns.Inv and ns.Books().roster and ns.Inv.Event(ns.Books().roster)
    local now = ServerNow()
    if not (e and e.start and now) or not L.On() then return end
    if now >= e.start and now < e.start + L.AFTER and not L.done["start:" .. e.start] then
        L.done["start:" .. e.start] = true
        if ns.Inv.Leads() then L.AtStart(e) end
    end
    if now >= e.start + L.AFTER and now < e.start + L.AFTER + 86400 and not L.done["end:" .. e.start] then
        L.done["end:" .. e.start] = true
        if ns.Inv.Leads() then
            L.AtEnd(e)
            -- the raid's record is whole: tell the other officers (Core/Share.lua)
            if ns.X and ns.X.Announce then ns.X.Announce() end
        end
    end
end

--- The habit, over the raids on record: { raids, late, noshow, avgLate (minutes) } or nil.
function L.Habit(key)
    -- by the whole name: the punctuality of one Nebeon is not the others' (16 Oct)
    local m = K.Member(key)
    local p = L.Book()[m and m.key or (key:match("^([^%-]+)") or key):lower()] or L.Book()[K.NameKey(key)]
    if not p then return nil end
    local n, late, noshow, sum = 0, 0, 0, 0
    for _, v in pairs(p) do
        n = n + 1
        if v.noshow then noshow = noshow + 1
        elseif v.late then late = late + 1 sum = sum + (v.d or 0) end
    end
    if n == 0 then return nil end
    return { raids = n, late = late, noshow = noshow, avgLate = late > 0 and math.floor(sum / late / 60 + 0.5) or 0 }
end

--- "late 3 of last 5, avg 11 min" / "perfect 6 of 6" / "1 no-show in 4" - and its colour.
function L.HabitText(key)
    local h = L.Habit(key)
    if not h then return nil end
    if h.late == 0 and h.noshow == 0 then return ("perfect %d of %d"):format(h.raids, h.raids), "good" end
    local parts = {}
    if h.late > 0 then parts[#parts + 1] = ("late %d of last %d, avg %d min"):format(h.late, h.raids, h.avgLate) end
    if h.noshow > 0 then parts[#parts + 1] = ("%d no-show"):format(h.noshow) end
    return table.concat(parts, ", "), (h.late + h.noshow) * 2 > h.raids and "warn" or "gold"
end

--- This login, in words: "8 min early" / "+12 min late" / nil.
function L.DeltaText(d)
    if not d then return nil end
    local m = math.floor(math.abs(d) / 60 + 0.5)
    if d > 0 then return ("+%d min late"):format(m), "warn" end
    return ("%d min early"):format(m), "good"
end

--- Who is still waiting: not yet with you. Joined people drop off by themselves.
function L.Prune()
    local here, keep = ns.Inv.Here(), {}
    for _, w in ipairs(L.waiting) do if not ns.Inv.IsHere(here, { name = w.name, key = w.key }) then keep[#keep + 1] = w end end
    L.waiting = keep
    return #keep
end

function L.Pulsing() return #L.waiting > 0 end

--------------------------------------------------------------------
-- the two ways to hear it
--------------------------------------------------------------------

local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.-)")
    return "^" .. p .. "$"
end

--- The client's "|Hplayer:Name|h[Name]|h has come online." - the name, or nil.
function L.FromChat(msg)
    if type(msg) ~= "string" or hidden(msg) then return nil end
    local pat = Pattern(_G.ERR_FRIEND_ONLINE_SS) or "^|Hplayer:(.-)|h%[.-%]|h has come online%.$"
    local who = msg:match(pat)
    if not who then return nil end
    return (who:gsub("%-.*$", ""))
end

--- The roster's online flags, compared with last time: who turned online since.
L.lastOnline = nil
function L.FromRoster()
    K._guildDirty = true
    local now, came = {}, {}
    for key, m in pairs(K.Guild().members) do
        if m.online then
            now[key] = true
            if L.lastOnline and not L.lastOnline[key] then came[#came + 1] = m.name end
        end
    end
    L.lastOnline = now
    return came
end

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

function L.Build()
    if L.frame then return L.frame end
    local ui = K.ui
    if not (ui and CreateFrame) then return nil end
    local f = CreateFrame("Frame", "BiSGuildLogins", UIParent)
    L.frame = f
    f:SetSize(L.W, L.H)
    local pos = ns.DB().loginsPos
    if type(pos) == "table" and pos[1] then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1], pos[2])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        local h = UIParent and UIParent.GetHeight and UIParent:GetHeight()
        if l and t and h then ns.DB().loginsPos = { math.floor(l + 0.5), math.floor(t - h + 0.5) } end
    end)
    f:Hide()
    -- Escape closes it, as every BiS window (6 Nov: the family audit found it had none) - combat-safe, Init.lua's way
    ns.EscKeys(f, function() f:Hide() end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ui.Fill(bg, "bg", 0.96)
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", 0, 0)
    edge:SetHeight(2)
    ui.Fill(edge, "accent")
    f.title = ui.Text(f, 12, "accent")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText("BiS> just logged in")
    f.sub = ui.Text(f, 10, "muted")
    f.sub:SetPoint("TOPLEFT", 10, -24)
    f.sub:SetWidth(L.W - 20)

    local function Btn(parent, label, w, fn)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, 18)
        local bbg = b:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        ui.Fill(bbg, "accentSoft")
        local hi = b:CreateTexture(nil, "ARTWORK")
        hi:SetAllPoints()
        ui.Fill(hi, "accent", 0.28)
        hi:Hide()
        b:SetScript("OnEnter", function() hi:Show() end)
        b:SetScript("OnLeave", function() hi:Hide() end)
        b.fs = ui.Text(b, 11, "gold", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    f.rows = {}
    for i = 1, L.ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 8, -40 - (i - 1) * 30)
        row:SetSize(L.W - 16, 28)
        row.name = ui.Text(row, 12, "ink")
        row.name:SetPoint("TOPLEFT", 2, -1)
        row.name:SetWidth(L.W - 100)
        -- the second line: this login against the start, and the habit (Arn: "habitually late, or
        -- perfect attendance")
        row.note = ui.Text(row, 10, "muted")
        row.note:SetPoint("TOPLEFT", 2, -15)
        row.note:SetWidth(L.W - 100)
        row.invite = Btn(row, "Invite", 64, function()
            local w = row.who
            if w then ns.Inv.One(w.name) L.Done(w.key) end
        end)
        row.invite:SetPoint("RIGHT", 0, 0)
        f.rows[i] = row
    end
    f.all = Btn(f, "Invite all", 120, function()
        for _, w in ipairs(L.waiting) do ns.Inv.One(w.name) end
        L.waiting = {}
        L.Paint()
    end)
    f.all:SetPoint("BOTTOMLEFT", 8, 8)
    f.later = Btn(f, "Not now", 90, function() L.waiting = {} L.Paint() end)
    f.later:SetPoint("BOTTOMRIGHT", -8, 8)
    return f
end

function L.Done(key)
    local keep = {}
    for _, w in ipairs(L.waiting) do if w.key ~= key then keep[#keep + 1] = w end end
    L.waiting = keep
    L.Paint()
end

function L.Paint()
    local f = L.frame
    if not f then return end
    L.Prune()
    if #L.waiting == 0 then f:Hide() return end
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(f.rows) do
        local w = L.waiting[i]
        row.who = w
        if w then
            local cc = w.class and colours and colours[w.class]
            row.name:SetText(w.signed and (w.name .. "  " .. ns.T.text("muted", w.signed)) or w.name)
            local now, nowC = L.DeltaText(w.delta)
            local habit, habitC = L.HabitText(w.key)
            local parts = {}
            if now then parts[#parts + 1] = ns.T.text(nowC, now) end
            if habit then parts[#parts + 1] = ns.T.text(habitC, habit) end
            row.note:SetText(#parts > 0 and table.concat(parts, "  ·  ") or ns.T.text("muted", "first raid on record"))
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(K.ui.rgb("ink")) end
            row:Show()
        else
            row:Hide()
        end
    end
    local more = #L.waiting - L.ROWS
    f.sub:SetText(("on the roster%s - %s"):format(more > 0 and (" (+%d more)"):format(more) or "",
        ns.Inv.Tools() and "invites go through BiS Tools" or "click to invite"))
    f.all.fs:SetText(("Invite all (%d)"):format(#L.waiting))
    f:Show()
end

function L.Show()
    L.Build()
    L.Paint()
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, msg)
    if event == "GROUP_ROSTER_UPDATE" then
        if L.frame and L.frame:IsShown() then L.Paint() end      -- whoever joined drops off
        return
    end
    -- the roster compared only while armed (LEAN: a big guild's roster walk on every roster event,
    -- all week, for a pop-up that only matters on raid night, would be waste). The first armed walk
    -- only takes the baseline - nobody is "just logged in" because the window opened.
    if event == "GUILD_ROSTER_UPDATE" then
        if not L.Armed() then L.lastOnline = nil return end
        for _, name in ipairs(L.FromRoster()) do L.CameOnline(name) end
        return
    end
    if not L.Armed() then return end                              -- cheap first: most system lines
    local who = L.FromChat(msg)
    if who then L.CameOnline(who) end
end)

-- the start and the end of raid time, looked for every L.TICK seconds
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(L.TICK, function() L.Tick() end) end
