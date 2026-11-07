--[[
  BiSGuild :: Core/Invite.lua - invites from the terminal, and the ROSTER page.

  Arn, 16 Oct 2026: "It'll plug into or use its own invite to raid module like BiS Tools", and "there
  are raid tools on discord and someone can import a code to build a roster and one click invites
  them to the raid team".

  PLUG IN FIRST, THROUGH ITS API. BiS Tools' party tool already does this well, and Arn shaped it
  (15 Oct): whole Forever names, a confirm list sorted by class with an x per person, the little
  "inviting..." box, refusals in red. When BiS Tools is installed and its party tool on, a list goes
  to BiSToolsAPI.InviteList (Arn: "I like OpenMap, that opens its stuff via API ... if installed it
  can API-call it" - never its insides). Without it - "bisg can do its own thing if no BiS Tools" -
  a second click within I.ARM seconds is the confirm, then one invite every I.GAP seconds.

  A ROSTER IS WHATEVER WAS PASTED. Discord raid tools export in their own shapes - a list, a table,
  "1. Name - Class", a CSV with a header. So the reader does not trust a format: it splits the text
  into pieces (lines, commas, tabs), throws away the words every roster has (classes, roles, "bench",
  headers), and looks for guild members' names in what is left - the first name is enough, Forever's
  whole "Name Surname" wins when both words are there. A piece naming nobody in the guild is shown
  as "not in guild" with its first plausible word, and is NOT invited: a Discord nickname is not a
  character name, and inviting a stranger by a guess is worse than leaving the line for a human.
]]
local ADDON, ns = ...
local K = ns.K

local I = {}
ns.Inv = I

I.GAP = 0.25            -- seconds between two of our own invites (BiS Tools paces its own)
I.ARM = 5               -- seconds the "click again to send" stays armed
I.MAX = 39              -- a raid, less you

local function Key(name) return K.NameKey(name) end

--------------------------------------------------------------------
-- who is with me
--------------------------------------------------------------------

--- Who is with me, by first name AND by whole name (members are filed whole since 16 Oct - the three
--- Nebeons - and the client may name a group member either way).
function I.Here()
    local here = {}
    local function add(name)
        if type(name) ~= "string" then return end
        here[Key(name)] = true
        here[(name:match("^([^%-]+)") or name):lower()] = true
    end
    add(UnitName and UnitName("player"))
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        local ok, name = pcall(UnitName, unit)
        if ok then add(name) end
    end
    return here
end

--- Is this member with me? By whole name, or by first name when the client named them that way.
function I.IsHere(here, m)
    if not m then return false end
    if m.key and here[m.key] then return true end
    return m.name ~= nil and here[Key(m.name)] == true
end

function I.Leads()
    if not (IsInGroup and IsInGroup()) then return true end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    return false
end

--------------------------------------------------------------------
-- reading a pasted roster
--------------------------------------------------------------------

I.SKIP = {}
for w in ([[name names class classes role roles spec specs tank tanks heal heals healer healers dps damage
    melee ranged caster casters support bench benched late absent tentative signed confirmed accepted
    declined maybe yes no raid team group party sign signup signups list roster player players character
    characters main alt alts discord the and or of in on at
    warrior warriors paladin paladins hunter hunters rogue rogues priest priests shaman shamans mage mages
    warlock warlocks druid druids protection prot holy disc discipline shadow restoration resto balance
    feral guardian arms fury retribution ret enhancement enh elemental ele arcane fire frost affliction
    demonology destruction beast marksmanship survival assassination combat subtlety]]):gmatch("%S+") do
    I.SKIP[w] = true
end

--- The plausible name words of a piece of text: letters (any alphabet's bytes), at least two long,
--- not a word every roster carries.
function I.Words(piece)
    local out = {}
    for w in piece:gmatch("[%a\128-\255']+") do
        if #w >= 2 and not I.SKIP[w:lower()] then out[#out + 1] = w end
    end
    return out
end

--- RAID-HELPER'S EXPORT (Arn pasted one, 16 Oct): JSON, with a "signUps" list. Each sign-up is a flat
--- object - name (the DISCORD nickname: "Mani/Asta", "Bloodbow/Yoshihide", "shwed09"), className
--- (a class, or "Absence" / "Tentative" / "Late" / "Bench"), specName, roleName. The rest of the
--- export (class and spec tables, emote ids, settings) is not about people and is never read: fed to
--- the any-shape reader it became a hundred fake "not in guild" people named cClassName and userId.
I.STANDING = { Absence = "absent", Bench = "bench", Tentative = "tentative", Late = "late" }
I.OUT = { absent = true, bench = true }       -- signed up as not coming: never invited
local function jstr(obj, key)
    local v = obj:match('"' .. key .. '"%s*:%s*"(.-)"')
    return v and v:gsub("\\u(%x%x%x%x)", function(h)
        local n = tonumber(h, 16)
        if n < 128 then return string.char(n) end
        if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
        return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
    end):gsub('\\"', '"') or nil
end
function I.ReadRaidHelper(text)
    local list = text:match('"signUps"%s*:%s*%[(.-)%]')
    if not list then return nil end
    -- startTime is the raid's start as a unix time (Arn, 16 Oct: "does the json say what time the
    -- raid is supposed to start?") - the same clock as GetServerTime(), so no time zone can bend it
    local event = { title = jstr(text, "displayTitle") or jstr(text, "title"), date = jstr(text, "date"),
                    time = jstr(text, "time"), channel = jstr(text, "channelName"),
                    start = tonumber(text:match('"startTime"%s*:%s*(%d+)')) }
    local out = {}
    for obj in list:gmatch("{(.-)}") do
        local name = jstr(obj, "name")
        if name and name ~= "" then
            local cls = jstr(obj, "className")
            out[#out + 1] = { name = name, standing = I.STANDING[cls or ""],
                              signed = jstr(obj, "specName") or I.STANDING[cls or ""] or cls,
                              position = tonumber(obj:match('"position"%s*:%s*(%d+)')) or 999 }
        end
    end
    table.sort(out, function(a, b) return a.position < b.position end)
    return out, event
end

--- The pasted export's event, read once per new paste (a 20,000-character export is not re-read on
--- every redraw or every system chat line - Logins.lua asks this on each one).
function I.Event(text)
    text = tostring(text or "")
    if I._readText ~= text then
        I._readText = text
        I._helper, I._event = I.ReadRaidHelper(text)
    end
    I.event = I._event
    return I._event
end

--- "starts in 2 h 15 min" / "started 40 min ago" / nil without a start time.
function I.When(e)
    local start = e and e.start
    local now = GetServerTime and GetServerTime()
    if not (start and now) then return nil end
    local d = start - now
    local m = math.floor(math.abs(d) / 60)
    local span = m >= 60 and ("%d h %d min"):format(math.floor(m / 60), m % 60) or ("%d min"):format(m)
    if math.abs(d) > 2 * 86400 then return (e.date or "") .. " " .. (e.time or "") end
    return d >= 0 and ("starts in " .. span) or ("started " .. span .. " ago")
end

--- text -> rows { typed, member (roster entry or nil), key, signed, standing }, one per person.
function I.Read(text)
    text = tostring(text or "")
    I.Event(text)
    if I._helper then return I.Match(I._helper) end
    return I.ReadAny(text)
end

--- Raid-Helper's sign-ups matched to the guild: every part of a nickname is tried ("Bloodbow/
--- Yoshihide" is Yoshihide's main and alt), digits and symbols dropped ("shwed09" is Shwed).
function I.Match(signups)
    local guild = K.Guild().members
    local whole = {}
    for key, m in pairs(guild) do if m.name then whole[m.name:lower()] = key end end
    local rows, seen = {}, {}
    for _, s in ipairs(signups) do
        local hit
        local words = {}
        for w in s.name:gmatch("[%a\128-\255']+") do if #w >= 2 then words[#words + 1] = w end end
        for i, w in ipairs(words) do
            local two = words[i + 1] and (w .. " " .. words[i + 1]):lower()
            local mm = K.Member(w)
            hit = (two and whole[two]) or (mm and mm.key)
            if hit then break end
        end
        local key = hit or ("?" .. s.name:lower())
        local row = seen[key]
        if not row then
            row = { typed = hit and guild[hit].name or s.name, member = hit and guild[hit] or nil, key = key,
                    specs = {}, standing = s.standing }
            seen[key] = row
            rows[#rows + 1] = row
        end
        -- ONE PERSON, SEVERAL SIGN-UPS (Arn's "Forever Class" export: Gnomerpills signed Fire,
        -- Subtlety, Holy, Shadow): one row, every spec. A real sign-up beats an earlier absence.
        if s.signed and not row.specs[s.signed] then
            row.specs[s.signed] = true
            row.signed = row.signed and (row.signed .. ", " .. s.signed) or s.signed
        end
        if not s.standing or not I.OUT[s.standing] then row.standing = s.standing end
    end
    return rows
end

function I.ReadAny(text)
    local guild = K.Guild().members
    local whole = {}
    for key, m in pairs(guild) do
        if m.name then whole[m.name:lower()] = key end
    end
    local rows, seen = {}, {}
    for piece in (tostring(text or "") .. "\n"):gmatch("([^\n,;\t|]*)[\n,;\t|]") do
        local words = I.Words(piece)
        local hit, typed
        for i, w in ipairs(words) do
            local two = words[i + 1] and (w .. " " .. words[i + 1]):lower()
            local mm = K.Member(w)
            local key = (two and whole[two]) or (mm and mm.key)
            if key then hit, typed = key, guild[key].name or w break end
        end
        if hit then
            if not seen[hit] then
                seen[hit] = true
                rows[#rows + 1] = { typed = typed, member = guild[hit], key = hit }
            end
        elseif words[1] then
            local key = "?" .. words[1]:lower()
            if not seen[key] then
                seen[key] = true
                rows[#rows + 1] = { typed = words[1], key = key }
            end
        end
    end
    return rows
end

--- Where each row stands now: "absent" / "bench" (signed up as not coming), "not in guild",
--- "with you", "online", "offline". Only "online" is ever invited.
function I.Status(row, here)
    if row.standing and I.OUT[row.standing] then return row.standing end
    if not row.member then return "not in guild" end
    if I.IsHere(here, row.member) then return "with you" end
    return row.member.online and "online" or "offline"
end

--------------------------------------------------------------------
-- sending
--------------------------------------------------------------------

--- BiS Tools' public API, when it is installed and its party tool is on (Arn, 16 Oct: "if installed it
--- can API-call it" - never its insides, which may change; BiSToolsAPI major 1 promises not to).
local function Tools()
    local A = _G.BiSToolsAPI
    if type(A) ~= "table" or A.major ~= 1 or not A.PartyReady then return nil end
    local ok, ready = pcall(A.PartyReady)
    return ok and ready and A or nil
end
I.Tools = Tools

local function ClassName(file)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return file and names and names[file] or file
end

--- Invite these guild members (roster entries), `label` naming the list. Through BiS Tools' confirm
--- list when it is here; else armed, then sent on the second click. Answers how many, and by what.
function I.Send(members, label)
    local here = I.Here()
    local go, with = {}, {}
    for _, m in ipairs(members) do
        local e = { name = m.name, class = ClassName(m.class), classFile = m.class, rank = m.rank }
        if here[Key(m.name)] then with[#with + 1] = e else go[#go + 1] = e end
    end
    if #go == 0 then K.Say(("everyone %s is already with you"):format(label), "good") return 0, "none" end
    local A = Tools()
    if A then
        local ok, n, why = pcall(A.InviteList, label, go)
        if ok and n then
            K.Say(("%d on BiS Tools' invite list - look it over, then Send"):format(n), "accent")
            return n, "tools"
        end
        if ok and why == "not leader" then K.Say("only the leader (or an assistant) can invite", "warn") return 0, why end
        -- anything else: BiS Tools could not take it - BiS Guild does it itself below
    end
    if not I.Leads() then K.Say("only the leader (or an assistant) can invite", "warn") return 0, "not leader" end
    local now = GetTime and GetTime() or 0
    local a = I.armed
    if not (a and a.label == label and now - a.at <= I.ARM) then
        I.armed = { label = label, at = now }
        K.Say(("invite %d %s? click again within %d s to send"):format(#go, label, I.ARM), "gold")
        return 0, "armed"
    end
    I.armed = nil
    local names = {}
    for _, e in ipairs(go) do names[#names + 1] = e.name end
    I.Queue(names)
    K.Say(("inviting %d: %s"):format(#names, table.concat(names, ", ")), "good")
    return #names, "sent"
end

--- One raider, from their card: no confirm - the click on their own card is the choice.
function I.One(name)
    local m = K.Member(name)
    local whole = m and m.name or name
    if I.Here()[Key(whole)] then K.Say(whole .. " is already with you", "good") return 0 end
    if not I.Leads() then K.Say("only the leader (or an assistant) can invite", "warn") return 0 end
    local A = Tools()
    local ok, n = false, nil
    if A and A.InviteOne then ok, n = pcall(A.InviteOne, whole) end
    if not (ok and n) then I.Queue({ whole }) end
    K.Say(("invited %s%s"):format(whole, m and "" or " (not in the guild roster - invited as written)"), "good")
    return 1
end

--- MORE THAN A PARTY HOLDS BECOMES A RAID BY ITSELF (Arn, 21 Oct: "auto turn the party into raid when
--- more than 5 people in the party or if the invited people will be more than 5") - BiS Tools' rule,
--- for when it is not here. The game counts the invites still out: a party, or you alone, takes five,
--- and the sixth is refused "party is full". It tells an addon nothing about invites out, so we count
--- our own (I.out, younger than I.OUT_FOR). A raid is made only from a party: alone, the overflow
--- WAITS (I.held) until the first one joins, the party becomes a raid, and then it goes. Nobody joins
--- in I.HOLD_FOR: dropped and said.
I.PARTY, I.HOLD_FOR, I.OUT_FOR = 5, 120, 60
I.out = {}

function I.Out(here)
    here = here or I.Here()
    local now, n = (GetTime and GetTime()) or 0, 0
    for name, t in pairs(I.out) do
        -- joined, by whatever name the client gives a group member: whole, or the first name alone
        local first = (name:match("^([^%s%-]+)") or name):lower()
        if here[Key(name)] or here[name:lower()] or here[first] or now - t > I.OUT_FOR then I.out[name] = nil
        else n = n + 1 end
    end
    return n
end

function I.Convert()
    local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    if convert then pcall(convert) end
end

function I.Hold(names)
    if I.held then
        for _, n in ipairs(names) do I.held.names[#I.held.names + 1] = n end
        return
    end
    local h = { names = names }
    I.held = h
    K.Say(("%d more wait for the raid - they go out once someone joins"):format(#names), "gold")
    if C_Timer and C_Timer.After then
        C_Timer.After(I.HOLD_FOR, function()
            if I.held ~= h then return end
            I.held = nil
            K.Say(("nobody joined - not invited: %s"):format(table.concat(names, ", ")), "warn")
        end)
    end
end

--- A roster change: the party exists - make it a raid; the raid exists - send who waited.
function I.Held()
    local h = I.held
    if not h or not (IsInGroup and IsInGroup()) then return end
    if not (IsInRaid and IsInRaid()) then
        if I.Leads() then I.Convert() end
        return
    end
    I.held = nil
    for _, n in ipairs(h.names) do I.queue[#I.queue + 1] = n end
    I.Pump()
end

I.queue = {}
function I.Queue(names)
    local now, later = names, nil
    if not (IsInRaid and IsInRaid()) then
        local here = I.Here()
        local with = math.max((GetNumGroupMembers and GetNumGroupMembers()) or 0, 1) + I.Out(here) + #I.queue
        if with + #names > I.PARTY then
            if IsInGroup and IsInGroup() then I.Convert() end
            now, later = {}, {}
            for i, n in ipairs(names) do
                if i <= I.PARTY - with then now[#now + 1] = n else later[#later + 1] = n end
            end
        end
    end
    for _, n in ipairs(now) do I.queue[#I.queue + 1] = n end
    if later and #later > 0 then I.Hold(later) end
    I.Pump()
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:SetScript("OnEvent", function() if I.held then I.Held() end end)
    I.events = ev
end

function I.Pump()
    if I._armed or #I.queue == 0 then return end
    local name = table.remove(I.queue, 1)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then
        if pcall(invite, name) then I.out[name] = (GetTime and GetTime()) or 0 end
    end
    I.sent = (I.sent or 0) + 1
    if #I.queue > 0 and C_Timer and C_Timer.After then
        I._armed = true
        C_Timer.After(I.GAP, function() I._armed = false I.Pump() end)
    elseif #I.queue > 0 then
        I.Pump()
    end
end

--- Every guild member on the record who is online and not with you: raid night's one button. Also
--- answers who was LEFT OUT and why (Arn, 16 Oct: "it only invited Shwed, it ignored Ari and Mare" -
--- the roster had them offline, and the button said nothing about it). The roster is read afresh:
--- the copy kept between roster events can be minutes old.
function I.OnlineRaiders()
    K._guildDirty = true
    local out, offline = {}, {}
    for name in pairs(ns.S.Cards()) do
        local m = K.Member(name)
        if m and m.online then out[#out + 1] = m elseif m then offline[#offline + 1] = m.name end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    table.sort(offline)
    return out, offline
end

--- The RAIDERS list's INVITE ONLINE: send who is online, then say who was not.
function I.InviteOnline()
    local members, offline = I.OnlineRaiders()
    local n = I.Send(members, "raiders on the record")
    if #offline > 0 then
        local said = K.frame and K.frame.status:GetText() or ""
        K.Say(said .. ("   |   offline, not invited: %s"):format(table.concat(offline, ", ")), "ink2")
    end
    return n, offline
end

--------------------------------------------------------------------
-- the ROSTER page
--------------------------------------------------------------------

I.STATUS_COLOUR = { ["online"] = "good", ["with you"] = "accent", ["offline"] = "muted", ["not in guild"] = "warn",
                    ["absent"] = "warn", ["bench"] = "gold" }

function K.BuildRoster(page, bodyH)
    local ui = K.ui
    local leftW = 330
    page.paste = ui.Panel(page, "PASTE A ROSTER", 8, 0, leftW, bodyH - 4)
    -- THE BOX LIVES IN A SCROLL FRAME, AND THE WHOLE DARK AREA FOCUSES IT (Arn, 16 Oct: "I can't
    -- paste to the paste a roster box"). A bare multi-line EditBox is only as tall as its text - empty,
    -- a line - so a click on the dark rectangle hit nothing and never gave it the cursor. The standard
    -- shape: the box is a scroll frame's child (a 20,000-character export scrolls), and a click
    -- anywhere in the frame hands the box the keyboard.
    local bbg = page.paste:CreateTexture(nil, "BORDER")
    bbg:SetPoint("TOPLEFT", 4, -22)
    bbg:SetSize(leftW - 8, bodyH - 62)
    ui.Fill(bbg, "sunken")
    local scroll = CreateFrame("ScrollFrame", nil, page.paste)
    scroll:SetPoint("TOPLEFT", 8, -26)
    scroll:SetSize(leftW - 16, bodyH - 70)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetSize(leftW - 16, bodyH - 70)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    box:SetMaxLetters(0)                 -- no cap: a Raid-Helper export runs past 20,000 characters
    box:SetFontObject("GameFontHighlightSmall")
    if box.SetFont then pcall(box.SetFont, box, K.FONT, 12, "") end
    box:SetTextColor(ui.rgb("ink"))
    scroll:SetScrollChild(box)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local now = self:GetVerticalScroll() or 0
        local most = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
        self:SetVerticalScroll(math.max(0, math.min(most, now - (delta or 0) * 30)))
    end)
    -- the cursor stays in view while typing or after a paste
    box:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, height = scroll:GetVerticalScroll() or 0, scroll:GetHeight() or 0
        y = -(y or 0)
        if y < top then scroll:SetVerticalScroll(y)
        elseif y + (h or 0) > top + height then scroll:SetVerticalScroll(y + (h or 0) - height) end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.box, page.scroll = box, scroll
    page.paste.right:SetText("names, a list, a table - any shape")

    local function Button(parent, label, x, y, w, fn)
        local b = CreateFrame("Button", nil, parent)
        b:SetPoint("BOTTOMLEFT", x, y)
        b:SetSize(w, 20)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        ui.Fill(bg, "accentSoft")
        local hi = K.Pop(b)
        b.fs = ui.Text(b, 12, "gold", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    local function Read()
        ns.Books().roster = page.box:GetText()
        page.box:ClearFocus()
        K.Paint()
    end
    -- PASTE (Arn, 16 Oct: "a get-from-clipboard button that Ctrl+V's in the right place"). No addon
    -- may read the clipboard - the game offers no call for it, on purpose - so the button does the
    -- rest: empties the box, gives it the cursor, and says to press Ctrl+V. A paste then reads itself.
    page.pasteBtn = Button(page.paste, "PASTE", 8, 8, 86, function()
        page.box:SetText("")
        page.box:SetFocus()
        K.Say("now press Ctrl+V - the roster reads itself", "gold")
    end)
    page.read = Button(page.paste, "READ IT", 100, 8, 86, Read)
    page.clear = Button(page.paste, "CLEAR", 192, 8, 70, function()
        ns.Books().roster = nil
        page.box:SetText("")
        K.Paint()
    end)
    -- a paste (many characters arriving at once, typed by the player) reads itself a moment later
    page.box:SetScript("OnTextChanged", function(self, userInput)
        local n = #(self:GetText() or "")
        local jump = n - (page.lastLen or 0)
        page.lastLen = n
        if userInput and jump > 20 and C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() if page.box:GetText() ~= ns.Books().roster then Read() end end)
        end
    end)

    local rx = leftW + 16
    page.list = ui.Panel(page, "THE ROSTER", rx, 0, K.W - rx - 8, bodyH - 4)
    page.grid = ui.Grid(page.list, { "NAME", "CLASS", "SIGNED", "NOW" },
        { { 140, "LEFT" }, { 70, "LEFT" }, { 170, "LEFT" }, { 80, "RIGHT" } }, K.LIST_ROWS - 2, 22,
        function(key)
            local r = I.byKey and I.byKey[key]
            if r and r.member then K.Go(r.member.name .. " <raider>") end
        end)
    page.send = Button(page.list, "INVITE ONLINE", 8, 8, 160, function()
        local rows, members = I.Read(ns.Books().roster), {}
        local here = I.Here()
        for _, r in ipairs(rows) do
            if r.member and I.Status(r, here) == "online" then members[#members + 1] = r.member end
        end
        I.Send(members, "on the pasted roster")
    end)
    -- THE ONE GREYED HINT (Arn, 16 Oct: "on the light way we have a greyed out button <needs BiS Tools>
    -- ... but only if it makes sense ... we are not overbearing"; _bisdev playbook 5b). Here, where a
    -- leader reviews a whole raid's invites, BiS Tools' confirm list really helps. Dim, beside the
    -- button, hidden when BiS Tools is here; its tooltip says what it adds. Nowhere else, never a pop-up.
    local tip = CreateFrame("Button", nil, page.list)
    tip:SetPoint("BOTTOMLEFT", 176, 8)
    tip:SetSize(200, 20)
    tip.fs = ui.Text(tip, 11, "muted", "LEFT")
    tip.fs:SetPoint("LEFT", 4, 0)
    tip.fs:SetText("confirm list - needs BiS Tools")
    tip:SetAlpha(0.6)
    tip:SetScript("OnEnter", function(self)
        local gt = _G.GameTooltip
        if not gt then return end
        gt:SetOwner(self, "ANCHOR_TOP")
        gt:AddLine("BiS Tools' confirm list")
        gt:AddLine("Look the invites over before they go: sorted by class, an x to leave someone out, a little "
            .. "inviting box, and refusals shown in red. BiS Guild's own invites work without it.", 1, 1, 1, true)
        gt:Show()
    end)
    tip:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    page.toolsHint = tip
    page.hint = ui.Text(page.list, 12, "ink2")
    page.hint:SetPoint("TOPLEFT", 12, -44)
    page.hint:SetWidth(K.W - rx - 40)
    if page.hint.SetWordWrap then page.hint:SetWordWrap(true) end
    page.hint:SetText("Paste the roster from your Discord raid tool (or just names) on the left and press READ IT. "
        .. "Guild members are found by name; anyone else is shown but never invited by a guess.")
    return page
end

function K.PaintRoster(p)
    local ui = K.ui
    local text = ns.Books().roster
    if type(text) == "string" and p.box:GetText() ~= text and not p.box:HasFocus() then p.box:SetText(text) end
    local rows = I.Read(text)
    local here = I.Here()
    -- WHO CAN BE INVITED FIRST, STRANGERS LAST (Arn's "Forever Class" paste, 16 Oct: 7 guild members
    -- scattered among 26 people not in the guild) - the pugs-at-the-bottom rule of RAIDERS. Sign-up
    -- order is kept inside each group.
    local ORDER = { ["online"] = 1, ["with you"] = 2, ["offline"] = 3, ["tentative"] = 3, ["late"] = 3,
                    ["absent"] = 4, ["bench"] = 4, ["not in guild"] = 5 }
    for i, r in ipairs(rows) do r.order, r.rank_ = i, ORDER[I.Status(r, here)] or 5 end
    table.sort(rows, function(a, b)
        if a.rank_ ~= b.rank_ then return a.rank_ < b.rank_ end
        return a.order < b.order
    end)
    local counts = { online = 0 }
    I.byKey = {}
    for _, r in ipairs(rows) do
        local s = I.Status(r, here)
        counts[s] = (counts[s] or 0) + 1
        I.byKey[r.key] = r
    end
    if #rows == 0 then p.hint:Show() else p.hint:Hide() end
    -- the Raid-Helper event this came from, in the paste panel's corner
    local e = I.event
    p.paste.right:SetText(e and e.title and ("%s  %s"):format(e.title, I.When(e) or ((e.date or "") .. " " .. (e.time or "")))
        or "names, a list, a table, Raid-Helper's JSON")
    p.list.right:SetText(#rows == 0 and "" or ("%d on it, %d online, %d not in guild"):format(#rows, counts.online,
        counts["not in guild"] or 0) .. ui.Showing(p.grid))
    p.send.fs:SetText(("INVITE %d ONLINE"):format(counts.online))
    -- the hint only when BiS Tools is not doing the job, and only once there is a roster to review
    if p.toolsHint then
        if I.Tools() or #rows == 0 then p.toolsHint:Hide() else p.toolsHint:Show() end
    end
    local off = ui.Scroll(p.grid, #rows)
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r then
            local s = I.Status(r, here)
            local m = r.member
            local cc = m and m.class and colours and colours[m.class]
            ui.SetRow(row, r.key, { m and m.name or r.typed, m and ClassName(m.class) or "",
                                    r.signed or (m and m.rank) or "", s },
                { cc and { cc.r, cc.g, cc.b } or (m and "ink" or "muted"), "ink2",
                  r.standing and "gold" or "muted", I.STATUS_COLOUR[s] or "ink" })
            row.who = m and m.name or nil               -- right-click: the game's player menu
        else
            ui.SetRow(row, nil, {})
        end
    end
end
