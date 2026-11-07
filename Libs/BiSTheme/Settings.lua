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
        window = function() return optionsFrame end, -- an options window to show INSIDE the page (BiSTheme.Options)
        build  = function(frame) ... end,            -- or: draw the page yourself (an addon without Options.lua)
        open   = { label = "mouse binds", func = function() ... end },   -- optional big button: the main window
        api    = { name = "BiSHealingAPI", about = "read the grid's ... " },  -- for other addon authors
      })
      BiSTheme.OpenSettings("BiSHealing")             -- the minimap's right-click (the family standard)

  The game's options panel itself is Blizzard's (Settings.RegisterCanvasLayoutCategory / ...Subcategory /
  RegisterAddOnCategory / OpenToCategory - present on Forever; Ace3, Gargul and others use the same calls
  there). Without it (an older client) every call here answers nil and the addon's own window still works.

  SELF-GUARDED like the other kit files: newest SETTINGS_MINOR wins, and the pages registered by an older copy
  are kept (they live on the shared BiSTheme table). Canon here; _bisdev/sync.ps1 copies it out.
]]
BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.SETTINGS_MINOR or 0) >= 1 then return end
T.SETTINGS_MINOR = 1

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
    if not f.openBtn then f.openBtn = button(f, "", 160, function() pcall(page.spec.open.func) end) end
    f.openBtn.label:SetText(tostring(spec.open.label or "open"))
    f.openBtn:ClearAllPoints()
    f.openBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -P.PAD, -P.PAD)
    f.openBtn:Show()
  elseif f.openBtn then
    f.openBtn:Hide()
  end
  -- the addon's own options window, held in the page while it shows: no scale, no drag, no close of its own
  if spec.window then
    local okW, win = pcall(spec.window)
    if okW and type(win) == "table" and win.SetParent then
      page.held = page.held or {}
      local h = page.held
      if h.win ~= win then
        h.win = win
        h.parent = win.GetParent and win:GetParent() or UIParent
        h.scale = win.GetScale and win:GetScale() or 1
        h.strata = win.GetFrameStrata and win:GetFrameStrata() or "MEDIUM"
        h.points = {}
        if win.GetNumPoints then
          for n = 1, win:GetNumPoints() do h.points[n] = { win:GetPoint(n) } end
        end
      end
      win:SetParent(f.body)
      if win.SetScale then win:SetScale(1) end
      if win.SetFrameStrata then win:SetFrameStrata(f.GetFrameStrata and f:GetFrameStrata() or "HIGH") end
      win:ClearAllPoints()
      win:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
      win:Show()
      page.inside = true
    end
  elseif spec.build and not f.built then
    f.built = true
    pcall(spec.build, f.body)
  end
end

--- Leaving the page gives the options window back to the screen, as it was, hidden.
function T.HideSettingsPage(addon)
  local page = T.settingsPages[addon]
  local h = page and page.held
  if not (h and h.win and page.inside) then return end
  local win = h.win
  page.inside = nil
  win:Hide()
  win:SetParent(h.parent or UIParent)
  if win.SetScale then win:SetScale(h.scale or 1) end
  if win.SetFrameStrata then win:SetFrameStrata(h.strata or "MEDIUM") end
  win:ClearAllPoints()
  if #h.points > 0 then
    for _, p in ipairs(h.points) do win:SetPoint(unpack(p)) end
  else
    win:SetPoint("CENTER")
  end
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
