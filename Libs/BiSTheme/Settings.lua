--[[
  BiSTheme / Settings.lua  --  ONE "BiS>" HOME in the game's own options (Esc > Options > AddOns).

  Arn, 7 Nov 2026 (the Forever 1.0 round): "when they open the options, they go to add-ons. They won't see
  BiSGamba, BiS Healing, they'll just see BiS> ... they click into that and then they can see all our add-ons
  ... and because that menu screen is a bigger size, we have a lot more room ... that cockpit philosophy of very
  easy to read, very functional, very reliable". And for whoever never finds the minimap button: "they could
  always reliably go press escape, go to the options, go to the add-on options, click our section".

  So the game's AddOns list carries ONE entry, "BiS>", whichever BiS addon loaded first made it:
    BiS>                     the front page: every BiS addon you have, its version and what is on, the shared
                             channel explained, and each addon's API for other addon authors
      BiS> Healing           a page per addon, under it: its own settings
      BiS> Tools  ...

  Usage from any addon (once, at PLAYER_LOGIN or later):
      BiSTheme.SettingsPage("BiSHealing", {
        title  = "Healing",                          -- shown as "BiS> Healing"
        about  = "Click-to-heal raid frames ...",    -- one or two plain lines
        status = function() return "frames on  -  target off" end,  -- what is on, in a few words (front page)
        window = function() return optionsFrame end, -- its own options window: a button on the page opens it
        build  = function(body) ... end,             -- the DASHBOARD: draw the whole page, once (T.Dash* below)
        refresh = function(body) ... end,            -- every time the page shows: paint what is true now
        open   = { label = "mouse binds", func = function() ... end },   -- optional big button: the main window
        api    = { name = "BiSHealingAPI", about = "read the grid's ... " },  -- for other addon authors
      })
      BiSTheme.OpenSettings("BiSHealing")             -- the minimap's right-click (the family standard)

  The game's options panel itself is Blizzard's (Settings.RegisterCanvasLayoutCategory / ...Subcategory /
  RegisterAddOnCategory / OpenToCategory - present on Forever; Ace3, Gargul and others use the same calls
  there). Without it (an older client) every call here answers nil and the addon's own window still works.

  MINOR 2 (Arn, 7 Nov, the first live look: "the windows are using like 30% of the available space ... we
  esentially just took the old option window kept it the same size and nestels it inside a bigger window" and
  "dont just shrink remake them all shrinking just makes them harder to read"). A page never takes the options
  window in any more: the old window stays the old window (the minimap's right-click, as before), and the page is
  a DASHBOARD the addon draws with the kit below - big switches, readable rows, a help strip - using the whole
  page. An addon that has not drawn one yet gets a plain page: what it is, what is on, a button to its window.

  SELF-GUARDED like the other kit files: newest SETTINGS_MINOR wins, and the pages registered by an older copy
  are kept (they live on the shared BiSTheme table). Canon here; _bisdev/sync.ps1 copies it out.
]]
BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.SETTINGS_MINOR or 0) >= 3 then return end
T.SETTINGS_MINOR = 3

-- palette fallback: only when this file is embedded and no other BiSTheme file ran (as the others do)
if not T.rgb then
  local FALLBACK = {
    bg = "121020", surface = "1a1730", sunken = "221d3c", line = "2a2446",
    line2 = "3a3260", ink = "ece8f6", ink2 = "c6bedd", muted = "968ead",
    accent = "b980ff", accentSoft = "2c2148", good = "4fd0cf", warn = "f08cb0",
    gold = "e5c04a", slate = "8fb4d6", dim = "8e86a6",
  }
  T.hex = T.hex or FALLBACK
  local cache = {}
  function T.rgb(name)
    local hex = T.hex[name] or T.hex.ink
    local c = cache[hex]
    if c then return c[1], c[2], c[3] end
    c = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    cache[hex] = c
    return c[1], c[2], c[3]
  end
  function T.text(name, s) return "|cff" .. (T.hex[name] or T.hex.ink) .. tostring(s) .. "|r" end
end

T.SETTINGS = {
  ROOT = "BiS>",
  PAD = 16,
  TITLE = 18, HEAD = 13, BODY = 11, SMALL = 10,   -- cockpit: big and readable
  ROW = 34,
  ABOUT_COMM = "Every BiS addon can talk to the same addons in your group and guild, over the game's own hidden "
    .. "addon channel - never in chat. That is how the ride clock, the version list, summons, rivals and the guild's "
    .. "recruits reach everyone with a BiS addon. It sends small notes only when there is something to say. Off: "
    .. "you hear nothing and say nothing, and every addon still works on its own.",
  ABOUT_API = "Other addon authors: each BiS addon answers through one global table, read-only, safe at any time "
    .. "(it answers nil and a reason when it cannot). Its version only goes up; nothing is taken away without a new "
    .. "major. The table's own file documents every call.",
}
T.settingsPages = T.settingsPages or {}         -- addon -> page (shared by every embedded copy)
T.settingsOrder = T.settingsOrder or {}

local function Settings_() return rawget(_G, "Settings") end

local function fs(parent, size, colour, text)
  local s = parent:CreateFontString(nil, "OVERLAY")
  if T.SetFont then T.SetFont(s, size) else s:SetFont(STANDARD_TEXT_FONT, size, "") end
  local r, g, b = T.rgb(colour or "ink")
  s:SetTextColor(r, g, b, 1)
  if s.SetJustifyH then s:SetJustifyH("LEFT") end
  s:SetText(text or "")
  return s
end

local function tex(parent, layer, colour, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  local r, g, b = T.rgb(colour)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

--- A big button that POPS under the mouse (the family's hover rule): a wash, an accent edge, bright words.
local function button(parent, label, w, onclick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  local bg = tex(b, "BACKGROUND", "sunken", 1)
  bg:SetAllPoints()
  b.wash = tex(b, "BORDER", "accent", 0.35)
  b.wash:SetAllPoints()
  b.wash:SetAlpha(0)
  b.edge = tex(b, "ARTWORK", "accent", 1)
  b.edge:SetPoint("BOTTOMLEFT") b.edge:SetPoint("BOTTOMRIGHT") b.edge:SetHeight(2)
  b.edge:SetAlpha(0.4)
  b.label = fs(b, T.SETTINGS.BODY, "ink2", label)
  b.label:SetPoint("CENTER")
  if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
  b:SetScript("OnEnter", function(s) s.wash:SetAlpha(1) s.edge:SetAlpha(1) s.label:SetTextColor(T.rgb("ink")) end)
  b:SetScript("OnLeave", function(s) s.wash:SetAlpha(0) s.edge:SetAlpha(0.4) s.label:SetTextColor(T.rgb("ink2")) end)
  b:SetScript("OnClick", function() onclick() end)
  return b
end
T.SettingsButton = button

local function version(addon)
  if T.StampText then return T.StampText(addon) end
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get, addon, "Version")
  return ok and type(v) == "string" and v or nil
end

local function categoryID(cat)
  if type(cat) ~= "table" then return nil end
  if cat.GetID then
    local ok, id = pcall(cat.GetID, cat)
    if ok and id ~= nil then return id end
  end
  return cat.ID
end

--------------------------------------------------------------------
-- the front page
--------------------------------------------------------------------

--- The "BiS>" entry in the game's AddOns options, made once by whichever BiS addon asks first. nil without the
--- game's Settings panel.
function T.SettingsRoot()
  if T.settingsRoot then return T.settingsRoot end
  local S = Settings_()
  if not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return nil end
  local f = CreateFrame("Frame")
  f:Hide()
  local ok, cat = pcall(S.RegisterCanvasLayoutCategory, f, T.SETTINGS.ROOT)
  if not (ok and cat) then return nil end
  if not pcall(S.RegisterAddOnCategory, cat) then return nil end
  T.settingsRoot = { frame = f, category = cat }
  f:SetScript("OnShow", function() T.PaintSettingsRoot() end)
  return T.settingsRoot
end

--- The front page's words: a row per addon (name, version, what is on, a button to its page), the shared channel,
--- the API notes. Drawn when shown, so it always says what is true now.
function T.PaintSettingsRoot()
  local root = T.settingsRoot
  if not root then return end
  local f, P = root.frame, T.SETTINGS
  if not f.title then
    f.title = fs(f, P.TITLE, "accent", "BiS>")
    f.title:SetPoint("TOPLEFT", P.PAD, -P.PAD)
    f.intro = fs(f, P.BODY, "ink2", "Every BiS addon you have, in one place. Click one to see and change what it does. "
      .. "A new install starts with only its main job on - everything else waits for you to switch it on.")
    f.intro:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.intro:SetPoint("RIGHT", f, "RIGHT", -P.PAD, 0)
    f.rows = {}
    f.commHead = fs(f, P.HEAD, "gold", "THE SHARED CHANNEL")
    f.comm = fs(f, P.SMALL, "ink2", P.ABOUT_COMM)
    f.apiHead = fs(f, P.HEAD, "gold", "FOR ADDON AUTHORS")
    f.api = fs(f, P.SMALL, "ink2", "")
  end
  local y = -(P.PAD + P.TITLE + 6 + 36)
  local i = 0
  local apiLines = { P.ABOUT_API }
  for _, addon in ipairs(T.settingsOrder) do
    local page = T.settingsPages[addon]
    local spec = page and page.spec
    if spec then
      i = i + 1
      local r = f.rows[i]
      if not r then
        r = CreateFrame("Frame", nil, f)
        r:SetHeight(P.ROW)
        r.bg = tex(r, "BACKGROUND", "sunken", 0.6)
        r.bg:SetAllPoints()
        r.name = fs(r, P.HEAD, "ink", "")
        r.name:SetPoint("LEFT", 10, 6)
        r.ver = fs(r, P.SMALL, "dim", "")
        r.ver:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.state = fs(r, P.SMALL, "ink2", "")
        r.state:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.go = button(r, "open", 90, function() T.OpenSettings(r.addon) end)
        r.go:SetPoint("RIGHT", -8, 0)
        f.rows[i] = r
      end
      r.addon = addon
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", f, "TOPLEFT", P.PAD, y)
      r:SetPoint("RIGHT", f, "RIGHT", -P.PAD, 0)
      r.name:SetText("BiS> " .. tostring(spec.title or addon))
      r.ver:SetText(version(addon) or "")
      local okS, s = pcall(function() return spec.status and spec.status() end)
      r.state:SetText(okS and type(s) == "string" and s or "")
      r:Show()
      y = y - P.ROW - 4
      if spec.api and spec.api.name then
        apiLines[#apiLines + 1] = T.text("ink", spec.api.name) .. "  -  " .. tostring(spec.api.about or "")
      end
    end
  end
  for j = i + 1, #f.rows do f.rows[j]:Hide() end
  y = y - 10
  f.commHead:ClearAllPoints() f.commHead:SetPoint("TOPLEFT", f, "TOPLEFT", P.PAD, y)
  f.comm:ClearAllPoints() f.comm:SetPoint("TOPLEFT", f.commHead, "BOTTOMLEFT", 0, -4)
  f.comm:SetPoint("RIGHT", f, "RIGHT", -P.PAD, 0)
  local lib = rawget(_G, "LibBiSComm")
  if lib and lib.Enabled and lib.SetEnabled then
    if not f.commBtn then
      f.commBtn = button(f, "", 200, function()
        local l = rawget(_G, "LibBiSComm")
        if l then pcall(l.SetEnabled, l, not l:Enabled()) end
        T.PaintSettingsRoot()
      end)
    end
    local okE, on = pcall(lib.Enabled, lib)
    f.commBtn.label:SetText((okE and on) and "the channel is ON - click to turn off" or "the channel is OFF - click to turn on")
    f.commBtn:ClearAllPoints()
    f.commBtn:SetPoint("TOPLEFT", f.comm, "BOTTOMLEFT", 0, -6)
    f.commBtn:SetWidth(260)
    f.commBtn:Show()
  elseif f.commBtn then
    f.commBtn:Hide()
  end
  f.apiHead:ClearAllPoints()
  f.apiHead:SetPoint("TOPLEFT", (f.commBtn and f.commBtn:IsShown()) and f.commBtn or f.comm, "BOTTOMLEFT", 0, -14)
  f.api:ClearAllPoints() f.api:SetPoint("TOPLEFT", f.apiHead, "BOTTOMLEFT", 0, -4)
  f.api:SetPoint("RIGHT", f, "RIGHT", -P.PAD, 0)
  f.api:SetText(table.concat(apiLines, "\n"))
end

--------------------------------------------------------------------
-- a page per addon
--------------------------------------------------------------------

--- Register (or update) an addon's page under "BiS>". Answers the page, or nil without the game's panel.
function T.SettingsPage(addon, spec)
  if type(addon) ~= "string" or type(spec) ~= "table" then return nil end
  local page = T.settingsPages[addon]
  if not page then
    page = { addon = addon }
    T.settingsPages[addon] = page
    T.settingsOrder[#T.settingsOrder + 1] = addon
    table.sort(T.settingsOrder)
  end
  page.spec = spec
  local root = T.SettingsRoot()
  local S = Settings_()
  if root and not page.category and S and S.RegisterCanvasLayoutSubcategory then
    local f = CreateFrame("Frame")
    f:Hide()
    local ok, sub = pcall(S.RegisterCanvasLayoutSubcategory, root.category, f, "BiS> " .. tostring(spec.title or addon))
    if ok and sub then
      page.frame, page.category = f, sub
      f:SetScript("OnShow", function() T.ShowSettingsPage(addon) end)
      f:SetScript("OnHide", function() T.HideSettingsPage(addon) end)
    end
  end
  return page.category and page or nil
end

--- The page shown: its head (name, version, what it is for, the main window's button), then the addon's own
--- options window held inside it, or what the addon draws itself.
function T.ShowSettingsPage(addon)
  local page = T.settingsPages[addon]
  if not (page and page.frame and page.spec) then return end
  local f, spec, P = page.frame, page.spec, T.SETTINGS
  if not f.title then
    f.title = fs(f, P.TITLE, "accent", "")
    f.title:SetPoint("TOPLEFT", P.PAD, -P.PAD)
    f.ver = fs(f, P.SMALL, "dim", "")
    f.ver:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.about = fs(f, P.BODY, "ink2", "")
    f.about:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.about:SetPoint("RIGHT", f, "RIGHT", -P.PAD, 0)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", P.PAD, -(P.PAD + P.TITLE + 6 + 34))
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -P.PAD, P.PAD)
  end
  f.title:SetText("BiS> " .. tostring(spec.title or addon))
  f.ver:SetText(version(addon) or "")
  f.about:SetText(spec.about or "")
  if spec.open and spec.open.func then
    -- the game's options panel closes first, so the window it opens is not left behind it (Nebbinator's helper,
    -- 7 Nov: "the desk button opens the window; it may sit behind the game's options panel")
    if not f.openBtn then f.openBtn = button(f, "", 160, function() T.CloseSettingsPanel() pcall(page.spec.open.func) end) end
    f.openBtn.label:SetText(tostring(spec.open.label or "open"))
    f.openBtn:ClearAllPoints()
    f.openBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -P.PAD, -P.PAD)
    f.openBtn:Show()
  elseif f.openBtn then
    f.openBtn:Hide()
  end
  if spec.build then
    -- THE DASHBOARD: the addon draws the whole body once, then paints it every time the page shows
    if f.optBtn then f.optBtn:Hide() end
    if f.state then f.state:Hide() end
    if not f.built then
      f.built = true
      local okB, why = pcall(spec.build, f.body)
      -- a broken dashboard reaches BugSack (the game's error handler), never the page's other addons
      if not okB and geterrorhandler then pcall(geterrorhandler(), addon .. " dashboard: " .. tostring(why)) end
    end
    if spec.refresh then pcall(spec.refresh, f.body) end
    return
  end
  -- NOT DRAWN YET: what is on, and a big button to the addon's own options window - which stays exactly as it is
  if not f.state then
    f.state = fs(f.body, P.HEAD, "ink", "")
    f.state:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
    f.state:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
  end
  local okS, s = pcall(function() return spec.status and spec.status() end)
  f.state:SetText(okS and type(s) == "string" and s or "")
  f.state:Show()
  if spec.window then
    if not f.optBtn then
      f.optBtn = button(f.body, "the options window", 200, function()
        T.CloseSettingsPanel()
        local okW, win = pcall(page.spec.window)
        if okW and type(win) == "table" and win.Show then
          if win.Raise then pcall(win.Raise, win) end
          win:Show()
        end
      end)
      f.optBtn:SetHeight(30)
      f.optBtn:SetPoint("TOPLEFT", f.state, "BOTTOMLEFT", 0, -14)
    end
    f.optBtn:Show()
  elseif f.optBtn then
    f.optBtn:Hide()
  end
end

--- Leaving the page: nothing to give back (minor 2 holds no window). Kept so a page's OnHide still has a target.
function T.HideSettingsPage(addon)
  local page = T.settingsPages[addon]
  if page and page.spec and page.spec.hide then pcall(page.spec.hide, page.frame and page.frame.body) end
end

--------------------------------------------------------------------
-- THE DASHBOARD KIT (minor 2): what an addon draws its page with
--------------------------------------------------------------------
-- The cockpit look (Arn: "a $1 billion jet fighter ... so simple and very functional", the Turbo Vision / Mac
-- Platinum depth he liked): dark insets, RAISED buttons (a light top edge, a dark bottom edge), big words, ON in
-- green and OFF in grey, and nothing on the page that does not do something. The same four kinds as Options.lua -
-- toggle, seg, step, button - read from the same option tables, so an addon's settings need no second copy.
-- Every row and every button POPS under the mouse (the family rule), and the row's help shows in the help strip.

T.SETTINGS.DASH = { ROW = 32, LABEL = 13, SW_W = 66, SW_H = 24, SEG_W = 70, STEP_W = 28, VAL_W = 76, BTN_W = 140,
                    HEAD = 30, HELP = 40 }

local function raised(b)
  b.bg = tex(b, "BACKGROUND", "surface", 1)
  b.bg:SetAllPoints()
  b.top = tex(b, "BORDER", "line2", 1)
  b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(1)
  b.bot = tex(b, "BORDER", "bg", 1)
  b.bot:SetPoint("BOTTOMLEFT") b.bot:SetPoint("BOTTOMRIGHT") b.bot:SetHeight(2)
  b.wash = tex(b, "ARTWORK", "accent", 0.35)
  b.wash:SetAllPoints()
  b.wash:SetAlpha(0)
end

local function hover(b, row)
  b:SetScript("OnEnter", function(s) s.wash:SetAlpha(1) if row and row.Pop then row:Pop(true) end end)
  b:SetScript("OnLeave", function(s) s.wash:SetAlpha(0) if row and row.Pop then row:Pop(false) end end)
end

--- A big raised button. `row` (optional): the dashboard row it sits on, kept lit while the mouse is on the button.
function T.DashButton(parent, label, w, onclick, row)
  local D = T.SETTINGS.DASH
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or D.BTN_W, D.SW_H)
  raised(b)
  b.label = fs(b, D.LABEL, "ink", label)
  b.label:SetPoint("CENTER", 0, 0)
  if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
  hover(b, row)
  b:SetScript("OnClick", function(s) if onclick then onclick(s) end end)
  return b
end

--- The ON / OFF switch: a lamp and a word, green when on. b:Set(on).
function T.DashSwitch(parent, onclick, row)
  local D = T.SETTINGS.DASH
  local b = T.DashButton(parent, "OFF", D.SW_W, onclick, row)
  b.fill = tex(b, "BORDER", "good", 0.22)
  b.fill:SetAllPoints()
  b.lamp = tex(b, "OVERLAY", "line2", 1)
  b.lamp:SetSize(8, 8)
  b.lamp:SetPoint("LEFT", 8, 0)
  b.label:ClearAllPoints()
  b.label:SetPoint("CENTER", 6, 0)
  function b:Set(on)
    self.on = on and true or false
    self.label:SetText(self.on and "ON" or "OFF")
    self.label:SetTextColor(T.rgb(self.on and "good" or "muted"))
    self.lamp:SetColorTexture(T.rgb(self.on and "good" or "line2"))
    self.fill:SetAlpha(self.on and 1 or 0)
  end
  b:Set(false)
  return b
end

--- A panel: a dark box with a gold title. Children anchor inside it below p.HEAD.
function T.DashPanel(parent, title)
  local D = T.SETTINGS.DASH
  local p = CreateFrame("Frame", nil, parent)
  p.bg = tex(p, "BACKGROUND", "bg", 0.92)
  p.bg:SetAllPoints()
  p.edges = {}
  for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
                         { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = tex(p, "BORDER", "line", 1)
    e:SetPoint(pts[1]) e:SetPoint(pts[2])
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    p.edges[i] = e
  end
  p.head = fs(p, T.SETTINGS.HEAD, "gold", title or "")
  p.head:SetPoint("TOPLEFT", 12, -9)
  p.HEAD = D.HEAD
  return p
end

--- The help strip: one line of words for whatever is under the mouse. h:Say(text), h:Idle().
function T.DashHelp(parent, idle)
  local D = T.SETTINGS.DASH
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(D.HELP)
  h.bg = tex(h, "BACKGROUND", "sunken", 1)
  h.bg:SetAllPoints()
  h.bar = tex(h, "BORDER", "accent", 1)
  h.bar:SetPoint("TOPLEFT") h.bar:SetPoint("BOTTOMLEFT") h.bar:SetWidth(3)
  h.text = fs(h, T.SETTINGS.BODY + 1, "ink2", "")
  h.text:SetPoint("TOPLEFT", 12, -6)
  h.text:SetPoint("BOTTOMRIGHT", -10, 6)
  if h.text.SetJustifyV then h.text:SetJustifyV("MIDDLE") end
  h.idle = idle or "Point at anything on this page to read what it does."
  function h:Say(text) self.text:SetText(text and text ~= "" and text or self.idle) end
  function h:Idle() self.text:SetText(self.idle) end
  h:Idle()
  return h
end

local DASH = {}

function DASH.toggle(row, opt, db)
  row.sw = T.DashSwitch(row, function() row:Change(not opt.get(db)) end, row)
  row.sw:SetPoint("RIGHT", -8, 0)
  row.ctlW = T.SETTINGS.DASH.SW_W
  row.paint = function() row.sw:Set(opt.get(db)) end
end

function DASH.seg(row, opt, db)
  local D = T.SETTINGS.DASH
  row.segs = {}
  local n = #opt.values
  for i, v in ipairs(opt.values) do
    local s = T.DashButton(row, tostring(v), D.SEG_W, function() row:Change(v) end, row)
    s:SetPoint("RIGHT", -8 - (n - i) * (D.SEG_W + 3), 0)
    s.fill = tex(s, "BORDER", "accent", 0.85)
    s.fill:SetAllPoints()
    s.value = v
    row.segs[i] = s
  end
  row.ctlW = n * (D.SEG_W + 3)
  row.paint = function()
    local cur = opt.get(db)
    for _, s in ipairs(row.segs) do
      s.on = s.value == cur
      s.fill:SetAlpha(s.on and 1 or 0)
      s.label:SetTextColor(T.rgb(s.on and "bg" or "ink2"))
    end
  end
end

function DASH.step(row, opt, db)
  local D = T.SETTINGS.DASH
  local function bump(dir)
    local v = tonumber(opt.get(db)) or opt.min
    v = v + dir * (opt.step or 1)
    if opt.min and v < opt.min then v = opt.min elseif opt.max and v > opt.max then v = opt.max end   -- the stepper clamps
    row:Change(v)
  end
  row.plus = T.DashButton(row, "+", D.STEP_W, function() bump(1) end, row)
  row.plus:SetPoint("RIGHT", -8, 0)
  row.val = fs(row, D.LABEL, "ink", "")
  row.val:SetWidth(D.VAL_W)
  if row.val.SetJustifyH then row.val:SetJustifyH("CENTER") end
  row.val:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
  row.minus = T.DashButton(row, "-", D.STEP_W, function() bump(-1) end, row)
  row.minus:SetPoint("RIGHT", row.val, "LEFT", -4, 0)
  row.ctlW = 2 * D.STEP_W + D.VAL_W + 8
  row.paint = function()
    local okV, s = pcall(function() return opt.show and opt.show(db) or opt.get(db) end)
    row.val:SetText(okV and tostring(s) or "?")
  end
end

function DASH.button(row, opt, db)
  local D = T.SETTINGS.DASH
  row.btn = T.DashButton(row, tostring(opt.button or "go"), D.BTN_W, function()
    if opt.action then opt.action(db) end
    if row.ctx and row.ctx.onChange then row.ctx.onChange(opt) end
  end, row)
  row.btn:SetPoint("RIGHT", -8, 0)
  row.ctlW = D.BTN_W
  row.paint = function() end
end

T.DashKinds = DASH

--- One setting as a big row: its words on the left, its control on the right. `opt` is the same table Options.lua
--- takes ({ kind, label, help, get, set, values | min, max, step, show | button, action }); ctx = { help = a help
--- strip, onChange = function(opt) }. row:Paint() reads the setting again; row:SetDim(true) greys it (tool off).
function T.DashControl(parent, opt, db, ctx)
  local D = T.SETTINGS.DASH
  local make = DASH[opt and opt.kind]
  if not make then error("BiSTheme: a dashboard has no '" .. tostring(opt and opt.kind) .. "' control", 2) end
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(D.ROW)
  if row.EnableMouse then row:EnableMouse(true) end
  row.opt, row.ctx = opt, ctx or {}
  row.bg = tex(row, "BACKGROUND", "sunken", 0.7)
  row.bg:SetAllPoints()
  row.wash = tex(row, "BORDER", "accent", 0.18)
  row.wash:SetAllPoints()
  row.wash:SetAlpha(0)
  row.bar = tex(row, "ARTWORK", "accent", 1)
  row.bar:SetPoint("TOPLEFT") row.bar:SetPoint("BOTTOMLEFT") row.bar:SetWidth(3)
  row.bar:SetAlpha(0)
  row.label = fs(row, D.LABEL, "ink", tostring(opt.label or ""))
  row.label:SetPoint("LEFT", 12, 0)
  if row.label.SetWordWrap then row.label:SetWordWrap(false) end
  function row:Pop(on)
    self.wash:SetAlpha(on and 1 or 0)
    self.bar:SetAlpha(on and 1 or 0)
    local h = self.ctx.help
    if h then if on then h:Say(self.opt.help or self.opt.label) else h:Idle() end end
  end
  function row:Change(v)
    self.opt.set(db, v)
    self:Paint()
    if self.ctx.onChange then self.ctx.onChange(self.opt) end
  end
  function row:Paint() if self.paint then self.paint() end end
  function row:SetDim(off)
    self.dim = off and true or false
    self.label:SetAlpha(off and 0.45 or 1)
  end
  row:SetScript("OnEnter", function(s) s:Pop(true) end)
  row:SetScript("OnLeave", function(s) s:Pop(false) end)
  make(row, opt, db)
  row.label:SetPoint("RIGHT", row, "RIGHT", -((row.ctlW or 0) + 20), 0)
  row:Paint()
  return row
end

--------------------------------------------------------------------
-- THE WHOLE DASHBOARD (minor 3): BiS> Tools' page, ready-made for every addon
--------------------------------------------------------------------
-- Arn, 8 Nov 2026, of the BiS> Tools page: "it looks way way better do it for the other ones". The shape:
--   left    a panel of SECTIONS - a row each, a lamp lit when it is on (a section with no switch has no lamp
--           colour of its own), ON / off; click = look at it, right-click = switch it
--   right   the picked one: its name, a big ON/OFF switch, an "open its window" button beside it, its words,
--           every setting as a big row in ONE column (shorter rows when many, never two columns), its command at
--           the foot
--   bottom  the help strip
-- model = { entries = { {key, title, desc, options, db, switch = {get, set}, open = {label, func}, usage} } (or a
-- function answering that), list = "SECTIONS", idle = "...", onChange = function(entry, opt) } - the options are the
-- same tables Options.lua takes, so an addon hands its sections over as they are. Answers d: d:Paint(), d:Select(key).
T.SETTINGS.DASH.LIST_W, T.SETTINGS.DASH.LIST_ROW, T.SETTINGS.DASH.GAP, T.SETTINGS.DASH.MIN_STEP = 220, 26, 12, 27

local Dash = {}
Dash.__index = Dash

function T.Dashboard(body, model)
  local D = T.SETTINGS.DASH
  local d = setmetatable({ body = body, model = model or {}, rows = {}, pages = {} }, Dash)
  body.dash = d
  local list = d.model.entries
  d.entries = type(list) == "function" and list() or list or {}
  d.help = T.DashHelp(body, d.model.idle or "Point at anything on this page to read what it does. Right-click a section in the list to switch it on or off.")
  d.help:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  d.help:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  d.list = T.DashPanel(body, d.model.list or "SECTIONS")
  d.list:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  d.list:SetPoint("BOTTOMLEFT", d.help, "TOPLEFT", 0, D.GAP)
  d.list:SetWidth(D.LIST_W)
  d.count = fs(d.list, T.SETTINGS.BODY, "ink2", "")
  d.count:SetPoint("TOPRIGHT", d.list, "TOPRIGHT", -10, -10)
  for i, e in ipairs(d.entries) do
    local r = CreateFrame("Button", nil, d.list)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetHeight(D.LIST_ROW)
    r:SetPoint("TOPLEFT", d.list, "TOPLEFT", 6, -(d.list.HEAD + (i - 1) * (D.LIST_ROW + 2)))
    r:SetPoint("RIGHT", d.list, "RIGHT", -6, 0)
    r.bg = tex(r, "BACKGROUND", "sunken", 1)
    r.bg:SetAllPoints()
    r.wash = tex(r, "BORDER", "accent", 0.35)
    r.wash:SetAllPoints()
    r.wash:SetAlpha(0)
    -- the bar and the lamp are their OWN size: anchored, never stretched (the 8 Nov cyan rows)
    r.bar = tex(r, "ARTWORK", "accent", 1)
    r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT") r.bar:SetWidth(3)
    r.bar:SetAlpha(0)
    r.lamp = tex(r, "OVERLAY", "line2", 1)
    r.lamp:SetSize(8, 8)
    r.lamp:SetPoint("LEFT", 10, 0)
    r.name = fs(r, D.LABEL - 1, "ink", e.title or e.key)
    r.name:SetPoint("LEFT", 26, 0)
    r.state = fs(r, T.SETTINGS.BODY, "muted", "")
    r.state:SetPoint("RIGHT", -8, 0)
    r.entry = e
    r:SetScript("OnClick", function(s, button)
      if button == "RightButton" and s.entry.switch then d:Switch(s.entry, not d:On(s.entry)) else d:Select(s.entry.key) end
    end)
    r:SetScript("OnEnter", function(s) s.wash:SetAlpha(1) s.bar:SetAlpha(1) d.help:Say(s.entry.desc) end)
    r:SetScript("OnLeave", function(s)
      s.wash:SetAlpha(0) s.bar:SetAlpha(s.entry.key == d.selected and 1 or 0)
      d.help:Idle()
    end)
    d.rows[i] = r
  end
  local p = T.DashPanel(body, "")
  d.detail = p
  p:SetPoint("TOPLEFT", d.list, "TOPRIGHT", D.GAP, 0)
  p:SetPoint("BOTTOMRIGHT", d.help, "TOPRIGHT", 0, D.GAP)
  p.name = fs(p, T.SETTINGS.TITLE + 2, "accent", "")
  p.name:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
  p.switch = T.DashSwitch(p, function() local e = d:Entry() if e and e.switch then d:Switch(e, not d:On(e)) end end)
  p.switch:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -12)
  p.open = T.DashButton(p, "open its window", 130, function()
    local e = d:Entry()
    T.CloseSettingsPanel()
    if e and e.open and e.open.func then pcall(e.open.func) end
    d:Paint()
  end)
  p.open:SetPoint("TOPRIGHT", p.switch, "TOPLEFT", -8, 0)
  p.desc = fs(p, D.LABEL - 1, "ink2", "")
  if p.desc.SetWordWrap then p.desc:SetWordWrap(true) end
  p.desc:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -8)
  p.desc:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.usage = fs(p, T.SETTINGS.SMALL, "muted", "")
  if p.usage.SetWordWrap then p.usage:SetWordWrap(true) end
  p.usage:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
  p.usage:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.none = fs(p, D.LABEL - 1, "muted", "Nothing to set here.")
  d:Select(d.entries[1] and d.entries[1].key)
  return d
end

function Dash:Entry(key)
  key = key or self.selected
  for _, e in ipairs(self.entries) do if e.key == key then return e end end
end

function Dash:On(e)
  if not (e and e.switch and e.switch.get) then return nil end
  local ok, v = pcall(e.switch.get)
  return ok and v and true or false
end

function Dash:Changed(e, opt)
  if self.model.onChange then pcall(self.model.onChange, e, opt) end
  self:Paint()
end

function Dash:Switch(e, on)
  if e.switch and e.switch.set then pcall(e.switch.set, on and true or false) end
  self:Changed(e)
end

function Dash:Select(key)
  self.selected = key
  for k, rows in pairs(self.pages) do
    if k ~= key then for _, r in ipairs(rows) do r:Hide() end end
  end
  self:Paint()
end

--- The settings rows of one section, built the first time it is picked.
function Dash:Page(e)
  if self.pages[e.key] then return self.pages[e.key] end
  local ctx = { help = self.help, onChange = function(opt) self:Changed(e, opt) end }
  local rows = {}
  for i, opt in ipairs(e.options or {}) do rows[i] = T.DashControl(self.detail, opt, e.db, ctx) end
  self.pages[e.key] = rows
  return rows
end

--- ONE column under the words, full width; shorter rows when many (never two columns: they cut every label).
function Dash:Layout(rows, top, bottom)
  local D, p = T.SETTINGS.DASH, self.detail
  local step = D.ROW + 4
  local h = p.GetHeight and p:GetHeight() or 0
  local avail = (type(h) == "number" and h or 0) + top - (bottom or 0) - 8
  if avail > 0 and #rows * step > avail then step = math.max(D.MIN_STEP, math.floor(avail / #rows)) end
  for i, r in ipairs(rows) do
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 14, top - (i - 1) * step)
    r:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    r:SetHeight(step - 4)
    r:Show()
  end
  self.step = step
  return step
end

function Dash:Paint()
  local on, all = 0, 0
  for _, r in ipairs(self.rows) do
    local e = r.entry
    local en = self:On(e)
    if e.switch then
      all = all + 1
      if en then on = on + 1 end
      r.lamp:SetColorTexture(T.rgb(en and "good" or "line2"))
      r.state:SetText(en and "ON" or "off")
      r.state:SetTextColor(T.rgb(en and "good" or "muted"))
      r.name:SetTextColor(T.rgb(en and "ink" or "ink2"))
    else
      r.lamp:SetColorTexture(T.rgb("accent"))
      r.state:SetText("")
    end
    local picked = e.key == self.selected
    r.bar:SetAlpha(picked and 1 or 0)
    r.bg:SetColorTexture(T.rgb(picked and "line2" or "sunken"))
  end
  self.count:SetText(all > 0 and (on .. " of " .. all .. " on") or "")
  local e = self:Entry()
  if not e then return end
  local p = self.detail
  local en = self:On(e)
  p.name:SetText(e.title or e.key)
  p.desc:SetText(e.desc or "")
  if e.switch then p.switch:Set(en) p.switch:Show() else p.switch:Hide() end
  if e.open and e.open.func then
    p.open.label:SetText(tostring(e.open.label or "open its window"))
    p.open:Show()
  else
    p.open:Hide()
  end
  -- the rows start right under the words, however many lines they took (2 lines when the client will not say)
  local okH, descH = pcall(function() return p.desc:GetStringHeight() end)
  descH = (okH and type(descH) == "number" and descH > 0) and descH or 30
  local top = -(12 + 24 + 8) - math.ceil(descH) - 12
  local bottom = 0
  if e.usage then
    p.usage:SetText("command:  " .. e.usage)
    p.usage:Show()
    local okU, uh = pcall(function() return p.usage:GetStringHeight() end)
    bottom = 10 + ((okU and type(uh) == "number" and uh > 0) and math.ceil(uh) or 26)
  else
    p.usage:Hide()
  end
  local rows = self:Page(e)
  if #rows == 0 then
    p.none:ClearAllPoints()
    p.none:SetPoint("TOPLEFT", p, "TOPLEFT", 14, top - 4)
    p.none:Show()
  else
    p.none:Hide()
    self:Layout(rows, top, bottom)
  end
  for _, r in ipairs(rows) do
    r:Paint()
    r:SetDim(e.switch ~= nil and not en)
  end
end

--- Put the game's options panel away (before a page's button opens the addon's own window over the screen).
function T.CloseSettingsPanel()
  local sp = rawget(_G, "SettingsPanel")
  if not (sp and sp.IsShown) then return false end
  local okS, shown = pcall(sp.IsShown, sp)
  if not (okS and shown) then return false end
  if HideUIPanel then return pcall(HideUIPanel, sp) and true or false end
  return pcall(sp.Hide, sp) and true or false
end

--- Open the game's options on an addon's page (the minimap's right-click), or on "BiS>" itself. True when it did.
function T.OpenSettings(addon)
  local S = Settings_()
  if not (S and S.OpenToCategory) then return false end
  local page = addon and T.settingsPages[addon]
  local cat = (page and page.category) or (T.settingsRoot and T.settingsRoot.category)
  local id = categoryID(cat)
  if id == nil then return false end
  return pcall(S.OpenToCategory, id) and true or false
end
