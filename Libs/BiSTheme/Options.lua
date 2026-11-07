--[[
  BiSTheme / Options.lua  --  the one options window every BiS addon wears.

  Arn, 10 Sep 2026, looking at BiSTools' Hub: "this is beautiful ... I want all
  option windows to look like this." So it stopped being BiSTools' window and
  became this file. See claude/bis-options.md for the law it implements.

  One narrow flat window, no tabs, no rail, no logo, no Blizzard art:

      BiS> Options_                                   x     <- 16 px header, the prompt
      nebbinator                                      #     <- section (accent, header shade)
        minimap button                                #     <- toggle
        BiS channel (/biscomm)                        #
        reset window position                  [ reset ]    <- button
      recruiting                                            <- a section with no on/off box
        auto-reply                    [first][always][off]  <- seg
        send cooldown                      <  10 s  >       <- step

  Usage from any addon:

      local f = BiSTheme.Options("NebbinatorOptions", 230, "Options")
      f:Section("nebbinator")                          -- no box
      f:Section("farm", { get = ..., set = ... })      -- with an on/off box
      f:Row({ kind = "toggle", label = "minimap button", get = ..., set = ... }, db)
      f:Fit()                                          -- size the window to its rows
      f:Toggle()                                       -- show / hide
      f.onChange = function() ... end                  -- repaint anything else that cares

  THIS FILE CARRIES ITS OWN PRIMITIVES ON PURPOSE. It borrows no widget kit from
  its host - not BiSTools' Farm kit, not Nebbinator's Kit - so the third addon to
  adopt is a table and a TOC line, and so every options window in the family is
  the same pixels rather than the same intentions.

  Self-guarded like Console.lua: an addon may ship a copy under Libs\BiSTheme\ so
  the window works without BiSTheme installed. Newest OPTIONS_MINOR wins; the
  canonical file lives in the BiSTheme addon and is copied out, never edited in
  place. Load it AFTER Console.lua - it uses the prompt when there is one, and
  degrades to a plain title when there is not.
]]

BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.OPTIONS_MINOR or 0) >= 4 then return end
T.OPTIONS_MINOR = 4      -- 2: Escape closes the window (UISpecialFrames), Arn 10 Sep
                         -- 3: a window opening on top of another moves beside it (Opt:Dodge), 14 Oct
                         -- 4: everything clickable POPS on hover, windows at scale 1.2, the build at rest in the
                         --    help strip (Arn, 6 Nov: "if you hover a row it should pop", "make 20% bigger", "a
                         --    finger print thing only you can see so you know what version i am on")

-- palette fallback: only when this file is embedded and neither BiSTheme.lua nor
-- Console.lua ran. Same table, same values, deliberately duplicated - a shared
-- local between two embedded files is a load-order bet, and this file may be the
-- only one of the pair an addon ships.
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
  function T.rgba(name, a) local r, g, b = T.rgb(name) return r, g, b, a or 1 end
  function T.text(name, s) return "|cff" .. (T.hex[name] or T.hex.ink) .. tostring(s) .. "|r" end
end

-- Console.lua owns Fit; define it here too for an addon that ships Options
-- without the prompt.
if not T.Fit then
  function T.Fit(fs, text, width)
    fs:SetText(text)
    if not width or not fs.GetStringWidth then return text end
    local t = text
    while fs:GetStringWidth() > width and #t > 1 do
      t = t:sub(1, -2)
      fs:SetText(t .. "...")
    end
    return fs:GetText()
  end
end

-- The shape, in one table so an addon can read the numbers a test wants to
-- assert rather than repeating them.
T.OPTIONS = {
  W       = 230,   -- a narrow window; the label budget below is what keeps it narrow
  ROW     = 16,
  HEADER  = 16,
  BOX     = 10,
  SEG_W   = 36,    -- "always" at 8 pt is ~29 px; 36 leaves the ellipsis unused
  STEP_W  = 18,
  STEP_V  = 40,    -- the value text between < and >
  BTN_W   = 60,
  HEAD_A  = 0.5,
  BODY_A  = 0.45,
  PAD     = 4,
  CTL     = 110,   -- pixels reserved on the right for any control
  INDENT  = 12,    -- an option label's x; a section name sits at 6
}

-- The layered near-blacks. Not in BiSTheme.hex because they are chrome, not
-- palette: the same five names BiSTools' Farm kit and Nebbinator's Kit use, with
-- the same values, so a window built here matches the windows around it.
local SHADE = {
  frame = "0d0b18", header = "141127", field = "17132e", hair = "2a2446", edge = "3a3260",
}

local function colour(name)
  local hex = SHADE[name]
  if hex then
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  end
  return T.rgb(name)
end

--------------------------------------------------------------------
-- primitives
--------------------------------------------------------------------

local P = {}

function P.tex(parent, layer, name, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  local r, g, b = colour(name)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

function P.fs(parent, text, size, name)
  local s = parent:CreateFontString(nil, "OVERLAY")
  if T.SetFont then T.SetFont(s, size or 8) else s:SetFont(STANDARD_TEXT_FONT, size or 8, "") end
  local r, g, b = colour(name or "ink")
  s:SetTextColor(r, g, b, 1)
  s:SetText(text or "")
  return s
end

function P.border(frame, name, a)
  local b = {}
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    local r, g, bl = colour(name)
    t:SetColorTexture(r, g, bl, a or 1)
    b[side] = t
  end
  b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(1)
  b.bottom:SetPoint("BOTTOMLEFT") b.bottom:SetPoint("BOTTOMRIGHT") b.bottom:SetHeight(1)
  b.left:SetPoint("TOPLEFT") b.left:SetPoint("BOTTOMLEFT") b.left:SetWidth(1)
  b.right:SetPoint("TOPRIGHT") b.right:SetPoint("BOTTOMRIGHT") b.right:SetWidth(1)
  -- The border remembers which colour name it is wearing. Four textures all
  -- holding the same three floats is not something a test can read back and
  -- name, and "assert on the paint, not the call" needs a name.
  b.name = name
  function b:set(n, alpha)
    local r, g, bl = colour(n)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
      self[side]:SetColorTexture(r, g, bl, alpha or 1)
    end
    self.name = n
  end
  return b
end

-- THE POP (minor 4; Arn, 6 Nov, asked four times across the family): anything clickable lights up clearly under the
-- mouse - a wash at GLOW, its edge in the accent, its label at full ink. A faint wash on the dark purple never showed.
T.OPTIONS.GLOW = T.OPTIONS.GLOW or 0.35
T.OPTIONS.SCALE = T.OPTIONS.SCALE or 1.2

-- a flat little button: field fill, edge border; under the mouse a wash, an accent edge, a bright label
function P.flat(parent, w, h, label, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  P.tex(b, "BACKGROUND", "field", 0.9)
  b.wash = P.tex(b, "BORDER", "accent", 0)
  b.edge = P.border(b, "edge", 1)
  b.label = P.fs(b, label or "", size or 8, "muted")
  b.label:SetPoint("CENTER")
  b:SetScript("OnEnter", function(s)
    s.wash:SetAlpha(T.OPTIONS.GLOW) s.edge:set(s.hoverEdge or "accent", 1)
    s.label:SetTextColor(colour("ink"))
  end)
  b:SetScript("OnLeave", function(s)
    s.wash:SetAlpha(0) s.edge:set("edge", 1)
    s.label:SetTextColor(colour(s.labelColour or "muted"))
  end)
  return b
end

-- the 10 px on/off box: filled accent when on, empty edge when off; under the mouse a wash and an accent edge
function P.box(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(T.OPTIONS.BOX, T.OPTIONS.BOX)
  b.fill = P.tex(b, "BACKGROUND", "accent", 1)
  b.wash = P.tex(b, "BORDER", "accent", 0)
  b.edge = P.border(b, "edge", 1)
  b:SetScript("OnEnter", function(s) s.wash:SetAlpha(T.OPTIONS.GLOW) s.edge:set("accent", 1) end)
  b:SetScript("OnLeave", function(s) s.wash:SetAlpha(0) s.edge:set(s.on and "accent" or "edge", 1) end)
  function b:Set(on)
    self.on = on and true or false
    if self.on then
      self.fill:Show()
      self.edge:set("accent", 1)
    else
      self.fill:Hide()
      self.edge:set("edge", 1)
    end
  end
  b:Set(false)
  return b
end

T.OptionsPrimitives = P   -- an adopter may want the flat button for its own footer

--------------------------------------------------------------------
-- the four control kinds, and no more
--------------------------------------------------------------------
-- If a setting does not fit one of these four it is a slash command. No
-- sliders (230 px has no room for a track, and a stepper is exact), no
-- free-text fields, no dropdowns.

local KINDS = {}

function KINDS.toggle(f, row, opt, db)
  local b = P.box(row)
  b:SetPoint("RIGHT", -6, 0)
  b:SetScript("OnClick", function()
    opt.set(db, not opt.get(db))
    f:Paint()
    f:Say(opt.label .. (opt.get(db) and " on" or " off"), opt.get(db) and "good" or "warn")
  end)
  row.ctl = b
  row.paint = function() b:Set(opt.get(db) and true or false) end
end

function KINDS.seg(f, row, opt, db)
  local O, segs = T.OPTIONS, {}
  for i, v in ipairs(opt.values) do
    local s = P.flat(row, O.SEG_W, 12, v)
    s:SetPoint("RIGHT", -6 - (#opt.values - i) * (O.SEG_W + 2), 0)
    T.Fit(s.label, v, O.SEG_W - 4)
    s:SetScript("OnClick", function()
      opt.set(db, v)
      f:Paint()
      f:Say(opt.label .. ": " .. v, "ink2")
    end)
    segs[i] = s
  end
  row.ctl = segs
  row.paint = function()
    local cur = opt.get(db)
    for i, s in ipairs(segs) do
      local on = opt.values[i] == cur
      s.edge:set(on and "accent" or "edge", 1)
      local r, g, b = colour(on and "accent" or "muted")
      s.label:SetTextColor(r, g, b, 1)
      -- hover must not leave the live one looking dead
      s:SetScript("OnLeave", function(x) x.edge:set(on and "accent" or "edge", 1) end)
    end
  end
end

function KINDS.step(f, row, opt, db)
  local O = T.OPTIONS
  local plus = P.flat(row, O.STEP_W, 12, ">")
  plus:SetPoint("RIGHT", -6, 0)
  local val = P.fs(row, "", 8, "ink2")
  val:SetPoint("RIGHT", plus, "LEFT", -4, 0)
  local minus = P.flat(row, O.STEP_W, 12, "<")
  minus:SetPoint("RIGHT", plus, "LEFT", -(O.STEP_V + 6), 0)

  -- THE STEPPER CLAMPS, not the setter. A setting whose own setter clamps is
  -- welcome to, but this must hold for one that does not - otherwise every
  -- adopter has to remember, and one of them will not.
  local function bump(dir)
    local v = tonumber(opt.get(db)) or opt.min
    v = v + dir * opt.step
    if v < opt.min then v = opt.min elseif v > opt.max then v = opt.max end
    opt.set(db, v)
    f:Paint()
    f:Say(opt.label .. ": " .. opt.show(db), "ink2")
  end
  plus:SetScript("OnClick", function() bump(1) end)
  minus:SetScript("OnClick", function() bump(-1) end)

  row.ctl = { minus = minus, plus = plus, val = val }
  row.paint = function() T.Fit(val, opt.show(db), O.STEP_V) end
end

function KINDS.button(f, row, opt, db)
  local O = T.OPTIONS
  local b = P.flat(row, O.BTN_W, 12, opt.button or "go")
  b:SetPoint("RIGHT", -6, 0)
  T.Fit(b.label, opt.button or "go", O.BTN_W - 4)
  b:SetScript("OnClick", function()
    opt.action(db)
    f:Paint()
    f:Say(opt.label, "ink2")
  end)
  row.ctl = b
  row.paint = function() end
end

T.OptionKinds = KINDS   -- so a test can count them, and fail when a fifth appears

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

local Opt = {}

--- Every change says itself in the prompt, never in the chat frame.
function Opt:Say(text, tone)
  if self.con then self.con:Say(text, tone) end
end

--- A section header: the addon's or tool's name, on the header shade. `box`
--- (optional) is a { get, set } pair - the thing this section switches on and off.
function Opt:Section(title, box)
  local O = T.OPTIONS
  local r = self:AddRow()
  r.isSection = true
  r.bg = P.tex(r, "BACKGROUND", "header", 0.6)
  r.name = P.fs(r, T.text("accent", title), 9, "ink")
  r.name:SetPoint("LEFT", 6, 0)
  T.Fit(r.name, T.text("accent", title), (self.colW or self.w) - 6 - O.CTL)
  if box then
    local b = P.box(r)
    b:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnClick", function()
      box.set(not box.get())
      self:Paint()
      if self.onChange then self.onChange() end
      self:Say(title .. (box.get() and " on" or " off"), box.get() and "good" or "warn")
    end)
    r.ctl = b
    r.paint = function() b:Set(box.get() and true or false) end
  end
  return r
end

--- One option row. `opt` is { kind, label, ... } per the four kinds above.
function Opt:Row(opt, db)
  local O = T.OPTIONS
  local build = KINDS[opt.kind]
  if not build then
    error("BiSTheme.Options: unknown control kind '" .. tostring(opt.kind) .. "' for '" ..
          tostring(opt.label) .. "'", 0)
  end
  local r = self:AddRow()
  r.opt = opt
  r.name = P.fs(r, opt.label, 8, "ink2")
  r.name:SetPoint("LEFT", O.INDENT, 0)
  -- Label budget: W - indent - control. Fit is the net, not the plan - pick
  -- plain words a raider understands and keep them under ~24 characters.
  T.Fit(r.name, opt.label, (self.colW or self.w) - O.INDENT - O.CTL)
  build(self, r, opt, db)
  return r
end

--- The next 16 px row down the body, full width. Section and Row build on it;
--- a caller wanting a list rather than an options list (BiSTools' Hub) asks for
--- a "Button" and decorates it itself.
function Opt:AddRow(frameType, name)
  local O = T.OPTIONS
  local r = CreateFrame(frameType or "Frame", name, self.body)
  r:SetHeight(O.ROW)
  r:SetPoint("TOPLEFT", 0, -self._y)
  r:SetPoint("TOPRIGHT", 0, -self._y)
  self._y = self._y + O.ROW
  self.rows[#self.rows + 1] = r
  return r
end

--- Size the window to the rows it ended up with: header + rows + a little pad.
--- `footH` is for a caller that pinned something to the bottom itself (the Hub's
--- `options` bar); an options window proper has no footer.
-- ---------------------------------------------------------------- the help strip
-- Arn, 14 Oct 2026, looking at the room the 1.43:1 shape leaves under the rows: "not sure how we ever
-- fill in that empty space" - "yes do the help strip". An options window keeps at least HELP_MIN at
-- the bottom, and whatever the shape adds goes there too. Hovering a setting (its name or any of its
-- controls) says what it does: the option's `help`, or its name alone when nobody wrote one yet. The
-- words stay until another setting is hovered - moving from a row onto its own button never blanks it.
T.OPTIONS.HELP_MIN = T.OPTIONS.HELP_MIN or 30
T.OPTIONS.HELP_IDLE = T.OPTIONS.HELP_IDLE or "hover a setting to see what it does"

--- Does this window hold settings (an options list), not just a list (the Hub)?
function Opt:HasHelp()
  for _, r in ipairs(self.rows) do if r.opt then return true end end
  return false
end

--- Say what a row does in the strip.
function Opt:Help(r)
  local hb = self.helpBox
  if not (hb and r) then return end
  local label = (r.opt and r.opt.label) or r.helpTitle or ""
  local words = r.help or (r.opt and r.opt.help)
  hb.title:SetText(T.text("accent", label))
  hb.text:SetText(words or T.text("muted", "(no notes on this one yet)"))
end

--- Hover a row, or anything on it, and the strip speaks.
function Opt:Hoverable(r)
  if r.hoverable then return end
  r.hoverable = true
  -- AND THE ROW POPS (minor 4): a wash and a bar on its left while the mouse is anywhere on it, its controls included
  r.lit = r.lit or P.tex(r, "BACKGROUND", "accent", 0)
  if not r.bar then
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(2)
    do local cr, cg, cb = colour("accent") r.bar:SetColorTexture(cr, cg, cb, 1) end
    r.bar:SetAlpha(0)
  end
  local function lit(on)
    r.lit:SetAlpha(on and T.OPTIONS.GLOW * 0.6 or 0)          -- a little softer than a button: text sits on it
    r.bar:SetAlpha(on and 1 or 0)
  end
  local function say() self:Help(r) lit(true) end
  local function left()
    -- moving from the row onto its own control is not leaving it
    local over = r.IsMouseOver and select(2, pcall(r.IsMouseOver, r))
    if over ~= true then lit(false) end
  end
  if r.EnableMouse then pcall(r.EnableMouse, r, true) end
  if r.HookScript then pcall(r.HookScript, r, "OnEnter", say) pcall(r.HookScript, r, "OnLeave", left) end
  if r.GetChildren then
    for _, c in ipairs({ r:GetChildren() }) do
      if c.HookScript then pcall(c.HookScript, c, "OnEnter", say) pcall(c.HookScript, c, "OnLeave", left) end
    end
  end
end

--- The strip itself, built once, laid along the body's bottom at `height`.
function Opt:HelpStrip(height)
  local O = T.OPTIONS
  local hb = self.helpBox
  if not hb then
    hb = CreateFrame("Frame", nil, self.body)
    P.tex(hb, "BACKGROUND", "sunken", 0.55)
    local hair = hb:CreateTexture(nil, "BORDER")
    hair:SetPoint("TOPLEFT") hair:SetPoint("TOPRIGHT") hair:SetHeight(1)
    do local r, g, b = colour("edge") hair:SetColorTexture(r, g, b, 1) end
    -- at rest the title line says the build, faint; hovering a setting puts its name there instead (one label)
    hb.title = P.fs(hb, self.fingerprint and T.text("dim", self.fingerprint) or "", 8, "ink")
    hb.title:SetPoint("TOPLEFT", 6, -4)
    hb.text = P.fs(hb, T.text("muted", O.HELP_IDLE), 8, "ink2")
    hb.text:SetPoint("TOPLEFT", hb.title, "BOTTOMLEFT", 0, -2)
    hb.text:SetPoint("RIGHT", hb, "RIGHT", -6, 0)
    if hb.text.SetJustifyH then hb.text:SetJustifyH("LEFT") end
    if hb.text.SetJustifyV then hb.text:SetJustifyV("TOP") end
    if hb.text.SetWordWrap then pcall(hb.text.SetWordWrap, hb.text, true) end
    self.helpBox = hb
  end
  hb:ClearAllPoints()
  hb:SetPoint("BOTTOMLEFT", self.body, "BOTTOMLEFT", 0, 0)
  hb:SetPoint("BOTTOMRIGHT", self.body, "BOTTOMRIGHT", 0, 0)
  hb:SetHeight(height)
  hb:Show()
  for _, r in ipairs(self.rows) do if r.opt or r.help then self:Hoverable(r) end end
end

function Opt:Fit(footH)
  local O = T.OPTIONS
  local help = self:HasHelp()
  local cols, tallest = self:Flow(footH)
  local rowsH = (cols > 1 and tallest or self._y)
  local body = math.max(rowsH + O.PAD + (help and O.HELP_MIN or 0), 1)
  -- THE BiSTheme STANDARD: every window exactly O.RATIO wide to high (Arn, 14 Oct: "that should be a
  -- bis theme standard 1.43:1 window size ... we can make them bigger to fit more but keeping that
  -- aspect ratio"). Too narrow: the columns widen. Too flat: the body grows, the room left below.
  local w, h = cols * self.colW, O.HEADER + body + (footH or 0)
  if w / h < O.RATIO then
    w = math.floor(h * O.RATIO + 0.5)
    local colW = w / cols
    if cols > 1 then
      for _, r in ipairs(self.rows) do
        local c = r.col or 1
        local _, _, _, _, y = r:GetPoint(1)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.body, "TOPLEFT", (c - 1) * colW, y or 0)
        r:SetWidth(colW)
      end
    end
  else
    h = math.floor(w / O.RATIO + 0.5)
    body = h - O.HEADER - (footH or 0)
  end
  self:SetWidth(w)
  self.body:SetHeight(body)
  self:SetHeight(h)
  -- the strip takes everything under the rows: its minimum, and whatever the shape added
  if help then self:HelpStrip(math.max(O.HELP_MIN, body - rowsH - O.PAD)) end
  self:Paint()
  return self
end

-- ---------------------------------------------------------------- the shape
-- Arn, 14 Oct 2026: "lets make our windows this aspect ratio 1.43:1". A window's sections are
-- poured into as many columns as bring it closest to T.OPTIONS.RATIO (width : height, compared as a
-- ratio of ratios, so 2.3 and 0.62 are judged fairly around 1.43). A section never splits across
-- columns, and the order is kept. One block (a list with no sections, BiSTools' Hub) stays one column.
T.OPTIONS.RATIO = T.OPTIONS.RATIO or 1.43

--- The rows in blocks: each section header starts one; rows before the first are a block too.
local function blocks(rows)
  local out, cur = {}, nil
  for _, r in ipairs(rows) do
    if r.isSection or not cur then cur = {} out[#out + 1] = cur end
    cur[#cur + 1] = r
  end
  return out
end

--- Blocks into n columns AS EVEN AS THEY CAN BE (Arn, 14 Oct: "it added empty space to get the
--- aspect ratio but did not move sections around ... the window be smaller ... no overly empty
--- space"): the biggest first, each into the shortest column; then any move or swap of a section
--- that shortens the tallest column, until none does. Inside a column the sections keep the order
--- they were written in, so it still reads top to bottom.
local function pour(bl, n, row)
  local items = {}
  for i, b in ipairs(bl) do items[#items + 1] = { i = i, b = b, h = #b * row } end
  table.sort(items, function(x, y) if x.h ~= y.h then return x.h > y.h end return x.i < y.i end)
  local cols = {}
  for c = 1, n do cols[c] = { h = 0, items = {} } end
  local function shortest()
    local s = cols[1]
    for _, c in ipairs(cols) do if c.h < s.h then s = c end end
    return s
  end
  for _, it in ipairs(items) do
    local c = shortest()
    c.items[#c.items + 1] = it
    c.h = c.h + it.h
  end
  -- better, while it gets better: a section out of the tallest column, or traded for a smaller one
  for _ = 1, 60 do
    local tall = cols[1]
    for _, c in ipairs(cols) do if c.h > tall.h then tall = c end end
    local done = false
    for ti, it in ipairs(tall.items) do
      for _, c in ipairs(cols) do
        if c ~= tall then
          if math.max(tall.h - it.h, c.h + it.h) < tall.h then             -- a move
            table.remove(tall.items, ti) c.items[#c.items + 1] = it
            tall.h, c.h = tall.h - it.h, c.h + it.h
            done = true
          else
            for oi, other in ipairs(c.items) do                            -- a swap
              local d = it.h - other.h
              if d > 0 and math.max(tall.h - d, c.h + d) < tall.h then
                tall.items[ti], c.items[oi] = other, it
                tall.h, c.h = tall.h - d, c.h + d
                done = true
                break
              end
            end
          end
        end
        if done then break end
      end
      if done then break end
    end
    if not done then break end
  end
  local out = {}
  for _, c in ipairs(cols) do
    if #c.items > 0 then
      table.sort(c.items, function(x, y) return x.i < y.i end)
      local col = { h = c.h, first = c.items[1].i }
      for _, it in ipairs(c.items) do col[#col + 1] = it.b end
      out[#out + 1] = col
    end
  end
  -- the column holding the first section goes first, and so on across
  table.sort(out, function(x, y) return x.first < y.first end)
  return out
end

T.PourColumns = pour            -- for the suite

--- How many columns, and how tall the tallest. Lays the rows out when more than one.
function Opt:Flow(footH)
  local O = T.OPTIONS
  local bl = blocks(self.rows)
  if #bl < 2 then return 1, self._y end
  local best, bestCols, bestScore
  for n = 1, math.min(#bl, 4) do
    local cols = pour(bl, n, O.ROW)
    local tall = 0
    for _, c in ipairs(cols) do tall = math.max(tall, c.h) end
    -- judged by the FINAL window: it is forced to O.RATIO anyway (Fit), so the best column count is
    -- the one that wastes the least room doing it - the smallest window that holds everything
    local w, h = #cols * self.colW, O.HEADER + tall + O.PAD + (footH or 0) + (self:HasHelp() and O.HELP_MIN or 0)
    local score = math.max(w, h * O.RATIO) * math.max(h, w / O.RATIO)
    if not bestScore or score < bestScore then best, bestCols, bestScore = #cols, cols, score end
  end
  local tallest = 0
  if best > 1 then
    for ci, c in ipairs(bestCols) do
      local y = 0
      for _, b in ipairs(c) do
        for _, r in ipairs(b) do
          r:ClearAllPoints()
          r:SetPoint("TOPLEFT", self.body, "TOPLEFT", (ci - 1) * self.colW, -y)
          r:SetWidth(self.colW)
          r.col = ci
          y = y + O.ROW
        end
      end
      tallest = math.max(tallest, y)
    end
    self:SetWidth(best * self.colW)
  end
  self.columns = best
  return best, tallest
end

function Opt:Paint()
  for _, r in ipairs(self.rows) do if r.paint then r.paint() end end
end

-- ---------------------------------------------------------------- not on top of each other
-- Arn, 14 Oct 2026, with BiS Tools' hub opened over BiS Healing's options: "can we make the option
-- smart enough if a window is open it does not open right on top of another one". Every window this
-- kit builds is listed in T.OPEN (T is the one global BiSTheme table, so every addon's windows share
-- the list - and the newest copy of this file builds all of them). Opening one that would cover an
-- open one moves it beside it: right, else left, else below - else where it was.
T.OPEN = T.OPEN or {}
T.DODGE_GAP = 8

--- Where a box should go so it covers none of `others`. Boxes are { l, b, r, t } in screen pixels;
--- answers the new left and top, or nil when it covers nothing (or nothing fits).
function T.DodgeRect(box, others, screenW, screenH)
  local function hits(a, o) return a[1] < o[3] and a[3] > o[1] and a[2] < o[4] and a[4] > o[2] end
  local function clear(a)
    if a[1] < 0 or a[2] < 0 or a[3] > screenW or a[4] > screenH then return false end
    for _, o in ipairs(others) do if hits(a, o) then return false end end
    return true
  end
  local covered
  for _, o in ipairs(others) do if hits(box, o) then covered = o break end end
  if not covered then return nil end
  local w, h, g = box[3] - box[1], box[4] - box[2], T.DODGE_GAP
  local tries = {}
  for _, o in ipairs(others) do
    tries[#tries + 1] = { o[3] + g, box[2], o[3] + g + w, box[4] }   -- right of it
    tries[#tries + 1] = { o[1] - g - w, box[2], o[1] - g, box[4] }   -- left of it
    tries[#tries + 1] = { box[1], o[2] - g - h, box[3], o[2] - g }   -- below it
  end
  for _, a in ipairs(tries) do if clear(a) then return a[1], a[4] end end
  return nil
end

--- A window about to open: off any other open BiS window. Rect reads are asked, never trusted - a
--- hidden or refused answer leaves the window where it was.
function Opt:Dodge()
  local function rect(f)
    local ok, l, b, w, h = pcall(f.GetRect, f)
    local okS, s = pcall(f.GetEffectiveScale, f)
    if not (ok and okS) then return nil end
    -- each asked by name: a frame not yet placed answers NOTHING, and ipairs stops at the first gap
    local function num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
    if not (num(l) and num(b) and num(w) and num(h) and num(s)) then return nil end
    return { l * s, b * s, (l + w) * s, (b + h) * s }
  end
  local mine = rect(self)
  if not mine then return false end
  local others = {}
  for f in pairs(T.OPEN) do
    if f ~= self and f:IsShown() then
      local r = rect(f)
      if r then others[#others + 1] = r end
    end
  end
  if #others == 0 then return false end
  local okU, sw, sh = pcall(function() return UIParent:GetWidth() * UIParent:GetEffectiveScale(),
    UIParent:GetHeight() * UIParent:GetEffectiveScale() end)
  if not okU then return false end
  local left, top = T.DodgeRect(mine, others, sw, sh)
  if not left then return false end
  local s = self:GetEffectiveScale()
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
  return true
end

function Opt:Toggle(want)
  if want == nil then want = not self:IsShown() end
  if want then self:Paint() self:Dodge() self:Show() else self:Hide() end
end

--- Drag the window back to the middle. "reset window position" wires to this.
function Opt:Recenter(y)
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "CENTER", 0, y or 60)
end

--- Build the frame. Returns it with Section / Row / Fit / Paint / Toggle on it.
-- ---------------------------------------------------------------- the fingerprint (minor 4)
-- Arn, 6 Nov: "a small version number on all the windows or a finger print thing only you can see so you know what
-- version i am on" (he had not reloaded and was ten builds behind). _bisdev/deploy.sh stamps the copy it puts in the
-- game with "## X-BiS-Build: <branch>@<commit> <MMDD-HHMM>"; a released zip has none. The window's addon is read from
-- its own name ("BiSGambaOptions" -> BiSGamba), so no caller has to say it.
local function meta(addon, key)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if type(get) ~= "function" or type(addon) ~= "string" then return nil end
  local ok, v = pcall(get, addon, key)
  if ok and type(v) == "string" and v ~= "" then return v end
  return nil
end

--- The addon a frame name belongs to: the name, then shorter by one CamelCase word, until one has a Version.
function T.AddonOf(name)
  local s = type(name) == "string" and name or nil
  while s and #s > 0 do
    if meta(s, "Version") then return s end
    local shorter = s:match("^(.+)%u[%l%d]*$")
    if not shorter or shorter == s then return nil end
    s = shorter
  end
  return nil
end

--- "BiSGamba 1.9.2" - and on a deployed test build "BiSGamba 1.9.2  9e52109 1106-1841". nil for an unknown addon.
function T.Fingerprint(addon)
  local v = meta(addon, "Version")
  if not v then return nil end
  local b = meta(addon, "X-BiS-Build")
  local sha = b and b:match("@(%S+)")
  local when = b and b:match("(%S+)$")
  return addon .. " " .. v .. (sha and ("  " .. sha .. " " .. (when or "")) or "")
end

function T.Options(name, w, title)
  local O = T.OPTIONS
  w = w or O.W
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, O.HEADER)
  if f.SetScale then f:SetScale(O.SCALE) end                   -- readable (Arn: "its so small cant read"); a caller
                                                                -- may set its own after (BiS Healing's 1.25)
  f.addon = T.AddonOf(name)
  f.fingerprint = T.Fingerprint(f.addon)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  P.tex(f, "BACKGROUND", "frame", O.BODY_A)
  P.border(f, "edge", 0.35)

  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT")
  head:SetHeight(O.HEADER)
  P.tex(head, "BACKGROUND", "header", O.HEAD_A)
  local hair = head:CreateTexture(nil, "BORDER")
  hair:SetPoint("BOTTOMLEFT") hair:SetPoint("BOTTOMRIGHT") hair:SetHeight(1)
  do local r, g, b = colour("edge") hair:SetColorTexture(r, g, b, 1) end

  -- Header budget, per the header law: 4 + prompt (<= w - 15 - 8) on the left,
  -- one 12 px x at -3 on the right. Nothing else goes in a 16 px bar.
  local fs = P.fs(head, "", 8, "ink")
  fs:SetPoint("LEFT", head, "LEFT", 4, 0)
  if T.Console then
    f.con = T.Console(fs, { width = w - 15 - 8 })
    f.con:Set("name", title or "Options", "accent")
  else
    T.Fit(fs, T.text("accent", title or "Options"), w - 15 - 8)
  end
  f.title = fs

  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local close = P.flat(head, 12, 12, "x")
  close:SetPoint("RIGHT", head, "RIGHT", -3, 0)
  do local r, g, b = colour("warn") close.label:SetTextColor(r, g, b, 1) end
  close.labelColour, close.hoverEdge = "warn", "warn"            -- it pops like every button, in the warning colour
  close:SetScript("OnClick", function() f:Hide() end)
  f.closeBtn = close

  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
  body:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
  body:SetHeight(1)

  f.head, f.body, f.rows, f.w, f._y = head, body, {}, w, 0
  f.colW = w            -- the column width, apart from f.w: a frame mock may keep its own width in .w
  for k, v in pairs(Opt) do f[k] = v end
  T.OPEN[f] = true

  -- A new frame is shown by default and the toggle is what decides. The harness
  -- caught this on the Hub's first day.
  f:Hide()

  -- Escape closes it, like every Blizzard panel (Arn, 10 Sep: "if you press esc
  -- it should close that option window" - on every BiS addon). The client
  -- closes the newest shown frame in UISpecialFrames on Escape; a name is
  -- required, and T.Options always has one.
  if name and UISpecialFrames then
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == name then listed = true end end
    if not listed then table.insert(UISpecialFrames, name) end
  end

  -- AND IF THE LOOK CHANGES UNDER IT. A window built before the user moved EllesmereUI's accent
  -- slider has the old colour baked into its textures; Paint() re-reads the palette for every row.
  if T.RegisterLooks then
    T.RegisterLooks(function() if f:IsShown() then f:Paint() end end)
  end

  if f.con then
    f:SetScript("OnUpdate", function(_, dt)
      f.elapsed = (f.elapsed or 0) + dt
      if f.elapsed >= 0.1 then f.elapsed = 0 f.con:Paint() end
    end)
  end
  return f
end
