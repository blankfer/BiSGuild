-- BiSGuild headless suite (made by _bisdev/new-addon.sh). Run from the addon root:
--   lua5.1 dev/tests.lua        or, from the AddOns folder: _bisdev/check.sh BiSGuild
local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local H = dofile(HERE .. "/kit.lua")   -- Nebbinator's strict harness (dev/harness.lua), verbatim
-- A LINE, as the client draws one (8 Nov 2026, the radar tracks; the kit stays verbatim, so it is added here): a texture
-- with two ends and a thickness, strict about its arguments as BiS Tools' mock is. Every frame the kit makes gets it.
do
    local kitCreate = _G.CreateFrame
    _G.CreateFrame = function(...)
        local fr = kitCreate(...)
        if fr and not rawget(fr, "CreateLine") then   -- the kit answers ANY unknown method with a quiet nil
            function fr:CreateLine(_, layer)
                local l = self:CreateTexture(nil, layer)
                l._isLine = true
                function l:SetThickness(w) if type(w) ~= "number" then error("SetThickness wants a number", 2) end self._thick = w end
                function l:SetStartPoint(p, rel, x, y)
                    if type(p) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then error("SetStartPoint(point, rel, x, y)", 2) end
                    self._from = { x, y }
                end
                function l:SetEndPoint(p, rel, x, y)
                    if type(p) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then error("SetEndPoint(point, rel, x, y)", 2) end
                    self._to = { x, y }
                end
                return l
            end
        end
        return fr
    end
end
local ROOT = os.getenv("BISGUILD") or (HERE .. "/..")
local FILES = H.TOC(ROOT, "BiSGuild.toc")

-- every global this addon may create; anything else is a leak and a red test
local ALLOWED = {
    BiSGuildDB = true, SLASH_BISGUILD1 = true,
    HARNESS = true, print = true, BiSTheme = true, LibBiSComm = true, SLASH_BISCOMM1 = true,
    -- the third-party map libs (Libs/THIRD-PARTY.txt): LibStub's one global, the pins' show flags
    LibStub = true, HBD_PINS_WORLDMAP_SHOW_PARENT = true, HBD_PINS_WORLDMAP_SHOW_CONTINENT = true,
    HBD_PINS_WORLDMAP_SHOW_WORLD = true,
    BiSGuildAPI = true,    -- API.lua, for other addons (16 Oct; _bisdev playbook 5a)
    -- the loot ledger, folded in from BiS Loot (Core/Loot.lua): its API, its library, its slash words
    BiSLootAPI = true, LibBiSLedger = true, SLASH_BISLOOT1 = true, SLASH_BISLOOT2 = true, SLASH_BISLOOT3 = true,
}
-- HEREBEDRAGONS DRIVES THE CLIENT'S OWN MAP ENGINE (the world map's data providers, the minimap's
-- zoom tables), which a headless mock cannot stand in for honestly - BiS Tools' suite found the same.
-- So its two files must COMPILE, and in their place a stand-in registers under the same LibStub name,
-- raises the real one's argument errors, refuses one frame on two maps, and records every pin.
local PINS = { world = {}, minimap = {} }
local function fakeHBDPins()
    local P = LibStub:NewLibrary("HereBeDragons-Pins-2.0", 999)
    local function check(ref, icon, map, x, y, what)
        if not ref then error("HereBeDragons-Pins-2.0: " .. what .. ": 'ref' must not be nil", 3) end
        if type(icon) ~= "table" or not icon.SetPoint then error("HereBeDragons-Pins-2.0: " .. what .. ": 'icon' must be a frame", 3) end
        if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
            error("HereBeDragons-Pins-2.0: " .. what .. ": 'uiMapID', 'x' and 'y' must be numbers", 3)
        end
    end
    function P:AddMinimapIconMap(ref, icon, map, x, y)
        check(ref, icon, map, x, y, "AddMinimapIconMap")
        if PINS.world[icon] then error("this frame is already a pin on the other map", 2) end
        PINS.minimap[icon] = { map = map, x = x, y = y } return true
    end
    function P:AddWorldMapIconMap(ref, icon, map, x, y, flag)
        check(ref, icon, map, x, y, "AddWorldMapIconMap")
        if PINS.minimap[icon] then error("this frame is already a pin on the other map", 2) end
        if flag ~= nil and type(flag) ~= "number" then error("showFlag must be a number (or nil)", 2) end
        PINS.world[icon] = { map = map, x = x, y = y, flag = flag } return true
    end
    function P:RemoveWorldMapIcon(ref, icon) PINS.world[icon] = nil end
    function P:RemoveMinimapIcon(ref, icon) PINS.minimap[icon] = nil end
    function P:RemoveAllWorldMapIcons() PINS.world = {} end
    function P:RemoveAllMinimapIcons() PINS.minimap = {} end
    _G.HBD_PINS_WORLDMAP_SHOW_PARENT, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT, _G.HBD_PINS_WORLDMAP_SHOW_WORLD = 1, 2, 3
    -- the core library's zone sizes in yards (the radar tracks' speed): two maps known, any other unknown (nil)
    local core = LibStub:NewLibrary("HereBeDragons-2.0", 999)
    if core then
        function core:GetZoneSize(map) if map == 1411 then return 5000, 3333 elseif map == 1454 then return 1700, 1100 end end
    end
end
local function Load()
    local before = {}
    for k in pairs(_G) do before[k] = true end
    local NS = {}
    for _, rel in ipairs(FILES) do
        local chunk, err = loadfile(ROOT .. "/" .. rel)
        if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
        if rel:find("HereBeDragons-2.0.lua", 1, true) then
            -- compiled; the engine is the client's
        elseif rel:find("HereBeDragons-Pins-2.0.lua", 1, true) then
            fakeHBDPins()
        else
            chunk("BiSGuild", NS)
        end
    end
    H.leaked = {}
    for k in pairs(_G) do
        if not before[k] and not ALLOWED[k] then H.leaked[#H.leaked + 1] = tostring(k) end
    end
    table.sort(H.leaked)
    return NS
end
local TOC_VERSION
do
    local fh = assert(io.open(ROOT .. "/BiSGuild.toc", "r"))
    for line in fh:lines() do TOC_VERSION = TOC_VERSION or line:match("^## Version:%s*(%S+)") end
    fh:close()
end
_G.GetAddOnMetadata = function(_, key) return key == "Version" and TOC_VERSION or nil end
local function fire(event, ...)
    for _, fr in ipairs(H.frames) do
        if fr._events[event] and fr._scripts.OnEvent then fr._scripts.OnEvent(fr, event, ...) end
    end
end
local function bytes(p) local fh = io.open(p, "rb") if not fh then return nil end local s = fh:read("*a") fh:close() return s end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local said = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = strip(m) end }

--------------------------------------------------------------------
H.section("load")
local NS = Load()
H.eq(#H.leaked, 0, "no accidental globals", table.concat(H.leaked, ", "))
H.eq(NS.VERSION, TOC_VERSION, "version is the TOC's")
fire("ADDON_LOADED", "BiSGuild")
H.ok(type(_G.BiSGuildDB) == "table" and _G.BiSGuildDB.comm == true, "SavedVariables shaped with defaults on first load")

H.section("embedded libs are canon (drift fences)")
H.eq(_G.LibBiSComm.MINOR, 19, "LibBiSComm minor 19")
local function listed(rel) for _, f in ipairs(FILES) do if f == rel then return true end end return false end
H.ok(listed("Libs/BiSTheme/Console.lua"), "TOC lists the Console embed")
-- the third-party map libs are BiS Tools' copies byte for byte, so the family carries one version
for _, rel in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
                       "Libs/HereBeDragons/HereBeDragons-2.0.lua", "Libs/HereBeDragons/HereBeDragons-Pins-2.0.lua" }) do
    H.ok(listed(rel), "TOC lists " .. rel)
    local theirs = bytes((os.getenv("BISTOOLS") or (ROOT .. "/../BiSTools")) .. "/" .. rel)
    if theirs then H.ok(bytes(ROOT .. "/" .. rel) == theirs, rel .. " byte-identical to BiS Tools'")
    else H.say("  (note) no BiSTools beside the checkout - " .. rel .. " fence skipped") end
end
H.ok(listed("Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua"), "TOC lists the comm embed")
do
    local canon = bytes((os.getenv("BISTHEME") or (ROOT .. "/../BiSTheme")) .. "/Console.lua")
    if canon then H.ok(bytes(ROOT .. "/Libs/BiSTheme/Console.lua") == canon, "Console.lua byte-identical to canon")
    else H.say("  (note) no canon BiSTheme beside the checkout - bytes fence skipped") end
    -- the options window's kit (Forever 1.0) and the one BiS> home: canon bytes too, Options right after Console
    local at = {}
    for i, f in ipairs(FILES) do at[f] = i end
    H.ok(at["Libs/BiSTheme/Options.lua"] and at["Libs/BiSTheme/Options.lua"] == at["Libs/BiSTheme/Console.lua"] + 1,
         "TOC lists the Options embed, right after Console")
    H.ok(listed("Libs/BiSTheme/Settings.lua"), "TOC lists the Settings embed")
    for _, name in ipairs({ "Options.lua", "Settings.lua" }) do
        local c = bytes((os.getenv("BISTHEME") or (ROOT .. "/../BiSTheme")) .. "/" .. name)
        if c then H.ok(bytes(ROOT .. "/Libs/BiSTheme/" .. name) == c, name .. " byte-identical to canon")
        else H.say("  (note) no canon BiSTheme beside the checkout - " .. name .. " fence skipped") end
    end
    local lib = bytes((os.getenv("BISDEV") or (ROOT .. "/../_bisdev")) .. "/LibBiSComm-1.0/LibBiSComm-1.0.lua")
    if lib then H.ok(bytes(ROOT .. "/Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua") == lib, "LibBiSComm byte-identical to _bisdev")
    else H.say("  (note) no _bisdev beside the checkout - lib bytes fence skipped") end
end

H.section("the shared BiS channel")
local lib = _G.LibBiSComm
H.ok(lib._booted and lib:Enabled(), "comm booted and on")
H.eq(lib.addons.BiSGuild, TOC_VERSION, "registered with the TOC version")

H.section("/bisg")
H.ok(type(_G.SlashCmdList.BISGUILD) == "function", "slash registered")
H.eq(_G.SLASH_BISGUILD1, "/bisg", "as /bisg")
_G.SlashCmdList.BISGUILD("help")
H.ok(said[1] and said[1]:find(TOC_VERSION, 1, true) ~= nil, "help says the version", said[1])

H.section("the off switch survives a logout")
lib:SetEnabled(false)
fire("PLAYER_LOGOUT")
H.eq(_G.BiSGuildDB.comm, false, "off is saved")
lib:SetEnabled(true)
fire("PLAYER_LOGOUT")
H.eq(_G.BiSGuildDB.comm, true, "on is saved")

--=============================================================================
-- FOREVER 1.0: A NEW INSTALL STARTS QUIET, AN EXISTING ONE KEEPS WHAT IT HAD (Arn, 7 Nov: "every new user ...
-- every module turned off ... BUT all the main functionalities start on" and "everybody that already has the
-- addons installed, I don't wanna change default settings that they have on"). The terminal and the record are
-- the core and have no switch. The extras were read as `x ~= false` - nil meant ON - so an existing save must be
-- FROZEN at what it showed before the stamp is written, or flipping the default would silently switch it off.
--=============================================================================
H.section("Forever 1.0: quiet for a new install, frozen for an existing one")
do
    local keep = _G.BiSGuildDB
    local L, M, C = NS.Login, NS.Pins, NS.Copy
    -- (a) the suite's own first load above was a fresh install: no saved table before ADDON_LOADED
    H.ok(keep.forever10 == true, "the first load stamped the save")
    H.ok(keep.logins == false and keep.mapDots == false and keep.versionNote == false,
         "a NEW install: login pop-up, map dots and the newer-version note all start OFF")
    H.ok(not L.On() and not M.On(), "and the modules read them as off")
    H.ok(keep.comm == true, "the shared channel stays on (it is how the record is shared - core)")

    -- a table made by our own db() BEFORE the client handed the saved variables in is still a new install
    -- (the client keeps the global we made when there is no saved file)
    _G.BiSGuildDB = nil
    NS.DB()
    NS.Settle()
    H.ok(_G.BiSGuildDB.forever10 and _G.BiSGuildDB.logins == false, "our own early table is not mistaken for a save")

    -- (b) an EXISTING save from 0.5.x: the extras never written (nil = on), a few things set
    _G.BiSGuildDB = { comm = true, logs = "C:\\WoW\\Logs", guilds = { ["R|G"] = { roster = "x" } } }
    NS.Settle()
    local d = _G.BiSGuildDB
    H.ok(d.forever10 == true, "an existing save is stamped")
    H.ok(d.logins == true and d.mapDots == true and d.versionNote == true,
         "and FROZEN: every nil-read extra written as the on it was showing", tostring(d.logins) .. tostring(d.mapDots))
    H.ok(L.On() and M.On(), "so the login pop-up and the map dots are still on for them")
    H.eq(d.logs, "C:\\WoW\\Logs", "nothing else touched")

    -- an existing save that had switched one OFF keeps it off
    _G.BiSGuildDB = { comm = false, logins = false }
    NS.Settle()
    H.ok(_G.BiSGuildDB.logins == false and _G.BiSGuildDB.mapDots == true and _G.BiSGuildDB.comm == false,
         "an existing 'off' stays off; the others freeze on")

    -- (c) the second load changes nothing, in either direction
    _G.BiSGuildDB.mapDots = false            -- the player switches dots off after the 1.0 load
    _G.BiSGuildDB.logins = nil               -- and something leaves a key unwritten
    NS.Settle()
    H.ok(_G.BiSGuildDB.mapDots == false and _G.BiSGuildDB.logins == nil, "a second load never runs the freeze again")
    local fresh = { forever10 = true, logins = false, mapDots = false, versionNote = false }
    _G.BiSGuildDB = fresh
    _G.BiSGuildDB.versionNote = true         -- a new player switched the note on
    NS.Settle()
    H.ok(_G.BiSGuildDB.versionNote == true and _G.BiSGuildDB.logins == false, "nor the quiet start")
    _G.BiSGuildDB = keep
end

--=============================================================================
--=============================================================================
-- The collector is gone (5 Oct 2026). Arn: "we can get rid of the attendence and consume check
-- lets do logs for that". The addon counted boss kills and who was standing there, which was a
-- SECOND source of truth against the combat log - and when two disagree, the one people believe is
-- the one on the website. Everything below tests the log report and the window instead.
--=============================================================================
local clock = 1000000
_G.GetServerTime = function() return clock end
_G.date = _G.date or os.date
local P = NS.P

H.section("nothing is collected in game any more")
do
    -- The addon used to count boss kills and who was there. It does not now, and the point of
    -- deleting it is that nothing is left half-wired: a watcher still registered for BOSS_KILL
    -- would be a second source of truth quietly disagreeing with the website.
    H.eq(NS.G, nil, "no night keeper")
    H.eq(NS.R, nil, "no roster reader")
    H.eq(NS.W, nil, "and nothing watching for a boss to die")

    for _, fr in ipairs(H.frames) do
        H.ok(not (fr._events and (fr._events.BOSS_KILL or fr._events.ENCOUNTER_END
                                  or fr._events.ENCOUNTER_START)),
             "no frame is still listening for an encounter")
    end

    -- and the record it used to keep is dropped rather than left to rot in saved variables where
    -- nothing can read it any more
    _G.BiSGuildDB.nights = { { kills = {} } }
    _G.BiSGuildDB.taught = { [1] = "flask" }
    fire("ADDON_LOADED", "BiSGuild")
    H.eq(_G.BiSGuildDB.nights, nil, "an old nights table is cleared on load")
    H.eq(_G.BiSGuildDB.taught, nil, "and the old consumables list with it")
end

H.section("no report is not an empty report")
do
    _G.BiSGuildReport = nil
    H.eq(P.Report(), nil, "with no file written there is no report")
    H.eq(P.Of("Kumlust"), nil, "and nobody has numbers from it")
    H.eq(#P.Rows(), 0, "and the list is empty rather than erroring")

    -- THE FILE IS NAMED IN THE TOC AND IS NOT IN GIT. A fresh install has none, and deploy.sh
    -- wipes the game folder before copying, so a deploy removes it too. Looking broken at that
    -- moment is the easy mistake; saying what to do is the fix. And a typo lands here too (anything
    -- unknown is the report), so it points at the NOTEBOOK - the PowerShell road is the officers'
    -- own since 18 Oct and a raider must never be sent down it
    for _, logs in ipairs({ false, true }) do
        _G.BiSGuildDB.logs = nil
        if logs then P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs") end
        local before = #said
        _G.SlashCmdList.BISGUILD("report")
        local out = table.concat(said, "\n", before + 1, #said)
        H.ok(out:find("/bisg paste", 1, true) ~= nil and out:find("/bisg script", 1, true) == nil,
             ("no report (%s logs folder): it points at the notebook, never the script"):format(logs and "a" or "no"), out)
    end
    _G.BiSGuildDB.logs = nil
end

--=============================================================================
-- THE WINDOW. Arn: "give me a bis themed window for bis guild so i can copy and paste and not have
-- to write out commands, also the warning can get lost easy in the chat, better to make them a pop
-- up in the window where they can confirm with a button".
--
-- THE OFFICERS' OWN SINCE 18 OCT 2026 (Arn: "a secret powershell feature just for us"). Raiders
-- read their logs in the notebook; the warning screen and the hash check went with the fingerprint.
--=============================================================================
H.section("the officers' window: the command, at once")
do
    local U = NS.U
    H.ok(U ~= nil, "there is a window")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")

    local f = U.Build()
    H.ok(f ~= nil, "it builds")
    U.Refresh()
    H.ok(f.warn == nil and f.hashLine == nil and f.back == nil, "no warning screen and no hash check any more")
    H.ok(f.cmd:GetText():find("logreport.ps1", 1, true) ~= nil, "the command is there at once", f.cmd:GetText())
    H.ok(f.cmd:GetText():find("_anniversary_\\Logs", 1, true) ~= nil,
         "with the paths already filled in - nothing to type")
    -- THE PROMPT IS A LABEL, NOT PART OF THE TEXT (5 Oct 2026): pasted with the command, PowerShell
    -- answers "The term 'PS>' is not recognized"
    H.ok(f.cmd:GetText():find("PS>", 1, true) == nil,
         "and no prompt in the copyable text", f.cmd:GetText())
    H.eq(f.prompt:GetText(), "PS>", "the prompt beside it is a label")

    -- THE CLIPBOARD IS PROTECTED, AND BEING IN THE CENSUS DID NOT MEAN WE COULD USE IT (5 Oct
    -- 2026). CopyToClipboard is on both baselines, the fence passed, and the client answered:
    --
    --   [ADDON_ACTION_FORBIDDEN] AddOn 'BiSGuild' tried to call the protected function 'UNKNOWN()'
    --
    -- The fence proves a NAME exists. It says nothing about permission.
    --
    -- And the guard written for this could not work: a pcall around a forbidden call returns CLEAN.
    -- The refusal arrives later as an event, so the window said "copied" while nothing had been,
    -- and the player got a red error on top. Measured on 3 Oct, written down, not applied.
    do
        -- a client that HAS the call must still not be called: the suite fails if anything reaches
        -- for it, which is the only way this stays out
        local reached = false
        local realCopy = _G.CopyToClipboard
        _G.CopyToClipboard = function() reached = true end

        f.cmd._scripts.OnMouseUp(f.cmd)
        H.eq(reached, false, "clicking the command NEVER calls the protected clipboard function")
        H.ok(f.flash:GetText():find("Ctrl+C", 1, true) ~= nil,
             "it says which key to press instead", f.flash:GetText())
        H.ok(f.flash:GetText():find("copied", 1, true) == nil,
             "and never claims it copied, because it did not")

        _G.CopyToClipboard = realCopy
    end

    -- IT SHOULD LOOK LIKE A SHELL (5 Oct 2026). Arn: "the more we make it look like a powershell
    -- window the better blinking _ and everything". Not only taste: the box holding a command you
    -- are about to run on your own computer should NOT look like the rest of the addon, because it
    -- is not part of it.
    H.ok(f.prompt ~= nil and f.prompt:GetText() == "PS>", "there is a prompt, not a label")
    H.ok(f.caret ~= nil and f.caret:GetText() == "_", "and a cursor")
    H.ok(f.cmdWrap ~= nil and f.cmdWrap._scripts.OnUpdate ~= nil, "which is driven by a ticker")

    -- the blink: half a second lit, half dark, at the rate the house console uses so two BiS
    -- windows open together do not blink against each other
    local tick = f.cmdWrap._scripts.OnUpdate
    f.cmdWrap.t = 0
    tick(f.cmdWrap, 0.1)
    local lit = f.caret:GetAlpha()
    tick(f.cmdWrap, 0.5)
    local dark = f.caret:GetAlpha()
    H.ok(lit == 1 and dark == 0, "the cursor blinks",
         tostring(lit) .. "/" .. tostring(dark))
    tick(f.cmdWrap, 0.5)
    H.eq(f.caret:GetAlpha(), 1, "and comes back - it is a blink, not a fade-out")

    -- ESCAPE CLOSES IT (5 Oct 2026, Arn: "esc does not close this window")
    H.ok(f._scripts.OnKeyDown ~= nil, "the window handles keys itself")
    U.Show()
    f._scripts.OnKeyDown(f, "ESCAPE")
    H.eq(f:IsShown(), false, "escape closes it")
    U.Show()
    f._scripts.OnKeyDown(f, "A")
    H.eq(f:IsShown(), true, "and any other key is left alone, so typing still reaches chat")

    -- no logs folder: the window says so rather than offering an empty command
    _G.BiSGuildDB.logs = nil
    U.Refresh()
    H.eq(f.cmd:GetText(), "", "with no logs folder there is no command to copy")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    U.Hide()
end

H.section("/bisg script: the officers' line, and the fingerprint gone")
do
    -- THE FINGERPRINT IS GONE (18 Oct 2026). Arn: "can we get rid of the fingerprint thing and just do
    -- a secret powershell feature just for us". It guarded the script raiders ran (4-18 Oct); raiders
    -- run the notebook now. Gone everywhere it lived, so nothing half-remembers it.
    for _, rel in ipairs({ "Core/Build.lua", "Tools/manifest.txt", "Tools/stamp.ps1", "Tools/fingerprint.ps1" }) do
        H.eq(bytes(ROOT .. "/" .. rel), nil, rel .. " is gone")
    end
    H.ok(NS.BUILD == nil and NS.parts == nil and NS.broken == nil and NS.TellBroken == nil,
         "and so are the build list, the per-file stamps and the not-whole switch-off")
    H.eq(bytes(ROOT .. "/BiSGuild.toc"):find("Build.lua", 1, true), nil, "the TOC no longer loads a build file")
    for _, rel in ipairs(FILES) do
        if not rel:find("^Libs/") then
            local body = bytes(ROOT .. "/" .. rel) or ""
            H.ok(not body:find("ns%.parts%["), rel .. " carries no version stamp")
        end
    end
    local ps = bytes(ROOT .. "/Tools/logreport.ps1") or ""
    H.ok(not ps:find("Test-BiSGuildCopy", 1, true) and not ps:find("fingerprint.ps1", 1, true),
         "the script no longer refuses a copy - there is no list to check it against")

    -- THE NOTEBOOK'S LINK, AND THE PAGE'S: one link, so the page can be the check (Arn, 18 Oct: "the
    -- link should also go into the curseforge description so people can double check")
    local cf = bytes(ROOT .. "/dev/cf-desc.md") or ""
    local page = cf:match("\n%-%-%-\n(.*)$") or ""
    H.ok(page:find("(" .. NS.U.NOTEBOOK .. ")", 1, true) ~= nil, "the CurseForge page carries the window's link, exactly")
    H.ok(not page:lower():find("fingerprint", 1, true) and not page:find("Get-FileHash", 1, true),
         "and no fingerprint or check line any more")

    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    local before = #said
    _G.SlashCmdList.BISGUILD("script")
    local out = table.concat(said, "\n", before + 1, #said)
    H.ok(out:find("PowerShell", 1, true) ~= nil, "/bisg script still says the word PowerShell")
    H.ok(out:find("/bisg paste", 1, true) ~= nil, "and sends raiders to the notebook instead")
    H.ok(not out:lower():find("fingerprint", 1, true) and not out:find("Get-FileHash", 1, true),
         "no fingerprint, no hash check", out)

    -- OFF THE HELP: the notebook is listed, the PowerShell road is not (it still works)
    before = #said
    _G.SlashCmdList.BISGUILD("help")
    local help = table.concat(said, "\n", before + 1, #said)
    H.ok(help:find("/bisg paste", 1, true) and not help:find("/bisg script", 1, true)
         and not help:find("/bisg window", 1, true) and not help:find("/bisg logs", 1, true),
         "/bisg help lists the notebook, not the PowerShell road", help)

    -- THE WARNING MUST COME FIRST. A caution printed under the command is one people scroll past
    -- having already copied the line.
    local warnAt = out:find("PowerShell", 1, true)
    local cmdAt = out:find("%-ExecutionPolicy")
    H.ok(warnAt and cmdAt and warnAt < cmdAt, "and all of it comes BEFORE the command itself")

    -- the file it tells you to hash must be the file the command runs
    local script = P.ScriptPath()
    H.ok(script and out:find(script, 1, true) ~= nil,
         "the file to check is the same path the command runs", tostring(script))
    _G.BiSGuildDB.logs = nil
end

H.section("told where the logs are, once")
do
    _G.BiSGuildDB.logs = nil
    H.eq(P.Logs(), nil, "nothing known to start with")
    H.eq(P.Command(), nil, "and no command can be built")

    H.eq(P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_"), nil,
         "the WoW folder is refused - it is the Logs folder we want")
    H.eq(P.SetLogs(""), nil, "and so is nothing")

    local set = P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    H.ok(set ~= nil, "the Logs folder is taken")

    -- A TRAILING SLASH WOULD MOVE THE WOW FOLDER UP A LEVEL, and the command would point at a
    -- folder with no addon in it. Pasted paths carry one often.
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs\\")
    H.eq(P.Logs(), "C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs",
         "a trailing slash is trimmed")
    -- and so are the quotes Windows adds when you copy a path
    P.SetLogs('"C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs"')
    H.eq(P.Logs(), "C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs",
         "and the quotes Windows wraps a copied path in")

    local cmd = P.Command()
    H.ok(cmd:find("logreport.ps1", 1, true) ~= nil, "the command names the script", cmd)
    H.ok(cmd:find("AddOns\\BiSGuild\\Tools", 1, true) ~= nil,
         "and finds the addon from the logs path alone - one answer reaches everything")
    H.ok(cmd:find("_anniversary_\\Logs", 1, true) ~= nil, "and passes the logs folder to it")
    H.ok(cmd:find("_anniversary_\\Interface", 1, true) ~= nil,
         "the script sits beside Logs in the SAME client folder, not a level up")

    -- A SHALLOW PATH STILL WORKS (5 Oct 2026). Arn set `x:\logs`, was told "logs folder
    -- remembered", and then /bisg script said "tell me where your logs are first" - the derivation
    -- went up TWO levels and re-appended the flavour, so anything shallower matched nothing and the
    -- addon denied knowing a folder it had just confirmed. Logs and Interface are siblings; one
    -- level is the whole answer.
    P.SetLogs("x:\\logs")
    H.eq(P.Logs(), "x:\\logs", "a short path is remembered")
    local short = P.ScriptPath()
    H.ok(short ~= nil, "and the script path still resolves from it", tostring(short))
    H.eq(short, "x:\\Interface\\AddOns\\BiSGuild\\Tools\\logreport.ps1",
         "one level up, then Interface", tostring(short))
    H.ok(P.Command() ~= nil, "so the command can be built")

    -- and when it genuinely cannot be worked out, it must not say "tell me where your logs are" at
    -- somebody who just told it
    _G.BiSGuildDB.logs = "Logs"
    local before2 = #said
    _G.SlashCmdList.BISGUILD("script")
    local out2 = table.concat(said, "\n", before2 + 1, #said)
    H.ok(out2:find("cannot work out where WoW is", 1, true) ~= nil,
         "a folder it cannot use is said to BE a folder it cannot use", out2)
    H.ok(out2:find("tell me where your logs are first", 1, true) == nil,
         "and not called missing when it was given")

    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")

    _G.SlashCmdList.BISGUILD("script")
    H.ok(said[#said - 1]:find("powershell", 1, true) ~= nil
         or said[#said - 2]:find("powershell", 1, true) ~= nil, "/bisg script prints it")

    _G.BiSGuildDB.logs = nil
    _G.SlashCmdList.BISGUILD("script")
    H.ok(said[#said]:find("/bisg logs", 1, true) ~= nil,
         "and asks for the folder first when it does not know", said[#said])
end

H.section("a report that was written")
do
    -- exactly the shape logreport.py writes
    _G.BiSGuildReport = {
        written = 1791182045, kills = 2, nights = 7, zones = "Illidan Stormrage",
        rows = {
            { name = "Belbearr", attend = 100, consumes = 0 },
            { name = "Kumlust", attend = 100, consumes = 100 },
            { name = "Interrup", attend = 50, consumes = 100 },
        },
    }
    H.ok(P.Report() ~= nil, "the report is read")
    H.eq(P.Of("Kumlust").consumes, 100, "one person's numbers come back")
    H.eq(P.Of("NotInRaid"), nil, "somebody not in it has none")

    local rows = P.Rows()
    H.eq(rows[1].name, "Kumlust", "best attendance first")
    H.eq(rows[2].name, "Belbearr", "a tie on attendance breaks on consumes, best first")
    H.eq(rows[3].name, "Interrup", "then lower attendance, however good their consumes")

    local before = #said
    _G.SlashCmdList.BISGUILD("report")
    local printed = table.concat(said, "\n", before + 1, #said)
    H.ok(printed:find("Kumlust", 1, true) ~= nil, "/bisg report prints the people in it")
    H.ok(printed:find("Illidan Stormrage", 1, true) ~= nil, "and says which bosses it came from")

    -- A PERCENTAGE NEEDS ITS DENOMINATOR ON SCREEN (5 Oct 2026). Arn asked how anyone keeps track
    -- of attendance over time - and the answer only means something if the window says how many
    -- nights it is over. 100% of one night is not a record, and somebody will argue with it.
    NS.U.Show()
    local shown = NS.U.frame.report:GetText()
    H.ok(shown:find("7 raid night", 1, true) ~= nil,
         "the window says how many nights the numbers are over", shown)
    NS.U.Hide()
    H.ok(printed:find("100%", 1, true) ~= nil, "with the percentages")

    -- a half-written or hand-mangled file must not take the addon down with it
    _G.BiSGuildReport = { written = 1, kills = 1 }
    H.eq(P.Report(), nil, "a report with no rows is no report")
    _G.BiSGuildReport = "not a table"
    H.eq(P.Report(), nil, "and neither is something that is not a table")
    _G.BiSGuildReport = nil
end

--=============================================================================
-- DOES EVERY LABEL FIT ITS WINDOW (6 Oct 2026, ported from BiSTools). Arn found labels running out
-- of a BiSTools window with that suite green, and asked for "a check for cut offs or overflows that
-- happens often". Every shown label inside the window is measured where it actually STARTS -
-- following what it is pinned to: the window's edge, a frame, another label - and must end inside.
--
-- WIDTH, CALIBRATED ON THE CLIENT, NOT GUESSED: capitals and digits 0.75 px per point, lowercase
-- 0.55, spaces and punctuation 0.3 (BiSTools, from Arn's screenshots). Inline |T..:w:h|t textures
-- take their width, colour escapes none. The mock's own GetStringWidth (0.6 flat) stays as it is:
-- BiSTheme's T.Fit trims by it, and changing it changes what the addon draws.
--=============================================================================
local function lineWidth(t, size)
    local tex = 0
    t = t:gsub("|T[^|]-:(%d+):%d+[^|]*|t", function(w) tex = tex + tonumber(w) return "" end)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local px = 0
    for ch in t:gmatch(".") do
        if ch:match("[%u%d]") then px = px + 0.75 elseif ch:match("%l") then px = px + 0.55 else px = px + 0.3 end
    end
    return px * size + tex
end
-- A "\n" is a new line, not a character: the widest LINE is the label's width. (BiSTools has no
-- multi-line labels; this window's warning is one.)
local function widest(text, size)
    local best, bestLine = 0, ""
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local w = lineWidth(line, size)
        if w > best then best, bestLine = w, line end
    end
    return best, bestLine
end
local function hasL(p) return p:find("LEFT") ~= nil end
local function hasR(p) return p:find("RIGHT") ~= nil end

-- left edge and width of any region, in px from the window's left; nil when it cannot be followed.
-- FRAMES ARE FOLLOWED, not assumed to span the window: the warning hangs off two corners, a button
-- off one corner and its own size. A frame with no anchor at all spans the window, as in BiSTools.
local box
local function edgeX(rel, relPoint, root, depth)
    local l, w = box(rel, root, depth + 1)
    if not l then return nil end
    if hasL(relPoint) then return l elseif hasR(relPoint) then return l + w end
    return l + w / 2
end
box = function(r, root, depth)
    depth = depth or 0
    if r == root then return 0, root._w end
    if r == nil or r == _G.UIParent or depth > 10 then return nil end
    if r._all then return box(r._parent, root, depth + 1) end
    local pts = r._points
    if not pts or #pts == 0 then
        if r._isLabel or r._isTexture then return nil end
        return 0, root._w
    end
    local lp, rp, mid
    for _, p in ipairs(pts) do
        if hasL(p.point) then lp = lp or p elseif hasR(p.point) then rp = rp or p else mid = mid or p end
    end
    local L, R
    if lp then L = edgeX(lp.rel or r._parent, lp.relPoint, root, depth) if not L then return nil end L = L + lp.x end
    if rp then R = edgeX(rp.rel or r._parent, rp.relPoint, root, depth) if not R then return nil end R = R + rp.x end
    -- ANCHORED BOTH SIDES = BOUNDED: the anchors set the width, not the text
    if L and R then return L, R - L end
    local w = r._w
    if r._isLabel and not w then w = (widest(r._text, r._size or 9)) end
    w = w or 0
    if L then return L, w end
    if R then return R - w, w end
    local c = edgeX(mid.rel or r._parent, mid.relPoint, root, depth)
    if not c then return nil end
    return c + mid.x - w / 2, w
end
local function insideShown(r, root)
    if r._shown == false then return false end
    local p = r._parent
    while p do
        if p._shown == false then return false end
        if p == root then return true end
        p = p._parent
    end
    return false
end
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- the font a button's own label draws in: UIPanelButtonTemplate's NormalFont is GameFontNormal
local BUTTON_SIZE = { UIPanelButtonTemplate = H.FONT_SIZE.GameFontNormal }

local function fitsIn(root, what)
    local width, bad, measured = root._w, {}, 0
    for _, fs in ipairs(H.labels) do
        if fs._text ~= "" and insideShown(fs, root) then
            local l, span = box(fs, root)
            if l then
                measured = measured + 1
                local need, line = widest(fs._text, fs._size or 9)
                -- A LABEL PINNED LEFT AND RIGHT (or given a width) is bounded by its span. The code
                -- breaks those lines itself with "\n" and never asks for word wrap, so a line wider
                -- than the span is one the client wraps or clips where nobody planned it: measured.
                local pl, pr = false, false
                for _, p in ipairs(fs._points or {}) do
                    if hasL(p.point) then pl = true elseif hasR(p.point) then pr = true end
                end
                local bounded = fs._w ~= nil or (pl and pr)
                if bounded and need > span + 1 then
                    bad[#bad + 1] = ("%q needs %d px, its span is %d"):format(plain(line), need, span)
                elseif l < -1 or l + span > width + 1 then
                    bad[#bad + 1] = ("%q needs %d px from %d, the window is %d"):format(plain(line), need, l, width)
                end
            end
        end
    end
    -- A BUTTON'S WORDS are a label too: centred on the button, and must fit the button
    for _, b in ipairs(H.frames) do
        local size = BUTTON_SIZE[b._template]
        if size and b._text ~= "" and insideShown(b, root) then
            local l, bw = box(b, root)
            if l then
                measured = measured + 1
                local need = lineWidth(b._text, size)
                if need > bw + 1 then
                    bad[#bad + 1] = ("button %q needs %d px, the button is %d"):format(plain(b._text), need, bw)
                elseif l < -1 or l + bw > width + 1 then
                    bad[#bad + 1] = ("button %q sits %d..%d, the window is %d"):format(plain(b._text), l, l + bw, width)
                end
            end
        end
    end
    H.ok(measured > 0, what .. ": the fit check measured something (a check that sees nothing proves nothing)")
    H.ok(#bad == 0, what .. ": every label fits - " .. table.concat(bad, "; "))
    H.say(("  (fit) %s: %d label(s) measured"):format(what, measured))
    return measured
end

H.section("every label fits the window")
do
    local U = NS.U
    local f = U.Build()
    local tick = f.cmdWrap._scripts.OnUpdate
    local function show()
        U.Show()
        -- the console fades its words in on the ticker, by the CLOCK: run a second of it, as the
        -- client would before anybody reads the window
        for _ = 1, 4 do H.clock = H.clock + 0.3 tick(f.cmdWrap, 0.3) end
    end
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    _G.BiSGuildReport = nil

    -- the command, no report yet, and the "press Ctrl+C" notice from clicking it
    show()
    f.cmd._scripts.OnMouseUp(f.cmd)
    fitsIn(f, "the command, no report yet")

    -- no logs folder: the header note asks for it
    _G.BiSGuildDB.logs = nil
    show()
    fitsIn(f, "the command, no logs folder")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")

    -- POPULATED, WITH THE LONGEST REAL THINGS IT WILL SHOW. A full Black Temple night is nine
    -- encounters, and logreport writes them all into `zones` (ENCOUNTER_START's names, sorted).
    -- Forever names carry a surname ("Name Surname"); a first name may be 12 letters.
    _G.BiSGuildReport = {
        written = 1791182045, kills = 9, nights = 12,
        zones = "Gurtogg Bloodboil, High Warlord Naj'entus, Illidan Stormrage, Mother Shahraz, "
             .. "Reliquary of Souls, Shade of Akama, Supremus, Teron Gorefiend, The Illidari Council",
        rows = {},
    }
    local names = { "Kumlustrande Stormwhisper", "Belbearr Ironhide", "Interrup Moonfallow",
                    "Hrsalinge Duskbringer", "Overlordwyn Blackthorne", "Kurki Saltmarsh",
                    "Thundermaul Highcrest", "Feathermoon Wildmantle", "Ashenvalea Grimstone",
                    "Dreamscythe Vandermolen" }
    for i, n in ipairs(names) do
        _G.BiSGuildReport.rows[i] = { name = n, attend = 100 - i * 7, consumes = 100 - i * 9 }
    end
    show()
    fitsIn(f, "the report, a full Black Temple night, long Forever names")

    -- the bosses did not vanish: they moved off the line and into the hover
    H.ok(f.lastHit:IsShown(), "with a report, the header lines can be hovered")
    do
        local tip, real = {}, _G.GameTooltip
        _G.GameTooltip = setmetatable({
            SetText = function(_, t) tip[#tip + 1] = t end,
            AddLine = function(_, t) tip[#tip + 1] = t end,
        }, { __index = real })
        f.lastHit._scripts.OnEnter(f.lastHit)
        _G.GameTooltip = real
        local all = table.concat(tip, "\n")
        H.eq(#tip, 10, "the hover says the kills, then one line per boss", all)
        H.ok(all:find("High Warlord Naj'entus", 1, true) and all:find("The Illidari Council", 1, true),
             "every boss is named there", all)
    end
    _G.BiSGuildReport = nil
    show()
    H.ok(not f.lastHit:IsShown(), "and with no report there is nothing to hover")

    U.Hide()
    _G.BiSGuildReport = nil
end

--=============================================================================
-- THE GUILD'S RECORD (16 Oct 2026). Arn: "All this data we are getting is from my computer, how are
-- other people going to get all this info, so if I miss one raid night what stops the addon from
-- updating". Every member keeps the nights; officers share them over the guild channel.
--=============================================================================
local function deq(a, b, skip)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not (skip and skip[k]) and not deq(v, b[k]) then return false end end
    for k in pairs(b) do if not (skip and skip[k]) and a[k] == nil then return false end end
    return true
end
local function raider(present, pulls, deaths)
    return { present = present, ready = present, pulls = pulls, flask = pulls, elixir = 0, food = pulls,
             weapon = 0, weaponSeen = pulls, pots = 1, deaths = deaths or 0 }
end
local function bigNight()
    local n = { kills = 8, raiders = {}, bosses = {} }
    local names = {}
    for i = 1, 25 do
        local name = ("Raider%02d"):format(i)
        names[#names + 1] = name
        n.raiders[name] = raider(8, 11, i % 3)
    end
    for b = 1, 8 do
        n.bosses[("Boss Number %d"):format(b)] = { pulls = 2, kills = 1, best = 180000 + b, killers = names }
    end
    return n
end
local S, X = NS.S, NS.X

H.section("the record: a report folds in, the fuller copy of a date wins")
do
    NS.Books().record = nil
    local gear = {}
    for i = 1, 19 do gear[i] = { 1000 + i, 30, i == 5 and 0 or 7, 0, {} } end
    local report = {
        rows = {},
        nightly = {
            ["2026-10-09"] = { kills = 3, raiders = { Alice = raider(3, 4), Bob = raider(1, 2, 1) }, bosses = {} },
            ["2026-10-16"] = { kills = 2, raiders = { Alice = raider(2, 3) },
                               bosses = { ["Boss One"] = { pulls = 3, kills = 2, best = 245000, killers = { "Alice" } } } },
        },
        cards = { Alice = { gear = gear, gearDate = "2026-10-16" } },
    }
    local n, g = S.Import(report)
    H.eq(n, 2, "both nights taken in")
    H.eq(g, 1, "and Alice's gear")
    H.eq(S.Record().nights["2026-10-16"].by, "Kumlust", "a night says who imported it")
    H.eq(select(1, S.Import(report)), 0, "the same report twice changes nothing")

    -- Bob was there for 1 of 3 kills on the 9th: not half, so not his night
    local cards = S.Cards()
    H.ok(deq(cards.Alice.attended, { "2026-10-09", "2026-10-16" }), "Alice earned both nights")
    H.ok(deq(cards.Bob.attended, {}), "Bob, at one kill of three, earned neither")
    H.eq(cards.Alice.last.date, "2026-10-16", "her latest night's numbers")
    H.eq(cards.Bob.deaths, 1, "deaths add up over the record")
    H.eq(#cards.Alice.issues, 1, "her unenchanted chest is the one red flag")
    H.eq(cards.Alice.issues[1].slot, "chest", "on the chest")
    H.eq(S.Bosses()["Boss One"].best, 245000, "the boss page has its fastest kill")

    -- a thinner copy of the 16th (somebody's log started late) does not replace a fuller one
    H.ok(not S.Put("2026-10-16", { kills = 1, raiders = { Alice = raider(1, 1) }, bosses = {} }, "Late"),
         "a thinner copy is refused")
    H.ok(S.Put("2026-10-16", { kills = 2, raiders = { Alice = raider(2, 3), Cara = raider(2, 3) }, bosses = {} }, "Full"),
         "a fuller copy wins")
    H.ok(not S.Put("2026-10-16", { kills = 2, raiders = { Alice = raider(2, 3), Dan = raider(2, 3) }, bosses = {} }, "Tie"),
         "an equal copy does not flip it back and forth")
    H.ok(not S.Put("16 Oct", { kills = 1, raiders = {} }), "a date that is not a date is refused")

    H.ok(not S.PutGear("Alice", "2026-10-09", gear), "older gear does not replace newer")

    -- Init clears the old collector's `nights` on every load; the record is under another name
    fire("ADDON_LOADED", "BiSGuild")
    H.eq(#S.Dates(), 2, "a reload keeps the record")
end

-- A NIGHT IS ONE RAID, MERGED KILL BY KILL (dev/NIGHTS.md; Arn, 17 Oct: "all the officers run the power
-- shell and their logs are slightly different ... will BiS Guild be able to determine all these
-- happened at the same time and even though they're slightly different, reconcile")
H.section("a night is one raid; two officers' copies merge kill by kill")
do
    local keepRecord = NS.Books().record          -- the sharing tests below read the nights above
    NS.Books().record = nil
    local F = S.F
    local function pull(t, e, b, k, who, extra)
        local r = {}
        for _, w in ipairs(who or {}) do r[w] = F.READY + F.FLASK + F.FOOD + F.SEEN end
        local p = { t = t, e = e, b = b, k = k, ms = 60000 + e, r = k == 1 and r or {}, d = {}, p = {} }
        for key, v in pairs(extra or {}) do p[key] = v end
        return p
    end
    local function raid(pulls, zone)
        local n = { v = 2, i = 409, zone = zone or "Molten Core", start = pulls[1].t, pulls = pulls }
        n.kills, n.raiders, n.bosses = S.Derive(pulls)
        return n
    end
    local T0 = 1792202400
    -- officer A logged from the start but missed Magmadar (disconnected); officer B logged late
    local A = raid({ pull(T0, 663, "Lucifron", 1, { "Ann", "Bo", "Cid" }),
                     pull(T0 + 3600, 665, "Gehennas", 1, { "Ann", "Bo" }) })
    local B = raid({ pull(T0 + 1800 + 40, 664, "Magmadar", 1, { "Ann", "Bo", "Cid" }),
                     -- the same Gehennas kill, B's PC clock 25 s off, and B saw Cid there too
                     pull(T0 + 3600 + 25, 665, "Gehennas", 1, { "Ann", "Bo", "Cid" }, { d = { Bo = 1 } }) })
    H.ok(S.Put("2026-10-16 409", A, "Officer A"), "officer A's raid filed")
    H.ok(S.SameRaid(A, B), "B's copy is the same raid: same instance, a pull in common within 3 minutes")
    H.ok(S.Put("2026-10-16 409", B, "Officer B"), "officer B's copy merges in")
    local n = S.Record().nights["2026-10-16 409"]
    H.eq(#n.pulls, 3, "three bosses: Lucifron (A), Magmadar (B only), Gehennas (both, once)")
    H.eq(n.kills, 3, "three kills")
    H.eq(n.raiders.Cid.present, 3, "Cid at all three - B saw him at Gehennas where A did not")
    H.eq(n.raiders.Bo.deaths, 1, "Bo's death at Gehennas, from B's copy of it")
    H.eq(n.by, "Officer A", "the raid keeps who filed it first")
    H.ok(not S.Put("2026-10-16 409", B, "Officer B"), "the same copy again changes nothing")
    H.ok(not S.Put("2026-10-16 409", A, "Officer A"), "nor does A's own again")
    H.eq(#S.Dates(), 1, "still one night")

    -- ANOTHER TIME ZONE: officer C is in New York; her log dated the raid the next day. Same UTC
    -- seconds, so it is the same raid, filed under the key already there
    local C = raid({ pull(T0 + 10, 663, "Lucifron", 1, { "Ann", "Bo", "Cid", "Dee" }) })
    S.Put("2026-10-17 409", C, "Officer C")
    H.eq(#S.Dates(), 1, "a key from another time zone joins the raid already on record")
    H.eq(S.Record().nights["2026-10-16 409"].raiders.Dee.present, 1, "and Dee, seen only by C, is in it")

    -- TWO RAIDS THE SAME EVENING: Onyxia after MC, one instance each - two nights; Dee came to Onyxia
    -- only and keeps her night (the bug: the two were added, and she lost it)
    local ony = { v = 2, i = 249, zone = "Onyxia's Lair", start = T0 + 9000,
                  pulls = { pull(T0 + 9000, 1084, "Onyxia", 1, { "Ann", "Dee" }) } }
    H.ok(S.Put("2026-10-16 249", ony, "Officer A"), "Onyxia the same evening is its own night")
    H.eq(#S.Dates(), 2, "two nights that date")
    local cards = S.Cards()
    H.ok(deq(cards.Dee.attended, { "2026-10-16 249" }), "Dee keeps the Onyxia night")
    H.eq(S.Label("2026-10-16 249"), "2026-10-16 Onyxia's Lair", "a raid is shown by its date and name")

    -- ANOTHER TEAM, SAME INSTANCE, SAME DATE, no pull in common: a second raid, not a merge
    local other = raid({ pull(T0 + 20000, 663, "Lucifron", 1, { "Zed", "Yan" }) })
    H.ok(S.Put("2026-10-16 409", other, "Team Two"), "another team's MC that evening is filed")
    H.ok(S.Record().nights["2026-10-16 409-2"] ~= nil, "under its own key, -2")
    H.eq(S.Label("2026-10-16 409-2"), "2026-10-16 Molten Core (2)", "and shown as the second")

    -- A WHOLE-DATE NIGHT (before 17 Oct, or from a copy not yet updated) never sits beside raids
    H.ok(not S.Put("2026-10-16", { kills = 9, raiders = { Ann = raider(9, 9) }, bosses = {} }, "Old copy"),
         "a whole-date night for a date with raids is refused - it would count the evening twice")
    NS.Books().record = nil
    S.Put("2026-10-20", { kills = 2, raiders = { Ann = raider(2, 2) }, bosses = {} }, "Old")
    H.ok(S.Record().nights["2026-10-20"] ~= nil, "on a date without raids it is kept, as before")
    S.Put("2026-10-20 409", raid({ pull(T0 + 4 * 86400, 663, "Lucifron", 1, { "Ann" }) }), "New")
    H.ok(S.Record().nights["2026-10-20"] == nil and S.Record().nights["2026-10-20 409"] ~= nil,
         "and a raid of that date replaces it: the whole-date night was every raid of it added")
    H.ok(not S.Put("2026-10-20 409x", raid({ pull(T0, 1, "X", 1, { "A" }) })), "a key that is not a key is refused")
    NS.Books().record = keepRecord
end

H.section("each guild its own books (Arn, 16 Oct: 'some people have alts in other guilds')")
do
    local main = NS.Books()
    main.roster = "Bob, Kio"
    local realGI = _G.GetGuildInfo
    _G.GetGuildInfo = function() return "Some Other Guild" end
    local alt = NS.Books()
    H.ok(alt ~= main, "an alt in another guild has other books")
    H.eq(alt.roster, nil, "and does not see the main guild's pasted roster")
    H.eq(#S.Dates(), 0, "nor its raid nights - so it can never share them with its own guild")
    _G.GetGuildInfo = function() return nil end
    H.ok(NS.Books() == NS.unfiled and next(NS.unfiled) == nil, "before the client names the guild: an empty stand-in, never a guess")
    _G.GetGuildInfo = realGI
    H.ok(NS.Books() == main and main.roster == "Bob, Kio", "back on the main: its own books, as they were")
    main.roster = nil

    -- the report from this computer is filed only where its raiders are
    local keepRep = _G.BiSGuildReport
    _G.BiSGuildReport = { rows = {}, nightly = { ["2026-10-20"] = { kills = 1, raiders = {
        Kumlust = { present = 1 }, Stranger1 = { present = 1 }, Stranger2 = { present = 1 } }, bosses = {} } } }
    S.imported = {}
    _G.GetGuildInfo = function() return "Some Other Guild" end
    local realInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function() return "Nobodyhere" end
    NS.K._guildDirty = true
    H.ok(not S.ImportWhenReady(), "an alt's guild with none of the report's raiders: not filed there")
    H.eq(NS.Books().record and NS.Books().record.nights["2026-10-20"], nil, "nothing in its books")
    _G.GetGuildInfo, _G.GetGuildRosterInfo = realGI, realInfo
    NS.K._guildDirty = true
    S.imported = {}
    H.ok(S.ImportWhenReady(), "the main's guild, where Kumlust is: filed")
    H.ok(S.Record().nights["2026-10-20"] ~= nil, "the night is in the main guild's books")
    S.Record().nights["2026-10-20"] = nil
    _G.BiSGuildReport = keepRep

    -- the books kept account-wide before the change go to the first guild seen after it - once
    local d = _G.BiSGuildDB
    local keepGuilds, keepFiled = d.guilds, d.filedTo
    d.guilds, d.filedTo = nil, nil
    d.record, d.roster = { nights = { ["2026-09-29"] = { kills = 1, raiders = {} } }, gear = {} }, "old paste"
    local b = NS.Books()
    H.ok(b.record and b.record.nights["2026-09-29"] and b.roster == "old paste", "the old books move into this guild's")
    H.ok(d.record == nil and d.roster == nil and d.filedTo ~= nil, "and are not left account-wide")
    _G.GetGuildInfo = function() return "Some Other Guild" end
    H.eq(NS.Books().record, nil, "a second guild does not get them too")
    _G.GetGuildInfo = realGI
    d.guilds, d.filedTo = keepGuilds, keepFiled
end

H.section("a night on the wire: small, and the same night after")
do
    local night = bigNight()
    local text = X.EncodeNight(night)
    local parts = math.ceil(#text / X.CHUNK)
    H.say(("   a 25-raider, 8-boss night: %d characters, %d parts"):format(#text, parts))
    H.ok(parts <= 12, "a full raid night is a dozen parts at most: " .. parts)
    H.ok(deq(X.DecodeNight(text), night), "and decodes to the same night")
    H.eq(X.DecodeNight("garbage"), nil, "garbage decodes to nothing")
    H.eq(X.DecodeNight("1#Bob:1.2#"), nil, "a raider short of numbers is refused")

    local gear = {}
    for i = 1, 19 do gear[i] = i == 18 and { 0, 0, 0, 0, {} } or { 30000 + i, 66, 2500 + i, i == 16 and 2623 or 0, i == 1 and { 4001, 4002 } or {} } end
    local gtext = X.EncodeGear(gear)
    H.ok(#gtext <= 2 * X.CHUNK, "a raider's gear is two parts at most: " .. #gtext)
    H.ok(deq(X.DecodeGear(gtext), gear), "and decodes to the same gear")
end

H.section("sharing: officers answer, members are not believed")
do
    local ROSTER = { { "Kumlust-Dreamscythe", 1 }, { "Bigboss", 0 }, { "Memberguy", 4 } }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] return r[1], "rank", r[2] end
    lib._guildDirty = true
    X._ranksDirty = true

    H.ok(X.IsOfficer("Kumlust") and X.IsOfficer("Bigboss"), "ranks 0 and 1 are officers")
    H.ok(not X.IsOfficer("Memberguy") and not X.IsOfficer("Stranger"), "a member and a stranger are not")
    -- THE GUILD INFORMATION TEXT IS NEVER READ (Arn's BugGrabber, 19 Oct: GetGuildInfoText is protected
    -- on Forever - an addon calling it is blocked). The mock is the client: calling it is the block.
    local asked = 0
    _G.GetGuildInfoText = function() asked = asked + 1 error("ADDON_ACTION_BLOCKED: GetGuildInfoText", 0) end
    H.eq(X.OfficerRank(), 1, "the guild master and the rank under")
    X.Announce()
    H.eq(asked, 0, "and the protected Guild Information text is never asked")
    NS.DB().officerRank = 4
    H.ok(X.IsOfficer("Memberguy"), "the saved officerRank still moves it, on this client (testing)")
    NS.DB().officerRank = nil
    _G.GetGuildInfoText = nil

    local function drain()
        for _ = 1, 40 do H.clock = H.clock + 2 H.RunTimers() end
    end
    local function ours(cmd)
        local out = {}
        for _, w in ipairs(H.wire) do
            if w.channel == "GUILD" and w.msg:find("|GLOG|" .. cmd .. "|", 1, true) then out[#out + 1] = w end
        end
        return out
    end
    local function hear(sender, w) lib:OnMessage("BiS", w.msg, "GUILD", sender) end

    drain()
    H.wire = {}
    -- an officer with nights says so; the line fits one message
    H.ok(X.Announce(), "an officer announces what they hold")
    drain()
    local have = ours("HAVE")
    H.eq(#have, 1, "in one line")
    H.ok(have[1] and have[1].msg:find("261016.2.2", 1, true), "newest first, with raiders and kills", have[1] and have[1].msg)

    -- somebody missing the 16th hears it and asks - once
    local mine = S.Record()
    NS.Books().record = { nights = {}, gear = {} }
    H.wire = {}
    hear("Memberguy", have[1])
    drain()
    H.eq(#ours("WANT"), 0, "a member's HAVE is not worth asking about")
    hear("Bigboss", have[1])
    drain()
    local want = ours("WANT")
    H.eq(#want, 1, "an officer's HAVE: the missing night is asked for, once")
    H.ok(want[1] and want[1].msg:find("2026-10-16", 1, true), "the newest missing date first")

    -- the officer answers: a part every two seconds, every part under the client's limit
    NS.Books().record = mine
    H.wire = {}
    X.handlers.WANT("Memberguy", "2026-10-16")
    drain()
    local parts = ours("NIGHT")
    H.ok(#parts >= 1, "the officer answers the WANT: " .. #parts .. " part(s)")
    local long = 0
    for _, w in ipairs(parts) do long = math.max(long, #w.msg) end
    H.ok(long <= 250, "every part fits the 255-byte limit: " .. long)

    -- the parts, heard by a member with nothing: the same night arrives
    local sent = mine.nights["2026-10-16"]
    NS.Books().record = { nights = {}, gear = {} }
    for _, w in ipairs(parts) do hear("Memberguy", w) end
    H.eq(S.Record().nights["2026-10-16"], nil, "from a member it is not taken in")
    for _, w in ipairs(parts) do hear("Bigboss", w) end
    H.ok(deq(S.Record().nights["2026-10-16"], sent, { by = true }), "from an officer it arrives whole")
    H.eq(S.Record().nights["2026-10-16"].by, "Bigboss", "and says who sent it")

    -- ONE ANSWER, NOT TEN: an officer who hears another officer's first part stands down
    NS.Books().record = mine
    H.wire = {}
    X.handlers.WANT("Memberguy", "2026-10-16")
    hear("Bigboss", parts[1])
    drain()
    H.eq(#ours("NIGHT"), 0, "another officer already answering: we stay quiet")

    -- a member never answers, even holding the night
    ROSTER[1][2] = 4
    X._ranksDirty = true
    H.wire = {}
    X.handlers.WANT("Bigboss", "2026-10-16")
    drain()
    H.eq(#ours("NIGHT"), 0, "a member holding the night does not answer")
    H.ok(not X.Announce(), "nor announce")
    ROSTER[1][2] = 1
    X._ranksDirty = true

    -- RAIDS ON THE WIRE (dev/NIGHTS.md, 17 Oct): HAVE2 / WANT2 / NIGHT2, every pull, merged on arrival
    do
        local F, T0 = S.F, 1792202400
        local function pull(t, e, b, k, who, deaths)
            local r = {}
            for _, w in ipairs(who) do r[w] = F.READY + F.FLASK + F.FOOD end
            return { t = t, e = e, b = b, k = k, ms = 90000, r = k == 1 and r or {}, d = deaths or {}, p = { Ann = 1 } }
        end
        local names25 = {}
        for i = 1, 25 do names25[i] = ("Raider%02d"):format(i) end
        local pulls = {}
        for b = 1, 10 do
            pulls[#pulls + 1] = pull(T0 + b * 900 - 300, 600 + b, "Boss " .. b, 0, {}, { Raider03 = 1 })      -- a wipe
            pulls[#pulls + 1] = pull(T0 + b * 900, 600 + b, "Boss " .. b, 1, names25)
        end
        local big = { v = 2, i = 409, zone = "Molten Core", start = T0, pulls = pulls }
        local text = X.EncodeRaid(big)
        local nparts = math.ceil(#text / X.CHUNK)
        H.say(("   a 25-raider raid, 10 kills and 10 wipes: %d characters, %d parts"):format(#text, nparts))
        H.ok(nparts <= X.MAX_PARTS, "a big raid fits the parts limit: " .. nparts)
        local back = X.DecodeRaid(text)
        H.ok(back and #back.pulls == 20 and back.pulls[2].r.Raider25 == F.READY + F.FLASK + F.FOOD
             and back.pulls[1].d.Raider03 == 1 and back.zone == "Molten Core",
             "and decodes to the same pulls, flags, deaths and raid name")
        H.eq(X.DecodeRaid("2#409#1#Ann#X#1.1.1.1.9:::#Z"), nil, "a pull pointing at a boss that is not there is refused")
        H.eq(X.DecodeRaid("garbage"), nil, "garbage decodes to nothing")
        -- the check number ignores times: two officers' clocks never agree to the second
        local shifted = { v = 2, i = 409, pulls = {} }
        for i, p in ipairs(pulls) do local q = {} for k2, v2 in pairs(p) do q[k2] = v2 end q.t = p.t + 40 shifted.pulls[i] = q end
        H.ok(select(2, X.Check(big)) == select(2, X.Check(shifted)), "the same raid on a clock 40 s off: the same check number")
        H.eq(X.Day("2026-10-17 409"), 20743, "a key's date as a day number")

        local mine = NS.Books().record
        NS.Books().record = { nights = {}, gear = {} }
        S.Put("2026-10-16 409", big, "Kumlust")
        local raidRecord = NS.Books().record
        H.wire = {}
        X.Announce()
        drain()
        local have2 = ours("HAVE2")
        H.ok(have2[1] and have2[1].msg:find("261016-409.20.", 1, true) and #have2[1].msg <= 250,
             "an officer announces its raids: key, pulls, check", have2[1] and have2[1].msg)
        -- a member with nothing hears it and asks with WANT2
        NS.Books().record = { nights = {}, gear = {} }
        X.wanted = {}
        H.wire = {}
        hear("Bigboss", have2[1])
        drain()
        local want2 = ours("WANT2")
        H.ok(want2[1] and want2[1].msg:find("2026-10-16 409", 1, true), "the missing raid is asked for by its key")
        -- the officer answers with NIGHT2; the member takes it in whole
        NS.Books().record = raidRecord
        H.wire = {}
        X.handlers.WANT2("Memberguy", "2026-10-16 409")
        drain()
        local p2 = ours("NIGHT2")
        H.ok(#p2 >= 1 and #p2 <= X.MAX_PARTS, "the officer answers in parts: " .. #p2)
        local longest = 0
        for _, w in ipairs(p2) do longest = math.max(longest, #w.msg) end
        H.ok(longest <= 250, "every part fits: " .. longest)
        -- the member's own copy came from another officer whose log missed the first two bosses: the
        -- answer MERGES into it, it does not replace it
        local partial = { v = 2, i = 409, zone = "Molten Core", start = T0 + 2400, pulls = {} }
        for i = 5, #pulls do partial.pulls[#partial.pulls + 1] = pulls[i] end
        NS.Books().record = { nights = {}, gear = {} }
        S.Put("2026-10-16 409", partial, "Otherofficer")
        for _, w in ipairs(p2) do hear("Bigboss", w) end
        local got = S.Record().nights["2026-10-16 409"]
        H.ok(got and #got.pulls == 20 and got.kills == 10, "merged: all 20 pulls, all 10 kills", got and #got.pulls)
        H.eq(got and got.by, "Otherofficer", "under the copy that was already there")
        -- and now it holds the same raid: the next HAVE2 asks for nothing
        X.wanted = {}
        H.wire = {}
        hear("Bigboss", have2[1])
        drain()
        H.eq(#ours("WANT2"), 0, "holding the same raid: nothing asked")
        -- an officer in another time zone filed it a day later: still the same raid, not asked for
        NS.Books().record = { nights = {}, gear = {} }
        S.Put("2026-10-17 409", big, "Eastcoast")
        X.wanted = {}
        H.wire = {}
        hear("Bigboss", have2[1])
        drain()
        H.eq(#ours("WANT2"), 0, "the same raid under the next date: recognised, nothing asked")
        -- a member's NIGHT2 is not taken in
        NS.Books().record = { nights = {}, gear = {} }
        for _, w in ipairs(p2) do hear("Memberguy", w) end
        H.eq(S.Record().nights["2026-10-16 409"], nil, "a member's raid is not believed")
        NS.Books().record = mine
        X.wanted = {}
    end

    -- PUNCTUALITY, SHARED (Arn, 16 Oct: "share the punctuality with the other officers too")
    local Lg = NS.Login
    local S0 = 1793840400
    NS.Books().punctual = {
        kio = { [S0] = { late = false, d = -600 } }, bob = { [S0] = { late = true, d = 720 } }, zed = { [S0] = { noshow = true } },
    }
    local ptext = X.EncodePunct(S0)
    H.eq(ptext, "bob:l720;kio:o-600;zed:n", "a raid's record on the wire: short, sorted")
    local back = X.DecodePunct(ptext)
    H.ok(back.kio.d == -600 and back.kio.late == false and back.bob.late and back.zed.noshow, "and back")
    H.eq(X.DecodePunct("kio:x1"), nil, "garbage is refused")
    H.wire = {}
    X.Announce()
    drain()
    local ph = ours("PHAVE")
    H.ok(ph[1] and ph[1].msg:find(S0 .. ".3", 1, true), "an officer announces its punctuality: this raid, 3 people", ph[1] and ph[1].msg)
    -- an officer who saw fewer people asks, and gets the record merged into its own
    local keepBook = NS.Books().punctual
    NS.Books().punctual = { bob = { [S0] = { late = false, d = -60 } } }   -- this officer saw Bob online at the start
    X.punctWanted = {}
    H.wire = {}
    hear("Memberguy", ph[1])
    drain()
    H.eq(#ours("PWANT"), 0, "a member's PHAVE is not asked about")
    hear("Bigboss", ph[1])
    drain()
    H.eq(#ours("PWANT"), 1, "an officer's PHAVE with more people: asked for")
    local mineNow = NS.Books().punctual
    NS.Books().punctual = keepBook
    H.wire = {}
    X.handlers.PWANT("Memberguy", tostring(S0))
    drain()
    local pp = ours("PUNC")
    H.ok(#pp >= 1, "the officer answers with the record")
    NS.Books().punctual = mineNow
    for _, w in ipairs(pp) do hear("Bigboss", w) end
    local mb = NS.Books().punctual
    H.ok(mb.kio and mb.kio[S0].d == -600, "Kio's on-time arrives")
    H.ok(mb.zed and mb.zed[S0].noshow, "Zed's no-show arrives")
    H.ok(mb.bob[S0].late == false and mb.bob[S0].d == -60,
         "Bob stays on time: one officer saw him online at the start - the other's 'late' was a relog")
    -- the merge's order: on time, then late (the smaller), then no-show
    H.ok(Lg.Merge("zed", S0, { late = true, d = 300 }) and mb.zed[S0].late, "late beats no-show - he came")
    H.ok(Lg.Merge("zed", S0, { late = true, d = 120 }) and mb.zed[S0].d == 120, "of two lates, the smaller stands")
    H.ok(not Lg.Merge("zed", S0, { noshow = true }), "and a no-show cannot undo either")
    NS.Books().punctual = nil
    H.wire = {}

    -- gear: asked for by name, answered only when ours is newer
    H.wire = {}
    X.handlers.GWANT("Memberguy", "Alice", "2026-10-16")
    drain()
    H.eq(#ours("GEAR"), 0, "nothing newer than what they have: no answer")
    X.handlers.GWANT("Memberguy", "Alice", "")
    drain()
    local gparts = ours("GEAR")
    H.ok(#gparts >= 1 and #gparts <= 2, "their gear goes out in one or two parts: " .. #gparts)
    local had = mine.gear.Alice
    NS.Books().record = { nights = {}, gear = {} }
    for _, w in ipairs(gparts) do hear("Bigboss", w) end
    H.ok(S.Record().gear.Alice and deq(S.Record().gear.Alice.gear, had.gear), "and arrives whole")

    NS.Books().record = mine
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    lib._guildDirty = true
    X._ranksDirty = true
    H.wire = {}
end

--=============================================================================
-- THE RAIDER TERMINAL (16 Oct 2026). Arn: "type in a raider name, show all the gear they have ...
-- what their attendance is, how much they consume" and "we type in a boss name, it's like its own
-- company ticker".
--=============================================================================
H.section("the terminal: what a typed line asks for")
do
    local K = NS.K
    local cards = { Kumlust = {}, Kumlance = {}, Margo = {}, Alice = {} }
    local bosses = { ["Ragnaros"] = {}, ["Magmadar"] = {} }
    local function p(line) return { K.Parse(line, cards, bosses) } end
    H.ok(deq(p("kumlust"), { "raider", "Kumlust" }), "a bare name, any case")
    H.ok(deq(p("KUMLUST <RAIDER> GO"), { "raider", "Kumlust" }), "the Bloomberg way works too")
    H.ok(deq(p("RAGNAROS <BOSS> GO"), { "boss", "Ragnaros" }), "and for a boss")
    H.ok(deq(p("rag"), { "boss", "Ragnaros" }), "the start of a name, when only one starts so")
    H.ok(deq(p("margo"), { "raider", "Margo" }), "a name ending in 'go' is not a GO")
    H.ok(deq(p("bosses"), { "bosses" }) and deq(p("<raider> go"), { "raiders" }), "the lists by word")
    local kind, offer = K.Parse("kum", cards, bosses)
    H.eq(kind, nil, "two raiders start with kum: not a guess")
    H.ok(deq(offer, { "Kumlance", "Kumlust" }), "but both are offered", offer and table.concat(offer, ","))
    H.eq(K.Parse("ma <boss>", cards, bosses), "boss", "<boss> narrows to bosses: Magmadar, not Margo")
    H.eq(K.Clock(245000), "4:05", "a kill time reads m:ss")
    H.eq(K.Clock(0), "-", "no kill, no time")
    H.ok(math.abs(K.W / K.H - 1.43) < 0.01, "the window is the family's 1.43:1")
end

H.section("the terminal: the raider card and the boss ticker")
do
    local K = NS.K
    local saved = NS.Books().record
    local gear = {}
    for i = 1, 19 do gear[i] = { 1000 + i, 30, (i == 5) and 0 or 9, 0, {} } end
    gear[18] = { 0, 0, 0, 0, {} }
    NS.Books().record = {
        nights = {
            ["2026-10-09"] = { kills = 2, raiders = { Alice = raider(2, 3), Bob = raider(2, 3, 2) },
                               bosses = { ["Boss One"] = { pulls = 3, kills = 1, best = 250000, killers = { "Alice", "Bob" } } } },
            ["2026-10-16"] = { kills = 2, raiders = { Alice = raider(2, 2) },
                               bosses = { ["Boss One"] = { pulls = 1, kills = 1, best = 245000, killers = { "Alice" } } } },
        },
        gear = { Alice = { date = "2026-10-16", gear = gear } },
    }
    _G.GetItemInfo = function(id) if id == 1001 then return "Helm of Testing", nil, 4 end return nil end

    -- empty first: the window says what to do instead of showing blank tables
    local rec = NS.Books().record
    NS.Books().record = { nights = {}, gear = {} }
    K.page = nil
    local f = K.Show()
    H.ok(f and f:IsShown(), "the terminal opens")
    H.eq(K.page, "raiders", "it opens on the raiders")
    -- the guild is listed (Kumlust, no raids): the long hint would print THROUGH his row (Arn, 5 Nov
    -- screenshot) - so the panel keeps its rows and the status line says where nights come from
    H.ok(f.pages.raiders.grid.rows[1]:IsShown(), "the guild is listed with no nights")
    -- THE ROW POPS UNDER THE MOUSE (Arn, 6 Nov, the family rule): a stronger tint and a bright bar on the left - both
    -- on the HIGHLIGHT layer, which the client draws over the text, so the tint stays a tint (16 Oct: 0.8 washed the
    -- words out) and the bar does the popping
    do
        local row = f.pages.raiders.grid.rows[1]
        local tint, bar
        for _, t in ipairs(row._regions or {}) do
            if t._layer == "HIGHLIGHT" and t._color then
                if t._w == 2 then bar = t elseif t._all then tint = t end
            end
        end
        H.ok(tint and tint._color[4] >= 0.25 and tint._color[4] <= 0.35, "a row's hover tint: clear, still a tint",
             tint and tint._color[4])
        H.ok(bar and bar._color[4] == 1, "and a bright bar on its left edge")
    end
    H.ok(not f.pages.raiders.panel.hint:IsShown(), "so no hint over the rows")
    H.ok(f.pages.raiders.panel.hint:GetText():find("LOG", 1, true), "the hint, for an empty list, says where the nights come from")
    f.keys.raiders:Click()
    H.ok(f.status:GetText():find("LOG tab", 1, true), "the status line says it instead", f.status:GetText())
    -- Arn, 16 Oct: clicking BOSSES on a fresh install did "nothing" - it must open its own page
    f.keys.bosses:Click()
    H.eq(K.page, "bosses", "the BOSSES tab opens the bosses, even empty")
    H.ok(f.pages.bosses:IsShown() and not f.pages.raiders:IsShown(), "and the page changes")
    H.ok(f.pages.bosses.panel.hint:IsShown(), "with its own why")
    NS.Books().record = rec

    f.keys.raiders:Click()
    H.eq(K.page, "raiders", "the RAIDERS tab")
    H.ok(not f.pages.raiders.panel.hint:IsShown(), "with nights, no hint")
    -- EVERY GUILD MEMBER IS LISTED (Arn, 18 Oct): the test guild is Kumlust alone, with no raids - so
    -- he heads the list, greyed, above Alice and Bob, who are pugs here
    local rows = f.pages.raiders.grid.rows
    H.eq(rows[1].key, "Kumlust", "a guild member with no raids is listed, above the pugs")
    H.eq(rows[1].cells[7]:GetText(), "no raids yet", "and says so")
    H.eq(rows[1].cells[3]:GetText(), "-", "with nothing to count")
    local row1 = rows[2]
    H.eq(row1.key, "Alice", "then Alice")
    H.eq(row1.cells[3]:GetText(), "100%", "Alice made both nights")
    H.eq(rows[3].cells[3]:GetText(), "50%", "Bob one of two")
    H.ok(not rows[4]:IsShown(), "and no empty rows show")
    H.eq(row1.cells[7]:GetText(), "1 no enchant", "Alice's gear: one flag")
    H.eq(rows[3].cells[7]:GetText(), "no gear seen",
         "Bob has no gear on record: not 'clean' - nobody saw it")

    -- a member with no raids opens a page that says so (Arn: "just a generic message that this player
    -- has no raids logged with us")
    rows[1]:Click()
    H.eq(K.page, "raider", "clicking a member with no raids opens their page")
    H.eq(K.key, "Kumlust", "theirs")
    H.eq(f.pages.raider.attLine:GetText(), "no raids logged with us yet", "and it says they have no raids with us")
    f.keys.raiders:Click()

    H.wire = {}
    row1:Click()
    H.eq(K.page, "raider", "clicking a row opens the card")
    H.eq(K.key, "Alice", "Alice's")
    local rc = f.pages.raider
    H.eq(rc.gear.rows[1].cells[2]:GetText(), "Helm of Testing", "the armory names the item")
    H.eq(rc.gear.rows[2].cells[2]:GetText(), "item 1002", "or says its number until the client knows it")
    H.eq(rc.gear.rows[5].cells[4]:GetText(), "no enchant", "the unenchanted chest is flagged")
    H.eq(rc.gear.rows[18].cells[2]:GetText(), "-", "an empty slot is a dash")

    -- HOVER FOR THE ITEM, ENCHANT INCLUDED (Arn: "the tooltip come out, ideally with the enchant")
    local tipped
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() tipped = "hidden" end,
                       SetHyperlink = function(_, l) tipped = l end }
    rc.gear.rows[2]:Fire("OnEnter")
    H.eq(tipped, "item:1002:9", "hovering the neck: the game's tooltip, with her enchant in it")
    rc.gear.rows[2]:Fire("OnLeave")
    H.eq(tipped, "hidden", "and it goes away")
    tipped = nil
    rc.gear.rows[18]:Fire("OnEnter")
    H.eq(tipped, nil, "an empty slot has no tooltip")
    local linked
    _G.ChatEdit_InsertLink = function(l) linked = l end
    _G.GetItemInfo = function(id)
        if id == 1001 then return "Helm of Testing", nil, 4 end
        if id == "item:1002:9" then return "Neck", "|cff1eff00|Hitem:1002:9|h[Neck]|h|r", 2 end
    end
    _G.IsShiftKeyDown = function() return false end
    rc.gear.rows[2]:Click()
    H.eq(linked, nil, "a plain click links nothing")
    _G.IsShiftKeyDown = function() return true end
    rc.gear.rows[2]:Click()
    H.ok(linked and linked:find("item:1002:9", 1, true), "shift-click puts the link in chat", linked)
    _G.GameTooltip, _G.ChatEdit_InsertLink, _G.IsShiftKeyDown = nil, nil, nil
    _G.GetItemInfo = function(id) if id == 1001 then return "Helm of Testing", nil, 4 end return nil end
    H.ok(rc.attLine:GetText():find("2 of 2 nights", 1, true), "attendance in words", rc.attLine:GetText())
    H.ok(rc.consLines[1]:GetText():find("2 of 2 pulls", 1, true), "her flask on the latest night", rc.consLines[1]:GetText())
    H.eq(rc.lootLines[1]:GetText(), "nothing awarded yet", "an empty ledger: says so (BiS Guild keeps it now)")
    for _ = 1, 3 do H.clock = H.clock + 2 H.RunTimers() end
    local asked = false
    for _, w in ipairs(H.wire) do if w.msg:find("|GLOG|GWANT|Alice|", 1, true) then asked = true end end
    H.ok(asked, "opening a card asks officers for newer gear")

    -- loot won, straight from BiS Loot's ledger
    -- the ledger is BiS Guild's own now (Core/Loot.lua, LibBiSLedger): two awards, one hers
    local LG = NS.Loot.Ledger()
    LG:Add("Kumlust", { kind = "award", who = "Alice", item = "1001", resp = "MS", raid = "MC", boss = "Boss One", t = 1700000000 })
    LG:Add("Kumlust", { kind = "award", who = "Bob", item = "1003", resp = "MS", raid = "MC", boss = "Boss One", t = 1700000100 })
    K.Go("alice")
    H.ok(rc.lootLines[1]:GetText():find("Helm of Testing", 1, true), "her loot from the ledger", rc.lootLines[1]:GetText())
    H.eq(rc.lootLines[2]:GetText(), "", "and only hers")
    LG:Reset()

    -- the boss ticker
    K.Go("BOSS ONE <BOSS> GO")
    H.eq(K.page, "boss", "a boss name opens its page")
    local bp = f.pages.boss
    H.ok(bp.statLines[1]:GetText():find("2", 1, true), "two kills", bp.statLines[1]:GetText())
    H.ok(bp.statLines[4]:GetText():find("4:05", 1, true), "the fastest", bp.statLines[4]:GetText())
    H.eq(bp.statLines[5]:GetText(), "first kill   2026-10-09", "the first kill")
    H.eq(bp.grid.rows[1].key, "Alice", "most kills first")
    H.eq(bp.grid.rows[1].cells[2]:GetText(), "2", "Alice was there for both")
    H.ok(f.tick:GetText():find("BOSS ONE DOWN 4:05", 1, true), "the ticker carries the newest night", f.tick:GetText())

    -- a miss says what it could have meant
    K.Go("bo")
    H.ok(f.status:GetText():find("did you mean", 1, true), "a near miss offers names", f.status:GetText())

    -- THE LISTS SCROLL (Arn's first real report: 34 raiders, 27 rows, everyone after Rollsy gone)
    local keep = NS.Books().record.nights["2026-10-09"].raiders
    for i = 1, 40 do keep[("Zed%02d"):format(i)] = raider(1, 1) end
    f.keys.raiders:Click()
    local grid, panel = f.pages.raiders.grid, f.pages.raiders.panel
    H.ok(panel.right:GetText():find("rows 1-27 of 43", 1, true), "the corner says which rows show", panel.right:GetText())
    panel:Fire("OnMouseWheel", -1)
    H.eq(grid.offset, 3, "the wheel moves three rows")
    for _ = 1, 20 do panel:Fire("OnMouseWheel", -1) end
    H.eq(grid.offset, 16, "and stops at the last row")
    H.eq(grid.rows[27].cells[1]:GetText(), "Zed40", "the last raider is reachable")
    for _ = 1, 20 do panel:Fire("OnMouseWheel", 1) end
    H.eq(grid.offset, 0, "and back to the top")
    for i = 1, 40 do keep[("Zed%02d"):format(i)] = nil end
    K.Paint()
    H.eq(panel.right:GetText(), "0 raiders, 1 no raids, 2 pugs, 2 nights", "a list that fits says nothing about rows")

    -- STILL IN THE GUILD? (Arn: "the sheet had a check ... group the people that are pugs all the
    -- way in the bottom ... by class, all shaman alphabetical")
    do
        local nights = NS.Books().record.nights["2026-10-09"].raiders
        nights.Cara, nights.Dax, nights.Eve = raider(2, 3), raider(2, 3), raider(2, 3)
        local ROSTER = {
            { "Eve Surname", "Raider", "MAGE" }, { "Bob-Dreamscythe", "Officer", "WARRIOR" },
            { "Alice", "Raider", "MAGE" }, { "Dax", "Initiate", "SHAMAN" },
        }
        local realNum, realInfo, realColours = _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.RAID_CLASS_COLORS
        _G.GetNumGuildMembers = function() return #ROSTER end
        _G.GetGuildRosterInfo = function(i)
            local r = ROSTER[i]
            if not r then return nil end
            return r[1], r[2], 0, 60, r[3], "", "", "", false, 0, r[3]
        end
        _G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
        K._guildDirty = true
        K.sort = "class"
        f.keys.raiders:Click()
        local rows = f.pages.raiders.grid.rows
        local order = {}
        for i = 1, 5 do order[i] = rows[i].key end
        H.ok(deq(order, { "Bob", "Dax", "Alice", "Eve", "Cara" }, nil),
             "by class (warrior, shaman, mage), alphabetical inside, the pug last", table.concat(order, ","))
        H.eq(rows[1].cells[2]:GetText(), "Officer", "the guild rank, matched across a realm suffix")
        H.eq(rows[4].cells[2]:GetText(), "Raider", "and across a Forever surname")
        H.eq(rows[5].cells[2]:GetText(), "pug", "somebody not on the roster is a pug")
        H.ok(f.pages.raiders.panel.right:GetText():find("4 raiders, 1 pugs", 1, true), "the corner counts them",
             f.pages.raiders.panel.right:GetText())

        -- ATTEND sorts by attendance - the pug still at the bottom
        f.pages.raiders.grid.headButtons[3]:Click()
        H.eq(K.sort, "attend", "clicking ATTEND sorts by attendance")
        H.eq(rows[5].key, "Cara", "the pug stays last")
        f.pages.raiders.grid.headButtons[1]:Click()
        H.eq(K.sort, "class", "clicking NAME goes back to by class")

        -- A ROSTER THAT IS NOT WHOLE CALLS NOBODY A PUG: they may only be offline
        _G.GetNumGuildMembers = function() return #ROSTER + 10 end
        K._guildDirty = true
        K.Paint()
        H.eq(rows[5].cells[2]:GetText(), "?", "missing from half a roster reads ?, not pug")

        -- RUN REPORT (Arn, 19 Oct: "what our raid team looks like at the moment ... Druid: raiders by name
        -- and how many ... by looking at the last 2-4 logs who has been consistently raiding")
        _G.GetNumGuildMembers = function() return #ROSTER end
        ROSTER[#ROSTER + 1] = { "Zara Leafsong", "Initiate", "DRUID" }
        K._guildDirty = true
        local rep = K.Report(4)
        local byClass = {}
        for _, b in ipairs(rep.classes) do byClass[b.class] = b end
        H.eq(#rep.raids, math.min(4, #NS.S.Dates()), "the last raids on record, at most four")
        H.ok(byClass.SHAMAN and byClass.SHAMAN.raiding[1] and byClass.SHAMAN.raiding[1].name == "Dax",
             "Dax raided: under shaman")
        H.ok(byClass.DRUID and #byClass.DRUID.raiding == 0 and byClass.DRUID.roster[1].name == "Zara"
             and byClass.DRUID.roster[1].level == 60, "Zara has no raids: on the druid roster side, with her level")
        local cara
        for _, b in ipairs(rep.classes) do for _, x in ipairs(b.raiding) do if x.name == "Cara" then cara = { b.class, x.pug } end end end
        H.ok(cara and cara[1] == "?" and cara[2], "Cara is not in the guild: a pug, class unknown", cara and cara[1])
        local order = {}
        for _, b in ipairs(rep.classes) do order[#order + 1] = b.class end
        H.eq(order[1], "WARRIOR", "classes in the RAIDERS list's order, warrior first")
        H.eq(order[#order], "?", "and the unknown last")
        -- no raids yet (Arn: "right now nobody will come out since there are no raids out yet"): the
        -- roster is the whole team
        local none = K.Report(0)
        H.ok(#none.raids == 0 and none.raiding == 0 and none.roster == #ROSTER, "no raids: the roster is the team",
             none.roster)
        local rr = K.ReportRows(rep)
        H.ok(rr[#rr].total and rr[#rr].n == rep.raiding, "a total line closes it")
        -- the button
        f.pages.raiders.report:Click()
        H.eq(K.page, "report", "RUN REPORT opens the report")
        H.ok(f.pages.report.panel.right:GetText():find("the last", 1, true), "titled by the raids it read",
             f.pages.report.panel.right:GetText())
        K.Go("raiders")
        table.remove(ROSTER)

        nights.Cara, nights.Dax, nights.Eve = nil, nil, nil
        _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.RAID_CLASS_COLORS = realNum, realInfo, realColours
        K._guildDirty = true
        K.Paint()
    end

    -- WHERE (Arn: "a map too showing where all the raiders are at"): dots from BiS addons sharing
    -- their spot, a list from the roster of everyone online
    do
        local Wh = NS.Where
        local ROSTER = {
            { "Kumlust", "Officer", "SHAMAN", "Durotar", true }, { "Bob", "Raider", "WARRIOR", "Durotar", true },
            { "Cara", "Raider", "MAGE", "Orgrimmar", true }, { "Dax", "Raider", "PRIEST", "Durotar", false },
        }
        local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
        _G.GetNumGuildMembers = function() return #ROSTER end
        _G.GetGuildRosterInfo = function(i)
            local r = ROSTER[i]
            if not r then return nil end
            return r[1], r[2], 0, 20, r[3], r[4], "", "", r[5], 0, r[3]
        end
        K._guildDirty = true
        local files = {}
        for i = 1, 12 do files[i] = 100000 + i end
        _G.C_Map = {
            GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
            GetMapArtLayerTextures = function() return files end,
            GetMapInfo = function(id) return { name = id == 1411 and "Durotar" or "Orgrimmar" } end,
            GetBestMapForUnit = function() return 1454 end,
        }
        local realMySpot = lib.MySpot
        lib.MySpot = function() return 1411, 0.40, 0.40 end
        lib.spots.Bob = { map = 1411, x = 0.5, y = 0.5, at = H.clock }

        -- the tabs sit in the middle of the window (Arn: "the top tabs shifted a little to the right")
        local first = f.keys.raiders:OffsetFor("TOPLEFT")
        local last = f.keys.log:OffsetFor("TOPLEFT") + f.keys.log:GetWidth()
        H.ok(math.abs(first - (K.W - last)) <= 1, "the tabs are centred: " .. first .. " left, " .. (K.W - last) .. " right")

        f.keys.where:Click()
        H.eq(K.page, "where", "the WHERE tab")
        local wp = f.pages.where
        H.ok(wp.map.title:GetText():find("DUROTAR", 1, true), "the map where the dots are, by name", wp.map.title:GetText())
        local shownTiles = 0
        for _, t in ipairs(wp.tiles) do if t:IsShown() then shownTiles = shownTiles + 1 end end
        H.eq(shownTiles, 12, "the zone drawn from its twelve tiles")

        -- THE EXPLORED PIECES DRAW OVER THE FOG (Arn, Zephras Isle: "it shows fog of war, I've
        -- explored some of that map") - a separate, higher layer, never the base's
        _G.C_MapExplorationInfo = { GetExploredMapTextures = function()
            return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 50, fileDataIDs = { 7001, 7002 } } }
        end }
        K.Paint()
        local base, over = 0, 0
        for _, t in ipairs(wp.tiles) do
            if t:IsShown() then
                if t._layer == "BORDER" then base = base + 1 elseif t._layer == "ARTWORK" then over = over + 1 end
            end
        end
        H.ok(base == 12 and over == 2, "12 fog tiles under, 2 explored pieces over: " .. base .. "/" .. over)
        H.ok(Wh.why.explored == 2 and Wh.why.records == 1, "and /bisg mapwhy can say what the game gave")
        local before = #said
        _G.SlashCmdList.BISGUILD("mapwhy")
        H.ok(said[before + 1] and said[before + 1]:find("12 base tile", 1, true), "/bisg mapwhy", said[before + 1])
        _G.C_MapExplorationInfo = nil
        K.Paint()
        H.eq(wp.map.right:GetText(), "2 dots", "Bob's dot and mine")
        local labels = {}
        for i, l in ipairs(wp.labels) do if wp.dots[i]:IsShown() then labels[#labels + 1] = l:GetText() end end
        table.sort(labels)
        H.ok(deq(labels, { "Bob", "you" }), "each dot named, mine as 'you'", table.concat(labels, ","))
        -- A DOT'S BLACK EDGE GOES WITH IT (Arn, 5 Nov: two black squares stayed on every map after
        -- Durotar's). The edge is its own texture: hiding a texture never hides one anchored to it.
        local edgesUp = 0
        for _, d in ipairs(wp.dots) do if d.edge:IsShown() then edgesUp = edgesUp + 1 end end
        H.eq(edgesUp, 2, "two dots, two black edges")
        local keepOnMap = Wh.OnMap
        Wh.OnMap = function() return nil end              -- another map: nobody on it
        K.Paint()
        Wh.OnMap = keepOnMap
        H.eq(wp.map.right:GetText(), "0 dots", "a map with nobody on it")
        edgesUp = 0
        for _, d in ipairs(wp.dots) do if d.edge:IsShown() then edgesUp = edgesUp + 1 end end
        H.eq(edgesUp, 0, "and no black edge left behind")
        K.Paint()

        -- THE LITTLE FIGURES (Arn: "actual size so very tiny maybe like 10 pixels max"; "store ... when they
        -- party or raid and are near us and keep that until next time we see them") - a stand-in of their
        -- race and sex, since Forever cannot build a body (no SetCustomRace)
        local Lk = NS.Looks
        local realExists = _G.UnitExists
        H.units = { player = { name = "Kumlust", race = "Tauren", sex = 2 }, target = { name = "Bob", race = "Orc", sex = 2 } }
        _G.UnitExists = function(u) return H.units[u] ~= nil or realExists(u) end
        H.eq(Lk.Display("Bob"), nil, "never seen: no look, a plain dot")
        H.ok(Lk.Note("target"), "targeting Bob notes his race and sex")
        H.eq(Lk.Display("Bob"), Lk.FOLK.Orc[1], "Bob: the orc man's stand-in")
        H.ok(_G.BiSGuildDB.looks.bob and _G.BiSGuildDB.looks.bob.race == "Orc", "kept in the saved data, by his roster name")
        H.units.target = { name = "Stranger Danger", race = "Human", sex = 3 }
        H.ok(not Lk.Note("target"), "somebody outside the guild is not kept")
        H.units.target = { name = "Bob", race = "Pandaren", sex = 2 }
        Lk.DB().cara = nil
        H.ok(not Lk.Note("target") and Lk.Display("Bob") == Lk.FOLK.Orc[1], "a race we cannot draw is not kept (Bob stays an orc)")
        K.Paint()
        local shownFigs = {}
        for _, fg in ipairs(wp.figs or {}) do if fg:IsShown() then shownFigs[#shownFigs + 1] = fg._display end end
        table.sort(shownFigs)
        H.ok(#shownFigs == 2 and shownFigs[1] == Lk.FOLK.Tauren[1] and shownFigs[2] == Lk.FOLK.Orc[1],
             "two figures: me a tauren man, Bob an orc man", table.concat(shownFigs, ","))
        local small = 0
        for _, d in ipairs(wp.dots) do if d:IsShown() and (d._w or d:GetWidth()) == 4 then small = small + 1 end end
        H.eq(small, 2, "each stands on a small dot")
        H.ok(wp.figs[1]:GetWidth() <= 10 and wp.figs[1]:GetHeight() <= 14, "about ten pixels")
        -- they face the way they went
        local bobFig
        for _, fg in ipairs(wp.figs) do if fg:IsShown() and fg._display == Lk.FOLK.Orc[1] then bobFig = fg end end
        lib.spots.Bob = { map = 1411, x = 0.55, y = 0.5, at = H.clock }
        K.Paint()
        H.ok(math.abs(bobFig._facing - math.pi / 2) < 1e-6, "Bob walked east: he faces east", bobFig._facing)
        local calls = bobFig._display
        bobFig._display = nil
        K.Paint()
        H.eq(bobFig._display, calls, "a repaint sets the look again only when it changed")
        lib.spots.Bob = { map = 1411, x = 0.5, y = 0.5, at = H.clock }
        H.units = {}
        _G.UnitExists = realExists
        K.Paint()

        local rows = wp.grid.rows
        H.eq(rows[1].cells[1]:GetText(), "Durotar", "the busiest zone first")
        H.eq(rows[1].cells[2]:GetText(), "2", "with how many are there")
        H.eq(rows[2].key, "bob", "then the people in it, alphabetical")
        H.eq(rows[2].cells[4]:GetText(), "on map", "Bob shares his spot")
        H.eq(rows[4].cells[1]:GetText(), "Orgrimmar", "the next zone")
        H.eq(rows[5].cells[4]:GetText(), "", "Cara is listed but not on the map - no BiS addon sharing")
        local listed = false
        for _, r in ipairs(rows) do if r.key == "dax" then listed = true end end
        H.ok(not listed, "an offline member is not listed")
        H.ok(wp.who.right:GetText():find("3 online", 1, true), "the corner counts who is online")

        -- clicking somebody on the map shows their map; somebody without a dot opens their card
        lib.spots.Cara = { map = 1454, x = 0.3, y = 0.3, at = H.clock }
        K.Paint()
        rows[5]:Click()
        H.eq(K.whereMap, 1454, "clicking Cara shows her map")
        H.ok(wp.map.title:GetText():find("ORGRIMMAR", 1, true), "Orgrimmar", wp.map.title:GetText())
        -- a capital is cut to its city with the box measured for BiS Tools' overlay (14 Oct)
        local box = Wh.CROP[1454]
        local want = ((box[3] - box[1]) * 1002) / ((box[4] - box[2]) * 668)
        H.ok(math.abs(wp.land:GetWidth() / wp.land:GetHeight() - want) < 0.01,
             "Orgrimmar's land is its crop box, not the parchment", wp.land:GetWidth() / wp.land:GetHeight())
        H.eq(wp.map.right:GetText(), "1 dot", "with her dot on it")

        -- THE WORLD VIEW (Arn, 16 Oct: "world view"): when the client can place zones on Azeroth's
        -- map, WHERE opens on the whole world - dots where people are, a marker per zone for the rest
        _G.C_Map.GetMapRectOnMap = function(from, to)
            if to ~= 947 then return nil end
            if from == 1411 then return 0.40, 0.50, 0.50, 0.60 end     -- Durotar, somewhere east
            if from == 1454 then return 0.42, 0.44, 0.48, 0.50 end     -- Orgrimmar, north of it
            if from == 2001 then return 0.70, 0.80, 0.20, 0.30 end     -- an island
        end
        _G.C_Map.GetMapChildrenInfo = function(root)
            if root ~= 947 then return {} end
            return { { name = "Orgrimmar", mapID = 1454, mapType = 3 }, { name = "Durotar", mapID = 1411, mapType = 3 } }
        end
        local keepInfo = _G.C_Map.GetMapInfo
        _G.C_Map.GetMapInfo = function(id) return { name = id == 947 and "Azeroth" or (id == 1411 and "Durotar" or "Orgrimmar"),
                                                     mapType = id == 947 and 1 or 3 } end
        Wh.zoneMaps, Wh.rects = nil, {}
        local keepWhere = K.whereMap
        K.whereMap, Wh.focus = nil, nil
        K.Paint()
        H.eq(Wh.shown, 947, "WHERE opens on the world")
        H.ok(wp.map.title:GetText():find("AZEROTH", 1, true), "titled so", wp.map.title:GetText())
        local wl, dots = {}, 0
        for i, l in ipairs(wp.labels) do
            if wp.dots[i]:IsShown() then dots = dots + 1 if l:IsShown() then wl[#wl + 1] = l:GetText() end end
        end
        table.sort(wl)
        H.eq(dots, 3, "every dot, from every zone, on one map")
        -- ONE LABEL FOR A CROWD (Arn, 19 Oct: "yeah its crowded"): you and Bob, close on the world map,
        -- share "you +1"; Cara, far off, keeps her own
        H.ok(deq(wl, { "Cara", "you +1" }), "close dots share one label, you leading", table.concat(wl, ","))
        local shownMarks = 0
        for _, m in ipairs(wp.marks) do if m:IsShown() then shownMarks = shownMarks + 1 end end
        H.eq(shownMarks, 0, "everyone online here has a dot: no zone markers")
        -- the crowd rule itself: Arn's Hillsbrad - you, Frankadank beside you, and a zone marker for two
        -- guildmates with no dot, all on one spot; a dot far off keeps its own label
        local cr = Wh.Crowd({ { x = 100, y = 50, n = 1, text = "Frankadank" }, { x = 104, y = 52, n = 1, me = true },
                              { x = 98, y = 56, n = 2, mark = true }, { x = 300, y = 50, n = 1 } })
        H.ok(cr[2].lead and cr[2].extra == 3 and not cr[1].lead and not cr[3].lead,
             "you lead the crowd: 'you +3' (Frankadank, and the zone's two)")
        H.ok(cr[4].lead and cr[4].extra == 0, "a dot far off keeps its own label")
        local cr2 = Wh.Crowd({ { x = 100, y = 50, n = 2, mark = true }, { x = 110, y = 50, n = 1 } })
        H.ok(cr2[2].lead and cr2[2].extra == 2 and not cr2[1].lead, "a dot leads over a zone marker")
        lib.spots.Cara = nil
        K.Paint()
        local markText
        for _, m in ipairs(wp.marks) do if m:IsShown() then markText = m.label:GetText() end end
        H.eq(markText, "Orgrimmar 1", "Cara without a dot: a marker in Orgrimmar, counted - never an invented dot")
        H.ok(wp.map.right:GetText():find("+1 zone", 1, true), "and the corner says so")
        -- DOCKED (Arn, 19 Oct: "how they track the oil tankers out at sea ... a player in an instance should
        -- show them but docked"): Cara in Shadowfang Keep sits at its door in Silverpine (1421: 44.8, 67.8)
        local cara = K.Member("Cara")
        local keepZone = cara.zone
        cara.zone = "Shadowfang Keep"
        local prevRect = _G.C_Map.GetMapRectOnMap
        _G.C_Map.GetMapRectOnMap = function(from, to)
            if from == 1421 and to == 947 then return 0.10, 0.20, 0.20, 0.30 end     -- Silverpine, far north-west
            return prevRect(from, to)
        end
        Wh.rects = {}
        local m1, dx, dy = Wh.Dock("Shadowfang Keep")
        H.ok(m1 == 1421 and math.abs(dx - 0.448) < 1e-9 and math.abs(dy - 0.678) < 1e-9, "Shadowfang Keep's door: Silverpine 44.8, 67.8")
        K.Paint()
        local docked, orgMark
        for _, m in ipairs(wp.marks) do
            if m:IsShown() and m.label:IsShown() then
                if m.label:GetText():find("docked", 1, true) then docked = m.label:GetText() end
                if m.label:GetText():find("Orgrimmar", 1, true) then orgMark = true end
            end
        end
        H.eq(docked, "Cara - docked: Shadowfang Keep", "Cara in the dungeon: docked at its door")
        H.ok(not orgMark, "and not counted in a zone as well")
        local keepFaction = _G.UnitFactionGroup
        _G.UnitFactionGroup = function() return "Alliance", "Alliance" end
        local wm = Wh.Dock("Warsong Gulch")
        _G.UnitFactionGroup = function() return "Horde", "Horde" end
        H.ok(wm == 1440 and Wh.Dock("Warsong Gulch") == 1413, "a battleground docks at your faction's door")
        _G.UnitFactionGroup = keepFaction
        cara.zone = keepZone
        _G.C_Map.GetMapRectOnMap = prevRect
        Wh.rects = {}
        K.Paint()
        H.ok(not wp.world:IsShown(), "on the world: no WORLD button")
        rows[2]:Click()                                       -- Bob, who has a dot
        H.eq(Wh.shown, 1411, "clicking somebody zooms to their zone")
        H.ok(wp.world:IsShown(), "and WORLD appears")
        wp.world:Click()
        H.eq(Wh.shown, 947, "WORLD goes back out")
        lib.spots.Cara = { map = 1454, x = 0.3, y = 0.3, at = H.clock }
        _G.C_Map.GetMapRectOnMap, _G.C_Map.GetMapChildrenInfo, _G.C_Map.GetMapInfo = nil, nil, keepInfo
        Wh.zoneMaps, Wh.rects = nil, {}
        K.whereMap = keepWhere
        K.Paint()

        -- THE BIG MAP: OpenMap's close-up when it is installed, the game's map when not
        local opened, glided, setTo
        _G.OpenWorldMap = function(m) opened = m end
        _G.WorldMapFrame = { SetMapID = function(_, m) setTo = m end }
        H.eq(wp.open.fs:GetText(), "OPEN WORLD MAP", "no OpenMap: the button opens the game's map")
        wp.open:Click()
        H.ok(opened == 1454 and setTo == 1454, "on Cara's zone")
        H.ok(f:IsShown(), "and the terminal stays open (Arn: 'it closes our window')")
        H.eq(f._strata, "HIGH", "on the world map's layer, so the one clicked last is in front")

        -- somebody without a dot: their card by the first word of a Forever whole name, or a plain why
        Wh.Person({ name = "Bob Ofpills", zone = "Durotar", level = 9 })
        H.ok(K.page == "raider" and K.key == "Bob", "'Bob Ofpills' from the roster opens Bob's card from the log")
        K.Go("where")
        Wh.Person({ name = "Fistfull Ofpills", zone = "Zephras Isle", level = 9 })
        H.ok(K.page == "where" and f.status:GetText():find("no raid nights yet", 1, true),
             "nobody on the record: it says why instead of 'no raider called'", f.status:GetText())

        -- THEIR ZONE WITHOUT A BIS ADDON (Arn: "can it still read where they are at and open to that
        -- map?"): the roster's zone name, found among the maps, opened - with no invented dot
        _G.C_Map.GetMapChildrenInfo = function(root)
            if root ~= 947 then return {} end
            return { { name = "Orgrimmar", mapID = 1454, mapType = 3 }, { name = "Orgrimmar", mapID = 9999, mapType = 4 },
                     { name = "Zephras Isle", mapID = 2001, mapType = 3 } }
        end
        Wh.zoneMaps = nil
        H.eq(Wh.MapForZone("orgrimmar"), 1454, "a zone name finds its map, the city before a dungeon floor of that name")
        K.whereMap = 1411
        Wh.Person({ name = "Fistfull Ofpills", zone = "Zephras Isle", level = 9 })
        H.eq(K.whereMap, 2001, "Fistfull's zone opens from the roster alone")
        H.ok(f.status:GetText():find("somewhere in Zephras Isle", 1, true), "and says 'somewhere in' - no exact spot",
             f.status:GetText())
        H.eq(Wh.focus, nil, "no dot to zoom on")
        -- IN AN INSTANCE (Arn, 19 Oct: "darth is online can we have a check that says this person is in
        -- an instance") - by name, or by the client's own map type (4 = dungeon)
        H.eq(Wh.Instance("Shadowfang Keep"), "dungeon", "Shadowfang Keep: a dungeon")
        H.eq(Wh.Instance("Molten Core"), "raid", "Molten Core: a raid")
        H.eq(Wh.Instance("Warsong Gulch"), "battleground", "Warsong Gulch: a battleground")
        H.eq(Wh.Instance("Zephras Isle"), nil, "a zone is not an instance")
        _G.C_Map.GetMapChildrenInfo = function(root)
            if root ~= 947 then return {} end
            return { { name = "Forever's New Crypt", mapID = 3001, mapType = 4 } }
        end
        Wh.zoneMaps = nil
        H.eq(Wh.Instance("Forever's New Crypt"), "dungeon", "a place the client lists as a dungeon, though not named here")
        K.whereMap = 1411
        Wh.Person({ name = "Darthsidiouz Sithlord", zone = "Shadowfang Keep", level = 21 })
        H.ok(f.status:GetText():find("Darthsidiouz Sithlord is in a dungeon - Shadowfang Keep, level 21", 1, true)
             and f.status:GetText():find("nobody's spot is shared", 1, true), "clicked: they are in a dungeon, and why no dot",
             f.status:GetText())
        H.eq(K.whereMap, 1411, "and no map is opened for it")
        _G.C_Map.GetMapChildrenInfo = nil
        Wh.zoneMaps = nil
        _G.OpenMapAPI = {
            WorldFromMap = function(m, x, y) return m == 1454 and 0.2 + x / 10 or nil, 0.3 + y / 10 end,
            IsStitched = function() return true end,
            ShowWorld = function(u, v, z) glided = { u, v, z } end,
        }
        K.Show("where")
        rows[5]:Click()
        H.eq(wp.open.fs:GetText(), "ZOOM IN OPENMAP", "with OpenMap and somebody picked: zoom in on them")
        wp.open:Click()
        H.RunTimers()
        H.ok(glided and math.abs(glided[1] - 0.23) < 1e-9 and glided[3] == Wh.ZOOM,
             "OpenMap glides to Cara, zoomed in", glided and table.concat(glided, ","))
        _G.InCombatLockdown = function() return true end
        K.Show("where")
        opened = nil
        H.ok(not Wh.OpenBig() and opened == nil, "never in combat - OpenMap's own notes: the map in a fight is blocked")
        H.ok(f.status:GetText():find("not in combat", 1, true), "and it says so")
        _G.InCombatLockdown, _G.OpenMapAPI, _G.OpenWorldMap, _G.WorldMapFrame = nil, nil, nil, nil

        -- THE ROSTER KEPT FRESH (Arn: "3 guildmates online and it only shows 2")
        local asks = 0
        local keepGI = _G.C_GuildInfo
        _G.C_GuildInfo = { GuildRoster = function() asks = asks + 1 end }
        K.Go("where")
        for _ = 1, 16 do f._scripts.OnUpdate(f, 1) end
        H.ok(asks >= 1, "WHERE open: the roster is asked for again every 15 s", asks)
        asks = 0
        fire("CHAT_MSG_SYSTEM", "|Hplayer:Nebeon|h[Nebeon]|h has come online.")
        H.eq(asks, 1, "a guildmate's 'has come online': asked at once")
        ROSTER[#ROSTER + 1] = { "Nebeon Nohealzforu", "Raider", "PRIEST", "Thunder Bluff", true }
        fire("GUILD_ROSTER_UPDATE")
        H.RunTimers()
        local seen = false
        for _, r in ipairs(wp.grid.rows) do if r.key == "nebeon nohealzforu" and r:IsShown() then seen = true end end
        H.ok(seen, "and the answer redraws WHERE: Nebeon is listed")
        ROSTER[#ROSTER] = nil
        K._guildDirty = true
        _G.C_GuildInfo = keepGI

        -- THREE NEBEONS (Arn: "not sure why the GM Neb is not showing up") - one first name, three
        -- characters; the online GM must not be overwritten by an offline alt
        ROSTER[#ROSTER + 1] = { "Nebeon Nohealzforu", "Guild Master", "PRIEST", "Mulgore", true }
        ROSTER[#ROSTER + 1] = { "Nebeon Nohotzforu", "Raider", "MAGE", "Orgrimmar", false }
        ROSTER[#ROSTER + 1] = { "Nebeon Nolightforu", "Raider", "PALADIN", "Orgrimmar", false }
        K._guildDirty = true
        K.Paint()
        local neb = 0
        for _, r in ipairs(wp.grid.rows) do if r:IsShown() and r.key and r.key:find("^nebeon") then neb = neb + 1 end end
        H.eq(neb, 1, "the online Nebeon is listed - and only he, the alts are offline")
        H.eq(K.Member("Nebeon").name, "Nebeon Nohealzforu", "a first name alone finds the online one")
        H.eq(K.Member("nebeon nolightforu").name, "Nebeon Nolightforu", "a whole name finds exactly that one")
        for _ = 1, 3 do ROSTER[#ROSTER] = nil end
        K._guildDirty = true

        -- it redraws itself while showing: a spot that moves, moves on the page
        lib.spots.Cara = { map = 1454, x = 0.6, y = 0.6, at = H.clock }
        local function dotX() local pt = wp.dots[1]._points and wp.dots[1]._points[1] return pt and pt.x end
        local before = dotX()
        local tick = f._scripts.OnUpdate
        tick(f, 1)
        H.eq(dotX(), before, "not redrawn every frame")
        for _ = 1, 5 do tick(f, 1) end
        H.ok(dotX() ~= before, "after five seconds the page draws the new spot", tostring(before) .. " -> " .. tostring(dotX()))

        -- no map at all (an instance, no art): it says so instead of a blank box
        K.whereMap = nil
        lib.spots.Bob, lib.spots.Cara = nil, nil
        lib.MySpot = function() return nil end
        _G.C_Map = nil
        K.Paint()
        H.ok(wp.none:IsShown() and wp.none:GetText():find("No map yet", 1, true), "no map: it says why", wp.none:GetText())

        local Cost = dofile("../_bisdev/dev/cost.lua")
        _G.C_Map = {
            GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
            GetMapArtLayerTextures = function() return files end,
            GetMapInfo = function() return { name = "Durotar" } end,
            GetBestMapForUnit = function() return 1411 end,
        }
        local nw, byw = Cost.Count(function() K.Paint() end)
        H.say(("   cost: one WHERE redraw = %d calls (%s)"):format(nw, Cost.Top(byw, 3)))
        H.ok(nw <= 40, "one WHERE redraw (every 5 s) stays small: " .. nw, Cost.Top(byw, 4))

        _G.C_Map = nil
        lib.MySpot = realMySpot
        K.whereMap = nil
        _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
        K._guildDirty = true
        f.keys.raiders:Click()
    end

    -- THE LOG TAB OPENS THE NOTEBOOK'S WINDOW, IN FRONT (Arn, 18 Oct: "in the logs we give them the
    -- link to go to the google code thing"; 16 Oct: "this windows kinda get overlapping")
    local pf = NS.U.BuildPaste()
    local raised = false
    pf.Raise = function() raised = true end
    pf:Hide()
    f.keys.log:Click()
    H.ok(pf:IsShown() and raised, "the LOG tab opens the paste window, raised over the terminal")
    H.ok(not (NS.U.frame and NS.U.frame:IsShown()), "not the PowerShell window - that one is the officers'")
    H.eq(pf.link:GetText(), NS.U.NOTEBOOK, "with the notebook's link in it")
    H.ok(NS.U.NOTEBOOK:find("^https://colab%.research%.google%.com/github/blankfer/BiSGuild/blob/main/") ~= nil,
         "on Google's Colab, from our GitHub, on main", NS.U.NOTEBOOK)
    -- a click selects it for Ctrl+C; a stray key cannot change it
    pf.link._scripts.OnMouseUp(pf.link)
    pf.link:SetText("oops")
    pf.link._scripts.OnTextChanged(pf.link, true)
    H.eq(pf.link:GetText(), NS.U.NOTEBOOK, "typing into the link box puts the link straight back")
    pf:Hide()
    pf.Raise = nil

    -- NO FUNCTION KEYS (Arn: "i have stuff keybound to those keys")
    local before = K.page
    f.cmd:Fire("OnKeyDown", "F2")
    H.eq(K.page, before, "F2 does nothing here - it is the raider's keybind")
    f.keys.bosses:Click()
    H.eq(K.page, "bosses", "the tab does it")
    f.cmd:SetText("alice")
    f.cmd:Fire("OnEnterPressed")
    H.eq(K.key, "Alice", "typing a name and Enter")
    H.eq(f.cmd:GetText(), "", "and the line clears for the next one")

    -- ESC: the line gives up the keyboard first, then each press walks back the way you came, and
    -- only a list closes the window (Arn: "so someone can spam esc to get back fast and close too")
    H.ok(f.cmd:HasFocus(), "the command line has the keyboard while open")
    f.cmd:Fire("OnEscapePressed")
    H.ok(not f.cmd:HasFocus(), "the first ESC hands the keyboard back")
    f.keys.bosses:Click()
    f.pages.bosses.grid.rows[1]:Click()                    -- BOSSES -> Boss One
    f.pages.boss.grid.rows[1]:Click()                      -- -> Alice, who killed it
    H.eq(K.key, "Alice", "boss page to a killer's card")
    H.ok(f.status:GetText():find("esc: back", 1, true), "a card says esc goes back")
    local function esc() f:Fire("OnKeyDown", "ESCAPE") end
    esc()
    H.ok(f:IsShown() and K.page == "boss" and K.key == "Boss One", "ESC: back to the boss she came from")
    esc()
    H.ok(f:IsShown() and K.page == "bosses", "ESC: back to the bosses list")
    esc()
    H.ok(not f:IsShown(), "ESC on a list closes the window")
    K.Show("alice")
    H.eq(K.page, "raider", "a card opened straight from /bisg alice")
    esc()
    H.ok(f:IsShown() and K.page == "raiders", "with nothing behind it, ESC goes to its list")
    esc()
    H.ok(not f:IsShown(), "and then closes")

    -- /bisg opens it; /bisg <name> opens a card
    _G.SlashCmdList.BISGUILD("")
    H.ok(f:IsShown(), "a bare /bisg opens the terminal")
    _G.SlashCmdList.BISGUILD("")
    H.ok(not f:IsShown(), "and closes it")
    _G.SlashCmdList.BISGUILD("bob")
    H.ok(f:IsShown() and K.key == "Bob", "/bisg bob opens Bob's card")
    K.Hide()

    _G.GetItemInfo = nil
    NS.Books().record = saved
end

H.section("ESC closes the logins window too (6 Nov: the family audit found it had none)")
do
    local lf = NS.Login and NS.Login.Build and NS.Login.Build()
    H.ok(lf and lf:GetScript("OnKeyDown") ~= nil, "BiSGuildLogins listens for Escape (ns.EscKeys, combat-safe)")
end

H.section("ESC in combat (Arn, 16 Oct: ADDON_ACTION_BLOCKED opening the terminal mid-fight)")
do
    local fighting = true
    _G.InCombatLockdown = function() return fighting end
    local f = CreateFrame("Frame")
    local escaped = 0
    local ok, err = pcall(NS.EscKeys, f, function() escaped = escaped + 1 end)
    H.ok(ok, "a window built in combat does not touch the protected call", err)
    H.ok(not f._keyboard, "and leaves the keyboard alone until the fight is over")
    ok, err = pcall(f._scripts.OnKeyDown, f, "ESCAPE")
    H.ok(ok and escaped == 1, "ESC in combat still steps back or closes", err)
    ok = pcall(f._scripts.OnKeyDown, f, "W")
    H.ok(ok, "any other key in combat: no protected call")
    fighting = false
    fire("PLAYER_REGEN_ENABLED")
    H.ok(f._keyboard and f._propagate, "out of combat: keyboard on, every key passing through to the game")
    f._scripts.OnKeyDown(f, "ESCAPE")
    H.eq(f._propagate, false, "ESC out of combat is kept from the game menu")
    H.RunTimers()
    H.eq(f._propagate, true, "and a moment later keys pass through again - the next one never vanishes")

    -- the real windows, opened mid-fight
    fighting = true
    local K = NS.K
    K.frame = nil
    ok, err = pcall(K.Show, "raiders")
    H.ok(ok and K.frame and K.frame:IsShown(), "the terminal opens mid-fight without a blocked action", err)
    ok, err = pcall(K.frame._scripts.OnKeyDown, K.frame, "ESCAPE")
    H.ok(ok and not K.frame:IsShown(), "and ESC closes it mid-fight", err)
    NS.U.frame = nil
    ok, err = pcall(NS.U.Show)
    H.ok(ok, "the log window too", err)
    NS.U.Hide()
    fighting = false
    fire("PLAYER_REGEN_ENABLED")
    _G.InCombatLockdown = nil
end

--=============================================================================
-- INVITES (16 Oct 2026). Arn: "it'll plug into or use its own invite to raid module like BiS Tools",
-- "someone can import a code to build a roster and one click invites them", and then: "I like
-- OpenMap, that opens its stuff via API ... if installed it can API-call it", "bisg can do its own
-- thing if no BiS Tools".
--=============================================================================
H.section("invites: a pasted roster, BiS Tools' API when it is here, our own when not")
do
    local I, K = NS.Inv, NS.K
    local ROSTER = {
        { "Bob", "Raider", "WARRIOR", true }, { "Kio Alpha", "Raider", "MAGE", true },
        { "Cara", "Raider", "MAGE", false }, { "Kumlust", "Officer", "SHAMAN", true },
    }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i)
        local r = ROSTER[i]
        if r then return r[1], r[2], 1, 30, r[3], "Orgrimmar", "", "", r[4], 0, r[3] end
    end
    K._guildDirty = true

    -- A DISCORD ROSTER IN ANY SHAPE: headers, roles, classes, numbering, a whole Forever name
    local pasted = "Molten Core - Tuesday 8pm\nTanks: Bob (Warrior)\nHealers: kio alpha, Cara\nDPS\n1. Darthsidiouz - Mage\n"
    local rows = I.Read(pasted)
    local byName = {}
    for _, r in ipairs(rows) do byName[r.typed] = r end
    H.ok(byName.Bob and byName.Bob.member, "Bob found in the guild, his class word ignored")
    H.ok(byName["Kio Alpha"] and byName["Kio Alpha"].member, "'kio alpha' finds Forever's whole name, any case")
    H.ok(byName.Cara and byName.Cara.member, "Cara on a comma line")
    H.ok(byName.Darthsidiouz and not byName.Darthsidiouz.member, "Darthsidiouz is not in the guild - listed, not guessed")
    H.ok(not byName.Tanks and not byName.Healers and not byName.DPS and not byName.Mage, "role and class words are not people")
    local here = I.Here()
    H.eq(I.Status(byName.Cara, here), "offline", "Cara is offline")
    H.eq(I.Status(byName.Darthsidiouz, here), "not in guild", "and the stranger says so")

    -- the ROSTER page: paste, READ IT, the list and its button
    local f = K.Show("roster")
    local rp = f.pages.roster
    H.eq(K.page, "roster", "the ROSTER tab")
    -- a click anywhere in the dark paste area gives the box the keyboard (Arn: "I can't paste")
    rp.box:ClearFocus()
    rp.scroll:Fire("OnMouseDown", "LeftButton")
    H.ok(rp.box:HasFocus(), "clicking the paste area puts the cursor in the box")
    H.eq(rp.scroll._child, rp.box, "and the box scrolls inside it")
    -- PASTE: the cursor in an empty box, and a paste reads itself (Arn: "a get-from-clipboard button")
    rp.box:SetText("old stuff")
    rp.box:ClearFocus()
    rp.pasteBtn:Click()
    H.ok(rp.box:HasFocus() and rp.box:GetText() == "", "PASTE empties the box and gives it the cursor")
    H.ok(f.status:GetText():find("Ctrl+V", 1, true), "and says to press Ctrl+V")
    rp.box._text = pasted
    rp.box:Fire("OnTextChanged", true)
    H.RunTimers()
    H.eq(NS.Books().roster, pasted, "a paste reads itself - no READ IT needed")
    rp.box:ClearFocus()
    rp.box:SetText(pasted)
    rp.read:Click()
    H.eq(NS.Books().roster, pasted, "READ IT keeps the paste across a reload")
    H.eq(rp.send.fs:GetText(), "INVITE 2 ONLINE", "two of them online and not you")

    -- THE GREYED HINT (Arn: "a greyed out button <needs BiS Tools> ... only if it makes sense")
    _G.BiSToolsAPI = nil
    K.Paint()
    H.ok(rp.toolsHint:IsShown() and rp.toolsHint.fs:GetText():find("needs BiS Tools", 1, true),
         "no BiS Tools, a roster to review: the dim 'confirm list - needs BiS Tools' beside INVITE")
    local tiplines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
                       AddLine = function(_, s) tiplines[#tiplines + 1] = s end }
    rp.toolsHint:Fire("OnEnter")
    H.ok(tiplines[2] and tiplines[2]:find("work without it", 1, true), "its tooltip says what BiS Tools adds - and that ours works without it")
    _G.GameTooltip = nil
    _G.BiSToolsAPI = { major = 1, version = 1, PartyReady = function() return true end }
    K.Paint()
    H.ok(not rp.toolsHint:IsShown(), "BiS Tools here: no hint")
    _G.BiSToolsAPI = nil
    K.Paint()

    -- WITHOUT BiS Tools: the second click sends, one invite at a time, whole names
    local invited = {}
    local keepPI = _G.C_PartyInfo
    _G.C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end, ConvertToRaid = function() end }
    _G.BiSToolsAPI = nil
    rp.send:Click()
    H.eq(#invited, 0, "the first click only asks")
    H.ok(f.status:GetText():find("click again", 1, true), "and says how to send", f.status:GetText())
    rp.send:Click()
    for _ = 1, 5 do H.RunTimers() end
    table.sort(invited)
    H.ok(deq(invited, { "Bob", "Kio Alpha" }), "the second click invites who is online - never the stranger, never Cara",
         table.concat(invited, ","))
    H.clock = H.clock + 60
    invited = {}
    rp.send:Click()
    H.eq(#invited, 0, "minutes later, a click asks again")
    H.clock = H.clock + 60
    I.armed = nil

    -- WITH BiS Tools: its API takes the list (its confirm list, its show, its refusals in red)
    local got
    _G.BiSToolsAPI = { major = 1, version = 1, PartyReady = function() return true end,
                       InviteList = function(label, people) got = { label = label, people = people } return #people end,
                       InviteOne = function(n) got = { one = n } return 1 end }
    rp.send:Click()
    H.ok(got and got.label == "on the pasted roster" and #got.people == 2, "BiS Tools installed: its API gets the list")
    H.eq(got and got.people[1].classFile ~= nil and true, true, "with each class, for its sort")
    H.eq(#invited, 0, "and BiS Guild sends nothing itself")
    _G.BiSToolsAPI.PartyReady = function() return false end
    rp.send:Click()
    H.ok(f.status:GetText():find("click again", 1, true), "its party tool off: BiS Guild does its own thing")
    I.armed = nil

    -- a raider's card: INVITE, at once, by the whole name
    _G.BiSToolsAPI = nil
    invited = {}
    NS.Books().record.nights["2026-10-09"].raiders.Kio = raider(2, 3)
    K.Go("kio <raider>")
    f.pages.raider.invite:Click()
    H.ok(deq(invited, { "Kio Alpha" }), "INVITE on Kio's card invites 'Kio Alpha' - the name an invite needs",
         table.concat(invited, ","))

    -- RAIDERS: INVITE ONLINE is everyone on the record who is online
    local online = {}
    for _, m in ipairs(I.OnlineRaiders()) do online[#online + 1] = m.name end
    H.ok(deq(online, { "Bob", "Kio Alpha" }), "raiders on the record and online: Bob, Kio", table.concat(online, ","))

    -- INVITE ONLINE SAYS WHO IT LEFT OUT (Arn: "it only invited Shwed, it ignored Ari and Mare")
    NS.Books().record.nights["2026-10-09"].raiders.Cara = raider(2, 3)
    invited = {}
    I.InviteOnline()
    I.InviteOnline()
    for _ = 1, 5 do H.RunTimers() end
    H.ok(f.status:GetText():find("offline, not invited: Cara", 1, true), "Cara, offline, is named - not silently skipped",
         f.status:GetText())
    NS.Books().record.nights["2026-10-09"].raiders.Cara = nil
    H.clock = H.clock + 60
    I.armed = nil

    -- RAID-HELPER'S EXPORT (Arn: "raid helper only does json"; two real exports pasted 16 Oct):
    -- sign-ups only, Discord nicknames, absences, one person signed for several specs
    local json = '{"date":"06-10-2026","signUps":['
        .. '{"cClassName":"Absence","className":"Absence","name":"Cara","id":1,"position":8,"status":"primary"},'
        .. '{"cClassName":"Mage","className":"Mage","specName":"Arcane","name":"Bloodbow/Kio","roleName":"Ranged","position":2},'
        .. '{"className":"Melee","specName":"Fury","name":"bob09","roleName":"Dps","position":3,"note":"Don\\u2019t know yet"},'
        .. '{"className":"Healer","specName":"Holy","name":"bob09","roleName":"Healers","position":4},'
        .. '{"className":"Tentative","specName":"Holy","name":"Figs","position":5}'
        .. '],"classes":[{"specs":[{"cName":"Protection","name":"Protection","roleName":"Tanks"}],"name":"Tank"}],'
        .. '"displayTitle":"Illidan did nothing wrong","time":"20:00","channelName":"tuesday-raid-sign-up"}'
    local hr = I.Read(json)
    local by = {}
    for _, r in ipairs(hr) do by[r.typed] = r end
    H.eq(#hr, 4, "four people: the class tables after the sign-ups are not people")
    H.ok(by["Kio Alpha"] and by["Kio Alpha"].member, "'Bloodbow/Kio' - a Discord main/alt - finds Kio Alpha")
    H.ok(by.Bob and by.Bob.signed == "Fury, Holy", "'bob09' is Bob, both his sign-ups on one row", by.Bob and by.Bob.signed)
    H.eq(I.Status(by.Cara, I.Here()), "absent", "Cara signed Absence: absent, never invited")
    H.ok(by.Figs and not by.Figs.member and by.Figs.standing == "tentative", "Figs: tentative, not in the guild")
    H.eq(I.event and I.event.title, "Illidan did nothing wrong", "the event's title for the header")
    local rp2 = f.pages.roster
    K.Go("roster")
    rp2.box:SetText(json)
    rp2.read:Click()
    H.ok(rp2.paste.right:GetText():find("Illidan did nothing wrong", 1, true), "shown over the paste")
    H.eq(rp2.send.fs:GetText(), "INVITE 2 ONLINE", "Kio and Bob online; Cara absent; Figs a stranger")
    local order = {}
    for i = 1, 4 do order[i] = rp2.grid.rows[i].cells[4]:GetText() end
    H.ok(deq(order, { "online", "online", "absent", "not in guild" }),
         "who can be invited first, the absent next, strangers last", table.concat(order, ","))
    NS.Books().roster = nil

    -- the same JSON pasted into the BiS> line (where the cursor sits when the terminal opens)
    f.cmd:SetText(json)
    f.cmd:Fire("OnEnterPressed")
    H.ok(K.page == "roster" and NS.Books().roster == json, "a roster in the BiS> line goes to ROSTER, not 'no raider called {'")
    NS.Books().roster = nil

    -- RIGHT-CLICK A RAIDER: the game's player menu (Arn: "can we right click and pull up the blizz menu?")
    local menu
    _G.UnitPopup_OpenMenu = function(which, ctx) menu = { which = which, name = ctx.name, chat = ctx.chatTarget } end
    NS.Books().record.nights["2026-10-09"].raiders.Kio = raider(2, 3)
    K.Go("raiders")
    local kioRow
    for _, row in ipairs(f.pages.raiders.grid.rows) do if row.key == "Kio" then kioRow = row end end
    kioRow:Click("RightButton")
    H.ok(menu and menu.which == "FRIEND" and menu.name == "Kio Alpha" and menu.chat == "Kio Alpha",
         "the player menu, by Forever's whole name - never the guild menu", menu and (menu.which .. " " .. menu.name))
    H.eq(K.page, "raiders", "and the right-click does not open the card")
    kioRow:Click("LeftButton")
    H.eq(K.key, "Kio", "a left-click still does")

    -- INSIDE AN INSTANCE THE GAME'S MENU BREAKS (7 Nov sweep): opened from our code it measures frames whose
    -- rects are secret there (FrameUtil), and the game's own menu stops working. So only where IsInInstance()
    -- reads a plain false; anywhere else (true, secret, or the call failing) one line says why, and nothing opens.
    -- The client answers IsInInstance with a SECRET boolean in places - the mock does too.
    local keepII, keepSV, keepFF = _G.IsInInstance, rawget(_G, "issecretvalue"), rawget(_G, "FriendsFrame_ShowDropdown")
    local SECRET = setmetatable({}, { __eq = function() error("attempt to compare a secret boolean value", 2) end })
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    local ffOpened
    _G.FriendsFrame_ShowDropdown = function() ffOpened = true end
    for _, case in ipairs({ { "in a dungeon", function() return true, "party" end },
                            { "a secret answer", function() return SECRET, "party" end },
                            { "the call failing", function() error("no") end } }) do
        menu, ffOpened = nil, nil
        _G.IsInInstance = case[2]
        local before = #said
        kioRow:Click("RightButton")
        H.ok(menu == nil and ffOpened == nil, case[1] .. ": the game's player menu is NOT opened")
        local line = table.concat(said, "\n", before + 1, #said)
        H.ok(#said == before + 1 and line:find("instance", 1, true), case[1] .. ": one line says why", line)
    end
    _G.IsInInstance = function() return false, "none" end
    menu = nil
    kioRow:Click("RightButton")
    H.ok(menu and menu.name == "Kio Alpha", "out in the world (a plain false): the menu opens as before")
    _G.IsInInstance, _G.issecretvalue, _G.FriendsFrame_ShowDropdown = keepII, keepSV, keepFF
    _G.UnitPopup_OpenMenu = nil
    NS.Books().record.nights["2026-10-09"].raiders.Kio = nil

    -- not the leader: nothing goes, and it says why
    H.inRaid, H.raid = true, { { name = "Kumlust" }, { name = "Zed" } }
    _G.UnitIsGroupLeader = function() return false end
    invited = {}
    I.Send((I.OnlineRaiders()), "raiders on the record")
    I.Send((I.OnlineRaiders()), "raiders on the record")
    H.ok(#invited == 0 and f.status:GetText():find("only the leader", 1, true), "only the leader invites", f.status:GetText())
    H.inRaid, H.raid, _G.UnitIsGroupLeader = false, { { name = "Kumlust" } }, nil

    NS.Books().record.nights["2026-10-09"].raiders.Kio = nil
    NS.Books().roster = nil
    _G.C_PartyInfo = keepPI
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    K._guildDirty = true
    K.Hide()
end

-- MORE THAN A PARTY HOLDS BECOMES A RAID (Arn, 21 Oct: "auto turn the party into raid when more than 5
-- people in the party or if the invited people will be more than 5"). THE CLIENT'S RULES: a party, or you
-- alone, holds five counting the invites out - the sixth is refused "party is full", no Lua error; a raid
-- is made only from a party. The kit's timers run at once whatever their delay, so this test keeps its
-- own clock that honours them.
do
    local I = NS.Inv
    local keep = { PI = _G.C_PartyInfo, IG = _G.IsInGroup, IR = _G.IsInRaid, N = _G.GetNumGroupMembers,
                   UN = _G.UnitName, Lead = _G.UnitIsGroupLeader, T = _G.C_Timer, clock = H.clock }
    local party, raid = { "Kumlust" }, false                    -- you first
    local out, full, made = {}, {}, 0
    _G.C_PartyInfo = {
        InviteUnit = function(n)
            if not raid and #party + #out >= 5 then full[#full + 1] = n return end
            out[#out + 1] = n
        end,
        ConvertToRaid = function() made = made + 1 if #party > 1 then raid = true end end,
    }
    _G.IsInGroup = function() return #party > 1 end
    _G.IsInRaid = function() return raid end
    _G.GetNumGroupMembers = function() return #party > 1 and #party or 0 end
    _G.UnitName = function(u)
        if u == "player" then return "Kumlust" end
        local i = tonumber(tostring(u):match("^party(%d+)$") or tostring(u):match("^raid(%d+)$") or "")
        if not i then return nil end
        return raid and party[i] or party[i + 1]
    end
    _G.UnitIsGroupLeader = function() return true end
    local due = {}
    _G.C_Timer = { After = function(d, fn) due[#due + 1] = { at = H.clock + d, fn = fn } end }
    local function run(dt)                          -- in small steps: a timer may set the next one
        local stop = H.clock + dt
        while H.clock < stop do
            H.clock = math.min(stop, H.clock + 0.05)
            for i = #due, 1, -1 do
                if due[i] and due[i].at <= H.clock then local t = table.remove(due, i) t.fn() end
            end
        end
    end
    local function join(n)                          -- an invite accepted: out of `out`, into the party
        for i, o in ipairs(out) do if o == n then table.remove(out, i) end end
        party[#party + 1] = (n:match("^(%S+)"))     -- Forever names a group member by first name
        fire("GROUP_ROSTER_UPDATE")
    end
    I.out, I.held, I.queue, I._armed = {}, nil, {}, false

    I.Queue({ "Ari", "Mare", "Shwed", "Kio Alpha", "Bob" })
    run(5)
    H.ok(#out == 4 and #full == 0 and I.held and I.held.names[1] == "Bob",
         "alone with five to ask: four go out, Bob WAITS - the game would refuse him (party full)", #out .. " out, " .. #full .. " refused")
    H.eq(made, 0, "no raid yet: alone there is no party to make one of")
    join("Ari")
    H.ok(made == 1 and raid, "Ari joins: the party becomes a raid by itself", made)
    fire("GROUP_ROSTER_UPDATE")                     -- the raid's own roster change
    run(5)
    H.ok(I.held == nil and out[#out] == "Bob" and #full == 0, "the raid is here: Bob is asked, nothing refused", table.concat(out, ","))

    -- ONE AT A TIME (the raid-night pop-up, each raider as they log in): three of you, two out
    party, raid, out, full, made, I.out, I.queue = { "Kumlust", "Tobi", "Kio" }, false, {}, {}, 0, {}, {}
    I.Queue({ "Ari" }) run(1)
    I.Queue({ "Mare" }) run(1)
    H.ok(#out == 2 and made == 0 and I.held == nil, "three of you, two asked: five, still a party", #out)
    I.Queue({ "Shwed" }) run(1)
    H.ok(made == 1 and I.held and I.held.names[1] == "Shwed" and #full == 0,
         "the next would be the sixth: the party becomes a raid, Shwed waits instead of being refused", #full)
    fire("GROUP_ROSTER_UPDATE") run(1)
    H.ok(I.held == nil and out[3] == "Shwed", "the raid made: Shwed is asked", table.concat(out, ","))

    -- a joined player stops counting as out, by first name or whole
    party, raid, out, full, made, I.out, I.queue = { "Kumlust" }, false, {}, {}, 0, {}, {}
    I.Queue({ "Kio Alpha", "Bob" }) run(1)
    H.eq(I.Out(), 2, "alone, two asked: two out")
    join("Kio Alpha")
    H.eq(I.Out(), 1, "Kio joins (the client calls him Kio): one out")
    H.clock = H.clock + I.OUT_FOR + 1
    H.eq(I.Out(), 0, "a minute unanswered: Bob no longer counts")

    -- nobody ever joins: the waiting ones are dropped and said, never sent on some later group
    party, raid, out, full, made, I.out, I.queue = { "Kumlust" }, false, {}, {}, 0, {}, {}
    I.Queue({ "A1", "B1", "C1", "D1", "E1", "F1" }) run(5)
    H.ok(I.held and #I.held.names == 2, "alone with six: two wait", I.held and #I.held.names)
    run(I.HOLD_FOR + 1)
    H.ok(I.held == nil, "two minutes and nobody joined: dropped")
    -- LEAN: the watcher is one look at I.held - a roster change with nobody waiting asks the game nothing
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local n, by = Cost.Count(function() I.events._scripts.OnEvent(I.events, "GROUP_ROSTER_UPDATE") end)
    H.ok(n == 0, "cost: a roster change, nobody waiting = 0 calls", Cost.Top and Cost.Top(by, 3))

    I.out, I.held, I.queue, I._armed = {}, nil, {}, false
    _G.C_PartyInfo, _G.IsInGroup, _G.IsInRaid, _G.GetNumGroupMembers = keep.PI, keep.IG, keep.IR, keep.N
    _G.UnitName, _G.UnitIsGroupLeader, _G.C_Timer = keep.UN, keep.Lead, keep.T
end

--=============================================================================
-- "X JUST LOGGED IN - INVITE?" (16 Oct 2026). Arn: "if the addons can see if someone logged in and
-- they are on the roster, makes the invite button pulse or a window pop up". And: "does the json say
-- what time the raid is supposed to start?" - it does, and the pop-up keeps to raid time.
--=============================================================================
H.section("logins: somebody on the roster comes online")
do
    local L, I, K = NS.Login, NS.Inv, NS.K
    local ROSTER = {
        { "Bob", "WARRIOR", false }, { "Kio Alpha", "MAGE", false }, { "Cara", "MAGE", false }, { "Zed", "ROGUE", false },
    }
    local realNum, realInfo, realPI = _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.C_PartyInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i)
        local r = ROSTER[i]
        if r then return r[1], "Raider", 1, 30, r[2], "Orgrimmar", "", "", r[3], 0, r[2] end
    end
    local invited = {}
    _G.C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end, ConvertToRaid = function() end }
    _G.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
    K._guildDirty = true
    L.waiting, L.told, L.lastOnline = {}, {}, nil
    local start = clock + 3600                                   -- raid in an hour
    NS.Books().roster = '{"date":"16-10-2026","signUps":['
        .. '{"className":"Mage","specName":"Arcane","name":"Bloodbow/Kio","position":1},'
        .. '{"className":"Warrior","specName":"Fury","name":"bob09","position":2},'
        .. '{"className":"Absence","name":"Cara","position":3}'
        .. '],"displayTitle":"Raid night","time":"20:00","startTime":' .. start .. '}'
    local function online(name) fire("CHAT_MSG_SYSTEM", ("|Hplayer:%s-Realm|h[%s]|h has come online."):format(name, name)) end

    -- a new install starts with the pop-up off (Forever 1.0): a roster and raid time arm nothing
    H.ok(_G.BiSGuildDB.logins == false and not L.Armed(), "a new install: the login pop-up starts off, never armed")
    online("Kio Alpha")
    H.eq(#L.waiting, 0, "and a login on the roster pops nothing up")
    L.told = {}
    _G.SlashCmdList.BISGUILD("logins on")
    H.ok(L.Armed(), "a roster pasted, raid in an hour, on my own: armed")
    online("Kio Alpha")
    H.eq(#L.waiting, 1, "Kio logs in: on the roster, so he waits for an invite")
    H.ok(L.frame and L.frame:IsShown(), "the window pops up")
    H.ok(L.frame.rows[1].name:GetText():find("Kio Alpha", 1, true) and L.frame.rows[1].name:GetText():find("Arcane", 1, true),
         "named, with what he signed", L.frame.rows[1].name:GetText())
    online("Kio Alpha")
    H.eq(#L.waiting, 1, "the same login twice is one row")
    online("Cara")
    H.eq(#L.waiting, 1, "Cara signed Absence: not offered")
    online("Zed")
    H.eq(#L.waiting, 1, "Zed is not on the roster: not offered")
    online("Bob")
    H.eq(#L.waiting, 2, "Bob joins the same window")
    H.eq(L.frame.all.fs:GetText(), "Invite all (2)", "Invite all says how many")
    H.ok(math.abs(L.W / L.H - 1.43) < 0.01, "the family's 1.43:1")

    -- the terminal's invite buttons pulse while somebody waits
    local f = K.Show("raiders")
    H.clock = H.clock + 0.3
    f._scripts.OnUpdate(f, 0.016)
    H.ok(f.pages.raiders.invite._alpha and f.pages.raiders.invite._alpha < 1 or (f.pages.raiders.invite.alpha or 1) < 1,
         "INVITE ONLINE pulses while someone waits")

    -- Invite on one row: he is invited by his whole name and leaves the window
    L.frame.rows[1].invite:Click()
    for _ = 1, 3 do H.RunTimers() end
    H.ok(invited[1] == "Kio Alpha" and #L.waiting == 1, "Invite: Kio Alpha invited, one left", table.concat(invited, ","))
    L.frame.later:Click()
    H.ok(#L.waiting == 0 and not L.frame:IsShown(), "Not now: the window goes")
    f._scripts.OnUpdate(f, 0.016)
    H.eq(f.pages.raiders.invite._alpha or f.pages.raiders.invite.alpha or 1, 1, "and the pulse stops, the button solid again")
    K.Hide()

    -- RAID TIME ONLY: five hours after the start, the same roster is quiet
    L.told = {}
    local keepClock = clock
    clock = start + 5 * 3600
    H.ok(not L.Armed(), "five hours after the start: not armed")
    online("Kio Alpha")
    H.eq(#L.waiting, 0, "and no pop-up")
    clock = keepClock

    -- THE ROSTER AS BACKUP (the login chat line can be switched off): baseline, then Bob turns online
    L.told, L.lastOnline = {}, nil
    fire("GUILD_ROSTER_UPDATE")
    H.eq(#L.waiting, 0, "the first roster look only takes the baseline - nobody 'just' logged in")
    ROSTER[1][3] = true
    fire("GUILD_ROSTER_UPDATE")
    H.ok(#L.waiting == 1 and L.waiting[1].name == "Bob", "Bob turned online in the roster: offered")
    L.waiting = {}
    if L.frame then L.frame:Hide() end

    -- not the leader of the group you are in: quiet
    H.inRaid, H.raid = true, { { name = "Kumlust" }, { name = "Zed" } }
    _G.UnitIsGroupLeader = function() return false end
    L.told = {}
    H.ok(not L.Armed(), "in someone else's group: not armed")
    H.inRaid, H.raid, _G.UnitIsGroupLeader = false, { { name = "Kumlust" } }, nil

    -- /bisg logins off
    _G.SlashCmdList.BISGUILD("logins off")
    H.ok(not L.Armed(), "/bisg logins off: never")
    _G.SlashCmdList.BISGUILD("logins on")

    -- the countdown over the paste
    H.eq(I.When(I.Event(NS.Books().roster)), "starts in 1 h 0 min", "the ROSTER header counts down to the start")

    -- PUNCTUALITY (Arn: "how close they were ... if the invite went out after, meaning they were late
    -- ... server time, real time, their time zone ... habitually late, or perfect attendance")
    NS.Books().punctual = nil
    L.told, L.done, L.loggedAt, L.waiting = {}, {}, {}, {}
    for _, r in ipairs(ROSTER) do r[3] = false end
    K._guildDirty = true
    clock = start - 10 * 60                                   -- ten minutes before the start
    ROSTER[2][3] = true
    online("Kio Alpha")
    H.ok(L.waiting[1] and L.waiting[1].delta == -600, "Kio logs in 10 min early")
    H.ok(L.frame.rows[1].note:GetText():find("10 min early", 1, true), "the pop-up says so", L.frame.rows[1].note:GetText())
    clock = start + 60                                        -- the start passes
    L.Tick()
    local book = NS.Books().punctual
    H.ok(book["kio alpha"] and book["kio alpha"][start] and book["kio alpha"][start].late == false and book["kio alpha"][start].d == -600,
         "at the start, online: on time - 10 min early on record")
    H.eq(book.bob, nil, "Bob is not online at the start: nothing yet")
    clock = start + 12 * 60                                   -- Bob, twelve minutes late
    ROSTER[1][3] = true
    K._guildDirty = true
    online("Bob")
    H.ok(book.bob and book.bob[start].late and book.bob[start].d == 720, "Bob logs in 12 min after the start: late, by 12 min")
    local bobRow
    for _, row in ipairs(L.frame.rows) do if row.who and row.who.name == "Bob" then bobRow = row end end
    H.ok(bobRow and bobRow.note:GetText():find("+12 min late", 1, true), "the pop-up: '+12 min late'", bobRow and bobRow.note:GetText())
    H.ok(bobRow and bobRow.note:GetText():find("late 1 of last 1", 1, true), "and his habit so far", bobRow and bobRow.note:GetText())
    L.Tick()
    H.ok(book["kio alpha"][start].late == false, "a second look at the start changes nothing")
    -- a few more raids: Kio perfect, Bob late again and a no-show
    for n = 1, 3 do
        local s = start + n * 7 * 86400
        L.Mark("kio alpha", s, { d = -300, late = false })
        L.Mark("bob", s, n == 3 and { noshow = true } or { d = 600, late = true })
    end
    H.eq(L.HabitText("Kio Alpha"), "perfect 4 of 4", "Kio: perfect 4 of 4")
    local bh, bc = L.HabitText("Bob")
    H.ok(bh == "late 3 of last 4, avg 11 min, 1 no-show" and bc == "warn", "Bob: habitually late, and once not at all", bh)
    for n = 4, 12 do L.Mark("kio alpha", start + n * 7 * 86400, { d = -60, late = false }) end
    local kept = 0
    for _ in pairs(book["kio alpha"]) do kept = kept + 1 end
    H.eq(kept, L.KEEP, "only the last " .. L.KEEP .. " raids are kept")
    -- the window closes: whoever signed and never came is a no-show (Cara signed Absence - she is not)
    NS.Books().roster = NS.Books().roster:gsub('"name":"Cara"', '"name":"Zed","specName":"Combat"'):gsub("Absence", "Rogue")
    clock = start + L.AFTER + 60
    L.Tick()
    H.ok(book.zed and book.zed[start] and book.zed[start].noshow, "Zed signed, never came: a no-show")
    H.ok(book.bob[start].late, "and the late stay late, not turned into no-shows")
    -- the raider card says it
    clock = start - 600
    NS.Books().record.nights["2026-10-09"].raiders.Bob = NS.Books().record.nights["2026-10-09"].raiders.Bob or raider(1, 2)
    K.Show("bob <raider>")
    H.ok(K.frame.pages.raider.punct:GetText():find("late 3 of last", 1, true), "Bob's card: punctual - late 3 of last ...",
         K.frame.pages.raider.punct:GetText())
    local wr = { NS.T.rgb("warn") }
    local pr = K.frame.pages.raider.punct._color
    H.ok(pr and math.abs(pr[1] - wr[1]) < 0.01, "in the warning colour - habitually late reads red")
    K.Hide()
    if L.frame then L.frame:Hide() end
    L.waiting = {}
    NS.Books().punctual = nil
    clock = start - 3600

    -- RAID NIGHT AT A GLANCE (Arn: "raid night > raiding <xxx> start time 00:00, any info at a glance")
    local tf = K.Show("raiders")
    local gl = strip(tf.glance.fs:GetText() or "")
    H.ok(tf.glance:IsShown() and gl:find("RAID NIGHT", 1, true) and gl:find("Raid night", 1, true)
         and gl:find("20:00", 1, true) and gl:find("starts in 1 h", 1, true) and gl:find("%d+ of %d+ online"),
         "the command bar: the raid, its time, the countdown, who is on", gl)
    tf.glance:Click()
    H.eq(K.page, "roster", "clicking it opens the roster")
    local keepClock2 = clock
    clock = start + 7 * 3600
    K.Paint()
    H.ok(not tf.glance:IsShown(), "the morning after: gone")
    clock = keepClock2
    K.Hide()

    NS.Books().roster = nil
    _G.ERR_FRIEND_ONLINE_SS = nil
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.C_PartyInfo = realNum, realInfo, realPI
    K._guildDirty = true
    L.waiting, L.told, L.lastOnline = {}, {}, nil
end

--=============================================================================
-- GUILDMATES ON THE WORLD MAP (16 Oct 2026). Arn: guildmates on the world map - and "not everyone
-- is going to install OpenMap", so the game's own map, through HereBeDragons-Pins.
--=============================================================================
H.section("guildmates' dots on the world map")
do
    local M = NS.Pins
    local function pins()
        local out = {}
        for icon, p in pairs(PINS.world) do out[#out + 1] = { who = icon.who or "#box", map = p.map, x = p.x, flag = p.flag, icon = icon } end
        table.sort(out, function(a, b) return a.who < b.who end)
        return out
    end
    local ROSTER = { { "Bob", "Raider", "WARRIOR" }, { "Cara", "Raider", "MAGE" } }
    local realNum, realInfo, realColours = _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.RAID_CLASS_COLORS
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] if r then return r[1], r[2], 0, 30, r[3], "Durotar", "", "", true, 0, r[3] end end
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    NS.K._guildDirty = true
    lib.spots = {}
    -- a new install starts with the dots off (Forever 1.0): nothing is drawn until the player switches them on
    lib.spots.Bob = { map = 1411, x = 0.5, y = 0.4, at = H.clock }
    H.ok(_G.BiSGuildDB.mapDots == false and M.Update() == 0, "a new install: the dots start off, nothing drawn")
    _G.SlashCmdList.BISGUILD("dots on")
    lib.spots = {}
    H.eq(M.Update(), 0, "nobody sharing: no dots")

    lib.spots.Bob = { map = 1411, x = 0.5, y = 0.4, at = H.clock }
    lib.spots.Cara = { map = 1454, x = 0.3, y = 0.6, at = H.clock }
    H.eq(M.Update(), 2, "two guildmates sharing: two dots")
    local p = pins()
    H.ok(p[1].who == "Bob" and p[1].map == 1411 and p[1].x == 0.5, "Bob on his zone map, where he is")
    H.eq(p[1].flag, _G.HBD_PINS_WORLDMAP_SHOW_PARENT, "on his zone and one level up - not the whole world (Forever's world positions are off)")
    H.eq(next(PINS.minimap), nil, "nothing on the minimap: the world map only")

    -- he moves: his dot moves, it is not drawn twice
    lib.spots.Bob = { map = 1411, x = 0.6, y = 0.4, at = H.clock }
    M.Update()
    p = pins()
    H.eq(#p, 2, "still two dots")
    H.eq(p[1].x, 0.6, "Bob's dot followed him")

    -- he logs off (the lib drops the stale spot): his dot goes, the frame goes back to the pool
    lib.spots.Bob = nil
    M.Update()
    p = pins()
    H.ok(#p == 1 and p[1].who == "Cara", "Bob gone from the map")
    H.eq(#M.pool, 1, "his pin frame kept for the next one")

    -- RADAR TRACKS (Arn 8 Nov: "think combat jet fighter" ... "Build it"): Cara's track - the friendly half-circle and
    -- its base, her callsign, no speed line yet (one spot only)
    local c = p[1].icon
    local arcShown = 0
    for _, l in ipairs(c.arc) do if l._isLine and l:IsShown() and l._from and l._to then arcShown = arcShown + 1 end end
    H.ok(arcShown == M.ARC_SEG and c.base:IsShown() and not c.vec:IsShown(), "a track: the half-circle and its base, no speed line yet")
    H.eq(c.tag:GetText(), "CARA 30", "her callsign: first name and level")
    H.ok(not c.box[1]:IsShown(), "not a box")

    -- the card under the mouse: LOCK, class and level, where, how old; four brackets close in
    local lines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
                       AddLine = function(_, s) lines[#lines + 1] = s end }
    c:Fire("OnEnter")
    H.eq(lines[1], "LOCK  CARA", "hovering a track locks on")
    H.ok(lines[2]:find("MAGE  LVL 30", 1, true), "class and level", lines[2])
    H.ok(lines[3]:find("Durotar  30,60", 1, true) and lines[3]:find("0s ago", 1, true),
         "where and how old (the roster's zone when the map has no name)", lines[3])
    local locked = 0
    for _, t in ipairs(c.lock) do if t:IsShown() then locked = locked + 1 end end
    H.eq(locked, 8, "the lock-on brackets close in")
    c:Fire("OnLeave")
    locked = 0
    for _, t in ipairs(c.lock) do if t:IsShown() then locked = locked + 1 end end
    H.eq(locked, 0, "and open again")
    _G.GameTooltip = nil
    c:Click()
    H.ok(NS.K.frame:IsShown() and NS.K.key == "Cara", "clicking a track opens their card in the terminal")
    NS.K.Hide()

    -- /bisg dots off takes them all away; on brings them back
    _G.SlashCmdList.BISGUILD("dots off")
    H.eq(#pins(), 0, "/bisg dots off: no tracks")
    H.eq(_G.BiSGuildDB.mapDots, false, "and it is remembered")
    _G.SlashCmdList.BISGUILD("dots on")
    H.eq(#pins(), 1, "/bisg dots on: back")

    -- the card says where the track STANDS (Arn 8 Nov: a dot in Tirisfal said "Durotar" - the roster lags)
    local keepMap = _G.C_Map
    _G.C_Map = setmetatable({ GetMapInfo = function(m) return m == 1454 and { name = "Orgrimmar" } or nil end },
                            { __index = keepMap })
    lines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
                       AddLine = function(_, s2) lines[#lines + 1] = s2 end }
    pins()[1].icon:Fire("OnEnter")
    H.ok(lines[3]:find("^Orgrimmar"), "the zone of the track's own map, not the roster's", table.concat(lines, " | "))
    pins()[1].icon:Fire("OnLeave")
    _G.GameTooltip, _G.C_Map = nil, keepMap

    -- THE SPEED LINE: her next spot 20 s later, 0.1 of Orgrimmar (1700 yd) east - 8.5 yd/s: on foot, heading east
    lib.spots.Cara = { map = 1454, x = 0.4, y = 0.6, at = H.clock + 20 }
    M.Update()
    c = pins()[1].icon
    local mo = M.motion.Cara
    H.ok(mo and mo.speed and math.abs(mo.speed - 8.5) < 0.01 and M.Compass(mo.hdg) == "E" and M.SpeedOf(mo.speed) == "ON FOOT",
         "her speed and heading from two spots: on foot, east", mo and mo.speed)
    H.ok(c.vec:IsShown() and c.vec._to[1] > 0 and math.abs(c.vec._to[2] - c.vec._from[2]) < 0.01,
         "the speed line points east (right)", c.vec._to and table.concat(c.vec._to, ","))
    lib.spots.Cara = { map = 1454, x = 0.4, y = 0.2, at = H.clock + 40 }       -- 440 yd north in 20 s: 22 yd/s
    M.Update()
    c = pins()[1].icon
    H.ok(M.Compass(M.motion.Cara.hdg) == "N" and M.SpeedOf(M.motion.Cara.speed) == "VERY FAST" and c.vec._to[2] > c.vec._from[2],
         "a flight north: a long line up", M.motion.Cara.speed)
    lines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
                       AddLine = function(_, s3) lines[#lines + 1] = s3 end }
    c:Fire("OnEnter")
    H.eq(lines[3], "HDG N  VERY FAST", "the card: heading and speed")
    c:Fire("OnLeave")
    _G.GameTooltip = nil

    -- OLD SPOTS FADE: no news for more than M.STALE - hollow grey, the age on the tag, no speed line
    local keepClock = H.clock
    H.clock = H.clock + 40 + M.STALE + 5
    M.Update()
    c = pins()[1].icon
    H.ok(c.stale and not c.vec:IsShown() and c.tag:GetText():find("%d+s$"), "a stale track: grey, its age on the tag", c.tag:GetText())
    H.clock = keepClock
    lib.spots.Cara = { map = 1454, x = 0.3, y = 0.6, at = H.clock }
    M.motion.Cara = nil

    -- the callsign only on the track's own zone map, not one level up
    _G.WorldMapFrame = { GetMapID = function() return 1411 end }
    M.Update()
    c = pins()[1].icon
    H.ok(not c.tag:IsShown(), "the continent's map (not hers): no callsign")
    _G.WorldMapFrame = { GetMapID = function() return 1454 end }
    c:Fire("OnShow")
    H.ok(c.tag:IsShown(), "her own zone's map: the callsign")
    _G.WorldMapFrame = nil

    -- GROUPS MERGE: three in one spot of Orgrimmar are one box with a count; hover for the names
    lib.spots.Dee = { map = 1454, x = 0.305, y = 0.605, at = H.clock }
    lib.spots.Eve = { map = 1454, x = 0.31, y = 0.59, at = H.clock }
    H.eq(M.Update(), 1, "three close together: one mark")
    local box = pins()[1].icon
    H.ok(box.members and #box.members == 3 and box.count:GetText() == "3" and box.box[1]:IsShown() and not box.base:IsShown(),
         "a box with 3 in it, no track symbol")
    lines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
                       AddLine = function(_, s4) lines[#lines + 1] = s4 end }
    box:Fire("OnEnter")
    H.ok(lines[1] == "3 GUILDMATES HERE" and lines[2] == "Cara" and lines[4] == "Eve", "hover: who is in it", table.concat(lines, " | "))
    box:Fire("OnLeave")
    _G.GameTooltip = nil
    box:Click()
    H.ok(NS.K.frame:IsShown(), "click: the terminal (its WHERE page)")
    NS.K.Hide()
    lib.spots.Dee, lib.spots.Eve = nil, nil
    H.eq(M.Update(), 1, "they part: Cara alone, a track again")
    H.ok(pins()[1].icon.base:IsShown(), "her symbol back")

    -- OPENMAP DRAWS THE GUILD TOO (Arn 8 Nov: "open maps does the same thing now" ... "make them better"): the tracks
    -- STAY ON; one line at the first login says whose switch is which; our switch sits in OpenMap's menu
    local toggles, said = {}, {}
    local keepPrint = NS.Print
    NS.Print = function(fmt, ...) said[#said + 1] = fmt:format(...) end
    _G.OpenMapAPI = { RegisterMenuToggle = function(owner, spec) toggles[#toggles + 1] = { owner = owner, spec = spec } end }
    _G.BiSGuildDB.toldOpenMap = nil
    fire("PLAYER_LOGIN")
    H.ok(M.On() and #pins() == 1, "OpenMap here: our tracks stay on")
    H.ok(#said == 1 and said[1]:find("OpenMap", 1, true) and said[1]:find("/bisg dots off", 1, true),
         "said once: whose switch is which", said[1])
    H.ok(#toggles == 1 and toggles[1].spec.id == M.TOGGLE_ID and toggles[1].spec.label == "BiS Guild radar tracks"
         and toggles[1].spec.get() == true, "our switch in OpenMap's menu, showing on")
    H.ok(BiSGuildAPI.MapDots() == true, "BiSGuildAPI.MapDots: on")
    fire("PLAYER_LOGIN")
    H.ok(#said == 1 and #toggles == 1, "the next login: not said again, not registered twice")
    toggles[1].spec.set(false)
    local ok3, why3 = BiSGuildAPI.MapDots()
    H.ok(not M.On() and #pins() == 0 and ok3 == false and why3 == "off", "OpenMap's switch off: ours gone, the API says off")
    toggles[1].spec.set(true)
    H.ok(M.On() and #pins() == 1, "and on again")
    _G.OpenMapAPI, NS.Print = nil, keepPrint

    -- NOT YOUR GROUP (Arn, 22 Oct: "both of these blue marks are frank how about they only show up if we are not
    -- in a party or raid"): Cara joins your raid - the game draws her, so her dot goes; she leaves, it comes back
    H.inRaid, H.raid = true, { "Me", "Cara" }
    H.units.raid1, H.units.raid2 = { name = "Me" }, { name = "Cara" }
    M.Update()
    H.eq(#pins(), 0, "Cara in your raid: no BiS dot (the game's own is there)")
    H.inRaid, H.raid = false, {}
    H.units.raid1, H.units.raid2 = nil, nil
    M.Update()
    H.eq(#pins(), 1, "she leaves the raid: her dot is back")
    -- a party: party1..party(n-1), the player is not one of them
    local realNum2, realRaid2 = _G.GetNumGroupMembers, _G.IsInRaid
    _G.GetNumGroupMembers, _G.IsInRaid = function() return 2 end, function() return false end
    H.units.party1 = { name = "Cara" }
    M.Update()
    H.eq(#pins(), 0, "Cara in your party: no BiS dot")
    _G.GetNumGroupMembers, _G.IsInRaid = realNum2, realRaid2
    H.units.party1 = nil
    M.Update()

    -- a spot arriving draws within a second, once for a burst
    local timers = #H.timers
    M.Soon() M.Soon() M.Soon()
    H.eq(#H.timers - timers, 1, "a burst of spots is one redraw")
    H.RunTimers()

    -- no library at all (a stripped copy): nothing drawn, nothing thrown
    local keep = LibStub.libs["HereBeDragons-Pins-2.0"]
    LibStub.libs["HereBeDragons-Pins-2.0"] = nil
    H.eq(M.Update(), 0, "without the pins library: no dots and no error")
    LibStub.libs["HereBeDragons-Pins-2.0"] = keep

    lib.spots = {}
    M.Update()
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.RAID_CLASS_COLORS = realNum, realInfo, realColours
    NS.K._guildDirty = true
end

--=============================================================================
-- BiSGuildAPI (16 Oct 2026, Arn: "lets do api calls for the other addons, and going forward our stuff
-- will have open api to call") - read-only copies, safe at any time
--=============================================================================
H.section("BiSGuildAPI: the guild's record for other addons")
do
    local A = _G.BiSGuildAPI
    H.ok(A and A.major == 1 and A.version >= 1, "BiSGuildAPI is there, major 1")
    H.ok(A.Ready(), "ready")
    local saved = NS.Books().record
    NS.Books().record = {
        nights = {
            ["2026-10-09"] = { kills = 2, raiders = { Alice = raider(2, 3), Bob = raider(1, 3, 2) },
                               bosses = { ["Boss One"] = { pulls = 3, kills = 1, best = 250000, killers = { "Alice" } } } },
            ["2026-10-16"] = { kills = 1, raiders = { Alice = raider(1, 2) }, bosses = {} },
        },
        gear = {},
    }
    local heard = {}
    A.RegisterCallback("test", "BiSGuild_Night", function(d) heard[#heard + 1] = d end)
    S.Put("2026-10-23", { kills = 1, raiders = { Alice = raider(1, 1) }, bosses = {} }, "Kumlust")
    H.ok(heard[1] == "2026-10-23", "BiSGuild_Night: a night entered the record")
    S.Put("2026-10-23", { kills = 1, raiders = { Alice = raider(1, 1) }, bosses = {} }, "Kumlust")
    H.eq(#heard, 1, "an equal copy is not news")
    A.UnregisterCallback("test", "BiSGuild_Night")

    H.ok(deq(A.Nights(), { "2026-10-09", "2026-10-16", "2026-10-23" }), "Nights, oldest first")
    local n = A.Night("2026-10-09")
    H.ok(n and n.raiders.Bob.deaths == 2 and n.bosses["Boss One"].best == 250000, "Night(date): the whole night")
    H.eq(select(2, A.Night("1999-01-01")), "no such night", "an unknown night: nil and why")
    -- v2: a key as people read it (dev/NIGHTS.md)
    H.ok(A.version >= 2, "the API's version went up with raids as nights (3 since MapDots)", A.version)
    H.eq(A.Label("2026-10-09"), "2026-10-09", "a whole-date night's label is its date")
    H.eq(A.Label("2026-10-24 409"), "2026-10-24 raid 409", "a raid not on record: its instance number")
    local rs = A.Raiders()
    H.ok(rs[1].name == "Alice" and rs[1].attend == 100 and rs[2].name == "Bob", "Raiders: everyone, attendance %")
    local alice = A.Raider("alice")
    H.ok(alice and alice.name == "Alice" and alice.nights == 3 and alice.last.date == "2026-10-23", "Raider(name), any case")
    H.eq(select(2, A.Raider("Nobody")), "no such raider", "an unknown raider: nil and why")
    local b = A.Boss("boss one")
    H.ok(b and b.kills == 1 and b.wipes == 2 and b.killers.Alice == 1, "Boss(name), any case: kills, wipes, who")
    H.ok(A.Bosses()["Boss One"].best == 250000, "Bosses: every page")
    H.eq(select(2, A.RaidNight()), "no raid pasted", "RaidNight with nothing pasted: nil and why")
    -- copies: nothing an answer is edited into reaches the record
    alice.attended[1] = "hacked"
    n.raiders.Bob.deaths = 99
    H.eq(A.Raider("Alice").attended[1], "2026-10-09", "answers are copies - the record cannot be edited through them")
    H.eq(S.Record().nights["2026-10-09"].raiders.Bob.deaths, 2, "not even a night's numbers")
    -- Open: the terminal on a raider
    H.ok(A.Open("alice <raider>") and NS.K.frame:IsShown() and NS.K.key == "Alice", "Open: the terminal, on her card")
    NS.K.Hide()

    -- BiS Guild's own loot panel asks BiSLootAPI first (it used to read BiSLootDB's lines)
    local keepLootAPI = _G.BiSLootAPI
    _G.BiSLootAPI = { major = 1, version = 1, AwardsTo = function(who)
        return who == "Alice" and { { itemId = 28830, item = "[Dragonspine Trophy]", boss = "Gruul", t = 5 } } or {} end }
    local loot, have = NS.K.Loot("Alice")
    H.ok(have and loot[1] and loot[1].item == 28830 and loot[1].boss == "Gruul", "the terminal's loot comes from BiSLootAPI")
    _G.BiSLootAPI = keepLootAPI

    -- not ready: before the addon has its pieces
    local keepS = NS.S
    NS.S = nil
    H.eq(select(2, A.Raiders()), "not ready", "before the record exists: nil, 'not ready' - never an error")
    NS.S = keepS
    NS.Books().record = saved
end

--=============================================================================
-- THE LOOT LEDGER, FOLDED IN FROM BiS LOOT (16 Oct 2026). Arn: "if they are going to install one thing
-- it's BiS Guild ... or maybe we put it into the library thing".
--=============================================================================
H.section("the loot ledger lives in BiS Guild now")
do
    local LT, Lib = NS.Loot, _G.LibBiSLedger
    -- the library is the canon's bytes
    local canon = bytes((os.getenv("BISDEV") or (ROOT .. "/../_bisdev")) .. "/LibBiSLedger-1.0/LibBiSLedger-1.0.lua")
    if canon then H.ok(bytes(ROOT .. "/Libs/LibBiSLedger-1.0/LibBiSLedger-1.0.lua") == canon, "LibBiSLedger byte-identical to _bisdev")
    else H.say("  (note) no _bisdev beside the checkout - ledger bytes fence skipped") end
    H.ok(listed("Libs/LibBiSLedger-1.0/LibBiSLedger-1.0.lua"), "the TOC carries it")

    local L = LT.Ledger()
    L:Reset()
    NS.Books().loot = { lines = {}, meta = {} }
    -- BiS LOOT'S SAVED LINES, taken in once and never doubled
    local function line(seq, prev, who, item, t)
        return Lib.pack({ v = "1", author = "Kumlust", seq = seq, prev = prev, t = t, kind = "award", who = who,
                          item = item, resp = "bis", boss = "Gruul", raid = "K-1" })
    end
    local l1 = line(1, "0", "Kio Alpha", "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r", 1700000100)
    local l2 = line(2, Lib.unpack(l1).sum, "Bob", "[Eye of Gruul]", 1700000200)
    _G.BiSLootDB = { lines = { l1, l2 }, snapshot = { l1 } }
    local before = #said
    H.eq(LT.ImportBiSLoot(), 2, "BiS Loot's two awards are taken in")
    H.ok(said[before + 1] and said[before + 1]:find("BiS Loot can be removed", 1, true), "and the player is told, once", said[before + 1])
    H.eq(LT.ImportBiSLoot(), 0, "a second login takes in nothing new - nothing doubles")
    H.eq(#said, before + 1, "and does not say it again")
    _G.BiSLootDB = { lines = { line(1, "0", "Kio Alpha", "[Forged]", 1) } }    -- a tampered copy
    H.eq(LT.ImportBiSLoot(), 0, "a line that clashes with the chain is a fork, never taken in")
    _G.BiSLootDB = nil
    H.ok(L:Verify().ok == false and L:Verify().forks == 1, "and is reported as a fork, as BiS Loot did")
    L.forks = {}

    -- BiSLootAPI, answered by BiS Guild
    local A = _G.BiSLootAPI
    H.ok(A and A.major == 1 and A.provider == "BiSGuild", "BiSLootAPI is BiS Guild's while BiS Loot is not installed")
    local kio = A.AwardsTo("Kio")
    H.ok(kio and #kio == 1 and kio[1].itemId == 28830, "AwardsTo: Kio's trophy, the id from the link")
    H.eq(#A.AwardsFrom("gruul"), 2, "AwardsFrom a boss")
    kio[1].who = "Hacker"
    H.eq(A.AwardsTo("Kio")[1].who, "Kio Alpha", "answers are copies")
    local heard = {}
    A.RegisterCallback("t", "BiSLoot_Award", function(a) heard[#heard + 1] = a.who end)

    -- /bisl: BiS Loot's words, kept
    local keepClock = clock
    clock = 1800000000                    -- now: after the imported awards
    _G.SlashCmdList.BISLOOT("award Zed [Gruul's Dragonslayer] os")
    clock = keepClock
    H.ok(heard[1] == "Zed", "/bisl award writes an award - and BiSLoot_Award fires")
    A.UnregisterCallback("t", "BiSLoot_Award")
    before = #said
    _G.SlashCmdList.BISLOOT("status")
    H.ok(said[before + 1] and said[before + 1]:find("3 events", 1, true), "/bisl status", said[before + 1])
    _G.SlashCmdList.BISLOOT("last 2")
    H.ok(said[before + 2] and said[before + 2]:find("Zed", 1, true), "/bisl last: newest first", said[before + 2])

    -- logout and back: the ledger is in this guild's books
    fire("PLAYER_LOGOUT")
    H.eq(#NS.Books().loot.lines, 3, "logout writes the three lines into the guild's books")
    LT.ledgers = {}
    H.eq(LT.Ledger().count, 3, "a new session reads them back")
    H.ok(LT.Ledger():Verify().ok, "verified on the way in")
    -- an alt in another guild has its own ledger
    local realGI = _G.GetGuildInfo
    _G.GetGuildInfo = function() return "Some Other Guild" end
    H.eq(LT.Ledger().count, 0, "an alt in another guild: an empty ledger of its own")
    _G.GetGuildInfo = realGI
    LT.ledgers = {}
    NS.Books().loot = nil
end

H.section("the terminal's edge is the family's, never the borrowed accent")
do
    -- Arn, 16 Oct: "there is a white line on top of the window". A 2 px "accent" bar - and the accent
    -- is EllesmereUI's when it is installed (his is white). Now a hairline all round in BiSTheme
    -- Options' fixed edge colour, the one BiS Tools' windows wear - whatever the accent is.
    local realTheme = _G.BiSTheme
    _G.BiSTheme = { hex = { accent = "ffffff" }, rgb = function() return 1, 1, 1 end, text = function(_, s) return s end }
    local f = NS.K.frame or NS.K.Build()
    local want = { 0x3a / 255, 0x32 / 255, 0x60 / 255 }
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = f.edges and f.edges[side]
        H.ok(e ~= nil, side .. " edge drawn")
        if e then
            local c = e._color or {}
            H.ok(math.abs((c[1] or -1) - want[1]) < 0.01 and math.abs((c[2] or -1) - want[2]) < 0.01
                 and math.abs((c[3] or -1) - want[3]) < 0.01, side .. " edge is 3a3260",
                 table.concat({ tostring(c[1]), tostring(c[2]), tostring(c[3]) }, ","))
        end
    end
    -- a fresh paint under a white accent keeps it purple
    NS.K.frame = nil
    local g = NS.K.Build()
    local c = g.edges.TOP._color
    H.ok(c and c[1] < 0.3, "built under a white EllesmereUI accent, the edge is still dark purple")
    NS.K.frame = f
    _G.BiSTheme = realTheme
end

H.section("the guild's versions: is a newer one about? (Core/Copies.lua)")
do
    local C, X = NS.Copy, NS.X
    local ROSTER = { { "Kumlust", 1 }, { "Bigboss", 0 }, { "Anna", 4 }, { "Bea", 4 }, { "Cid", 4 },
                     { "Dot", 4 }, { "Eve", 4 }, { "Fay", 4 } }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] return r[1], "rank", r[2] end
    X._ranksDirty = true
    local function drain() for _ = 1, 20 do H.clock = H.clock + 2 H.RunTimers() end end
    local function builds()
        local out = {}
        for _, w in ipairs(H.wire) do
            if w.channel == "GUILD" and w.msg:find("|GLOG|BUILD|", 1, true) then out[#out + 1] = w.msg end
        end
        return out
    end
    drain()
    NS.Books().copies = nil
    C.toldOld = nil
    local V = TOC_VERSION
    local OLDFP = ("AB"):rep(32)        -- what a 0.1.x copy still sends in the middle field

    -- at login: one line, asking. THE MIDDLE FIELD STAYS, AS "-": 0.1.x copies drop a BUILD line whose
    -- middle is not "-" or 64 hex, and they are the very copies that need to hear a newer one is about
    H.wire = {}
    C.lastSent = nil
    H.ok(C.Say(true), "the copy tells the guild")
    drain()
    local b = builds()
    H.eq(#b, 1, "in one line")
    H.ok(b[1] and b[1]:find("|BUILD|" .. V .. "|-|?", 1, true), "its version, a '-' where the fingerprint was, and a question", b[1])
    H.ok(b[1] and #b[1] <= 250, "under the client's limit: " .. (b[1] and #b[1] or 0))
    -- the 0.1.1 check, verbatim from the released Core/Copies.lua C.Hear: our line passes it
    local fp = "-"
    H.ok(fp == "-" or (#fp == 64 and fp:match("^%x+$")), "a released 0.1.1 copy accepts that line")

    -- what is believed: guildmates only, never ourselves, nothing malformed
    C.Hear("Stranger", "9.0.0", "-", ".")
    C.Hear("Kumlust", "9.0.0", "-", ".")
    C.Hear("Anna", "0.1;drop", "-", ".")
    H.eq(next(C.Book()), nil, "a stranger, ourselves and garbage are not written down")
    H.ok(not C.toldOld, "and none of them told us anything")

    -- an old copy still sends its fingerprint: heard all the same, the field ignored
    C.Hear("Anna-Dreamscythe", V, OLDFP, ".")
    C.Hear("Bea", "0.0.0", OLDFP, ".x")
    H.eq(C.Summary().newer, 0, "the same version and an older one: nothing newer")
    H.ok(not C.toldOld, "so nothing said")
    -- THE NOTE HAS A SWITCH NOW, OFF FOR A NEW INSTALL (Forever 1.0): the shared lib's /biscomm ver lists the
    -- versions and speaks up only for a critical one, so a chat line on every newer copy is a nag for a new player
    local before = #said
    H.eq(_G.BiSGuildDB.versionNote, false, "a new install: the newer-version note starts off")
    C.Hear("Eve", "9.0.0", "-", ".")
    H.eq(#said, before, "a newer copy heard: written down, nothing said in chat")
    H.eq(C.Summary().newer, 1, "but the book still knows")
    _G.BiSGuildDB.versionNote = true                     -- an existing save, frozen on (or the switch turned on)
    before = #said
    C.Hear("Eve", "9.0.0", "-", ".")
    local told = table.concat(said, "\n", before + 1)
    H.ok(told:find("1 guildmate(s) run BiS Guild 9.0.0", 1, true) and told:find("CurseForge", 1, true),
         "a newer copy about: said, with where to update", told)
    before = #said
    C.Hear("Fay", "9.1.0", "-", ".")
    H.eq(#said, before, "once a session")
    H.eq(C.Summary().newest, "9.1.0", "the newest is kept")
    H.ok(C.Newer("0.10.0", "0.9.3") and not C.Newer("0.9.3", "0.10.0"), "0.10.0 is newer than 0.9.3")

    -- an ask is answered - by a few, not by everyone
    H.wire = {}
    C.lastSent, C.waiting = nil, nil
    C.Hear("Anna", V, "-", "?")
    H.ok(C.waiting, "an ask: we wait our turn")
    C.Hear("Bea", V, "-", ".")
    drain()
    H.eq(#builds(), 1, "and answer, when not enough copies of our version already have")
    H.wire = {}
    C.Hear("Cid", V, "-", "?")
    drain()
    H.eq(#builds(), 0, "a second ask right after: we spoke a moment ago, so we stay quiet")
    C.lastSent, C.waiting = nil, nil
    C.Hear("Dot", "0.0.0", "-", "?")
    for _, n in ipairs({ "Anna", "Bea", "Fay" }) do C.Hear(n, V, OLDFP, ".") end
    drain()
    H.eq(#builds(), 0, C.ENOUGH .. " copies of our version answered first: we stand down")

    -- /bisg copy is gone with the fingerprint: it is just a word now, and words are the report
    H.eq(NS.Copy.Report, nil, "no /bisg copy report any more")

    -- a guildmate's copy is forgotten after a month
    C.Book().Anna.t = time() - C.KEEP - 1
    C.Summary()
    H.eq(C.Book().Anna, nil, "a month-old copy is dropped")

    -- lean: hearing a whole guild log in
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local n, by = Cost.Count(function()
        for i = 1, 40 do C.Hear(ROSTER[(i % #ROSTER) + 1][1], V, "-", ".") end
    end)
    H.say(("   cost: hearing 40 copies = %d calls (%s)"):format(n, Cost.Top(by, 3)))
    H.ok(n <= 3 * 40, "hearing a copy costs a few client calls: " .. n, Cost.Top(by, 4))

    NS.Books().copies = nil
    C.toldOld, C.waiting, C.lastSent = nil, nil, nil
    _G.BiSGuildDB.versionNote = false
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    X._ranksDirty = true
    drain()
    H.wire = {}
end

-- WHAT AN OPEN WINDOW COSTS, IN CLIENT CALLS (7 Oct 2026). BiSHealing asked the client ~630,000
-- things a second and every suite was green; Arn: "make sure stuff like this does not happen".
-- The window ticks every frame while it is open (the cursor, the prompt, the typing). A second of
-- frames is held to a budget with the family's counter.
H.section("what a second of the open window costs")
do
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local U = NS.U
    local f = U.Build()
    U.Show()
    local tick = f.cmdWrap._scripts.OnUpdate
    for _ = 1, 30 do H.clock = H.clock + 0.1 tick(f.cmdWrap, 0.1) end     -- settled, typed out
    local n, by = Cost.Count(function()
        for _ = 1, 60 do H.clock = H.clock + 1 / 60 tick(f.cmdWrap, 1 / 60) end
    end)
    H.say(("   cost: open window, 1 s = %d calls (%s)"):format(n, Cost.Top(by, 3)))
    H.ok(n <= 120, "a second of the open window asks the client at most two things a frame: " .. n,
         Cost.Top(by, 4))

    -- a second of the open terminal: the ticker slides one SetPoint a frame
    local K = NS.K
    local kf = K.Show("raiders")
    local tick = kf._scripts.OnUpdate
    local nk, byk = Cost.Count(function()
        for _ = 1, 60 do H.clock = H.clock + 1 / 60 tick(kf, 1 / 60) end
    end)
    H.say(("   cost: open terminal, 1 s = %d calls (%s)"):format(nk, Cost.Top(byk, 3)))
    H.ok(nk <= 120, "a second of the open terminal: at most two client calls a frame: " .. nk, Cost.Top(byk, 4))
    K.Hide()

    -- A BIG ROSTER KEPT IS NOT A SLOW ONE (Arn, 16 Oct: "kept the old roster, not bad as long as it's
    -- not making it lag because it's a lot of text"): a 70-sign-up Raid-Helper export, redrawn
    local parts = {}
    for i = 1, 70 do
        parts[i] = ('{"cClassName":"Melee","className":"Melee","cSpecName":"Fury","specEmoteId":"637564445215948810",'
            .. '"userId":"%d","cRoleName":"Dps","entryTime":1791494745,"specName":"Fury","name":"Raider%02d",'
            .. '"roleName":"Dps","roleEmoteId":"592440132129521664","id":%d,"position":%d,"status":"primary"}'):format(i, i, i, i)
    end
    local big = '{"date":"04-11-2026","signUps":[' .. table.concat(parts, ",") .. '],"displayTitle":"Forever Class"}'
    NS.Books().roster = big
    K.Show("roster")
    K.Paint()                                      -- the first draw reads the export once
    local nr, byr = Cost.Count(function() for _ = 1, 10 do K.Paint() end end)
    H.say(("   cost: ROSTER with a %d-character export, 10 redraws = %d calls (%s)"):format(#big, nr, Cost.Top(byr, 3)))
    H.ok(nr <= 10 * 20, "a kept 70-person export costs a redraw almost nothing: " .. nr, Cost.Top(byr, 4))
    NS.Books().roster = nil
    K.Hide()

    -- hearing a whole 25-raider night from an officer: the roster is read once, not once a part
    local text = NS.X.EncodeNight(bigNight())
    local parts, N = {}, math.ceil(#text / NS.X.CHUNK)
    for i = 1, N do parts[i] = text:sub((i - 1) * NS.X.CHUNK + 1, i * NS.X.CHUNK) end
    local saved = NS.Books().record
    NS.Books().record = { nights = {}, gear = {} }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return 1 end
    _G.GetGuildRosterInfo = function() return "Bigboss", "rank", 0 end
    NS.X._ranksDirty = true
    local n2, by2 = Cost.Count(function()
        for i = 1, N do NS.X.handlers.NIGHT("Bigboss", "2026-10-23", i, N, parts[i]) end
    end)
    H.say(("   cost: hearing a %d-part night = %d calls (%s)"):format(N, n2, Cost.Top(by2, 3)))
    H.ok(NS.S.Record().nights["2026-10-23"] ~= nil, "the night arrived")
    H.ok(n2 <= 4 * N, "hearing a night costs a few client calls a part: " .. n2, Cost.Top(by2, 4))
    NS.Books().record = saved
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    NS.X._ranksDirty = true
end

-- THE PASTE (17 Oct: the Colab notebook - "drag and drop their log ... hit run ... something to
-- paste"). dev/test_logreport.py proves the reader's text decodes here; this proves the box and every
-- refusal a person can meet.
do
    H.section("the paste: the notebook's text in, no PowerShell")
    local S, X, U = NS.S, NS.X, NS.U
    local keep = NS.Books().record
    NS.Books().record = { nights = {}, gear = {} }
    local T0 = 1792202400
    local raid = { v = 2, i = 409, zone = "Molten Core", start = T0, pulls = {
        { t = T0, e = 663, b = "Lucifron", k = 1, ms = 60000, r = { Ann = 9, Bo = 9 }, d = {}, p = {} },
        { t = T0 + 900, e = 664, b = "Magmadar", k = 1, ms = 70000, r = { Ann = 9, Bo = 9 }, d = { Bo = 1 }, p = {} } } }
    local gear = {}
    for i = 1, 19 do gear[i] = { i == 18 and 0 or 1000 + i, i == 18 and 0 or 30, 0, 0, {} } end
    local function paste(lines)
        local body, n = {}, 0
        for _, l in ipairs(lines) do body[#body + 1] = l n = n + #l end
        return "BiSGuild paste 2\n" .. table.concat(body, "\n") .. ("\nEND~%d~%d\n"):format(#body, n)
    end
    local good = paste({ "R~2026-10-16 409~" .. X.EncodeRaid(raid), "G~Ann~2026-10-16~" .. X.EncodeGear(gear) })

    local r, g, bad = X.ImportPaste("----- copy everything -----\n" .. good .. "----- end -----")
    H.ok(r == 1 and g == 1 and bad == 0, "the notebook's text, markers and all: one raid, one gear set", tostring(g))
    H.eq(S.Record().nights["2026-10-16 409"].kills, 2, "the raid is on record, two kills")
    H.eq(S.Record().nights["2026-10-16 409"].raiders.Bo.deaths, 1, "with each raider's numbers")
    H.eq(select(1, X.ImportPaste(good)), 0, "the same paste again: nothing new")
    NS.Books().record = { nights = {}, gear = {} }
    H.eq(select(1, X.ImportPaste((good:gsub("\n", "\r\n")))), 1, "copied on Windows (CR LF line ends): still read")
    H.eq(select(2, X.ImportPaste("")), "nothing pasted", "an empty box says so")
    H.ok(select(2, X.ImportPaste("hello there")):find("not a BiS Guild paste", 1, true), "text from somewhere else is refused")
    H.ok(select(2, X.ImportPaste(good:gsub("paste 2", "paste 9"))):find("update BiS Guild", 1, true),
         "a newer layout: update BiS Guild")
    H.ok(select(2, X.ImportPaste(good:gsub("END~[^\n]*", ""))):find("cut off", 1, true), "no END line: cut off")
    H.ok(select(2, X.ImportPaste(good:gsub("Lucifron", "Lucifro"))):find("damaged", 1, true),
         "a letter missing: damaged, refused whole")
    local junk = paste({ "R~2026-10-16 409~2#garbage", "Q~what" })
    local r2, g2, bad2 = X.ImportPaste(junk)
    H.ok(r2 == 0 and bad2 == 2, "lines that do not decode are counted, never guessed at")

    -- the window: Import says what happened, in the window
    NS.Books().record = { nights = {}, gear = {} }
    SlashCmdList.BISGUILD("paste")
    local p = U.paste
    H.ok(p and p:IsShown(), "/bisg paste opens the paste window")
    H.ok(math.abs(U.PW / U.PH - 1.43) < 0.01, "at the family's 1.43:1")
    p.box:SetText(good)
    -- MOSTLY NOT OUR GUILD (Arn, 18 Oct: "a check that says this has more people not in your guild"):
    -- Ann and Bo are not in the test guild - said, nothing taken, and the same text pressed again goes in
    H.eq(U.DoPaste(), nil, "a raid of strangers: Import stops first")
    H.ok(p.status:GetText():find("2 of 2 aren't in your guild", 1, true), "and says how many aren't in the guild",
         p.status:GetText())
    H.eq(S.Record().nights["2026-10-16 409"], nil, "nothing taken in yet")
    H.eq(p:GetScript("OnUpdate"), nil, "and no bar")
    fitsIn(p, "the paste window: the link, and the guild warning")
    U.DoPaste()
    -- THE BAR (Arn, 18 Oct: "fake progress bars - to make it look like its doing something"): the raid
    -- is in at once; the bar plays it out, the window narrating, and only then says the result
    H.ok(S.Record().nights["2026-10-16 409"] ~= nil, "Import: the raid is on record at once")
    local step = p:GetScript("OnUpdate")
    H.ok(step ~= nil and p.bar:IsShown(), "and the bar starts")
    step(p, U.BAR_LEN * 0.3)
    local lit = 0
    for _, b in ipairs(p.bar.blocks) do if b:IsShown() then lit = lit + 1 end end
    H.ok(lit > 0 and lit < U.BAR_BLOCKS, "a third of the way: part of the bar lit", lit)
    H.ok(p.status:GetText():find("Raid 2026-10-16 Molten Core", 1, true), "the window says which raid it is reading", p.status:GetText())
    H.ok(U.DoPaste() == nil, "a second Import while the bar runs does nothing")
    step(p, U.BAR_LEN)
    H.ok(p.status:GetText():find("1 raid", 1, true), "at the end: '1 raid(s) taken in'", p.status:GetText())
    H.eq(p:GetScript("OnUpdate"), nil, "and the bar stops ticking (nothing runs after)")
    H.eq(p.box:GetText(), "", "and the box empties")
    p.box:SetText("nonsense")
    U.DoPaste()
    H.ok(p.status:GetText():find("not a BiS Guild paste", 1, true), "a refusal is said in the window too", p.status:GetText())
    -- the script window's button opens it, above the PowerShell warning
    U.Build()
    p:Hide()
    U.frame:Show()
    U.frame.pasteBtn:GetScript("OnClick")()
    H.ok(p:IsShown(), "'Paste from the notebook' on the script window opens it")
    -- Arn's first paste (18 Oct): it opened BEHIND the script window, and the text ran off the screen
    H.ok(not U.frame:IsShown(), "and the script window steps aside, so the paste is in front")
    local onText = p.box:GetScript("OnTextChanged")
    p.box:SetText(good)
    onText(p.box, true)
    H.ok(p.status:GetText():find("pasted: 4 lines", 1, true), "pasting says what came in, in words", p.status:GetText())
    p.box:SetText("hello")
    onText(p.box, true)
    H.ok(p.status:GetText():find("doesn't look like", 1, true), "and when it is something else", p.status:GetText())
    p:Hide()
    NS.Books().record = keep
end

-- A WRONG RAID IS ARCHIVED, NEVER DELETED (18 Oct 2026). Arn: "someone can accidently upload a wrong log
-- and we need a way to purge it maybe a list to click it off where it archives it or something incase
-- soemeone accidently clicks a correct log" - and an officer's archive is everyone's.
H.section("a wrong raid is archived, never deleted - and an officer's archive is the guild's")
do
    local S, X, U = NS.S, NS.X, NS.U
    local keep = NS.Books().record
    local ROSTER = { { "Kumlust", 1 }, { "Bigboss", 0 }, { "Anna", 4 } }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] return r[1], "rank", r[2] end
    X._ranksDirty = true
    local function drain() for _ = 1, 20 do H.clock = H.clock + 2 H.RunTimers() end end
    local function sent(cmd)
        local out = {}
        for _, w in ipairs(H.wire) do
            if w.channel == "GUILD" and w.msg:find("|GLOG|" .. cmd .. "|", 1, true) then out[#out + 1] = w.msg end
        end
        return out
    end
    drain()
    local T0 = 1792202400
    local function raid(t0)
        return { v = 2, i = 409, zone = "Molten Core", start = t0, pulls = {
            { t = t0, e = 663, b = "Lucifron", k = 1, ms = 60000, r = { Ann = 9, Bo = 9 }, d = {}, p = {} } } }
    end
    local KEY = "2026-10-16 409"
    NS.Books().record = { nights = {}, gear = {} }
    H.ok(S.Put(KEY, raid(T0), "Kumlust"), "a raid on record")
    S.Put("2026-10-09 409", raid(T0 - 7 * 86400), "Kumlust")
    H.eq(#S.Dates(), 2, "two raids")
    local p, h = X.Check(S.Record().nights[KEY])

    -- archived by an officer (we are one): off the record, kept whole, and the guild told
    H.wire = {}
    H.ok(X.SetArchived(KEY, true), "archived")
    H.eq(S.Record().nights[KEY], nil, "off the record - nothing counts it")
    H.eq(#S.Dates(), 1, "one raid counted now")
    H.ok(S.Record().archived[KEY] and S.Record().archived[KEY].night.pulls[1].b == "Lucifron", "but kept, whole")
    H.eq(#S.Cards().Ann.attended, 1, "Ann's attendance no longer counts it")
    drain()
    local a = sent("ARCH")
    H.eq(#a, 1, "an officer's archive goes to the guild, in one line")
    H.ok(a[1] and a[1]:find(("|ARCH|261016-409|%d|%d|1|"):format(p, h), 1, true), "by key, check number and time", a[1])
    H.ok(a[1] and #a[1] <= 250, "under the client's limit")

    -- SEEN ONLY IN AN ARCHIVED RAID: OFF THE RAIDERS LIST (Arn, 18 Oct: "if a raider only apperes in one
    -- log and we archive that log can we hide all those people"). Their gear stays on record (every log
    -- brings everyone's gear), so the card is there - the list leaves it off. Ann and Bo are in the
    -- other raid too; Zed, gear only, is not; Kumlust, gear only, is a guild member.
    do
        local g = {}
        for i = 1, 19 do g[i] = { 0, 0, 0, 0, {} } end
        S.PutGear("Zed", "2026-10-16", g)
        S.PutGear("Kumlust", "2026-10-16", g)
        local names = {}
        for _, r in ipairs(NS.K.Rows(S.Cards())) do names[r.name] = r end
        H.ok(S.Cards().Zed ~= nil, "Zed's gear is still on record")
        H.eq(names.Zed, nil, "but Zed, seen in no raid on record, is not listed")
        H.ok(names.Ann and not names.Ann.none, "Ann, in a raid still on record, is")
        H.ok(names.Kumlust and names.Kumlust.none, "a guild member seen only in gear: a member with no raids")
    end

    -- the same raid again - pasted again, or another officer's copy: not let back in
    H.eq(S.Put(KEY, raid(T0), "Bigboss"), false, "the same raid again is not let back in")
    H.ok(X.HaveRaid(KEY, p, h), "and counts as held, so it is never asked for")

    -- restored: back, and the guild told
    H.wire = {}
    H.ok(X.SetArchived(KEY, false), "restored")
    H.ok(S.Record().nights[KEY] ~= nil and S.Record().archived[KEY] == nil, "back on record")
    H.eq(#S.Cards().Ann.attended, 2, "and counted again")
    drain()
    H.ok((sent("ARCH")[1] or ""):find(("|%d|%d|0|"):format(p, h), 1, true), "the restore goes to the guild too")

    -- what we hear: an officer's archive files ours away; a member's is not believed; the older loses
    X.HearArch("Anna", "261016-409", p, h, "1", time() + 5)
    H.ok(S.Record().nights[KEY] ~= nil, "a member's archive is not believed")
    X.HearArch("Bigboss", "261016-409", p, h, "1", 1)
    H.ok(S.Record().nights[KEY] ~= nil, "an archive decided before our restore loses")
    X.HearArch("Bigboss", "261016-409", p, h, "1", time() + 5)
    H.eq(S.Record().nights[KEY], nil, "an officer's later archive files ours away")
    X.HearArch("Bigboss", "261017-409", p, h, "0", time() + 10)
    H.ok(S.Record().nights[KEY] ~= nil, "a restore dated a day off (another time zone) still finds our raid")
    X.HearArch("Bigboss", "261016-409", p + 1, h, "1", time() + 20)
    H.ok(S.Record().nights[KEY] ~= nil, "an archive of a different raid under the same key touches nothing")

    -- THE OFFICER WHO WAS OFFLINE still offers a raid we archived: we say so again, once a session
    X.HearArch("Bigboss", "261016-409", p, h, "1", time() + 30)
    X.retold = {}
    local offer = ("261016-409.%d.%d"):format(p, h)
    H.wire = {}
    X.handlers.HAVE2("Bigboss", offer)
    drain()
    H.eq(#sent("ARCH"), 1, "an officer still offering an archived raid hears that it is archived")
    H.eq(#sent("WANT2"), 0, "and nobody asks for it back")
    H.wire = {}
    X.handlers.HAVE2("Bigboss", offer)
    drain()
    H.eq(#sent("ARCH"), 0, "once a session")

    -- FORENAME OR WHOLE NAME (Arn, the guild master, was told "only your copy"): the guild list says
    -- "Nebeon Nohealzforu", the player's own name can be "Nebeon" - the client's shape, online 9th
    do
        local realInfo2 = _G.GetGuildRosterInfo
        local R2 = { { "Nebeon Nohealzforu", 0, true }, { "Nebeon Nohotzforu", 1, false }, { "Nebeon Notrapforu", 4, false },
                     { "Solo Person", 2, false } }
        _G.GetNumGuildMembers = function() return #R2 end
        _G.GetGuildRosterInfo = function(i)
            local r = R2[i]
            return r[1], "rank", r[2], 60, "MAGE", "", "", "", r[3], 0, "MAGE"
        end
        X._ranksDirty = true
        H.eq(X.Rank("Nebeon Nohealzforu"), 0, "a whole name: its own rank")
        H.eq(X.Rank("Nebeon Notrapforu-Realm"), 4, "realm dropped")
        H.eq(X.Rank("Nebeon"), 0, "a forename shared by alts: the one online (the guild master)")
        H.eq(X.Rank("Solo"), 2, "a forename only one member has: theirs")
        H.eq(X.Rank("Nebeon Fakename"), nil, "a whole name not on the list is not ours")
        H.eq(X.Rank("Stranger"), nil, "nor a stranger")
        _G.GetNumGuildMembers, _G.GetGuildRosterInfo = function() return #ROSTER end, realInfo2
        X._ranksDirty = true
    end

    -- a member's own archive stays theirs
    ROSTER[1][2] = 4
    X._ranksDirty = true
    NS.Books().record = { nights = {}, gear = {} }
    S.Put(KEY, raid(T0), "Kumlust")
    H.wire = {}
    H.ok(X.SetArchived(KEY, true), "a member can archive in their own copy")
    drain()
    H.eq(#sent("ARCH"), 0, "and nothing goes to the guild")
    ROSTER[1][2] = 1
    X._ranksDirty = true

    -- THE LIST: the raids on record newest first with Archive, the archived below with Restore
    NS.Books().record = { nights = {}, gear = {} }
    S.Put(KEY, raid(T0), "Kumlust")
    S.Put("2026-10-09 409", raid(T0 - 7 * 86400), "Kumlust")
    X.SetArchived("2026-10-09 409", true)
    U.ShowPaste()
    U.paste.listBtn:Click()
    local w = U.raids
    H.ok(w and w:IsShown(), "'Raids on record' in the paste window opens the list")
    -- ONE WINDOW AT A TIME (Arn, 18 Oct: "it opens the window right on top of the otherone")
    H.ok(not U.paste:IsShown(), "and the paste window steps aside - never two on top of each other")
    w.back:Click()
    H.ok(U.paste:IsShown() and not w:IsShown(), "Back returns to the paste window, alone")
    U.Show()
    H.ok(U.frame:IsShown() and not U.paste:IsShown(), "the officers' window opens alone too")
    U.paste.listBtn:Click()
    H.ok(w:IsShown() and not U.frame:IsShown(), "and steps aside for the list")
    H.ok(w.rows[1].label:GetText():find("2026-10-16 Molten Core", 1, true), "the raids on record first",
         w.rows[1].label:GetText())
    H.ok(w.rows[1].sizes:GetText():find("1 kill, 2 raiders", 1, true), "with their size", w.rows[1].sizes:GetText())
    H.eq(w.rows[1].btn:GetText(), "Archive", "and an Archive button")
    H.ok(w.rows[2].label:GetText():find("2026-10-09 Molten Core", 1, true) and w.rows[2].btn:GetText() == "Restore",
         "the archived below, with Restore")
    H.ok(w.rows[2].sizes:GetText():find("archived by Kumlust", 1, true), "and who archived it", w.rows[2].sizes:GetText())
    H.ok(not w.rows[3]:IsShown(), "and no empty rows")
    H.ok(w.who:GetText():find("1 on record, 1 archived", 1, true), "the counts", w.who:GetText())
    H.ok(w.who:GetText():find("whole guild", 1, true), "and an officer is told it goes to the whole guild")
    fitsIn(w, "the raids on record")
    w.rows[2].btn:Click()
    H.ok(S.Record().nights["2026-10-09 409"] ~= nil, "Restore in the list brings it back, at once")
    -- THE ROW'S BAR (Arn, 18 Oct: "when i click archive it turns to a fake progress bar and says restore")
    H.ok(w.rows[2].bar:IsShown() and not w.rows[2].btn:IsShown(), "the button turns into a bar")
    H.ok(w.rows[2].sizes:GetText():find("restoring...", 1, true), "and the row says what it is doing", w.rows[2].sizes:GetText())
    local step = w:GetScript("OnUpdate")
    H.ok(step ~= nil, "the bar ticks")
    step(w, U.ROW_BAR_LEN * 0.5)
    local lit = 0
    for _, b in ipairs(w.rows[2].bar.blocks) do if b:IsShown() then lit = lit + 1 end end
    H.ok(lit > 0 and lit < U.ROW_BLOCKS, "half way: half lit", lit)
    -- SEVERAL AT ONCE (Arn, 18 Oct: "i cant click on another one to start the next archive")
    w.rows[1].btn:Click()
    H.eq(S.Record().nights[KEY], nil, "a second row clicked while the first plays: archived too, at once")
    H.ok(w.rows[1].bar:IsShown() and w.rows[2].bar:IsShown(), "two bars at once")
    w.rows[2].btn:Click()
    H.ok(S.Record().nights["2026-10-09 409"] ~= nil, "a row mid-bar ignores another click")
    U.PaintRaids()
    H.ok(w.rows[2].bar:IsShown(), "and nothing repaints the list from under them")
    step(w, U.ROW_BAR_LEN * 0.5)                     -- row 2's bar ends; row 1's is half way
    H.ok(w.rows[2].btn:IsShown() and not w.rows[2].bar:IsShown(), "the first bar done: its button is back")
    H.eq(w.rows[2].btn:GetText(), "Archive", "saying what it does now")
    H.ok(w.rows[1].bar:IsShown(), "while the other still plays")
    H.ok(w.rows[2].label:GetText():find("2026-10-09", 1, true), "and no row has moved yet")
    step(w, U.ROW_BAR_LEN)
    H.eq(w:GetScript("OnUpdate"), nil, "all done: nothing left ticking")
    H.ok(w.rows[1].label:GetText():find("2026-10-09", 1, true) and w.rows[1].btn:GetText() == "Archive",
         "then the list re-sorts: the restored raid on top")
    H.eq(w.rows[2].btn:GetText(), "Restore", "the archived one to the bottom, with Restore")
    -- closed mid-bar: finished, nothing ticking on a hidden window
    w.rows[2].btn:Click()
    w:Hide()
    w:Fire("OnHide")             -- the client fires it on Hide; the kit (Nebbinator's, verbatim) does not
    H.eq(w:GetScript("OnUpdate"), nil, "closing the list mid-bar finishes it - nothing ticks on")
    H.ok(S.Record().nights[KEY] ~= nil, "and the restore stands")
    U.paste:Hide()

    NS.Books().record = keep
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    X._ranksDirty = true
    drain()
    H.wire = {}
end

-- RECRUITS (21 Oct 2026): BiS> Nebbinator's guild book in the terminal, through NebbinatorAPI v2. The stand-in
-- answers in the shapes Nebbinator's API.lua documents (and its own suite holds): Team rows carry class,
-- level and note only on an officer's client, Needs a list of { classFile, class, spec, role, count }.
H.section("RECRUITS: the guild's recruits, from BiS> Nebbinator")
do
    local K = NS.K
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    local ROSTER = { { "Kumlust-Dreamscythe", 4 } }
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] return r[1], "rank", r[2] end
    X._ranksDirty = true
    local f = K.Show()
    -- six tabs, centred, and the first one clear of the prompt
    H.ok(f.keys.recruits ~= nil, "a RECRUITS tab")
    local first = f.keys.raiders:OffsetFor("TOPLEFT")
    local last = f.keys.log:OffsetFor("TOPLEFT") + f.keys.log:GetWidth()
    H.ok(math.abs(first - (K.W - last)) <= 1 and first >= 180, "six tabs centred, clear of the prompt's 180 px: " .. first)

    _G.NebbinatorAPI = nil
    f.keys.recruits:Click()
    local p = f.pages.recruits
    H.eq(K.page, "recruits", "the tab opens its page")
    H.ok(p.needLines[1]:GetText():find("BiS> Nebbinator keeps the guild's recruits", 1, true), "without Nebbinator: what would be here",
         p.needLines[1]:GetText())
    H.ok(p.needsBy:GetText():find("install it", 1, true) and not p.setNeeds:IsShown(), "and which addon brings it")
    _G.NebbinatorAPI = { major = 1, version = 1, Ready = function() return true end }
    K.Paint()
    H.ok(p.needLines[1]:GetText():find("Update BiS> Nebbinator", 1, true), "an old Nebbinator (version 1): update it")

    local now = GetServerTime()                  -- the API's clock (the kit's, here)
    local opened
    local officerClient = false
    _G.NebbinatorAPI = {
        major = 1, version = 2,
        Ready = function() return true end,
        Needs = function() return { text = "2 Resto Shaman", by = "Bigboss", at = now - 2 * 86400,
            list = { { classFile = "SHAMAN", class = "Shaman", spec = "Resto", role = "HEALER", count = 2 } } } end,
        Team = function()
            return { { name = "Newest", status = "contacted", by = "Memberguy", at = now - 120,
                       class = officerClient and "PRIEST" or nil, note = officerClient and "good logs" or nil },
                     { name = "Older", status = "trial", by = "Kumlust", at = now - 7200 } }
        end,
        Stats = function() return { posts = 4, whispers = 3, where = { { key = "Trade", posts = 2, whispers = 3 },
            { key = "General", posts = 2, whispers = 0 } }, ad = {}, when = {} } end,
        Open = function(page) opened = page return true end,
    }
    K.Paint()
    H.eq(p.needLines[1]:GetText(), "2  Resto Shaman", "everyone sees what the guild needs")
    H.ok(p.needsBy:GetText():find("set by Bigboss, 2 d ago", 1, true), "and who set it", p.needsBy:GetText())
    H.ok(not p.setNeeds:IsShown(), "a member has no SET THEM")
    H.ok(p.hint:IsShown() and p.hint:GetText():find("Officers see", 1, true), "and no list - officers see it")
    H.ok(not p.grid.rows[1]:IsShown(), "no rows")

    ROSTER = { { "Kumlust-Dreamscythe", 1 } }
    X._ranksDirty = true
    officerClient = true
    K.Paint()
    H.ok(p.setNeeds:IsShown(), "an officer: SET THEM")
    p.setNeeds:Click()
    H.eq(opened, "Team", "which opens Nebbinator's Team page (the needs are set and sent there)")
    H.ok(not p.hint:IsShown() and p.grid.rows[1]:IsShown(), "the guild's list")
    H.eq(p.grid.rows[1].cells[1]:GetText(), "Newest", "newest first")
    H.eq(p.grid.rows[1].cells[3]:GetText(), "Memberguy", "who is talking to them")
    H.eq(p.grid.rows[1].cells[5]:GetText(), "good logs", "the note")
    H.eq(p.grid.rows[1].who, "Newest", "right-click: the game's menu for them")
    H.eq(p.workLines[2]:GetText(), "Trade  3 / 2", "what works: the best channel")
    H.eq(p.list.right:GetText(), "2 on the list", "how many")
    -- typed
    K.Go("raiders")
    K.Go("recruits")
    H.eq(K.page, "recruits", "typing recruits opens it too")
    _G.NebbinatorAPI = { major = 1, version = 2, Ready = function() error("boom") end, Team = function() end }
    local ok = pcall(K.Paint)
    H.ok(ok, "a broken Nebbinator never breaks the terminal")
    _G.NebbinatorAPI = nil
    K.Hide()
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    X._ranksDirty = true
end

--=============================================================================
-- FOREVER 1.0: ONE OPTIONS HOME (Arn, 7 Nov: "when they open the options, they go to add-ons ... they'll just see
-- BiS> ... click into that add-on"). Every extra a new install starts with OFF has a switch here, and every switch
-- runs the same function as its slash command. No minimap button - BiS Guild never had one.
--=============================================================================
H.section("Forever 1.0: the options window and the BiS> page")
do
    local O, T, L, M, C = NS.Opt, _G.BiSTheme, NS.Login, NS.Pins, NS.Copy
    H.ok(T.OPTIONS_MINOR and T.OPTIONS_MINOR >= 4 and T.Options, "the shared options kit loaded")
    local f = O.Build()
    H.ok(f and f:GetName() == "BiSGuildOptions" and not f:IsShown(), "the window builds, named, and starts hidden")
    H.eq(O.Build(), f, "built once")
    local rowsBy = {}
    for _, r in ipairs(f.rows) do if r.opt then rowsBy[r.opt.key] = r end end
    -- every quiet-start extra has a visible switch, and the channel's two
    for _, key in ipairs({ "logins", "mapDots", "versionNote", "comm", "commShare" }) do
        H.ok(rowsBy[key] and rowsBy[key].opt.kind == "toggle", "a switch for " .. key)
    end
    for key in pairs(NS.QUIET) do H.ok(rowsBy[key] ~= nil, "quiet-start key " .. key .. " can be switched on in the window") end
    H.ok(rowsBy.terminal and rowsBy.terminal.opt.kind == "button", "and a button to the terminal")
    H.ok(math.abs(f:GetWidth() / f:GetHeight() - 1.43) < 0.02, "the family's 1.43:1",
         ("%d x %d"):format(f:GetWidth(), f:GetHeight()))
    -- every clickable row pops under the mouse (the standing rule): the kit hooks the row and its control
    H.ok(rowsBy.logins.hoverable and rowsBy.logins.lit and rowsBy.logins.bar, "rows pop under the mouse (wash + bar)")
    rowsBy.logins._scripts.hook_OnEnter(rowsBy.logins)
    H.ok(rowsBy.logins.lit:GetAlpha() > 0 and rowsBy.logins.bar:GetAlpha() == 1, "and light up when hovered")
    rowsBy.logins.ctl._scripts.OnEnter(rowsBy.logins.ctl)
    H.ok(rowsBy.logins.ctl.wash:GetAlpha() > 0, "its box too")

    -- a switch does what its slash command does (earlier sections switched dots and logins on, as a player would)
    _G.SlashCmdList.BISGUILD("dots off")
    _G.SlashCmdList.BISGUILD("logins off")
    f:Paint()
    H.ok(not rowsBy.mapDots.ctl.on and not rowsBy.logins.ctl.on and not rowsBy.versionNote.ctl.on,
         "a new install: the three extras paint off")
    lib.spots = { Bob = { map = 1411, x = 0.5, y = 0.4, at = H.clock } }
    rowsBy.mapDots.ctl:Click()
    H.ok(_G.BiSGuildDB.mapDots == true and M.On() and rowsBy.mapDots.ctl.on, "dots: on from the window, saved, painted")
    rowsBy.mapDots.ctl:Click()
    H.ok(_G.BiSGuildDB.mapDots == false and M.Update() == 0, "and off again: no dots")
    L.waiting = { { name = "Kio Alpha", key = "kio alpha" } }
    rowsBy.logins.ctl:Click()
    H.ok(_G.BiSGuildDB.logins == true and L.On(), "logins: on from the window")
    rowsBy.logins.ctl:Click()
    H.ok(_G.BiSGuildDB.logins == false and #L.waiting == 0, "off: and whoever was waiting goes with the window")
    rowsBy.versionNote.ctl:Click()
    H.ok(_G.BiSGuildDB.versionNote == true and C.NoteOn(), "the newer-version note: on from the window")
    _G.SlashCmdList.BISGUILD("note off")
    H.ok(_G.BiSGuildDB.versionNote == false and not C.NoteOn(), "/bisg note off: the same switch")
    f:Paint()
    H.ok(not rowsBy.versionNote.ctl.on, "and the window shows it")
    rowsBy.comm.ctl:Click()
    H.ok(not lib:Enabled() and _G.BiSGuildDB.comm == false, "the BiS channel: off from the window, and saved at once")
    rowsBy.comm.ctl:Click()
    H.ok(lib:Enabled() and _G.BiSGuildDB.comm == true, "and on again")
    local share = lib:Sharing()
    rowsBy.commShare.ctl:Click()
    H.ok(lib:Sharing() == not share and _G.BiSGuildDB.commShare == lib:Sharing(), "share my spot: flips, saved")
    rowsBy.commShare.ctl:Click()
    H.eq(lib:Sharing(), share, "and back")
    rowsBy.terminal.ctl:Click()
    H.ok(NS.K.frame and NS.K.frame:IsShown(), "the terminal button opens the terminal")
    NS.K.Hide()

    -- the BiS> page: the game's Settings panel stood in as Forever's does where it matters (BiSTheme/dev/tests.lua
    -- section 10): a subcategory needs a REGISTERED parent, an unknown id opens nothing, categories answer GetID
    H.eq(O.Register(), nil, "no game options panel: no page, no error")
    local reg, opened, nextId = {}, {}, 0
    local function Category(name)
        nextId = nextId + 1
        local c = { name = name, id = nextId }
        function c:GetID() return self.id end
        reg[c.id] = c
        return c
    end
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) local c = Category(name) c.frame = frame return c, {} end,
        RegisterAddOnCategory = function(c) c.addon = true end,
        RegisterCanvasLayoutSubcategory = function(parent, frame, name)
            if not (parent and parent.addon) then error("parent category is not registered") end
            local c = Category(name) c.frame, c.parentCat = frame, parent
            return c, {}
        end,
        OpenToCategory = function(id) if not reg[id] then return false end opened[#opened + 1] = reg[id].name return true end,
    }
    fire("PLAYER_LOGIN")
    local page = T.settingsPages.BiSGuild
    H.ok(page and page.category and page.category.name == "BiS> Guild" and page.category.parentCat.name == "BiS>",
         "at login: BiS> Guild, under the one BiS> entry")
    local spec = page and page.spec or {}
    H.eq(spec.status and spec.status(), "logins off  -  dots off  -  note off", "the front page says what is on")
    H.ok(spec.api and spec.api.name == "BiSGuildAPI" and _G.BiSGuildAPI ~= nil, "and names the API table, which exists")
    H.ok(spec.open and spec.open.label == "the terminal", "the page's big button: the terminal")
    spec.open.func()
    H.ok(NS.K.frame:IsShown(), "which opens it")
    NS.K.Hide()
    -- THE DASHBOARD (Settings minor 3, the family rule - Arn, 8 Nov, of BiS> Tools: "it looks way way better do it
    -- for the other ones"): the page draws itself from the window's own rows and never takes the window in
    H.ok(T.SETTINGS_MINOR == 3 and T.Dashboard, "the kit's Settings minor 3: the whole dashboard")
    H.ok(spec.build and spec.refresh and spec.window == nil, "the page is a dashboard, not the options window in a box")
    f:Hide()
    local parentBefore, scaleBefore = f:GetParent(), f:GetScale()
    -- a spy on the note's setter BEFORE the page is first drawn: the section switch must take this road
    local realSetNote, noteCalls = O.SetNote, 0
    O.SetNote = function(on) noteCalls = noteCalls + 1 return realSetNote(on) end
    T.ShowSettingsPage("BiSGuild")
    H.ok(f:GetParent() == parentBefore and f:GetScale() == scaleBefore and not f:IsShown(),
         "showing the page leaves the options window alone: same parent, same scale, still hidden")
    H.ok(not (page.frame.optBtn and page.frame.optBtn:IsShown()), "no stand-in button: the dashboard is the page")
    local d = page.frame.body.dash
    local titles = {}
    for i, r in ipairs(d and d.rows or {}) do titles[i] = r.entry.title end
    H.eq(table.concat(titles, ", "), "the terminal, login pop-up, map dots, the BiS channel, version note",
         "a row per section down the left")
    H.ok(d.list.head:GetText() == "SECTIONS" and d.selected == "terminal", "the list's title; the terminal picked first")
    for _, r in ipairs(d.rows) do
        H.ok(not r.lamp._all and r.lamp._w == 8 and not r.bar._all and r.bar._w == 3,
             "a row's lamp and bar are their own size: " .. r.entry.title)
        H.ok(r.entry.desc and #r.entry.desc > 20, "every section says what it is for: " .. r.entry.title)
    end
    H.eq(d.count:GetText(), "1 of 4 on", "how many are on (only the BiS channel, a new install's quiet start)")
    -- the terminal: no switch of its own, a button to it, its command
    H.ok(not d.detail.switch:IsShown() and d.detail.open:IsShown() and d.detail.none:IsShown(),
         "the terminal: always on, nothing to set, a button to open it")
    H.eq(d.detail.usage:GetText(), "command:  /bisg", "and its command at the foot")
    d.detail.open:Click()
    H.ok(NS.K.frame:IsShown(), "which opens the terminal")
    NS.K.Hide()
    -- pick a section: its words and its switch
    local rowBy = {}
    for _, r in ipairs(d.rows) do rowBy[r.entry.key] = r end
    rowBy.dots:Click("LeftButton")
    H.ok(d.selected == "dots" and d.detail.name:GetText() == "map dots" and d.detail.switch:IsShown()
         and not d.detail.switch.on, "click map dots: its name, its switch (off)")
    H.eq(d.detail.usage:GetText(), "command:  /bisg dots on | off", "and its slash command")
    -- the big switch: the SAME saved value the options window shows, and the window agrees after its Paint
    d.detail.switch:Click()
    H.ok(_G.BiSGuildDB.mapDots == true and M.On() and d.detail.switch.on and rowBy.dots.state:GetText() == "ON",
         "the big switch: dots on, saved, the list follows")
    f:Paint()
    H.ok(rowsBy.mapDots.ctl.on, "the options window's row agrees")
    _G.SlashCmdList.BISGUILD("dots off")
    spec.refresh(page.frame.body)
    H.ok(not d.detail.switch.on and rowBy.dots.state:GetText() == "off", "/bisg dots off: the page shows it on its next paint")
    -- right-click in the list: the logins setter (whoever was waiting goes with the window - only SetLogins does that)
    L.waiting = { { name = "Kio Alpha", key = "kio alpha" } }
    rowBy.logins:Click("RightButton")
    H.ok(_G.BiSGuildDB.logins == true and L.On(), "right-click login pop-up: on")
    rowBy.logins:Click("RightButton")
    H.ok(_G.BiSGuildDB.logins == false and #L.waiting == 0, "and off, through SetLogins: the waiting list went with it")
    -- a section switch goes through the same setter as its slash command
    rowBy.note:Click("LeftButton")
    d.detail.switch:Click()
    H.ok(noteCalls == 1 and _G.BiSGuildDB.versionNote == true and C.NoteOn(), "version note: on, through O.SetNote")
    _G.SlashCmdList.BISGUILD("note off")
    H.ok(noteCalls == 2 and not C.NoteOn(), "/bisg note off: the same O.SetNote")
    O.SetNote = realSetNote
    -- the BiS channel: its own switch, and sharing your spot as a setting row under it
    rowBy.comm:Click("LeftButton")
    local commRows = d.pages.comm or {}
    H.ok(d.detail.switch.on and #commRows == 1 and commRows[1].opt.key == "commShare", "the BiS channel: on, and share my spot under it")
    local shareWas = lib:Sharing()
    commRows[1].sw:Click()
    H.ok(lib:Sharing() == not shareWas and _G.BiSGuildDB.commShare == lib:Sharing(), "share my spot from the page: flips, saved")
    f:Paint()
    H.eq(rowsBy.commShare.ctl.on, lib:Sharing(), "and the options window's row agrees after its Paint")
    commRows[1].sw:Click()
    H.eq(lib:Sharing(), shareWas, "and back")
    d.detail.switch:Click()
    H.ok(not lib:Enabled() and _G.BiSGuildDB.comm == false and commRows[1].dim, "channel off from the page: saved, its row greyed")
    rowBy.comm:Click("RightButton")
    H.ok(lib:Enabled() and _G.BiSGuildDB.comm == true, "right-click: on again")
    -- pointing at a section reads its words in the help strip
    rowBy.dots._scripts.OnEnter(rowBy.dots)
    H.eq(d.help.text:GetText(), rowBy.dots.entry.desc, "a list row pops and reads its words")
    rowBy.dots._scripts.OnLeave(rowBy.dots)
    -- an open options window is repainted when the page changes something
    f:Show()
    rowBy.dots:Click("RightButton")
    H.ok(_G.BiSGuildDB.mapDots == true and rowsBy.mapDots.ctl.on, "the window, open, repaints when the page flips a switch")
    rowBy.dots:Click("RightButton")
    f:Hide()
    H.ok(f:GetParent() == parentBefore and f:GetScale() == scaleBefore, "the options window was never re-parented")
    T.HideSettingsPage("BiSGuild")
    H.ok(not f:IsShown() and f:GetParent() == parentBefore, "leaving the page gives nothing back - nothing was taken")
    local before = #opened
    _G.SlashCmdList.BISGUILD("options")
    H.ok(f:IsShown() and #opened == before, "/bisg options opens the options window itself, not the game's options")
    f:Hide()
    H.ok(T.OpenSettings("BiSGuild") and opened[#opened] == "BiS> Guild", "(the family's OpenSettings still reaches the page)")
    _G.Settings = nil
    T.settingsPages.BiSGuild.category = nil
    _G.SlashCmdList.BISGUILD("options")
    H.ok(f:IsShown(), "without the game's panel too")
    f:Hide()
    T.settingsRoot, T.settingsPages, T.settingsOrder = nil, {}, {}

    -- NO MINIMAP BUTTON (BiS Guild never had one; /bisg and the BiS> page are the doors)
    H.ok(not listed("Libs/BiSTheme/Minimap.lua") and T.Minimap == nil, "no minimap button: the kit is not even loaded")
    -- and still no fingerprint of BiS Guild's own (dropped 18 Oct): the kit's help strip may name the build at rest
    H.ok(NS.BUILD == nil and bytes(ROOT .. "/Core/Build.lua") == nil, "BiS Guild carries no build fingerprint of its own")
    _G.SlashCmdList.BISGUILD("help")
end

H.report()
