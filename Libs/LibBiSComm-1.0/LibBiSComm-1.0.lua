-- LibBiSComm-1.0
-- The shared BiS addon channel. EMBEDDED in every BiS addon, not installed as
-- one: a client with a single BiS addon carries the whole layer, which is the
-- entire point. Highest version present wins and upgrades in place.
--
--   Wire format:  PROTO|MOD|CMD|a1|a2|...
--
-- Every field is escaped on the wire (minor 6) so a payload may carry "|" - an
-- item link does: "\1" -> "\1\1", "|" -> "\1\2", undone on receipt. A field
-- with neither byte is sent as-is, so CORE and SUMMON traffic is byte-identical
-- to minor 5 and older copies still read it.
--
-- MOD is what lets unrelated addons share one prefix. An unknown MOD or CMD is
-- ignored in silence, so a client running an older or newer BiS addon is never
-- half-understood -- the same additive rule that let Rez fold into Innervate.
--
-- CORE is deliberately three commands. It carries only what a client knows
-- about ITSELF and nobody else can see:
--
--   HI    |libMinor|addonsBlob|known     who is here, running what
--   ASK   |what                          somebody wants WHERE (summoner)
--   WHERE |in|type|instName|zone|x|y|map am I inside an instance, and where
--   SUM   |state|summoner|area|left      OFFER / OK / NO on a summon offer
--
-- House rules, in the lib so they cannot drift addon to addon:
--   * draws nothing, prints nothing (one /biscomm for status and the off switch;
--     /bis belongs to LoonBestInSlot on the raid's clients - minor 4 gave it back) - the ONE exception, minor 18:
--     a line when you are below a release marked critical, or too old to talk to a guildmate's lib
--     (Arn: "we only alert for big critical updates or compatibility"); once a session, never in a fight
--   * no periodic chatter: WHERE pushes on a real change, otherwise it answers
--   * every host callback is pcall'd -- a lib fault cannot kill the addon
--   * off means silent AND deaf

-- minor 9 (7 Oct 2026): the cost pass - one roster walk per roster tick, the prefix asked first
-- minor 10 (12 Oct 2026): Forever's own rules (debt 37) - re-announce when the chat lockdown lifts,
-- the realm's outgoing-message block, RAID only when UnitInRaid says so, a per-sender inbox limit
-- minor 11 (14 Oct 2026): no hook on C_SummonInfo.ConfirmSummon on Forever - a hooked Blizzard
-- method can break the client until relaunch (Overlord 2.0, seen 11-12 Oct); summons are TBC's
-- minor 12 (14 Oct 2026): SPOT - where guildmates are, for BiS Tools' map: every embedder shares
-- your spot on the GUILD channel while you move (cascading 15/30/60 s by guild size), one switch
-- for all of them (/biscomm share on|off), and lib.spots for any addon to draw
-- minor 15 (21 Oct 2026): RIDE - when the zeppelins and boats dock, learned by riding them and shared with the
-- guild, so one rider with any BiS addon sets the clock for everyone; lib:RidesAt / RideSched for any addon to
-- show (BiS Tools draws the card; the lib still draws nothing)
-- minor 16 (21 Oct 2026): FOJJI - anyone with any BiS addon shows up in FojjiCore's party Experience and Campfires
-- windows: the lib says FojjiCore's own two lines (FOJJI_GXP_V1, FojjiCamp1) and answers its asks; quiet when
-- FojjiCore's journal is loaded here
-- minor 17 (22 Oct 2026): BiS> in - asking for Innervate / Power Infusion / Mana Tide (MOD IN: OPT, CD, REQ, CLAIM,
-- CANCEL); the first claim wins everywhere; the buttons are BiSTheme's shared Ask piece (docs/bisin.md)
--   + (23 Oct) the Deeprun Tram on the ride clock: two stops on lib.TRAM_MAP (no map in its zone - your world spot,
--   lib:TramSpot), a dwell per stop, two cars half a loop apart (sched.cars); lib:RideSure - the confidence %, moved
--   here from BiS Tools so every addon says the same number; Stormwind Harbor's Darkshore boat (sw_aub)
-- minor 18 (6 Nov 2026): VER - which BiS addons, which versions, across the GUILD and the group (MOD VER, guild-
-- scoped: HAVE|libMinor|addonsBlob|criticalBlob|compatMin). lib:Versions() / /biscomm ver list who runs what; a
-- release is marked critical by its TOC (## X-BiS-Critical: <version>) and that, or a lib too new to talk to us, is
-- the only thing ever said. Said once a session, never in a fight; a late login is answered by whoever is newer,
-- the first answer silencing the rest.
-- minor 19 (13 Nov 2026): no event is (un)registered after load. A player on a gamepad got "blocked from an action
-- only available to the Blizzard UI" every so often, naming BiS> Memories: FojjiCore's group events and BiS> in's
-- two were switched on and off from timers (joining a group, an ask running out), and Forever refuses that while
-- its gamepad UI is on (_bisdev/docs/solved.md, "Registering events can itself be guarded"). Now registered once at
-- load and gated in the handlers (lib._fjGrouped, lib._bisinWant).
local MAJOR, MINOR = "LibBiSComm-1.0", 20

local lib = _G.LibBiSComm
if lib and (lib.MINOR or 0) >= MINOR then return end   -- an equal or newer copy won
lib = lib or {}
_G.LibBiSComm = lib
lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Upgrading in place: everything the old copy learned survives. Wiping these
-- on a reload-in-place would drop the raid off every grid at once.
lib.peers     = lib.peers     or {}    -- name -> peer table
lib.handlers  = lib.handlers  or {}    -- mod -> cmd -> fn
lib.callbacks = lib.callbacks or {}    -- event -> { fn, ... }
lib.addons    = lib.addons    or {}    -- name -> version, what this client runs
lib.guildMods = lib.guildMods or {}    -- mod -> true: may ride the GUILD channel (minor 6)
if lib.enabled == nil then lib.enabled = true end

lib.PREFIX = "BiS"
lib.PROTO  = 1

local PREFIX, PROTO, SEP = lib.PREFIX, lib.PROTO, "|"

local ANSWER_MIN, ANSWER_JITTER = 1, 2   -- 1-3s: 25 clients must not answer as one
local HI_THROTTLE    = 5
local WHERE_THROTTLE = 3
local ASK_COALESCE   = 3
local OFFER_FALLBACK = 120               -- summon offer lifetime if the API is quiet

--------------------------------------------------------------------
-- small helpers (self-contained: the lib must work in an addon that has none)
--------------------------------------------------------------------

local function Now()
    if GetTime then return GetTime() end
    return 0
end

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn); return true end
    return false
end

-- A VALUE THE CLIENT WILL NOT LET US LOOK AT (4 Oct 2026). On WoW Forever a string handed to an
-- addon can be a SECRET VALUE: it is truthy, so `if not v` lets it straight through, and it errors
-- the moment anything reads it - a match, a comparison, or being used as a table key.
--
-- Feature-detected, never version-checked: Forever carries a modern API behind a 1.60 interface
-- number, so "does this client have the call" is the only honest question. A client without it has
-- no secret values and this is always false.
local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
lib.Secret = Secret

-- GUARDED HERE, so every caller is guarded at once. Short() takes names from UnitName() as well as
-- from the wire, and on this client both can come back secret inside an instance. A nil is the
-- honest answer: we do not know who that is, and every caller already handles not knowing.
local function Short(name)
    if name == nil or Secret(name) or type(name) ~= "string" then return nil end
    return string.match(name, "^([^%-]+)") or name
end
lib.Short = Short

--- A unit's WHOLE name, as its addon messages arrive (minor 14). Forever measured, 18 Oct 2026 (Arn's
--- /run): UnitName("player") is "Chain" while his messages come from "Chain Healz" - so minor 13 and
--- before took its own GUILD echo for a guildmate (Arn on his own map twice, "you'n Healz") and could
--- never match a party member's "Name Surname" to a unit. GetUnitName(unit, false) carries the
--- surname (solved.md, 13 Oct); UnitName is the fallback where it is missing or hidden.
local function FullName(unit)
    if GetUnitName then
        local ok, n = pcall(GetUnitName, unit, false)
        if ok and n ~= nil and not Secret(n) and type(n) == "string" and n ~= "" then return Short(n) end
    end
    return Short(UnitName and UnitName(unit) or nil)
end
lib.FullName = FullName

local function PlayerName()
    return FullName("player")
end

--- A name's first word: what UnitName gives on Forever ("Chain" of "Chain Healz").
local function First(name)
    return name and (string.match(name, "^(%S+)") or name) or nil
end

local function InGroup()
    if IsInRaid and IsInRaid() then return true end
    if IsInGroup and IsInGroup() then return true end
    return false
end

-- A dungeon-finder group silently DROPS "RAID"/"PARTY" addon messages. Summon
-- work happens at instance doorsteps, which is exactly where this bites.
local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    -- RAID ONLY WHEN THE CLIENT SAYS YOU ARE IN ONE (minor 10). Overlord found IsInRaid() can stay
    -- true right after leaving an instance while RAID refuses every message (Sync.lua); UnitInRaid
    -- on yourself is the stricter answer. Asked secret-guarded; a hidden answer is "not sure", and
    -- PARTY still reaches the people beside you.
    if IsInRaid and IsInRaid() then
        local sure = true
        if UnitInRaid then
            local ok, r = pcall(UnitInRaid, "player")
            sure = ok and not Secret(r) and r ~= nil and r ~= false
        end
        if sure then return "RAID" end
    end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end
lib.GroupChannel = GroupChannel

local function ForEachMember(cb)
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local unit = "raid" .. i
            if UnitExists and UnitExists(unit) then cb(unit, FullName(unit)) end
        end
    else
        cb("player", PlayerName())
        for i = 1, math.max(0, n - 1) do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) then cb(unit, FullName(unit)) end
        end
    end
end

--- The unit of a name: the whole name exactly, or - for a first name alone (a caller holding UnitName's
--- answer) - the one member whose first name it is. Two members sharing it: nobody, never a guess.
local function UnitOf(name)
    name = Short(name)
    if not name then return nil end
    if name == PlayerName() then return "player" end
    local found, byFirst, firsts = nil, nil, 0
    local bare = not string.find(name, " ", 1, true)
    ForEachMember(function(unit, n)
        if found or not n then return end
        if n == name then found = unit
        elseif bare and First(n) == name then byFirst, firsts = unit, firsts + 1 end
    end)
    if found then return found end
    if firsts == 1 then return byFirst end
    return nil
end
lib.UnitOf = UnitOf

-- WindfuryComm++ shipped `tonumber(string.gsub(v, ".", "0"))`: "." matches every
-- character, so "2.1.3" became 0 for everybody and its update notice has never
-- once fired. Parse the numbers out; never pattern-mangle a version.
function lib.VersionCmp(a, b)
    local function parts(v)
        local t = {}
        for n in string.gmatch(tostring(v or ""), "(%d+)") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

function lib.VersionGT(a, b) return lib.VersionCmp(a, b) > 0 end

-- MINOR 6: "|" inside a field. SEP is "|", and an item link is full of them, so a
-- field is escaped before it is joined and unescaped after the split. Two bytes
-- for "|", not one: with "|" -> "\1" alone, a field "||" and a field "\1" would
-- both go out as "\1\1" and could never be told apart again.
local ESC, PIPE = "\1", "\2"

local function escape(s)
    if not string.find(s, "[\1|]") then return s end
    return (string.gsub(s, "[\1|]", function(ch)
        if ch == ESC then return ESC .. ESC end
        return ESC .. PIPE
    end))
end

local function unescape(s)
    if not string.find(s, ESC, 1, true) then return s end
    return (string.gsub(s, "\1(.)", function(ch)
        if ch == ESC then return ESC end
        if ch == PIPE then return SEP end
        return ch
    end))
end
lib._escape, lib._unescape = escape, unescape

local function split(msg)
    local out, i = {}, 1
    for piece in string.gmatch(msg .. SEP, "([^" .. SEP .. "]*)%" .. SEP) do
        out[i] = unescape(piece); i = i + 1
    end
    return out
end
lib._split = split

-- MINOR 6: guild membership for guard 3 on the GUILD channel. Rebuilt lazily after
-- GUILD_ROSTER_UPDATE; a name the roster does not list is refused, never guessed.
function lib:InGuild(name)
    name = Short(name)
    if not name then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    if self._guildDirty ~= false or not self._guild then
        local roster = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local member = GetGuildRosterInfo and GetGuildRosterInfo(i)
            if member then roster[Short(member)] = true end
        end
        self._guild, self._guildDirty = roster, false
    end
    return self._guild[name] == true
end

local function fire(event, ...)
    for _, fn in ipairs(lib.callbacks[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then lib._lastError = err end   -- a host bug must not stop the next host
    end
end

--------------------------------------------------------------------
-- peers
--------------------------------------------------------------------

local function peer(name)
    local p = lib.peers[name]
    if not p then
        p = { name = name, addons = {}, where = nil, summon = nil }
        lib.peers[name] = p
    end
    return p
end

--- The peers key for a name (minor 14): the whole name as it arrived, or a first name alone when one
--- peer has it (a caller holding UnitName's "Bree" for the peer "Bree Stone").
function lib:PeerKey(name)
    name = Short(name or "")
    if not name or name == "" then return nil end
    if self.peers[name] then return name end
    if string.find(name, " ", 1, true) then return nil end
    local hit
    for k in pairs(self.peers) do
        if First(k) == name then
            if hit then return nil end                       -- two of them: never a guess
            hit = k
        end
    end
    return hit
end
function lib:Peer(name) local k = self:PeerKey(name) return k and self.peers[k] or nil end
function lib:Peers() return self.peers end

function lib:Count()
    local n = 0
    for _ in pairs(self.peers) do n = n + 1 end
    return n
end

-- Does this group member run any BiS addon? Everything downstream hangs off
-- this: a name that answers is fact, a name that does not is a guess, and the
-- two must never look alike in a UI.
function lib:HasLib(name)
    name = Short(name or "")
    local me = PlayerName()
    if name == me or (name == First(me) and not string.find(name or "", " ", 1, true)) then return true end
    return self:PeerKey(name) ~= nil
end

-- ONE WALK OF THE ROSTER, NOT ONE PER PEER (7 Oct 2026). This asked UnitOf about every peer,
-- and UnitOf walks the whole raid: ~1,000 roster questions a tick in a 25-man, ~4,700 in a 40,
-- on an event that comes in bursts. Walk once into a set, then look each peer up in it.
function lib:PurgeAbsent()
    local here = {}
    ForEachMember(function(_, n) if n and not Secret(n) then here[n] = true end end)
    local me = PlayerName()
    for name in pairs(self.peers) do
        if name ~= me and not here[name] then self.peers[name] = nil end
    end
    -- BiS> in (minor 17): who left the group leaves its lists too, in the same one walk
    local b = self.bisin
    if b then
        for name in pairs(b.peers) do
            if not here[name] then b.peers[name] = nil end
        end
    end
end

--------------------------------------------------------------------
-- registration by host addons
--------------------------------------------------------------------

function lib:RegisterAddon(name, version)
    if not name then return end
    self.addons[name] = tostring(version or "?")
end

function lib:RegisterHandler(mod, cmd, fn)
    self.handlers[mod] = self.handlers[mod] or {}
    self.handlers[mod][cmd] = fn
end

-- MINOR 6: a MOD that may ride the GUILD channel (BiSLoot's LOOT). CORE never can:
-- HI / WHERE / SUM are about the group, and a guild line must not plant a peer.
function lib:RegisterGuildMod(mod)
    if not mod or mod == "CORE" then return false end
    self.guildMods[mod] = true
    return true
end

-- events: "PEER" (name, peer) | "WHERE" (name, where) | "SUM" (name, summon)
function lib:RegisterCallback(event, fn)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
end

function lib:Enabled() return self.enabled and true or false end

-- Off is silent AND deaf. A client that still listened while claiming to be off
-- would be the same lie as Innervate's closed window that kept a live drag strip.
function lib:SetEnabled(on)
    self.enabled = on and true or false
    if not self.enabled then
        self.peers = {}
        lib.peers = self.peers
    end
    return self.enabled
end

--------------------------------------------------------------------
-- send / receive
--------------------------------------------------------------------

local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

-- The group: RAID / PARTY / INSTANCE_CHAT, whichever this client is in.
function lib:Send(mod, cmd, ...)
    return self:SendTo(nil, mod, cmd, ...)
end

-- MINOR 6: an explicit channel. nil = the group (as Send). "GUILD" only for a MOD
-- registered with RegisterGuildMod - the guild reaches four raids at once, which is
-- what BiSLoot's ledger sync needs and exactly what CORE must never do.
function lib:SendTo(channel, mod, cmd, ...)
    if not self.enabled then return false end
    if not mod or not cmd then return false end
    local chan
    if channel == nil then
        chan = GroupChannel()
        if not chan then return false end
    elseif channel == "GUILD" then
        if not self.guildMods[mod] then
            self._lastError = "not guild-scoped: " .. tostring(mod)
            return false
        end
        if not (IsInGuild and IsInGuild()) then return false end
        chan = "GUILD"
    elseif GROUP_CHANNELS[channel] then
        chan = channel
    else
        self._lastError = "channel not allowed: " .. tostring(channel)
        return false
    end
    local parts = { PROTO, escape(tostring(mod)), escape(tostring(cmd)) }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = "" elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = escape(tostring(v))
    end
    local msg = table.concat(parts, SEP)
    -- The client drops anything past 255 bytes and never tells the sender. Say
    -- so instead of losing it silently. Counted AFTER escaping: that is what goes out.
    if #msg > 250 then
        self._lastError = "message too long: " .. mod .. "/" .. cmd .. " " .. #msg
        return false
    end
    return self:_Queue(msg, chan)
end

--------------------------------------------------------------------
-- THE OUTBOX (minor 8, 6 Oct 2026)
--
-- Until minor 7 every Send went straight to the client and its answer was never read. Overlord
-- measured the client on Forever (27 Sep): about ONE addon message a second PER PREFIX, shared by
-- group, raid and channel together; past that the send answers a throttle code and the message
-- simply does not leave. Eight BiS addons share this lib's one prefix, so they share that one
-- message a second - and a fight's worth of HI, WHERE and answers was being lost with no error
-- anywhere. Chat lockdown (InChatMessagingLockdown) refuses everything for a while besides.
--
-- So: one queue for the whole client (the lib is loaded ONCE however many addons embed it), one
-- message per SEND_GAP, the client's answer read every time. A throttle puts the message back at
-- the head and waits; lockdown holds the queue until it lifts; any other refusal is dropped and
-- said in _lastError. An old message is thrown away rather than sent late - a WHERE from half a
-- minute ago is a lie about where somebody is. The same line already waiting is not queued twice.
--
-- Send still answers true for "accepted", which now means "queued": the first one in a quiet
-- second still leaves at once.
--------------------------------------------------------------------

local SEND_GAP   = 1.0    -- seconds between two of OUR messages; the client allows about one.
                          -- lib.sendGap overrides it: a host SUITE about something else may set 0
local SEND_TTL   = 30     -- a message older than this is stale and dropped, not sent
local OUTBOX_MAX = 40     -- past this a new message is refused, not queued

lib.outbox = lib.outbox or {}
lib.nextSendAt = lib.nextSendAt or 0
lib.sentCount, lib.refusedCount = lib.sentCount or 0, lib.refusedCount or 0

-- The client's answer, by NAME where it has the enum (our census does not record Enum tables, so
-- Forever's numbers are unverified). Retail's numbers, which FojjiCore retries on, are the fallback.
local function ResultKind(r)
    if r == nil or r == true or r == 0 then return "sent" end     -- 2.5.x answers nothing
    if Secret(r) then return "sent" end
    if r == false then return "again" end
    local E = Enum and Enum.SendAddonMessageResult
    local throttle, channel, general = 3, 8, 9
    if type(E) == "table" then
        throttle = E.AddonMessageThrottle or throttle
        channel  = E.ChannelThrottle or channel
        general  = E.GeneralError or general
    end
    if r == throttle or r == channel or r == general then return "again" end
    return "refused"
end

local function clear(t) for i = #t, 1, -1 do t[i] = nil end end

local function ChatLocked()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return false end
    -- a HIDDEN answer about the lockdown is itself a sign of one (minor 10; ForeverAuras treats any
    -- unreadable restriction check as "restricted"): hold, and let the TTL drop what goes stale
    if Secret(v) then return true end
    return v and true or false
end
lib.ChatLocked = ChatLocked

--- THE REALM'S OWN "BLOCK" (minor 10) - AN ANSWER, NOT A GATE SINCE MINOR 13. Measured on Forever,
--- 18 Oct 2026 (Arn's /run): C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() says plain TRUE while
--- C_ChatInfo.SendAddonMessage("BiS", "test", "GUILD") answers 0 and the message arrives. Minor 10-12
--- held the outbox on it - and so sent NOTHING on Forever (Arn's lib: "sent 0 ... err dropped a stale
--- message"): no spots, no GLOG, no BiS> now, no peers. The send's own result is the client's real
--- word (ResultKind: throttle / general error are retried, anything else is named); this question is
--- only reported, in /biscomm.
local function OutgoingBlocked()
    local f = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return false end
    if Secret(v) then return true end
    return v and true or false
end
lib.OutgoingBlocked = OutgoingBlocked

local function RawSend(msg, chan)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return true, C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
    elseif SendAddonMessage then
        return true, SendAddonMessage(PREFIX, msg, chan)
    end
    return false
end

function lib:_Queue(msg, chan)
    local q = self.outbox
    for _, m in ipairs(q) do
        if m.msg == msg and m.chan == chan then return true end    -- already waiting
    end
    if #q >= OUTBOX_MAX then
        self._lastError = "outbox full: " .. #q .. " waiting"
        return false
    end
    q[#q + 1] = { msg = msg, chan = chan, at = Now() }
    self:_Pump()
    return true
end

function lib:_Arm(delay)
    if self._pumpArmed then return end
    if After(math.max(delay, 0.05), function() lib._pumpArmed = false; lib:_Pump() end) then
        self._pumpArmed = true
    end
end

function lib:_Pump()
    local q = self.outbox
    local gap = tonumber(self.sendGap) or SEND_GAP
    while #q > 0 do
        if not self.enabled then clear(q); return end
        local now = Now()
        -- the clock went BACKWARDS under us (a harness rewinding GetTime; the client never does):
        -- a wait longer than any backoff we set is not a wait, it is a broken clock - send now
        if self.nextSendAt - now > 2 * gap then self.nextSendAt = now end
        if q[1].at > now then q[1].at = now end
        if now - q[1].at > SEND_TTL then
            table.remove(q, 1)
            self._lastError = "dropped a stale message"
        elseif ChatLocked() then
            self:_Arm(SEND_GAP)
            return
        elseif now < self.nextSendAt then
            self:_Arm(self.nextSendAt - now)
            return
        else
            local m = q[1]
            local can, r = RawSend(m.msg, m.chan)
            if not can then clear(q); return end
            local kind = ResultKind(r)
            if kind == "again" then
                -- it did NOT leave: keep it at the head and back off a little further
                self.refusedCount = self.refusedCount + 1
                self.nextSendAt = now + 2 * gap
                self:_Arm(2 * gap)
                return
            end
            table.remove(q, 1)
            self.nextSendAt = now + gap
            if kind == "sent" then
                self.sentCount = self.sentCount + 1
            else
                self.refusedCount = self.refusedCount + 1
                self._lastError = "the client refused a message (" .. tostring(r) .. ")"
            end
        end
    end
end

lib.INBOX_BURST, lib.INBOX_RATE = 20, 2
lib.inbox = lib.inbox or {}
lib.droppedIn = lib.droppedIn or 0

--- May this sender's message in? A token bucket per sender, refilled by the clock.
function lib:_Admit(sender)
    local now = Now()
    local b = self.inbox[sender]
    if not b then b = { tokens = self.INBOX_BURST, at = now } self.inbox[sender] = b end
    if now > b.at then
        b.tokens = math.min(self.INBOX_BURST, b.tokens + (now - b.at) * self.INBOX_RATE)
    end
    b.at = now
    if b.tokens < 1 then
        self.droppedIn = self.droppedIn + 1
        return false
    end
    b.tokens = b.tokens - 1
    return true
end

--- THE LOCKDOWN LIFTED (minor 10). Messages that waited out a boss died at SEND_TTL, and every
--- peer's did too - so after every encounter the roster was as stale as the fight was long. On
--- the lift: send what is still waiting, and say HI - twice, a moment apart, because the others
--- come out of the lockdown a moment later than we do (LibSpecialization's way, EllesmereUI;
--- Overlord's catch-up burst). The short-answer rule keeps it from becoming 25 x 25.
function lib:OnRestrictionChanged()
    if ChatLocked() then return false end          -- (never the realm "block": see OutgoingBlocked)
    self:_Pump()
    if not InGroup() then return false end
    local first = 1 + math.random() * 2
    local function hi() if InGroup() then lib:Hi() end end
    if not After(first, hi) then hi() end
    After(first + 3, hi)
    return true
end

function lib:OnMessage(prefix, msg, channel, sender)
    if not self.enabled then return end
    -- EVERY ARGUMENT, BEFORE ANYTHING READS ONE (4 Oct 2026). CHAT_MSG_ADDON hands over four
    -- values and on this client any of them can be a secret: seen in a dungeon, where the client
    -- hides chat. A secret is truthy, so `not msg` never caught it - the error arrived further
    -- down, out of `split(msg)` or out of using the sender as a table key, and OnEvent does not
    -- pcall, so it landed on the player's screen as a red wall in the middle of a pull.
    --
    -- BiSMemories shipped 0.5.1 to fix exactly this shape one layer up, in CHAT_MSG_LOOT. It was
    -- still here underneath, in the lib seven addons embed. Found 4 Oct in FojjiCore's dungeon
    -- journal, which guards its text AND its sender - the sender being the half nobody here had
    -- thought of.
    --
    -- Nothing hidden is worth answering: a message we may not read is not a message, and a peer we
    -- may not name cannot be put in the table. Dropping it is the whole fix.
    -- the PREFIX first (7 Oct 2026, the cost pass): every addon's messages come through here, and
    -- a raid's worth of them is hundreds a second - one question decides "not ours", not four
    if Secret(prefix) or prefix ~= PREFIX then return end
    if Secret(msg) or Secret(channel) or Secret(sender) then return end
    if type(msg) ~= "string" then return end
    sender = Short(sender)
    if not sender then return end
    -- ONE PEER CANNOT FLOOD US (minor 10). A per-sender bucket: INBOX_BURST at once, then
    -- INBOX_RATE a second (Olympus admits 60 then 2/s; we are far quieter - nothing of ours sends
    -- more than a message a second). Past it the line is dropped before any parsing, and counted.
    if not self:_Admit(sender) then return end

    local p = split(msg)
    local proto, mod, cmd = tonumber(p[1] or ""), p[2], p[3]
    if not mod or not cmd then return end

    -- Guard 1: our framing only. A newer client's message parsed as ours would
    -- corrupt state rather than be rejected.
    if proto ~= PROTO then
        if proto and proto > PROTO then self._sawNewer = true end
        return
    end
    -- Guard 2: group channels only - or GUILD for a guild-scoped MOD (minor 6). A
    -- whisper from a stranger must not be able to plant a position or a summon state,
    -- and neither may a guild line: CORE is never guild-scoped.
    local guild = (channel == "GUILD")
    if channel and not GROUP_CHANNELS[channel] and not guild then return end
    if guild and not self.guildMods[mod] then return end
    -- Guard 3: a sender we can actually see - in the group, or for GUILD in the
    -- guild roster (minor 6).
    if sender ~= PlayerName() then
        if guild then
            if not self:InGuild(sender) then return end
        elseif not UnitOf(sender) then
            return
        end
    end
    -- Guard 4: my own echo. The client hands every group addon message back to
    -- its sender too; taking it would make me my own peer (MINOR 2 did: a
    -- summoner at the stone counted himself twice - Arn, 8 Sep). What I know
    -- about myself lives in self.where / self.summon, never in peers.
    if sender == PlayerName() then return end

    -- A guild sender is not a group peer: grids and summon lists are about the
    -- group, and forty officers across four raids must not appear on them.
    if not guild then
        local isNew = (self.peers[sender] == nil)
        local pr = peer(sender)
        pr.seen = Now()
        if isNew then fire("PEER", sender, pr) end
    end

    local args = {}
    for i = 4, #p do args[i - 3] = p[i] end

    local core = self._core[cmd]
    if mod == "CORE" and core then
        local ok, err = pcall(core, sender, unpack(args))
        if not ok then self._lastError = err end
        return
    end
    -- Guard 4: unknown MOD or CMD is ignored, not guessed at.
    local h = self.handlers[mod] and self.handlers[mod][cmd]
    if h then
        local ok, err = pcall(h, sender, unpack(args))
        if not ok then self._lastError = err end
    end
end

--------------------------------------------------------------------
-- CORE: identity
--------------------------------------------------------------------

function lib:AddonsBlob()
    local out = {}
    for name, ver in pairs(self.addons) do out[#out + 1] = name .. "=" .. ver end
    table.sort(out)
    return table.concat(out, ",")
end

function lib:Hi()
    if not InGroup() then return false end
    return self:Send("CORE", "HI", self.MINOR, self:AddonsBlob(), self:Count())
end

lib._core = {}

lib._core.HI = function(sender, minor, blob, known)
    local pr = peer(sender)
    pr.libMinor = tonumber(minor or "") or 0
    pr.addons = {}
    for entry in string.gmatch(blob or "", "([^,]+)") do
        local n, v = string.match(entry, "^(.-)=(.*)$")
        if n then pr.addons[n] = v end
    end
    fire("PEER", sender, pr)

    -- Answer a HI only when the sender is SHORT: it knows fewer of us than
    -- there are (a reload, a fresh join, a lost HI). A client that knows
    -- everybody already needs no answer - answering every HI "once per 5 s"
    -- (minor 2) turned 8 people zoning into Karazhan into 30 HIs on a 25-man
    -- (raid25.lua). HI_THROTTLE still spaces my own answers.
    local theyKnow = tonumber(known or "") or 0
    local short = theyKnow < (lib:Count() - 1)
    if not lib._hiPending and short then
        lib._hiPending = true
        local send = function()
            lib._hiPending = false
            lib._lastHi = Now()
            lib:Hi()
        end
        -- jittered like every answer; if my last HI is inside the throttle the
        -- answer waits it out instead of being dropped (a reload right after a
        -- join lost 7 of 21 peers that way - raid25.lua)
        local delay = ANSWER_MIN + math.random() * ANSWER_JITTER
        local wait = HI_THROTTLE - (Now() - (lib._lastHi or 0))
        if wait > delay then delay = wait end
        if not After(delay, send) then send() end
    end
end

--------------------------------------------------------------------
-- CORE: where am I
--------------------------------------------------------------------

-- Everything here is about the SELF. UnitPosition on somebody else goes nil the
-- moment they are in another instance -- which is precisely the case a summoner
-- cares about -- while a client's own position is never unknown.
function lib:MyWhere()
    local inInst, instType = false, "none"
    if IsInInstance then
        local a, b = IsInInstance()
        inInst, instType = a and true or false, b or "none"
    end
    -- mapId ALWAYS: outdoors it is the continent's instance id, the same number
    -- UnitPosition hands out, and the summoner compares against it to turn two
    -- positions into yards. MINOR 1 only sent it inside an instance, so a peer
    -- standing next to the summoner in Stormwind read as "far".
    local instName, mapId = "", ""
    if GetInstanceInfo then
        local n, _, _, _, _, _, _, id = GetInstanceInfo()
        mapId = id or ""
        if inInst then instName = n or "" end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local x, y = "", ""
    if UnitPosition then
        local py, px = UnitPosition("player")
        if px and py then
            x = string.format("%.1f", px)
            y = string.format("%.1f", py)
        end
    end
    return {
        inInstance = inInst, instType = instType, instName = instName,
        zone = zone, x = tonumber(x), y = tonumber(y), mapId = mapId,
        at = Now(),
    }
end

local function whereKey(w)
    return tostring(w.inInstance) .. w.instType .. w.instName .. w.zone
end

function lib:SendWhere(force)
    if not InGroup() then return false end
    local w = self:MyWhere()
    local key = whereKey(w)
    -- Push only on a real change. Walking around is not news; zoning is.
    if not force and key == self._lastWhereKey and (Now() - (self._lastWhereAt or 0)) < WHERE_THROTTLE then
        return false
    end
    self._lastWhereKey, self._lastWhereAt = key, Now()
    self.where = w
    return self:Send("CORE", "WHERE", w.inInstance, w.instType, w.instName, w.zone,
                     w.x or "", w.y or "", w.mapId)
end

-- A summoner asking. Everyone answers once, spread over 1-3s; repeat asks
-- inside the window fold into the one answer already scheduled.
function lib:Ask()
    return self:Send("CORE", "ASK", "WHERE")
end

lib._core.ASK = function(sender, what)
    if what ~= "WHERE" then return end
    if lib._askPending then return end
    if (Now() - (lib._lastAnswer or 0)) < ASK_COALESCE and lib._lastAnswer then return end
    lib._askPending = true
    local send = function()
        lib._askPending = false
        lib._lastAnswer = Now()
        lib:SendWhere(true)
    end
    if not After(ANSWER_MIN + math.random() * ANSWER_JITTER, send) then send() end
end

lib._core.WHERE = function(sender, inInst, instType, instName, zone, x, y, mapId)
    local pr = peer(sender)
    pr.where = {
        inInstance = (inInst == "1"),
        instType   = instType or "none",
        instName   = instName or "",
        zone       = zone or "",
        x = tonumber(x or ""), y = tonumber(y or ""),
        mapId = mapId or "",
        at = Now(),
    }
    fire("WHERE", sender, pr.where)
end

--------------------------------------------------------------------
-- CORE: summon offers
--------------------------------------------------------------------
-- CONFIRM_SUMMON fires on the person being summoned, never on the summoner, and
-- clicking a meeting stone is a game-object interaction the client does not
-- expose at all. This is the only honest way a summoner learns what happened.

function lib:SendSummon(state, summoner, area, left)
    self.summon = (state ~= "NO") and
        { state = state, summoner = summoner, area = area, left = left, at = Now() } or nil
    return self:Send("CORE", "SUM", state, summoner or "", area or "", left or "")
end

-- MINOR 6: 2.5.6.69795 has these only at C_SummonInfo.* (BiSProbe, 16 Sep) - the
-- globals minor 5 read are gone. C_SummonInfo first, the old globals as the fallback,
-- looked up at call time in pair form (the API fence in _bisdev/audit reads that shape).
local function SummonAPI()
    local who  = (C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner) or GetSummonConfirmSummoner
    local area = (C_SummonInfo and C_SummonInfo.GetSummonConfirmAreaName) or GetSummonConfirmAreaName
    local left = (C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft) or GetSummonConfirmTimeLeft
    return who, area, left
end

function lib:OnConfirmSummon()
    local getWho, getArea, getLeft = SummonAPI()
    local summoner = getWho and getWho() or ""
    local area     = getArea and getArea() or ""
    local left     = getLeft and getLeft() or OFFER_FALLBACK
    -- MINOR 5: the 2.5.x client fires CONFIRM_SUMMON on bystanders too (Arn, 10 Sep:
    -- "randomly if any other person gets a summon it says SUMMON by someone") - with
    -- no summoner, no area, no clock. That is not an offer to ME; announcing it as
    -- one would put a phantom OFFER on every summoner's list. Ask the client.
    if not self:HasPendingSummon(summoner, area, left) then return end
    left = tonumber(left) or OFFER_FALLBACK
    if left <= 0 then left = OFFER_FALLBACK end
    self._offerId = (self._offerId or 0) + 1
    local id = self._offerId
    self:SendSummon("OFFER", Short(summoner), area, math.floor(left))
    -- An offer that lapses unanswered is the exact case that used to leave the
    -- summoner staring at the same name: say so when the clock runs out.
    After(left, function()
        if lib._offerId == id and lib.summon and lib.summon.state == "OFFER" then
            lib:SendSummon("NO", nil, nil, nil)
        end
    end)
end

-- Is there really a summon waiting on THIS client? Only the client's summon API can
-- say. MINOR 6: when neither C_SummonInfo nor the old globals exist the answer is NO -
-- minor 5 said yes there, and on 2.5.6.69795 (globals gone) that turned every
-- bystander's CONFIRM_SUMMON back into a phantom OFFER.
function lib:HasPendingSummon(summoner, area, left)
    local getWho, getArea, getLeft = SummonAPI()
    if not getWho then return false end
    summoner = summoner or (getWho() or "")
    area = area or (getArea and getArea() or "")
    left = tonumber(left or (getLeft and getLeft())) or 0
    return (summoner ~= "" or area ~= "" or left > 0) and true or false
end

function lib:OnConfirmed()      -- they clicked Accept
    if self.summon and self.summon.state == "OFFER" then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("OK", self.summon.summoner, self.summon.area, nil)
    end
end

function lib:OnCancelSummon()   -- declined, or it timed out client-side
    if self.summon then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("NO", nil, nil, nil)
    end
end

lib._core.SUM = function(sender, state, summoner, area, left)
    local pr = peer(sender)
    if state == "NO" then
        pr.summon = nil
    else
        pr.summon = {
            state = state, summoner = summoner, area = area,
            left = tonumber(left or ""), at = Now(),
        }
    end
    fire("SUM", sender, pr.summon)
end

--------------------------------------------------------------------
-- events
--------------------------------------------------------------------

function lib:Boot()
    if self._booted then return end
    self._booted = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end

    local f = self._frame or (CreateFrame and CreateFrame("Frame"))
    if not f then return end
    self._frame = f

    local function reg(ev)
        -- An event this client does not have must not stop the rest registering.
        pcall(f.RegisterEvent, f, ev)
    end
    reg("CHAT_MSG_ADDON")
    reg("PLAYER_ENTERING_WORLD")
    reg("ZONE_CHANGED_NEW_AREA")
    reg("GROUP_ROSTER_UPDATE")
    reg("CONFIRM_SUMMON")
    reg("CANCEL_SUMMON")
    reg("GUILD_ROSTER_UPDATE")
    reg("ADDON_RESTRICTION_STATE_CHANGED")     -- Forever: the lockdown starting or lifting (minor 10)
    if self.StartSpots then self:StartSpots() end -- minor 12: guild spots
    if self.StartRides then self:StartRides() end -- minor 15: the ride clock
    if self.StartFojji then self:StartFojji() end -- minor 16: FojjiCore's Experience and Campfires windows
    if self.StartBisIn then self:StartBisIn() end -- minor 19: BiS> in's two events, registered once, here
    if self.StartVersions then self:StartVersions() end -- minor 18: who runs which version

    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        if event == "CHAT_MSG_ADDON" then
            lib:OnMessage(a1, a2, a3, a4)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            lib:OnRestrictionChanged()
        elseif event == "GUILD_ROSTER_UPDATE" then
            lib._guildDirty = true
        elseif event == "CONFIRM_SUMMON" then
            lib:OnConfirmSummon()
        elseif event == "CANCEL_SUMMON" then
            lib:OnCancelSummon()
        elseif event == "GROUP_ROSTER_UPDATE" then
            lib:OnRoster()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- login / reload: my table may be empty, say HI and let the short
            -- rule fill it
            lib:SendWhere(true)
            if not After(1 + math.random() * 2, function() lib:Hi() end) then lib:Hi() end
        else
            -- ZONE_CHANGED_NEW_AREA: a zone line is news about WHERE, not who
            -- I am; peers survive zoning (the blip rule), so no HI here
            lib:SendWhere(true)
        end
    end)

    -- Accept has no event of its own; the popup calls ConfirmSummon(). MINOR 6: on
    -- 2.5.6.69795 that is C_SummonInfo.ConfirmSummon - minor 5 looked only for the
    -- global, found nothing, and never saw an accept.
    -- MINOR 11: not on Forever. There a hooksecurefunc on a Blizzard object's method can
    -- start failing in Blizzard's own caller ("attempt to call a nil value") until the game
    -- is relaunched (Overlord 2.0 pulled all of its own, 11-12 Oct) - and the summon popup's
    -- Accept is the caller here. Forever is asked by interface number, as BiSTools' summon
    -- tool asks it (16000-19999; WOW_PROJECT_ID reads 1 on the beta). Its summon tool does
    -- not run there, so no accept is missed that anybody reads.
    local iface = GetBuildInfo and select(4, GetBuildInfo())
    lib.forever = type(iface) == "number" and iface >= 16000 and iface < 20000
    if lib.forever then
        -- no hook
    elseif hooksecurefunc and C_SummonInfo and C_SummonInfo.ConfirmSummon then
        hooksecurefunc(C_SummonInfo, "ConfirmSummon", function() lib:OnConfirmed() end)
    elseif hooksecurefunc and type(_G.ConfirmSummon) == "function" then
        hooksecurefunc("ConfirmSummon", function() lib:OnConfirmed() end)
    end
end

-- A zone-in reads the roster as EMPTY for a moment. Wiping the peer table on
-- that blip took Innervate's whole grid out for a night; wait 10s before
-- believing an empty group.
function lib:OnRoster()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 0 then
        -- HI only when *I* just arrived (0 -> n). Somebody else joining is his
        -- HI to say, and everyone short-answers it; a leave is a purge, not a
        -- conversation. Minor 2 said HI on every roster tick - 22 messages per
        -- join / leave / promote on a 25-man (raid25.lua).
        local arrived = (self._lastN or 0) == 0
        self._lastN, self._emptySince = n, nil
        self:PurgeAbsent()
        if arrived then
            if not After(1 + math.random() * 2, function() lib:Hi() end) then self:Hi() end
        end
        return
    end
    if (self._lastN or 0) == 0 then return end
    self._emptySince = self._emptySince or Now()
    if (Now() - self._emptySince) < 10 then return end
    self._lastN, self._emptySince = 0, nil
    self.peers = {}
    lib.peers = self.peers
end

--------------------------------------------------------------------
-- SPOT: where your guildmates are, for a map (minor 12)
--------------------------------------------------------------------
-- Arn, 14 Oct 2026: "what are the chances we can show all guild locations?" - the game hands an
-- addon the GROUP's positions only, so BiS clients share their own: "on by default but toggleable,
-- lets cascading small guild 15 sec as it get bigger maybe once a min" - and in the LIBRARY, so
-- every BiS addon shares and one switch rules them all ("or does it go in a library?").
--
--   SPOT|AT|uiMapID|x|y     x, y 0-1 on that zone map, three decimals; GUILD channel only
--
-- Sent only while you MOVE (past SPOT_STEP of the map since the last one), never inside an
-- instance or with a hidden position, at most every 15 s with up to 20 guildmates online, 30 s up
-- to 50, 60 s beyond. Received into lib.spots[name] = { map, x, y, at } and fired as "SPOT"; a spot
-- older than SPOT_STALE is a lie about where somebody is, and dropped. The lib has no SavedVariables:
-- each embedder remembers the switch (db.commShare) beside the comm switch, as it does /biscomm off.
lib.spots = lib.spots or {}
if lib.share == nil then lib.share = true end
lib.guildMods.SPOT = true
local SPOT_CHECK, SPOT_STEP, SPOT_STALE = 5, 0.012, 180
-- STANDING STILL STILL SHOWS (minor 13; Arn, 18 Oct: a guildmate standing in Undercity was gone from
-- the map - he had sent his spot once, then stood, and three minutes on every map dropped it as
-- stale). Still, the spot goes again every SPOT_RESEND - inside SPOT_STALE, so it never lapses.
local SPOT_RESEND = 120
lib.SPOT_CHECK, lib.SPOT_STEP, lib.SPOT_STALE, lib.SPOT_RESEND = SPOT_CHECK, SPOT_STEP, SPOT_STALE, SPOT_RESEND

local function plainNum(v)
    if v == nil or Secret(v) or type(v) ~= "number" then return nil end
    return v
end

function lib:Sharing() return self.share and true or false end
function lib:SetSharing(on)
    self.share = on and true or false
    if not self.share then self._spotSent = nil end
end

--- How often to send, by how many guildmates are online.
function lib:ShareEvery()
    local ok, _, online = pcall(GetNumGuildMembers)
    online = ok and plainNum(online) or 0
    if online <= 20 then return 15 elseif online <= 50 then return 30 end
    return 60
end

--- My spot on my zone map, or nil (an instance, a hidden position, no map).
function lib:MySpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    if IsInInstance then
        local ok, inside = pcall(IsInInstance)
        if not ok or Secret(inside) or inside then return nil end
    end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and plainNum(map) or nil
    if not map then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok2 or pos == nil or Secret(pos) then return nil end
    local ok3, x, y = pcall(function() return pos:GetXY() end)
    if not ok3 then return nil end
    x = plainNum(x)
    y = plainNum(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return map, x, y
end

--- One look (every SPOT_CHECK s): send my spot if I may and should. Answers what it did.
function lib:ShareTick()
    if not (self.enabled and self.share) then return "off" end
    if not (IsInGuild and IsInGuild()) then return "no guild" end
    local map, x, y = self:MySpot()
    if not map then return "hidden" end
    local s, now = self._spotSent, Now()
    if s and s.map == map and math.abs(s.x - x) < SPOT_STEP and math.abs(s.y - y) < SPOT_STEP
        and now - s.at < SPOT_RESEND then
        return "still"
    end
    if s and now - s.at < self:ShareEvery() then return "wait" end
    if not self:SendTo("GUILD", "SPOT", "AT", tostring(map), ("%.3f"):format(x), ("%.3f"):format(y)) then
        return "not sent"
    end
    self._spotSent = { map = map, x = x, y = y, at = now }
    return "sent"
end

--- Guildmates' spots, the stale ones dropped. name -> { map, x, y, at }
function lib:Spots()
    local now = Now()
    for name, s in pairs(self.spots) do
        if now - s.at > SPOT_STALE then self.spots[name] = nil end
    end
    return self.spots
end

-- a guildmate's spot (OnMessage already let in only a guild-roster sender, never my own echo)
lib.handlers.SPOT = lib.handlers.SPOT or {}
lib.handlers.SPOT.AT = function(sender, map, x, y)
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local s = { map = map, x = x, y = y, at = Now() }
    lib.spots[sender] = s
    fire("SPOT", sender, s)
end

function lib:StartSpots()
    if self._spotTicker or not (C_Timer and C_Timer.NewTicker) then return end
    self._spotTicker = C_Timer.NewTicker(SPOT_CHECK, function() lib:ShareTick() end)
end
-- a copy loading after the lib already booted (an upgrade in place) starts it here
if lib._booted then lib:StartSpots() end

--------------------------------------------------------------------
-- RIDE: when the zeppelins and boats dock - learned by riding, shared with the guild (minor 15)
--------------------------------------------------------------------
-- Arn, 21 Oct 2026: "the timer lives in the libraries, so somebody that has BiS Healing and leaves can start the
-- timer and someone that is not on the Zeppelin will get [it] ... their card will say I'm in Orgrimmar ...
-- Zeppelin just arrived, leaving for Undercity". Built first inside BiS Shell's ZEPPELIN.EXE, moved here so
-- ANY one BiS addon learns, shares, answers and shows it.
--
--   RIDE|AT|route|end|arrival|loop|seen|via    a ride docked at `end` at server time `arrival`
--   RIDE|ASK|route                             somebody arrived with no clock for that route
--
-- EVERY RIDE RUNS A FIXED LOOP and waits RIDE_DWELL at each end (the shape ForeverTransport taught - studied,
-- not copied), so one moment and the loop's length give every arrival at both ends: the far end is half a loop
-- on. HOW IT LEARNS, once a second and only on a map with a stop (or its capital, or while riding):
--   the departure - you were on a stop, now you are off it, CARRIED: your spot moved more than RIDE_CARRY map
--                   units a second while IsPlayerMoving says no (not falling, not on a flight)
--   a loading screen soon after a stop - you are on its ride (when it left: unknown)
--   the arrival   - riding, on the far end's stop. The loop = the ride twice + a dwell at each end; a later
--                   arrival refines it (whole loops between two arrivals, the time shared out)
-- Shared on GUILD and the group. A newer sighting replaces ours; nobody's is passed on again (no echo).
-- Arriving with no clock asks the guild once; one who knows answers after 1-5 s unless someone did first.
-- THE LIB STILL DRAWS NOTHING (Arn, 21 Oct: "everybody with the library does not show the clock by default.
-- BiS Tools enables the card and more options live in BiS Tools" - "the library still draws nothing"). It learns,
-- shares and answers: lib:RidesAt(map) for the rides from here, lib:RideSched(stop), lib:RideLine(stop, sched)
-- for the words, the "RIDE" callback on every new sighting. BiS Tools draws the card from these.
-- The lib has no SavedVariables: an embedder hands it a table (lib:RideStore(db.rides)) and the clock lives
-- there too; without one, the clock lasts the session and the guild fills it in.
-- UNVERIFIED in game: RIDE_CARRY (how fast a ride moves you on the map) and RIDE_DWELL (the long-known minute).

-- RIDE_FOR: no ride's leg is longer (the longest loops are ~8 min, a leg half that) - a "ride" older than this
-- is a hearth or a walk, and is forgotten: its far end reached later is NOT an arrival. RIDE_MIN_LEG: a ride seen
-- leaving cannot arrive sooner.
-- RIDE_CARRY / RIDE_STILL measured on Arn's rides (21 Oct, /biscomm ride): a zeppelin cruises at 0.5-0.6 map units a
-- second and starts at under 0.4; standing still reads 0.00. "Carried" also needs IsPlayerMoving to say no, so a
-- low line cannot mistake a run for a ride.
local RIDE_DWELL, RIDE_CARRY, RIDE_FOR, RIDE_AT_STOP, RIDE_MIN_LEG = 60, 0.2, 480, 120, 20
local RIDE_STILL = 0.08
local RIDE_CLOSER = 0.05                -- map units: less than this closer to the dock in a look = no longer closing in
local RIDE_REFINE = 0.3                 -- a later arrival may move the loop this much (a first ride was 18% off)
-- THE MEASURED LOOPS (21 Oct, Arn: "the timers are off again" - no zeppelin at the tower the card called docked).
-- A loop learned from one ride end to end was 7-51 s off (Org-UC 374 vs 356.3), and the error repeats every loop:
-- seven loops after the sighting the card was two minutes out. These are measured over many rides - the
-- NauticusClassic / NauticusClassicResurrected transport dataset (MIT, github.com/psynct/NauticusClassic,
-- github.com/sam-k-taylor/NauticusClassicResurrected), as ForeverTransport carries it; the Skycutter's is
-- ForeverTransport's own Forever measure. A known route keeps its loop whatever a ride or a guildmate says: a
-- sighting only moves WHEN it docks. Menethil-Auberdine is left out (Forever's route there is a triangle).
local RIDE_LOOP = {
  ["org_uc~uc_org"] = 356.29, ["gg_org~org_gg"] = 303.47, ["gg_uc~uc_gg"] = 335.30,
  ["bb~rat"] = 350.82, ["men_th~thera"] = 329.32, ["aub_rut~rut"] = 316.25, ["sky_mul~sky_zeph"] = 347,
  -- THE DEEPRUN TRAM (minor 17), measured on Forever by Arn's probe ridden there and back (23 Oct): 58.6 s a ride,
  -- 13 s at each end - one car's loop 2 x 58.6 + 2 x 13
  ["tram_if~tram_sw"] = 143.2,
}
lib.RIDE_LOOP = RIDE_LOOP
-- RIDE_AREA: map units round a stop's measured spot where its docked ride may sit (Arn's Skycutter: yards off it)
local RIDE_AREA = 4
local RIDE_ASK_EVERY, RIDE_STALE, RIDE_LOOK = 60, 6 * 3600, 1
lib.RIDE_DWELL, lib.RIDE_CARRY, lib.RIDE_LOOK = RIDE_DWELL, RIDE_CARRY, RIDE_LOOK
lib.guildMods.RIDE = true

-- THE STOPS: one platform or pier each - its map (uiMapID), its spot (0-100 on that map) and a radius in the
-- same units. A tower's two platforms are two stops of one `group`; `to` is the group its ride goes to.
-- MEASURED = Arn's probe in game (21 Oct); C = the zeppelin master's spot on Wowhead Classic; U = a dock pin from
-- the HandyNotes TravelGuide Classic data (no NPC stands on those piers). Forever may have moved the Classic ones.
lib.RIDE_STOPS = {
  { id = "sky_mul", group = "skywatch", name = "Skywatcher Plateau", map = 1412, x = 34.3, y = 25.7, r = 1.5,
    kind = "zeppelin", place = "dock", ship = "the Skycutter", to = "zephras", toName = "Zephras Isle",
    npc = 262502, who = "Skycutter Dockhand", face = "Dockhand", src = "MEASURED" },
  { id = "sky_zeph", group = "zephras", name = "Valanaar", map = 2521, x = 58.0, y = 80.5, r = 1.5,
    kind = "zeppelin", place = "dock", ship = "the Skycutter", to = "skywatch", toName = "Mulgore",
    npc = 275270, who = "Windshapers Dockmaster", face = "Dockmaster", src = "MEASURED" },
  -- MEASURED by Arn 21 Oct: Frezza (npc 9564, the Classic id and name) stands at 50.8 13.7; Snurk Bucksquick (12136)
  -- at 50.6 12.8, Classic's spot exactly. The place has no subzone name.
  { id = "org_uc", group = "orgtower", name = "Orgrimmar's zeppelin tower", map = 1411, x = 50.8, y = 13.7, r = 1.5,
    kind = "zeppelin", ship = "the Thundercaller", to = "uctower", toName = "Undercity",
    npc = 9564, who = "Frezza", src = "MEASURED" },
  { id = "org_gg", group = "orgtower", name = "Orgrimmar's zeppelin tower", map = 1411, x = 50.6, y = 12.8, r = 1.5,
    kind = "zeppelin", ship = "the Iron Eagle", to = "ggtower", toName = "Grom'gol",
    npc = 12136, who = "Snurk Bucksquick", face = "Snurk", src = "MEASURED" },
  -- MEASURED by Arn 21 Oct: Zapetta (9566) at 60.7 58.8, Hin Denburg (3150) at 61.8 59.1 - Classic's, held
  { id = "uc_org", group = "uctower", name = "Undercity's zeppelin tower", map = 1420, x = 60.7, y = 58.8, r = 1.5,
    kind = "zeppelin", ship = "the Thundercaller", to = "orgtower", toName = "Orgrimmar",
    npc = 9566, who = "Zapetta", src = "MEASURED" },
  { id = "uc_gg", group = "uctower", name = "Undercity's zeppelin tower", map = 1420, x = 61.8, y = 59.1, r = 1.5,
    kind = "zeppelin", ship = "the Purple Princess", to = "ggtower", toName = "Grom'gol",
    npc = 3150, who = "Hin Denburg", src = "MEASURED" },
  -- MEASURED by Arn 21 Oct: Nez'raz (3149) at 31.4 29.7, Squibby Overspeck (12137) at 31.6 29.0, the subzone
  -- "Grom'gol Base Camp" - Classic's spots, held
  { id = "gg_org", group = "ggtower", name = "Grom'gol's zeppelin tower", map = 1434, x = 31.4, y = 29.7, r = 1.5,
    kind = "zeppelin", ship = "the Iron Eagle", to = "orgtower", toName = "Orgrimmar",
    npc = 3149, who = "Nez'raz", src = "MEASURED" },
  { id = "gg_uc", group = "ggtower", name = "Grom'gol's zeppelin tower", map = 1434, x = 31.6, y = 29.0, r = 1.5,
    kind = "zeppelin", ship = "the Purple Princess", to = "uctower", toName = "Undercity",
    npc = 12137, who = "Squibby Overspeck", face = "Squibby", src = "MEASURED" },
  { id = "bb", group = "bootybay", name = "Booty Bay's pier", map = 1434, x = 25.9, y = 73.1, r = 1.5,
    kind = "boat", ship = "the Maiden's Fancy", to = "ratchet", toName = "Ratchet",
    npc = 4631, who = "Wharfmaster Lozgil", face = "Lozgil", src = "U" },
  -- MEASURED by Arn 21 Oct: Grimble <Shipmaster> (npc 9558) stands on the pier at 63.5 38.6, subzone "Ratchet" - the
  -- one who announces the boat
  { id = "rat", group = "ratchet", name = "Ratchet's pier", map = 1413, x = 63.5, y = 38.6, r = 1.5,
    kind = "boat", ship = "the Maiden's Fancy", to = "bootybay", toName = "Booty Bay",
    npc = 9558, who = "Grimble", src = "MEASURED" },
  { id = "men_th", group = "menethil_s", name = "Menethil Harbor", map = 1437, x = 5.0, y = 63.5, r = 1.5,
    kind = "boat", ship = "the Lady Mehley", to = "theramore", toName = "Theramore",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  { id = "men_aub", group = "menethil_n", name = "Menethil Harbor", map = 1437, x = 4.6, y = 57.1, r = 1.5,
    kind = "boat", ship = "the Bravery", to = "auberdine_s", toName = "Auberdine",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  { id = "thera", group = "theramore", name = "Theramore's pier", map = 1445, x = 71.6, y = 56.5, r = 1.5,
    kind = "boat", ship = "the Lady Mehley", to = "menethil_s", toName = "Menethil Harbor",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  { id = "aub_men", group = "auberdine_s", name = "Auberdine's pier", map = 1439, x = 32.4, y = 43.8, r = 1.5,
    kind = "boat", ship = "the Bravery", to = "menethil_n", toName = "Menethil Harbor",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  { id = "aub_rut", group = "auberdine_n", name = "Auberdine's pier", map = 1439, x = 33.2, y = 40.1, r = 1.5,
    kind = "boat", ship = "the Moonspray", to = "rutheran", toName = "Rut'theran Village",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  { id = "rut", group = "rutheran", name = "Rut'theran Village", map = 1438, x = 54.9, y = 96.8, r = 1.5,
    kind = "boat", ship = "the Moonspray", to = "auberdine_n", toName = "Auberdine",
    who = "The harbormaster", face = "Harbormaster", src = "U" },
  -- MEASURED by Arn 22 Oct (beta): FOREVER'S OWN - the Darkshore boat leaves from Stormwind's harbor, a route Classic
  -- never had. Idrieth Mossgrove (npc 276318) works the dock at 25.9 54.3, the ship lies at 22.6 56.0: the stop sits
  -- between, its radius reaching both. The Auberdine end and the ship's name: not measured yet.
  { id = "sw_aub", group = "stormwind", name = "Stormwind Harbor", map = 1453, x = 24.2, y = 55.2, r = 2.2,
    kind = "boat", to = "auberdine_s", toName = "Auberdine",
    npc = 276318, who = "Idrieth Mossgrove", face = "Idrieth", src = "MEASURED" },
  -- FOREVER'S OWN: TANARIS - THE RIVERGLADES (minor 20; Arn, 13 Nov, on the boat at Steamwheedle Port: "no card"). Arn
  -- stood at 68, 23 by Wharfmaster Steamfizzle (npc 260405); the Polestar codex (facts) has him at 67.6 23.1 and
  -- Wharfmaster Whizzbuzz (259961) at the Riverglades end, 79.4 53.1 on map 2548. P = that codex. The ship's name and
  -- its loop: not known yet - the clock learns the loop from the first ride seen.
  { id = "tan_rg", group = "steamwheedle", name = "Steamwheedle Port", map = 1446, x = 67.6, y = 23.1, r = 2.2,
    kind = "boat", to = "riverglades", toName = "the Riverglades",
    npc = 260405, who = "Wharfmaster Steamfizzle", face = "Steamfizzle", src = "P" },
  { id = "rg_tan", group = "riverglades", name = "the Riverglades' pier", map = 2548, x = 79.4, y = 53.1, r = 2.2,
    kind = "boat", to = "steamwheedle", toName = "Tanaris",
    npc = 259961, who = "Wharfmaster Whizzbuzz", face = "Whizzbuzz", src = "P" },
  -- THE DEEPRUN TRAM (minor 17; Arn, 23 Oct: "go ahead with the tram in the library"). No map in its zone (C_Map is
  -- nil the whole ride - measured), so its stops stand on lib.TRAM_MAP, and lib:RideSpot hands back your WORLD
  -- position there: along the track and across it, in tens of yards (UnitPosition: x -45.6 the whole ride, y 2471.3
  -- at Stormwind's platform to -12 at Ironforge's; 42.3 yd/s). The car stops 13 s (dwell); two cars run the line,
  -- half a loop apart (cars - UNVERIFIED, the web's "when one leaves Stormwind the other reaches Ironforge").
  { id = "tram_sw", group = "tramsw", name = "the Deeprun Tram, Stormwind", map = -369, x = 247.13, y = -4.0, r = 3,
    kind = "tram", to = "tramif", toName = "Ironforge", dwell = 13, cars = 2, src = "MEASURED" },
  { id = "tram_if", group = "tramif", name = "the Deeprun Tram, Ironforge", map = -369, x = -1.2, y = -4.0, r = 3,
    kind = "tram", to = "tramsw", toName = "Stormwind", dwell = 13, cars = 2,
    npc = 12997, who = "Monty", face = "Monty", src = "MEASURED" },
}
lib.TRAM_MAP, lib.TRAM_INSTANCE, lib.TRAM_ZONE = -369, 369, "Deeprun Tram"
-- A CAPITAL AND ITS ZONE (Arn: "their card will say I'm in Orgrimmar"): the towers stand on the zone's map, the
-- player stands in the city's - RidesAt answers a capital's rides too
lib.RIDE_CITY = { [1454] = 1411, [1456] = 1412, [1458] = 1420 }   -- Orgrimmar, Thunder Bluff, Undercity

lib.rideById, lib.ridePartner, lib.rideKeys, lib.rideMaps = {}, {}, {}, {}
for _, s in ipairs(lib.RIDE_STOPS) do lib.rideById[s.id] = s lib.rideMaps[s.map] = true end
for _, s in ipairs(lib.RIDE_STOPS) do
  for _, o in ipairs(lib.RIDE_STOPS) do
    if o.group == s.to and o.to == s.group then lib.ridePartner[s.id] = o end
  end
end

--- A route's name: its two ends' ids sorted and joined - the same from either end.
function lib:RideKey(s)
  if type(s) == "string" then s = self.rideById[s] end
  local o = s and self.ridePartner[s.id]
  if not o then return nil end
  local a, b = s.id, o.id
  if a > b then a, b = b, a end
  return a .. "~" .. b
end
for _, s in ipairs(lib.RIDE_STOPS) do local k = lib:RideKey(s) if k then lib.rideKeys[k] = true end end

lib.rides = lib.rides or {}            -- route -> { at, t, rtt, seen, by, via }
lib.rideStores = lib.rideStores or {}  -- the embedders' saved tables, every one kept in step

local function ServerNow()
  local t = GetServerTime and plainNum(GetServerTime())
  if t then return t end
  return math.floor(Now())
end
lib.RideNow = ServerNow

local function said(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or v == nil or Secret(v) then return nil end
  return v and true or false
end

--- An embedder's saved table: what it remembers comes in (the newer wins), and from now on every new sighting
--- is written there too.
function lib:RideStore(tbl)
  if type(tbl) ~= "table" then return nil end
  for _, s in ipairs(self.rideStores) do if s == tbl then return tbl end end
  self.rideStores[#self.rideStores + 1] = tbl
  for key, rec in pairs(tbl) do
    if type(rec) == "table" and self.rideKeys[key] then
      local mine = self.rides[key]
      if not mine or (rec.seen or 0) > (mine.seen or 0) then self.rides[key] = rec end
    end
  end
  for key, rec in pairs(self.rides) do tbl[key] = rec end
  return tbl
end

local function store(key, rec)
  lib.rides[key] = rec
  for _, t in ipairs(lib.rideStores) do t[key] = rec end
end

--- A route's loop: the measured one (RIDE_LOOP) where there is one, else what its record learned.
function lib:RideLoop(key, rec)
  return RIDE_LOOP[key] or (rec and rec.rtt)
end

--- When the ride docked at stop s by record rec: the far end is half a loop from the near one.
function lib:RideArrival(rec, s)
  if rec.at == s.id then return rec.t end
  local rtt = self:RideLoop(self:RideKey(s), rec)
  if not rtt then return nil end
  return rec.t + rtt / 2
end

--- The ride at stop s (a stop or its id) now: { docked, left, rtt, by, via, age } - left is the seconds to the
--- arrival, or while docked to the departure. nil while nobody has timed it.
function lib:RideSched(s, now)
  if type(s) == "string" then s = self.rideById[s] end
  local key = s and self:RideKey(s)
  local rec = key and self.rides[key]
  local rtt = self:RideLoop(key, rec)
  if not (rec and rtt and rec.t) then return nil end
  now = now or ServerNow()
  local A = self:RideArrival(rec, s)
  local D = s.dwell or RIDE_DWELL
  -- EVERY CAR (the tram has two, half a loop apart): each its own phase; the stop sees the one docked, else the next in
  local cars, best = {}, nil
  for c = 0, (s.cars or 1) - 1 do
    local phase = (now - A - c * rtt / (s.cars or 1)) % rtt
    local docked = phase < D
    local car = { docked = docked, left = docked and (D - phase) or (rtt - phase), phase = phase }
    cars[#cars + 1] = car
    if not best or (car.docked and not best.docked) or (car.docked == best.docked and car.left < best.left) then best = car end
  end
  return { docked = best.docked, left = best.left, rtt = rtt, dwell = D, cars = #cars > 1 and cars or nil,
           by = rec.by, via = rec.via, age = now - (rec.seen or rec.t) }
end

--- HOW SURE (minor 17 - moved here from BiS Tools' ride card so every addon says the same number; Arn, 22 Oct:
--- "a confidence % the longer its been since a reading the less confidence its correct"). 0-100: the chance the
--- countdown is still within RIDE_SURE_WITHIN seconds - a bell curve as wide as a reading's error and the loop's
--- error times the laps since; a measured loop drifts slower than a learned one; past RIDE_STALE (a server restart
--- resets every ride, and the client cannot tell us one happened) 0. nil with nothing to judge by.
lib.RIDE_SURE_WITHIN, lib.RIDE_READ_ERR, lib.RIDE_LAP_ERR = 10, 2, { measured = 1, learned = 4 }
local function erf(x)                          -- Abramowitz and Stegun 7.1.26: good to 1.5e-7
  local sg = x < 0 and -1 or 1
  x = math.abs(x)
  local t = 1 / (1 + 0.3275911 * x)
  local p = ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
  return sg * (1 - p * math.exp(-x * x))
end
function lib:RideSure(sched, s)
  if not (sched and type(sched.rtt) == "number" and sched.rtt > 0 and type(sched.age) == "number") then return nil end
  if sched.age > RIDE_STALE then return 0 end
  if type(s) == "string" then s = self.rideById[s] end
  local measured = s and RIDE_LOOP[self:RideKey(s) or ""] ~= nil
  local drift = math.max(0, sched.age) / sched.rtt * (measured and self.RIDE_LAP_ERR.measured or self.RIDE_LAP_ERR.learned)
  local width = math.sqrt(self.RIDE_READ_ERR ^ 2 + drift ^ 2)
  return math.floor(100 * erf(self.RIDE_SURE_WITHIN / (width * math.sqrt(2))) + 0.5)
end

--- Every stop on a map (a capital counts as its zone), each with its ride now: { { stop, sched }, ... }.
function lib:RidesAt(map, now)
  local out = {}
  map = self.RIDE_CITY[map] or map
  for _, s in ipairs(self.RIDE_STOPS) do
    if s.map == map then out[#out + 1] = { stop = s, sched = self:RideSched(s, now) } end
  end
  return out
end

--- A record fit to keep: a route we know, one of its ends, times this side of a fortnight, a sane loop.
function lib:RideSane(key, at, t, rtt, seen)
  if not (key and self.rideKeys[key] and at and self.rideById[at] and self:RideKey(at) == key) then return false end
  local now = ServerNow()
  if type(t) ~= "number" or math.abs(t - now) > 14 * 86400 then return false end
  if type(seen) ~= "number" or seen > now + 300 or now - seen > 14 * 86400 then return false end
  if rtt ~= nil and (type(rtt) ~= "number" or rtt < 120 or rtt > 1200) then return false end
  return true
end

--- Keep a record if it is newer than ours. by: who saw it (nil = you: then it is shared).
function lib:RideSet(key, at, t, rtt, seen, by, via)
  if not self:RideSane(key, at, t, rtt, seen) then return false end
  local old = self.rides[key]
  if old and (old.seen or 0) >= seen - 1 then return false end
  local mine = by == nil
  store(key, { at = at, t = t, rtt = rtt or (old and old.rtt), seen = seen,
               by = by or PlayerName() or "you", via = via or (mine and self:RideVia()) or nil })
  if mine then self:RideShare(key) end
  fire("RIDE", key, self.rides[key])
  return true
end

--- One of my addons, for "timed by Chain - BiS Healing" (the first registered, by name).
function lib:RideVia()
  local names = {}
  for name in pairs(self.addons) do names[#names + 1] = name end
  table.sort(names)
  return names[1]
end

--- The ride docked at stop s at time t; est: the loop from a ride seen end to end (or nil).
function lib:RideLearn(s, t, est)
  local key = self:RideKey(s)
  if not key then return nil end
  local old = self.rides[key]
  local rtt = old and old.rtt
  -- A RIDE SEEN END TO END (est) is the measure: it replaces a kept loop however far off that was (Arn's first rides
  -- saved one two minutes short). An arrival some loops after a kept one refines the loop - the whole loops between
  -- them, the time shared out - only when it agrees with the best guess to within RIDE_REFINE.
  local guess = RIDE_LOOP[key] or est or rtt
  if guess and old and old.rtt and not RIDE_LOOP[key] then
    local A0 = self:RideArrival(old, s)
    local n = A0 and math.floor((t - A0) / guess + 0.5) or 0
    if n >= 1 then
      local r2 = (t - A0) / n
      if math.abs(r2 - guess) < RIDE_REFINE * guess then guess = r2 end
    end
  end
  rtt = guess
  self:RideSet(key, s.id, t, rtt and math.floor(rtt * 10 + 0.5) / 10 or nil, ServerNow(), nil)
  return self.rides[key]
end

--- The stop I am on, by my spot on this map (0-100), or nil - the nearer one at a tower's two platforms.
function lib:RideStopAt(map, x, y)
  local best, bd
  for _, s in ipairs(self.RIDE_STOPS) do
    if s.map == map then
      local d = math.sqrt((s.x - x) ^ 2 + (s.y - y) ^ 2)
      if d <= s.r and (not bd or d < bd) then best, bd = s, d end
    end
  end
  return best
end

--- The nearest stop on this map within `within` map units of my spot, and how far.
function lib:RideNear(map, x, y, within)
  local best, bd
  for _, s in ipairs(self.RIDE_STOPS) do
    if s.map == map then
      local d = math.sqrt((s.x - x) ^ 2 + (s.y - y) ^ 2)
      if d <= within and (not bd or d < bd) then best, bd = s, d end
    end
  end
  return best, bd
end

-- THE RIDE LOG (/biscomm ride): the last RIDE_TRACE looks, so a ride the clock missed says why (Arn's first ride
-- of the Skycutter, 21 Oct, learned nothing - and nothing told us what it had seen)
local RIDE_TRACE = 300               -- about five minutes of looks: a whole leg of a ride
local function trace(line)
  local t = lib._rideTrace
  t[#t + 1] = line
  if #t > RIDE_TRACE then table.remove(t, 1) end
end
lib._rideTrace = lib._rideTrace or {}

--- One look. AS RIDDEN (Arn, 21 Oct - the first rule learned nothing): you walk off the dock's spot onto the ship,
--- wait aboard yards away, and are carried off from THERE; the ship docks yards from the far spot. So:
---   the departure: CARRIED (moving more than RIDE_CARRY map units a second while IsPlayerMoving says no) and moving
---                  AWAY from a stop you were near (RIDE_AREA) within the last RIDE_AT_STOP seconds
---   the arrival:   riding, near the far end's stop, and NOT carried any more - it has stopped
--- LEAN: on a dock it asks for the map, the spot and the time; your feet and a flight only when you move fast.
function lib:RideLook()
  local map, x, y = self:RideSpot()
  if not map then return nil end
  local clock = Now()
  local inside = x and self:RideStopAt(map, x, y) or nil
  local near, nd = nil, nil
  if x then near, nd = self:RideNear(map, x, y, RIDE_AREA) end
  local prev = self._ridePrev
  local feet = said(IsPlayerMoving)
  self._ridePrev = { m = map, x = x, y = y, stop = inside, clock = clock, feet = feet }
  local speed, carried, measured = 0, false, false
  if prev and prev.m == map and x and prev.x then
    measured = true                                        -- two looks on one map: a speed (else nothing is known)
    local dt = math.max(0.2, clock - (prev.clock or clock))
    speed = math.sqrt((x - prev.x) ^ 2 + (y - prev.y) ^ 2) / dt
    -- still on BOTH looks (Arn's Ghost Wolf, 21 Oct: a run that stops just before a look moved the second before
    -- while IsPlayerMoving already says no - "carried" at the foot of the tower, a false departure)
    if speed >= RIDE_CARRY then
      carried = feet == false and prev.feet == false and not said(IsFalling) and not said(UnitOnTaxi, "player")
    end
  end
  local last, lastAt = self._rideLast, self._rideLastAt
  if near then self._rideLast, self._rideLastAt = near, clock end
  local stillBefore = self._rideStillAt                    -- the last look standing still, before this one
  if measured and speed < RIDE_STILL then self._rideStillAt = clock end
  local riding = self.riding
  if riding and clock - riding.t0 > RIDE_FOR then self.riding, riding = nil, nil end
  local said_
  if riding then
    local long = clock - riding.t0
    -- DOCKED = IT STOPPED GETTING CLOSER (Arn's log, 21 Oct: a docked zeppelin bobs - "speed 0.21" standing still -
    -- so "truly still" came up to 30 s late): near the far end, the distance to its stop no longer shrinking, or
    -- truly still
    local closing = near and near.group == riding.from.to and nd or nil
    local stopped = measured and (speed < RIDE_STILL
      or (closing and riding.lastD and closing >= riding.lastD - RIDE_CLOSER))
    if closing then riding.lastD = closing end
    if closing and stopped and not (riding.dep and long < RIDE_MIN_LEG)
       and not said(UnitOnTaxi, "player") then
      self.riding = nil
      local now = ServerNow()
      local est = riding.dep and (2 * (now - riding.dep) + 2 * (near.dwell or RIDE_DWELL)) or nil
      self:RideLearn(near, now, est)
      said_ = "arrived " .. near.id
    elseif inside and inside.group ~= riding.from.group and inside.group ~= riding.from.to then
      self.riding = nil                                    -- somewhere else entirely: not that ride
      said_ = "not that ride"
    end
  elseif carried and last and lastAt and clock - lastAt <= RIDE_AT_STOP and last.map == map and x and prev and prev.x then
    -- carried AWAY from the stop (a ship coming in to a dock is carried TOWARD it - not a departure)
    local before = math.sqrt((last.x - prev.x) ^ 2 + (last.y - prev.y) ^ 2)
    local after = math.sqrt((last.x - x) ^ 2 + (last.y - y) ^ 2)
    if after > before then
      -- it left when you last stood still (a zeppelin creeps off before it is fast enough to count as carried)
      local now = ServerNow()
      local lag = (stillBefore and clock - stillBefore <= RIDE_AT_STOP) and math.floor(clock - stillBefore + 0.5) or 0
      local dep = now - lag
      self.riding = { from = last, dep = dep, t0 = clock - lag }
      self:RideLearn(last, dep - (last.dwell or RIDE_DWELL))
      said_ = "departed " .. last.id .. (lag > 0 and (" (" .. lag .. " s ago)") or "")
    end
  end
  trace(("%d map %d %s %s speed %.2f%s%s%s"):format(math.floor(clock), map, near and near.id or "-",
    nd and ("%.1f"):format(nd) or "-", speed, carried and " carried" or "", self.riding and " riding" or "",
    said_ and (" - " .. said_) or ""))
  if inside and not (prev and prev.stop == inside) then self:RideAsk(inside) end   -- just arrived: no clock? ask
  return said_ and said_:match("^(%a+)") or (inside and "on" or "off")
end

--- My map and my spot on it, 0-100 (x, y nil where the client will not say).
function lib:RideSpot()
  local ok, map = false, nil
  if C_Map and C_Map.GetBestMapForUnit then ok, map = pcall(C_Map.GetBestMapForUnit, "player") end
  map = ok and plainNum(map) or nil
  if not map then return self:TramSpot() end
  if not (C_Map.GetPlayerMapPosition) then return map end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or pos == nil or Secret(pos) then return map end
  local ok3, x, y = pcall(function() return pos:GetXY() end)
  if not ok3 then return map end
  x = plainNum(x)
  y = plainNum(y)
  if not (x and y) then return map end
  return map, x * 100, y * 100
end

--- In the Deeprun Tram? Its instance id (GetInstanceInfo's 8th answer), or its name in any of the client's three
--- zone answers (Arn's first try, 23 Oct: the instance id alone missed it once).
function lib:InTram()
  if GetInstanceInfo then
    local ok, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if ok and plainNum(id) == self.TRAM_INSTANCE then return true end
  end
  for _, fn in ipairs({ GetRealZoneText or false, GetZoneText or false, GetMinimapZoneText or false }) do
    if fn then
      local ok, z = pcall(fn)
      if ok and type(z) == "string" and not Secret(z) and z:find(self.TRAM_ZONE, 1, true) then return true end
    end
  end
  return false
end

--- Your spot in the tram, as RideSpot gives it there: lib.TRAM_MAP, then along the track and across it in tens of
--- yards (UnitPosition's second and first answers - the order Arn's probe printed them in). nil anywhere else.
function lib:TramSpot()
  if not (UnitPosition and self:InTram()) then return nil end
  local ok, across, along = pcall(UnitPosition, "player")
  if not ok then return self.TRAM_MAP end
  across = plainNum(across)
  along = plainNum(along)
  if not (across and along) then return self.TRAM_MAP end
  return self.TRAM_MAP, along / 10, across / 10
end

--- A loading screen: soon after a stop, I am on its ride (when it left: unknown).
function lib:RideLeaving()
  if not self.riding and self._rideLast and Now() - (self._rideLastAt or 0) <= RIDE_AT_STOP then
    self.riding = { from = self._rideLast, t0 = Now() }
    trace(("%d loading screen - riding from %s"):format(math.floor(Now()), self._rideLast.id))
  end
  return self.riding
end

function lib:RideShare(key)
  local rec = self.rides[key]
  if not (rec and self.enabled) then return false end
  local a = self:SendTo("GUILD", "RIDE", "AT", key, rec.at, tostring(rec.t), rec.rtt and tostring(rec.rtt) or "",
                        tostring(rec.seen), rec.via or "")
  local b = self:Send("RIDE", "AT", key, rec.at, tostring(rec.t), rec.rtt and tostring(rec.rtt) or "",
                      tostring(rec.seen), rec.via or "")
  return a or b
end

--- On a stop with no clock (or an old one): ask the guild, once a minute a route at most.
function lib:RideAsk(s)
  local key = self:RideKey(s)
  if not (key and self.enabled) then return false end
  local rec = self.rides[key]
  local now = ServerNow()
  if rec and rec.rtt and now - (rec.seen or 0) < RIDE_STALE then return false end
  self._rideAsked = self._rideAsked or {}
  if self._rideAsked[key] and now - self._rideAsked[key] < RIDE_ASK_EVERY then return false end
  self._rideAsked[key] = now
  return self:SendTo("GUILD", "RIDE", "ASK", key)
end

lib._rideHeard = lib._rideHeard or {}
lib.handlers.RIDE = lib.handlers.RIDE or {}
lib.handlers.RIDE.AT = function(sender, key, at, t, rtt, seen, via)
  t, seen = tonumber(t), tonumber(seen)
  rtt = (rtt and rtt ~= "") and tonumber(rtt) or nil
  lib._rideHeard[key or ""] = ServerNow()
  return lib:RideSet(key, at, t, rtt, seen, sender, (via and via ~= "") and via or nil)
end
-- somebody asks: answer after a short random wait, unless somebody else answers first
lib.handlers.RIDE.ASK = function(sender, key)
  local rec = key and lib.rides[key]
  if not (rec and rec.rtt) then return false end
  local asked = ServerNow()
  local function answer()
    if (lib._rideHeard[key] or 0) >= asked then return end
    lib:RideShare(key)
  end
  if not After(1 + math.random() * 4, answer) then answer() end
  return true
end

--------------------------------------------------------------------
-- the watch: once a second, only where a ride is (its map or its capital) or while riding
--------------------------------------------------------------------

function lib:RideWanted()
  if self.riding then return true end
  if self:InTram() then return true end                    -- the tram has no map: its own question (minor 17)
  local ok, map = pcall(C_Map and C_Map.GetBestMapForUnit or function() end, "player")
  map = ok and plainNum(map) or nil
  if not map then return false end
  return self.rideMaps[map] or self.RIDE_CITY[map] ~= nil
end

function lib:RideRewatch()
  local f = self._rideFrame
  if not f then return nil end
  local on = self.enabled and self:RideWanted()
  if on and not self._rideWatching then
    self._rideWatching, self._rideIn = true, 0
    f:SetScript("OnUpdate", function(_, elapsed)
      lib._rideIn = (lib._rideIn or 0) - (tonumber(elapsed) or 0)
      if lib._rideIn > 0 then return end
      lib._rideIn = RIDE_LOOK
      lib:RideLook()
    end)
  elseif not on and self._rideWatching then
    self._rideWatching = nil
    f:SetScript("OnUpdate", nil)
  end
  return self._rideWatching
end

function lib:StartRides()
  if self._rideFrame or not CreateFrame then return end
  local f = CreateFrame("Frame")
  self._rideFrame = f
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
                        "ZONE_CHANGED_INDOORS" }) do
    pcall(f.RegisterEvent, f, ev)
  end
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then lib:RideLeaving() return end
    lib:RideRewatch()
  end)
end
if lib._booted then lib:StartRides() end

--------------------------------------------------------------------
-- words for a ride (the lib draws nothing: BiS Tools' card and BiS Shell's game say these)
--------------------------------------------------------------------

local function clock(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
lib.RideClock = clock

--- One ride in words: "Zeppelin to Undercity - arrives in 3:10", "... - here now, leaves in 0:45".
function lib:RideLine(s, sc)
  if type(s) == "string" then s = self.rideById[s] end
  if not s then return nil end
  local what = (s.kind == "zeppelin" and "Zeppelin" or s.kind == "tram" and "Tram" or "Boat") .. " to " .. tostring(s.toName)
  if not sc then return what .. " - not timed yet" end
  if sc.docked then return what .. " - here now, leaves in " .. clock(sc.left) end
  return what .. " - arrives in " .. clock(sc.left)
end

--------------------------------------------------------------------
-- BiS> in: asking for Innervate, Power Infusion, Mana Tide (minor 17)
--------------------------------------------------------------------
-- Arn, 22 Oct 2026 (docs/bisin.md, the plan): "a mage can ask for an innervate ... as long as they have an addon
-- installed the mages can turn /bisin on and they opt in and a druid /bisin on and they opt in and now the druid sees
-- all the people that opt in and who ever he clicks the druid cast innervate on them ... all this is api so ideally we
-- dont have to make them install bishealing". TBC's BiS Innervate did it (REQ / CLAIM / CANCEL); this is Forever's.
-- The lib says and remembers; it draws nothing - the buttons are BiSTheme's shared Ask piece (step 2).
--
--   OPT|on|give|ask|class|cds   I'm in (on 1/0); the spells I give ("innervate,pi"); I ask (1/0); my class;
--                               my cooldowns ("innervate:<readyAt>,..."). Said on /bisin, to a new group member, and
--                               back to anyone new who says it - so a late joiner learns who is in.
--   CD|spell|readyAt            my spell is ready again at readyAt (server time); 0 = now. Said when I cast it.
--   REQ|id|spell                I ask. Over by CANCEL, by the spell landing, or BISIN_TTL later on its own.
--   CLAIM|id|at                 mine, casting - sent on the click. The FIRST claim wins everywhere: the earliest at,
--                               the lower name on a tie - so two druids clicking at once agree who has it.
--   CANCEL|id|why               the ask is over.
--
-- Group channel only, from someone in the group (OnMessage's guards). Off is deaf: an opted-out client keeps nothing.
-- Mana Tide reaches the shaman's own PARTY only, so in a raid it counts only his subgroup's asks and givers.
lib.BISIN = lib.BISIN or {
    innervate = { id = 29166, class = "DRUID",   cd = 360, target = true },
    pi        = { id = 10060, class = "PRIEST",  cd = 180, target = true },
    tide      = { id = 16190, class = "SHAMAN",  cd = 300, target = false, party = true },
}
lib.BISIN_ORDER = { "innervate", "pi", "tide" }
-- who asks: the classes with mana (Arn: "healers and casters only ... never warriors or rogues")
lib.BISIN_MANA = { MAGE = true, WARLOCK = true, DRUID = true, HUNTER = true, PRIEST = true, SHAMAN = true, PALADIN = true }
lib.BISIN_TTL, lib.BISIN_SAY_GAP = 30, 2
do
    local B = lib.BISIN
    local function state()
        local s = lib.bisin
        if not s then
            s = { on = false, give = {}, ask = false, class = nil, cd = {}, peers = {}, reqs = {}, n = 0, told = {} }
            lib.bisin = s
        end
        return s
    end
    lib.BisInState = state

    local function ServerNow2()
        if GetServerTime then
            local ok, t = pcall(GetServerTime)
            if ok and not Secret(t) and type(t) == "number" then return t end
        end
        return math.floor(Now())
    end

    local function myClass()
        if not UnitClass then return nil end
        local ok, _, file = pcall(UnitClass, "player")
        if not ok or Secret(file) or type(file) ~= "string" then return nil end
        return file
    end

    local function knows(id)
        local f = IsPlayerSpell or IsSpellKnown
        if not f then return false end
        local ok, v = pcall(f, id)
        return ok and not Secret(v) and v == true
    end

    local function list(set)
        local out = {}
        for _, k in ipairs(lib.BISIN_ORDER) do if set[k] then out[#out + 1] = k end end
        return table.concat(out, ",")
    end
    local function unlist(s)
        local set = {}
        for k in tostring(s or ""):gmatch("[^,]+") do if B[k] then set[k] = true end end
        return set
    end

    --- The OPT line's fields for me.
    local function optFields()
        local s = state()
        local cds = {}
        for k, t in pairs(s.cd) do if B[k] and t > ServerNow2() then cds[#cds + 1] = k .. ":" .. t end end
        table.sort(cds)
        return s.on and "1" or "0", list(s.give), s.ask and "1" or "0", s.class or "", table.concat(cds, ",")
    end

    local function sayOpt()
        local s = state()
        s.saidAt = Now()
        return lib:Send("IN", "OPT", optFields())
    end

    --- /bisin on|off. On: my part from my class and spells (a druid who knows Innervate gives it; every class with
    --- mana asks); `opts` may set give / ask by hand (a UI's choices). Off: deaf, and the others are told.
    function lib:BisInSet(on, opts)
        local s = state()
        s.on = on and true or false
        s.class = myClass()
        s.give, s.ask = {}, false
        if s.on then
            for k, sp in pairs(B) do
                if s.class == sp.class and knows(sp.id) then s.give[k] = true end
            end
            s.ask = s.class ~= nil and lib.BISIN_MANA[s.class] == true
            if type(opts) == "table" then
                if type(opts.give) == "table" then s.give = {} for k, v in pairs(opts.give) do if B[k] and v then s.give[k] = true end end end
                if opts.ask ~= nil then s.ask = opts.ask and true or false end
            end
        else
            s.peers, s.reqs = {}, {}
        end
        lib:BisInWatch()
        sayOpt()
        fire("BISIN", "me")
        return s.on
    end

    function lib:BisInMe()
        local s = state()
        return { on = s.on, give = s.give, ask = s.ask, class = s.class }
    end

    --- Is this group member in my party (a raid's subgroup)? Out of a raid, everyone is.
    local function sameParty(name)
        if not (IsInRaid and IsInRaid()) then return true end
        if not GetRaidRosterInfo then return true end
        local mine, theirs
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        local me = PlayerName()
        for i = 1, n do
            local ok, rn, _, sub = pcall(GetRaidRosterInfo, i)
            if ok and not Secret(rn) and type(rn) == "string" then
                rn = Short(rn)
                if rn == me or First(rn) == First(me) and not rn:find(" ", 1, true) then mine = sub end
                if rn == name or (First(rn) == First(name) and not rn:find(" ", 1, true)) then theirs = sub end
            end
        end
        return mine ~= nil and mine == theirs
    end

    --- Who gives this spell, in the group: ready now, the soonest ready-at of the rest, and the givers' names.
    function lib:BisInReady(spell)
        local s, sp = state(), B[spell]
        if not (s.on and sp) then return 0, nil, {} end
        local now, ready, soonest, givers = ServerNow2(), 0, nil, {}
        for name, p in pairs(s.peers) do
            if p.on and p.give[spell] and (not sp.party or sameParty(name)) then
                givers[#givers + 1] = name
                local at = p.cd[spell] or 0
                if at <= now then ready = ready + 1
                elseif not soonest or at < soonest then soonest = at end
            end
        end
        table.sort(givers)
        return ready, (ready == 0) and soonest or nil, givers
    end

    --- The faces a giver sees: the mana users who opted in to ask, never me. { name, class }, by name.
    function lib:BisInAskers()
        local s, out = state(), {}
        if not s.on then return out end
        for name, p in pairs(s.peers) do
            if p.on and p.ask then out[#out + 1] = { name = name, class = p.class } end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    local function expire()
        local s, now = state(), Now()
        for id, r in pairs(s.reqs) do
            if now - r.at > lib.BISIN_TTL then s.reqs[id] = nil end
        end
    end

    function lib:BisInRequest(id)
        expire()
        return state().reqs[id]
    end

    --- The open asks for a spell I give: unclaimed, not mine; Mana Tide only from my party.
    function lib:BisInRequests(spell)
        expire()
        local s, out = state(), {}
        if not (s.on and s.give[spell]) then return out end
        for _, r in pairs(s.reqs) do
            if r.spell == spell and not r.claim and r.owner ~= PlayerName()
               and (not B[spell].party or sameParty(r.owner)) then
                out[#out + 1] = r
            end
        end
        table.sort(out, function(a, b) return a.at < b.at end)
        return out
    end

    --- I ask: a request id, or nil and why (nobody gives it here, I'm not in, I have no mana).
    function lib:BisInAsk(spell)
        local s = state()
        if not s.on then return nil, "off" end
        if not s.ask then return nil, "nothing to ask" end
        local _, _, givers = self:BisInReady(spell)
        if #givers == 0 then return nil, "nobody gives it here" end
        s.n = s.n + 1
        local id = (PlayerName() or "?"):gsub("%s", "") .. "-" .. ServerNow2() .. "-" .. s.n
        s.reqs[id] = { id = id, owner = PlayerName(), spell = spell, at = Now() }
        self:Send("IN", "REQ", id, spell)
        fire("BISIN", "ask", s.reqs[id])
        self:BisInWatch()
        return id
    end

    -- the first claim wins everywhere: the earlier at, the lower name on a tie
    local function better(a, b)
        if not b then return true end
        if a.at ~= b.at then return a.at < b.at end
        return a.by < b.by
    end

    --- The giver's click: mine, casting.
    function lib:BisInClaim(id)
        local s = state()
        local r = self:BisInRequest(id)
        if not (s.on and r) then return false end
        local c = { by = PlayerName(), at = ServerNow2() }
        if better(c, r.claim) then r.claim = c end
        self:Send("IN", "CLAIM", id, tostring(c.at))
        fire("BISIN", "claim", r)
        return r.claim.by == c.by
    end

    --- The asker takes it back (or the spell landed).
    function lib:BisInCancel(id, why)
        local s = state()
        local r = s.reqs[id]
        if not r then return false end
        s.reqs[id] = nil
        if r.owner == PlayerName() then self:Send("IN", "CANCEL", id, why or "taken back") end
        fire("BISIN", "end", r)
        return true
    end

    --- My own cast of a spell I give: its cooldown, to the group.
    function lib:BisInCast(spellId)
        local s = state()
        if not s.on or Secret(spellId) then return nil end
        for k, sp in pairs(B) do
            if sp.id == spellId and s.give[k] then
                s.cd[k] = ServerNow2() + sp.cd
                self:Send("IN", "CD", k, tostring(s.cd[k]))
                fire("BISIN", "cd", k)
                return k
            end
        end
        return nil
    end

    -- the messages ---------------------------------------------------
    local H = {}
    function H.OPT(sender, on, give, ask, class, cds)
        local s = state()
        if not s.on then return end
        local known = s.peers[sender] ~= nil
        if on ~= "1" then
            s.peers[sender] = nil
            fire("BISIN", "roster")
            return
        end
        local p = { on = true, give = unlist(give), ask = ask == "1", class = class ~= "" and class or nil, cd = {} }
        for k, t in tostring(cds or ""):gmatch("([%a]+):(%d+)") do if B[k] then p.cd[k] = tonumber(t) end end
        s.peers[sender] = p
        fire("BISIN", "roster")
        -- SOMEONE NEW LEARNS ME BACK - always, whatever I said before: what I said then may have reached them while
        -- they were still out, and off is deaf. A burst of new faces (a raid opting in at once) shares one reply.
        if not known and not s.replying then
            s.replying = true
            local function reply() s.replying = nil sayOpt() end
            if not After(0.3 + math.random() * 0.7, reply) then reply() end
        end
    end
    function H.CD(sender, spell, at)
        local s = state()
        local p = s.on and s.peers[sender]
        if not (p and B[spell]) then return end
        p.cd[spell] = tonumber(at) or 0
        fire("BISIN", "cd", spell, sender)
    end
    function H.REQ(sender, id, spell)
        local s = state()
        if not (s.on and B[spell] and type(id) == "string" and id ~= "") then return end
        s.reqs[id] = s.reqs[id] or { id = id, owner = sender, spell = spell, at = Now() }
        fire("BISIN", "ask", s.reqs[id])
    end
    function H.CLAIM(sender, id, at)
        local s = state()
        local r = s.on and s.reqs[id]
        if not r then return end
        local c = { by = sender, at = tonumber(at) or ServerNow2() }
        if better(c, r.claim) then r.claim = c fire("BISIN", "claim", r) end
    end
    function H.CANCEL(sender, id)
        local s = state()
        local r = s.on and s.reqs[id]
        if not (r and r.owner == sender) then return end
        s.reqs[id] = nil
        fire("BISIN", "end", r)
    end
    for cmd, fn in pairs(H) do lib:RegisterHandler("IN", cmd, fn) end

    -- a new group member hears who is in (the lib's PEER is the first line from them)
    lib.callbacks.PEER = lib.callbacks.PEER or {}
    if not lib._bisinPeerHook then
        lib._bisinPeerHook = true
        table.insert(lib.callbacks.PEER, function()
            local s = lib.bisin
            if s and s.on and Now() - (s.saidAt or -999) >= lib.BISIN_SAY_GAP then
                if not After(0.5 + math.random(), function() sayOpt() end) then sayOpt() end
            end
        end)
    end

    --- My own asks that are still open.
    local function mine()
        expire()
        local s, me, out = state(), PlayerName(), {}
        for _, r in pairs(s.reqs) do if r.owner == me then out[#out + 1] = r end end
        return out
    end

    --- My own open ask for a spell (the asker's button: "asked" / "Arn is coming"), or nil.
    function lib:BisInMine(spell)
        for _, r in ipairs(mine()) do if r.spell == spell then return r end end
        return nil
    end

    --- The spell landed on me: my ask for it is over (UNIT_AURA, only while I have one open). Asked "hidden?" first -
    --- in a lockdown auras go secret, and then BISIN_TTL ends it instead.
    function lib:BisInLanded()
        local got = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        if not got then return 0 end
        local n = 0
        for _, r in ipairs(mine()) do
            local ok, aura = pcall(got, B[r.spell].id)
            if ok and aura ~= nil and not Secret(aura) then
                self:BisInCancel(r.id, "got it")
                n = n + 1
            end
        end
        self:BisInWatch()
        return n
    end

    -- minor 19 (13 Nov 2026, a player's gamepad): both events registered ONCE, at load (lib:StartBisIn), and the
    -- handler asks lib._bisinWant. This used to register/unregister them as asks opened and closed - from timers too
    -- (an ask running out) - and Forever refuses (un)registering from a timer while the gamepad UI is on: the
    -- "blocked from an action only available to the Blizzard UI" dialog, naming whichever BiS addon's copy won.
    function lib:StartBisIn()
        if not CreateFrame then return end
        local f = self._bisinFrame or CreateFrame("Frame")
        self._bisinFrame = f
        self._bisinWant = self._bisinWant or {}
        if not f._all then
            for _, ev in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA" }) do
                if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, ev, "player") else pcall(f.RegisterEvent, f, ev) end
            end
            f._all = true
        end
        f:SetScript("OnEvent", function(_, event, unit, _, spellId)
            if unit ~= "player" then return end
            local w = lib._bisinWant
            if event == "UNIT_AURA" then
                if w.aura then lib:BisInLanded() end
            elseif w.cast then
                lib:BisInCast(spellId)
            end
        end)
    end

    -- my casts while I give something; my buffs while I have an ask open - nothing else, nothing while out
    function lib:BisInWatch()
        local s = state()
        local w = self._bisinWant or {}
        self._bisinWant = w
        w.cast = (s.on and next(s.give) ~= nil) and true or false
        w.aura = (s.on and #mine() > 0) and true or false
    end
end

--------------------------------------------------------------------
-- FOJJI: show up in FojjiCore's Experience and Campfires windows (minor 16)
--------------------------------------------------------------------
-- Arn, 21 Oct 2026, the stress test: his cousin, running only BiS addons, read "No Addon" in FojjiCore's party
-- Experience window - "fojji does this thing where it shares exp and campfire stuff to party can our addon
-- broadcast the same thing so they pick it up". In the LIB (his pick), so anyone with any BiS addon shows up.
--
-- FojjiCore_DungeonJournal's Levelling.lua (read 21 Oct) speaks two plain lines of its own:
--   FOJJI_GXP_V1  X1;level;xp;max     the group channel, and GUILD at most every max(30, min(300, online / 2)) s;
--                                      "Q1" on the group channel = say yours (it never answers one on GUILD)
--   FojjiCamp1    S6;cooldown;campfire;tools;slot1;slot2;slot3;slot4;;known;buffDur;buffEnd    group only;
--                                      "R" = say yours
-- Its receivers check every field (whole numbers in range, exactly 12 fields), so a line it does not take is
-- ignored - never an error on anybody's screen. We SAY ours and answer its asks; we never read anyone's.
-- QUIET when FojjiCore_DungeonJournal is loaded here (it says the same - never twice), at the level cap (it
-- stops there), with /biscomm off, in a chat lockdown, and for any number the client hides.
-- The group channel is the one FojjiCore listens on: INSTANCE_CHAT in a dungeon-finder group, else RAID, else PARTY.
do
    local FJ_XP, FJ_CAMP = "FOJJI_GXP_V1", "FojjiCamp1"
    local FJ_BUFF, FJ_CD, FJ_ASK_GAP = 1229741, 3600, 5
    local FJ_FIRES = { 279982, 279974, 279961, 279981 }
    -- the profession tools in FojjiCore's order: item n is bit n-1 of the tools mask, and a profession's place in
    -- this list is its number on the wire (1-11) - THE ORDER IS THE PROTOCOL. { skill line, tool items }
    local FJ_PROFS = {
        { 171, { 279956, 279970, 279990 } },             -- Alchemy
        { 164, { 279944, 279988, 279955 } },             -- Blacksmithing
        { 333, { 279976, 279985, 279987 } },             -- Enchanting
        { 202, { 279950, 279949, 279989 } },             -- Engineering
        { 182, { 279962, 279964, 279947 } },             -- Herbalism
        { 165, { 279978, 279941, 279945 } },             -- Leatherworking
        { 186, { 279960, 279948, 279952 } },             -- Mining
        { 393, { 279979, 279969, 279938 } },             -- Skinning
        { 197, { 279972, 279973, 279943, 279959 } },     -- Tailoring
        { 129, { 279968, 279940, 279951 } },             -- First Aid (always the third slot)
        { 356, { 279967, 279965, 279966 } },             -- Fishing (always the fourth)
    }
    local FJ_ITEMS, FJ_SKILL = {}, {}
    for i, p in ipairs(FJ_PROFS) do
        FJ_SKILL[p[1]] = i
        for _, id in ipairs(p[2]) do FJ_ITEMS[#FJ_ITEMS + 1] = id end
    end
    lib.FJ_XP, lib.FJ_CAMP, lib.FJ_ITEMS = FJ_XP, FJ_CAMP, FJ_ITEMS

    local function state()
        local s = lib._fj
        if not s then
            s = { lastSent = {}, lastAt = {}, pending = {}, asked = {}, soon = {}, camp = nil, useSpells = nil }
            lib._fj = s
        end
        return s
    end

    local function ask(fn, ...)
        if not fn then return nil end
        local ok, v = pcall(fn, ...)
        if not ok or Secret(v) then return nil end
        return v
    end

    -- after a short wait, once however many times it is asked meanwhile (events come in bursts)
    local function soon(key, delay, fn)
        local s = state()
        if s.soon[key] then return end
        s.soon[key] = true
        if not After(delay, function() s.soon[key] = nil fn() end) then s.soon[key] = nil fn() end
    end

    local function send(prefix, msg, chan)
        local f = C_ChatInfo and C_ChatInfo.SendAddonMessage
        if not f then return false end
        local ok, r = pcall(f, prefix, msg, chan)
        if not ok then return false end
        local kind = ResultKind(r)
        if kind ~= "sent" then
            lib.refusedCount = (lib.refusedCount or 0) + 1
            return false, kind
        end
        lib.sentCount = (lib.sentCount or 0) + 1
        return true
    end

    --- The group channel FojjiCore listens on, or nil alone.
    function lib:FojjiChannel()
        if ask(IsInGroup, LE_PARTY_CATEGORY_INSTANCE or 2) == true then return "INSTANCE_CHAT" end
        if ask(IsInRaid) == true then return "RAID" end
        if ask(IsInGroup) == true then return "PARTY" end
        return nil
    end

    --- Why we say nothing now, or nil.
    function lib:FojjiQuiet()
        if not self.enabled then return "comm off" end
        if ChatLocked() then return "chat lockdown" end
        if C_AddOns and ask(C_AddOns.IsAddOnLoaded, "FojjiCore_DungeonJournal") == true then return "FojjiCore here" end
        local level = plainNum(ask(UnitLevel, "player"))
        if not level then return "no level" end
        if level >= (plainNum(ask(GetMaxPlayerLevel)) or 60) then return "level cap" end
        return nil
    end

    --- "X1;level;xp;max", or nil when any of them is hidden.
    function lib:FojjiXPLine()
        local level = plainNum(ask(UnitLevel, "player"))
        local have, need = plainNum(ask(UnitXP, "player")), plainNum(ask(UnitXPMax, "player"))
        if not (level and have and need) or level < 1 or have < 0 or have > need then return nil end
        return ("X1;%d;%d;%d"):format(level, have, need)
    end

    local function gap(ch)
        if ch ~= "GUILD" then return 0.5 end
        local ok, _, o = pcall(GetNumGuildMembers)
        local online = ok and plainNum(o) or 0
        return math.max(30, math.min(300, online * 0.5))
    end

    --- My experience, to the group channel and the guild (or `only` one), when it changed or `force`.
    function lib:FojjiSendXP(force, only)
        if self:FojjiQuiet() then return "quiet" end
        local msg = self:FojjiXPLine()
        if not msg then return "hidden" end
        local s, now, chans = state(), Now(), {}
        local group = self:FojjiChannel()
        if group then chans[#chans + 1] = group end
        if ask(IsInGuild) == true then chans[#chans + 1] = "GUILD" end
        for _, ch in ipairs(chans) do
            if (not only or only == ch) and (force or s.lastSent[ch] ~= msg) then
                local wait = gap(ch) - (now - (s.lastAt[ch] or -999))
                if force or wait <= 0 then
                    local sent, why = send(FJ_XP, msg, ch)
                    if sent then
                        s.lastSent[ch], s.lastAt[ch] = msg, now
                    elseif why == "again" and not s.pending[ch] then
                        -- about one line a second per prefix (measured): the group's line took the second, so the
                        -- guild's goes in the next one - FojjiCore's own two sends in a row lose the second
                        s.pending[ch] = true
                        After(1.1, function() s.pending[ch] = nil lib:FojjiSendXP(force, ch) end)
                    end
                elseif not s.pending[ch] then
                    -- held: when the wait is over, the NEWEST number goes
                    s.pending[ch] = true
                    After(wait + 0.1, function() s.pending[ch] = nil lib:FojjiSendXP(false, ch) end)
                end
            end
        end
        return "ok"
    end

    -- the campfire: what is in the bags, the professions, the buff (each looked at only when it may have changed)
    local function camp()
        local s = state()
        if not s.camp then
            s.camp = { expires = 0, campfire = 0, mask = 0, slots = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } } }
        end
        return s.camp
    end

    function lib:FojjiScanItems()
        local d = camp()
        local count = C_Item and C_Item.GetItemCount
        d.mask, d.campfire = 0, 0
        if not count then return d end
        for i, id in ipairs(FJ_ITEMS) do
            if (plainNum(ask(count, id, false, false, false, false)) or 0) > 0 then d.mask = d.mask + 2 ^ (i - 1) end
        end
        for _, id in ipairs(FJ_FIRES) do
            if (plainNum(ask(count, id, false, false, false, false)) or 0) > 0 then d.campfire = id break end
        end
        return d
    end

    -- two main professions, then First Aid in the third slot and Fishing in the fourth (FojjiCore's own order)
    function lib:FojjiScanSkills()
        local d = camp()
        d.slots = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
        if not (GetProfessions and GetProfessionInfo) then return d end
        local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        if not ok then return d end
        local primary = 0
        for _, idx in ipairs({ p1 or false, p2 or false, p3 or false, p4 or false, p5 or false, p6 or false }) do
            if idx and not Secret(idx) then
                local okI, _, _, skill, _, _, _, line = pcall(GetProfessionInfo, idx)
                local cat = okI and not Secret(line) and FJ_SKILL[line]
                skill = okI and plainNum(skill) or 0
                if cat then
                    local slot
                    if cat == 10 then slot = 3 elseif cat == 11 then slot = 4
                    elseif primary < 2 then primary = primary + 1 slot = primary end
                    if slot then d.slots[slot] = { cat, math.max(0, math.min(1000, math.floor(skill))) } end
                end
            end
        end
        return d
    end

    -- the campfire's buff; not in a fight or a lockdown (auras go secret there) - then the last look stands
    function lib:FojjiScanBuff()
        local d = camp()
        if ask(InCombatLockdown) == true then return false end
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and ask(C_Secrets.ShouldAurasBeSecret) ~= false then return false end
        if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
        local ok, buff = pcall(C_UnitAuras.GetPlayerAuraBySpellID, FJ_BUFF)
        if not ok or Secret(buff) then return false end
        local dur, fin = 0, 0
        if type(buff) == "table" then
            local du, ex = plainNum(buff.duration), plainNum(buff.expirationTime)
            local now = plainNum(ask(GetServerTime))
            if du and ex and now and du > 0 then
                dur = math.floor(du + 0.5)
                fin = now + math.floor(math.max(0, ex - Now()) + 0.5)
            end
        end
        if d.known and d.buffDur == dur and math.abs((d.buffEnd or 0) - fin) <= 1 then return false end
        d.known, d.buffDur, d.buffEnd = true, dur, fin
        return true
    end

    function lib:FojjiCampLine()
        local s, d = state(), camp()
        if not s.scanned then
            s.scanned = true
            self:FojjiScanItems() self:FojjiScanSkills() self:FojjiScanBuff()
        end
        local f = { "S6", ("%.0f"):format(d.expires or 0), tostring(d.campfire or 0), ("%.0f"):format(d.mask or 0) }
        for _, slot in ipairs(d.slots) do f[#f + 1] = slot[1] .. ":" .. slot[2] end
        f[#f + 1] = ""
        f[#f + 1] = d.known and "1" or "0"
        f[#f + 1] = ("%.0f"):format(d.buffDur or 0)
        f[#f + 1] = ("%.0f"):format(d.buffEnd or 0)
        return table.concat(f, ";")
    end

    --- My campfire line to the group (never the guild), when it changed or `force`.
    function lib:FojjiSendCamp(force)
        if self:FojjiQuiet() then return "quiet" end
        local ch = self:FojjiChannel()
        if not ch then return "alone" end
        local s, msg = state(), self:FojjiCampLine()
        if not force and msg == s.campSent then return "same" end
        local sent, why = send(FJ_CAMP, msg, ch)
        if sent then
            s.campSent = msg
        elseif why == "again" and not s.campRetry then
            s.campRetry = true
            After(1.1, function() s.campRetry = nil lib:FojjiSendCamp(force) end)
        end
        return "ok"
    end

    -- a profession tool used: the hour's cooldown starts (its use spells learnt once, from the items)
    function lib:FojjiCast(spell)
        if ask(InCombatLockdown) == true then return end
        spell = plainNum(spell)
        if not spell then return end
        local s = state()
        if not s.useSpells and C_Item and C_Item.GetItemSpell then
            s.useSpells = {}
            for _, id in ipairs(FJ_ITEMS) do
                local ok, _, sp = pcall(C_Item.GetItemSpell, id)
                if ok and plainNum(sp) then s.useSpells[sp] = true end
            end
        end
        if not (s.useSpells and s.useSpells[spell]) then return end
        local now = plainNum(ask(GetServerTime))
        if not now then return end
        camp().expires = now + FJ_CD
        self:FojjiSendCamp(true)
    end

    --- FojjiCore asks ("Q1" / "R"), on the group channel: answered once per FJ_ASK_GAP, after a jitter.
    function lib:FojjiHeard(prefix, msg, channel, sender)
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then return end
        if prefix ~= FJ_XP and prefix ~= FJ_CAMP then return end
        if not self.enabled or channel == "GUILD" or channel ~= self:FojjiChannel() then return end
        if Short(sender) == Short(ask(UnitName, "player")) then return end
        local s, now = state(), Now()
        local what = (prefix == FJ_XP and msg == "Q1") and "xp" or (prefix == FJ_CAMP and msg == "R") and "camp" or nil
        if not what or now - (s.asked[what] or -999) < FJ_ASK_GAP then return end
        s.asked[what] = now
        local function answer()
            if what == "xp" then lib:FojjiSendXP(true, channel) else lib:FojjiSendCamp(true) end
        end
        if not After(0.2 + math.random() * 0.6, answer) then answer() end
    end

    -- in a group: listen to the bags, the professions, the buff and the casts; alone, not at all.
    -- minor 19 (13 Nov 2026): registered ONCE in StartFojji (load time) and gated by lib._fjGrouped in the handler.
    -- FojjiGrouped used to (un)register them from the roster timer - refused by Forever while the gamepad UI is on.
    local GROUP_EVENTS = { "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED" }
    local GROUP_UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }
    local GROUP_ONLY = { BAG_UPDATE_DELAYED = true, SKILL_LINES_CHANGED = true, PLAYER_REGEN_ENABLED = true,
                         UNIT_AURA = true, UNIT_SPELLCAST_SUCCEEDED = true }
    function lib:FojjiGrouped(on)
        if not self._fjFrame or (self._fjGrouped or false) == on then return end
        self._fjGrouped = on
    end

    function lib:FojjiRoster()
        local ch = self:FojjiChannel()
        local joined = ch and not self._fjGrouped
        self:FojjiGrouped(ch and true or false)
        if joined then
            -- just arrived: both lines once, the way FojjiCore says hello
            soon("joined", 0.5 + math.random(), function()
                local now = lib:FojjiChannel()
                if not now then return end
                lib:FojjiSendXP(true, now)
                state().scanned = nil
                lib:FojjiSendCamp(true)
            end)
        end
    end

    function lib:StartFojji()
        if not CreateFrame then return end
        -- an older copy (minor 16-18) may have made the frame already: this one, loading after it (still load
        -- time), adds the group events once and takes over the handler
        local f = self._fjFrame
        if f and f._all then return end
        if not f then
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
                pcall(C_ChatInfo.RegisterAddonMessagePrefix, FJ_XP)
                pcall(C_ChatInfo.RegisterAddonMessagePrefix, FJ_CAMP)
            end
            f = CreateFrame("Frame")
            self._fjFrame = f
            for _, ev in ipairs({ "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
                                  "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }) do
                pcall(f.RegisterEvent, f, ev)
            end
        end
        for _, ev in ipairs(GROUP_EVENTS) do pcall(f.RegisterEvent, f, ev) end
        for _, ev in ipairs(GROUP_UNIT_EVENTS) do
            if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, ev, "player") else pcall(f.RegisterEvent, f, ev) end
        end
        f._all = true
        f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
            if GROUP_ONLY[event] and not lib._fjGrouped then return end    -- alone: heard, not acted on
            if event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
                lib:FojjiHeard(a1, a2, a3, a4)
            elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                soon("roster", 0.5, function() lib:FojjiRoster() end)
            elseif event == "PLAYER_XP_UPDATE" then
                soon("xp", 0.5, function() lib:FojjiSendXP(false) end)
            elseif event == "PLAYER_LEVEL_UP" then
                soon("level", 1, function() lib:FojjiSendXP(true) end)
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if a1 == "player" then lib:FojjiCast(a3) end
            elseif event == "UNIT_AURA" then
                soon("buff", 1, function() if lib:FojjiScanBuff() then lib:FojjiSendCamp(false) end end)
            elseif event == "BAG_UPDATE_DELAYED" then
                soon("bags", 1, function() lib:FojjiScanItems() lib:FojjiSendCamp(false) end)
            elseif event == "SKILL_LINES_CHANGED" then
                soon("skills", 1, function() lib:FojjiScanSkills() lib:FojjiSendCamp(false) end)
            elseif event == "PLAYER_REGEN_ENABLED" then
                soon("fight", 4, function() if lib:FojjiScanBuff() then lib:FojjiSendCamp(false) end end)
            end
        end)
    end
end
if lib._booted then lib:StartFojji() end
if lib._booted then lib:StartBisIn() end

--------------------------------------------------------------------
-- VER (minor 18): who runs which version - listed, and said only when it is critical
--------------------------------------------------------------------
-- Arn, 6 Nov 2026: "we should build it for our addons but only listing and we only alert for big critical updates
-- or compatibility, i only really pay attention to the gargul or rclc before raid otherwise i ignore them" - and
-- "yes with guild". An addon can never reach the internet; a newer version is known only because somebody near you
-- runs it. So every BiS client says what it runs - once after login (VER_FIRST), on the GUILD and the group - and
-- whoever runs something NEWER than a late arrival answers it, after a random wait, the first answer silencing the
-- rest (a guild of forty logging in is not forty times forty). Nothing ticks.
lib.vers = lib.vers or {}             -- sender -> { addons = {name = ver}, crit = {name = ver}, minor, compat, at }
lib.versNewest = lib.versNewest or {} -- addon -> { ver, who } - the newest seen anywhere
lib.versCrit = lib.versCrit or {}     -- addon -> the highest version anyone has marked critical
lib.versTold = lib.versTold or {}     -- addon (or "_compat") -> said this session
lib.VER_FIRST, lib.VER_GAP = 15, 300  -- seconds after login; the least gap between my own unasked lines
lib.VER_WAIT = { 2, 10 }              -- an answer's random wait, seconds
-- the oldest lib minor that can still talk to this one: a guildmate's says it, and ours below theirs is the only
-- compatibility notice. 1 = every BiS lib so far.
lib.COMPAT_MIN = 1

local function verMeta(addon, key)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(get) ~= "function" or type(addon) ~= "string" then return nil end
    local ok, v = pcall(get, addon, key)
    if not ok or Secret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function verParse(blob)
    local t = {}
    for entry in string.gmatch(tostring(blob or ""), "([^,]+)") do
        local n, v = string.match(entry, "^(.-)=(.*)$")
        if n and n ~= "" and v and v ~= "" then t[n] = v end
    end
    return t
end

local function verBlob(t)
    local out = {}
    for n, v in pairs(t) do out[#out + 1] = n .. "=" .. v end
    table.sort(out)
    return table.concat(out, ",")
end

--- The criticals this client knows: its own addons' TOC marks, and any heard - passed on, so the word spreads even
--- while the one who marked it is offline.
function lib:CritKnown()
    local t = {}
    for n, v in pairs(self.versCrit) do t[n] = v end
    for n in pairs(self.addons) do
        local c = verMeta(n, "X-BiS-Critical")
        if c and (not t[n] or lib.VersionGT(c, t[n])) then t[n] = c end
    end
    return t
end

function lib:VersionLine()
    return self.MINOR, self:AddonsBlob(), verBlob(self:CritKnown()), self.COMPAT_MIN
end

--- Say what I run on the GUILD. Unasked, at most once a VER_GAP; `answer` = a late arrival needs it. The group is
--- never sent this: it already has every version from HI (_VersionsFromPeer), and a group that stands still must
--- cost nothing (raid25.lua: "zero messages in 600 s of nobody moving").
function lib:SendVersions(answer)
    local now = Now()
    if not answer and self._verAt and now - self._verAt < self.VER_GAP then return false end
    self._verAt = now
    if not (IsInGuild and IsInGuild()) then return false end
    return self:SendTo("GUILD", "VER", "HAVE", self:VersionLine())
end

--- A group member's versions come with their HI (CORE already carries every addon and version) - read, never asked
--- again: a roster tick that changes nothing must cost nothing (raid25.lua holds that).
function lib:_VersionsFromPeer(name, pr)
    for n, v in pairs((pr and pr.addons) or {}) do
        local nw = self.versNewest[n]
        if v ~= "?" and (not nw or lib.VersionGT(v, nw.ver)) then self.versNewest[n] = { ver = v, who = name } end
    end
end

--- What a line from `sender` teaches me, and whether I know better than them (they need an answer).
function lib:_OnVersions(sender, minor, blob, crit, compat)
    local r = { addons = verParse(blob), crit = verParse(crit), minor = tonumber(minor or "") or 0,
                compat = tonumber(compat or "") or 0, at = Now() }
    self.vers[sender] = r
    for n, v in pairs(r.addons) do
        local nw = self.versNewest[n]
        if not nw or lib.VersionGT(v, nw.ver) then self.versNewest[n] = { ver = v, who = sender } end
    end
    for n, c in pairs(r.crit) do
        if not self.versCrit[n] or lib.VersionGT(c, self.versCrit[n]) then self.versCrit[n] = c end
    end
    -- what I could teach them: a newer version of something they run, or a critical they have not heard
    local teach = {}
    local known = self:CritKnown()
    for n, v in pairs(r.addons) do
        local mine = self.addons[n]
        if mine and lib.VersionGT(mine, v) then teach[n] = mine end
        local c = known[n]
        if c and lib.VersionGT(c, v) and not (r.crit[n] and not lib.VersionGT(c, r.crit[n])) then teach[n] = teach[n] or c end
    end
    -- someone else's line may already carry what I was waiting to say: that part is no longer mine to say
    if self._verTeach then
        for n, v in pairs(self._verTeach) do
            local theirs = r.addons[n]
            if theirs and not lib.VersionGT(v, theirs) then self._verTeach[n] = nil end
        end
    end
    if next(teach) then
        if not self._verTeach then
            self._verTeach = teach
            local w = self.VER_WAIT
            local wait = w[1] + math.random() * (w[2] - w[1])
            local function answer()
                local left = self._verTeach
                self._verTeach = nil
                if left and next(left) then self:SendVersions(true) end
            end
            if not After(wait, answer) then answer() end
        else
            for n, v in pairs(teach) do self._verTeach[n] = self._verTeach[n] or v end
        end
    end
    self:CheckVersions()
    fire("VERSIONS", sender, r)
end

--- The only words this lib ever says unasked: below a critical release, or too old to talk to a guildmate's lib.
--- Once a session each; in a fight they wait for it to end.
function lib:CheckVersions()
    local say = {}
    for n, mine in pairs(self.addons) do
        local c = self.versCrit[n]
        if c and lib.VersionGT(c, mine) and not self.versTold[n] then say[#say + 1] = { n, c, mine } end
    end
    local compatWho
    if not self.versTold._compat then
        for who, r in pairs(self.vers) do if (r.compat or 0) > self.MINOR then compatWho = who end end
    end
    if #say == 0 and not compatWho then return false end
    if InCombatLockdown and InCombatLockdown() then
        if not self._verHeld then
            self._verHeld = true
            local function again() self._verHeld = nil self:CheckVersions() end
            After(5, again)
        end
        return false
    end
    local function line(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb980ffBiS|r " .. s) end end
    table.sort(say, function(a, b) return a[1] < b[1] end)
    for _, s in ipairs(say) do
        self.versTold[s[1]] = true
        line(("%s %s is a critical update (you have %s) - update it on CurseForge, then /reload."):format(s[1], s[2], s[3]))
    end
    if compatWho then
        self.versTold._compat = true
        line(("your BiS addons' shared channel is too old to talk to %s's - update any BiS addon on CurseForge, then /reload.")
            :format(compatWho))
    end
    return true
end

--- The list: every BiS addon you run or anyone around runs - yours, the newest seen and who has it, the critical
--- mark, how many run it. Sorted by name.
function lib:Versions()
    local names = {}
    for n in pairs(self.addons) do names[n] = true end
    for n in pairs(self.versNewest) do names[n] = true end
    local known = self:CritKnown()
    local out = {}
    for n in pairs(names) do
        local mine, nw = self.addons[n], self.versNewest[n]
        local newest, who = mine, mine and "you" or nil
        if nw and (not mine or lib.VersionGT(nw.ver, mine)) then newest, who = nw.ver, nw.who end
        local runs = mine and 1 or 0
        for _, r in pairs(self.vers) do if r.addons[n] then runs = runs + 1 end end
        out[#out + 1] = { addon = n, mine = mine, newest = newest, who = who, critical = known[n], runs = runs }
    end
    table.sort(out, function(a, b) return a.addon < b.addon end)
    return out
end

function lib:StartVersions()
    if self._verStarted then return end
    self._verStarted = true
    self:RegisterGuildMod("VER")
    self:RegisterHandler("VER", "HAVE", function(sender, ...) lib:_OnVersions(sender, ...) end)
    self:RegisterCallback("PEER", function(name, pr) lib:_VersionsFromPeer(name, pr) end)
    local first = self.VER_FIRST + math.random() * 10
    local function hello() lib:SendVersions() end
    if not After(first, hello) then hello() end
end
if lib._booted then lib:StartVersions() end

--------------------------------------------------------------------
-- the one slash: status and the honest off switch
--------------------------------------------------------------------

-- Always (re)set, even over an older copy's handler: minor 3 took "/bis", which
-- LoonBestInSlot also owns, so the newest copy must move the slash to /biscomm.
if SlashCmdList then
    _G.SLASH_BISCOMM1 = "/biscomm"
    SlashCmdList["BISCOMM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local say = function(s)
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb980ffBiS|r " .. s) end
        end
        if msg == "comm off" or msg == "off" then
            lib:SetEnabled(false); say("comm off - silent and deaf until /biscomm on")
        elseif msg == "comm on" or msg == "on" then
            lib:SetEnabled(true); lib:Hi(); say("comm on")
        elseif msg == "share off" then
            lib:SetSharing(false); say("share off - your guild no longer sees where you are on their map")
        elseif msg == "ride" then
            -- the ride log: what the clock's last looks saw (a ride it missed says why)
            -- the moments that matter (carried, a departure, an arrival, a loading screen), then the last few looks
            local t = lib._rideTrace or {}
            say(("ride log (%d looks kept): time, map, nearest stop, distance, speed"):format(#t))
            local shown = 0
            for i = 1, math.max(0, #t - 8) do
                if shown < 24 and (t[i]:find("carried", 1, true) or t[i]:find(" - ", 1, true)
                                   or t[i]:find("loading", 1, true)) then
                    say("  " .. t[i]) shown = shown + 1
                end
            end
            say("  ...the last looks:")
            for i = math.max(1, #t - 7), #t do say("  " .. t[i]) end
        elseif msg == "share on" then
            lib:SetSharing(true); say("share on - your guild sees where you are on their map (while you move, outside instances)")
        elseif msg == "ver" or msg == "versions" then
            -- minor 18: who runs which BiS addon, from the guild and the group (nothing is fetched - this is what
            -- the people around you said)
            local list = lib.Versions and lib:Versions() or {}
            say(("BiS addons around you (%d):"):format(#list))
            for _, e in ipairs(list) do
                local mine = e.mine and ("you " .. e.mine) or "you: not installed"
                local newest = (e.newest and e.who ~= "you") and ("   newest " .. e.newest .. " (" .. tostring(e.who) .. ")") or ""
                local crit = e.critical and ("   critical " .. e.critical) or ""
                say(("  %s   %s%s%s   - %d run it"):format(e.addon, mine, newest, crit, e.runs or 0))
            end
        else
            say(("comm %s, share %s, lib %d, %d peer(s), running %s")
                :format(lib:Enabled() and "on" or "off", lib:Sharing() and "on" or "off", lib.MINOR, lib:Count(),
                        lib:AddonsBlob() ~= "" and lib:AddonsBlob() or "nothing"))
            -- what left and what did not (minor 13: the night "sent 0" took four /run lines to see)
            local timed = 0
            for _ in pairs(lib.rides or {}) do timed = timed + 1 end
            say(("rides timed: %d%s"):format(timed, lib.riding and (" - riding from " .. lib.riding.from.name) or ""))
            local quiet = lib.FojjiQuiet and lib:FojjiQuiet()
            say("FojjiCore's windows: " .. (quiet and ("quiet (" .. quiet .. ")") or "your experience and campfire are shared"))
            local bi = lib.bisin
            if bi and bi.on then
                local g = {}
                for _, k in ipairs(lib.BISIN_ORDER) do if bi.give[k] then g[#g + 1] = k end end
                local n = 0
                for _ in pairs(bi.peers) do n = n + 1 end
                say(("BiS> in: on - you give %s%s; %d in the group opted in"):format(#g > 0 and table.concat(g, ", ") or "nothing",
                    bi.ask and ", you ask" or "", n))
            else
                say("BiS> in: off")
            end
            say(("sent %d, refused %d, waiting %d%s%s"):format(lib.sentCount or 0, lib.refusedCount or 0,
                #(lib.outbox or {}), lib._lastError and (", last trouble: " .. lib._lastError) or "",
                OutgoingBlocked() and " (the realm says restricted - Forever always does; ignored)" or ""))
            say("/biscomm on | off  -  /biscomm share on | off  -  /biscomm ride (the ride clock's log)  -  /biscomm ver (who runs what)")
        end
    end
end

return lib
