-- BiS Guild - Core/Recruits.lua
-- RECRUITS (Arn, 21 Oct 2026: "add potential recruits and people contacted to the BiS guild in a list so
-- officers can see and maybe officers can tell what we need"): the terminal's tab over BiS> Nebbinator's
-- guild book, read through NebbinatorAPI (version 2) - nothing here is kept or sent by BiS Guild itself.
--   WHAT WE NEED   everyone: the needs an officer last sent, and who sent them; an officer's button opens
--                  Nebbinator's Team page, where the needs are set and sent
--   RECRUITS       officers: the guild's list - who, how far, who is talking to them, when, the note
--                  (Arn's pick: a summary, never what a recruit whispered)
--   WHAT WORKS     officers: which channel brings whispers
-- Without Nebbinator, a greyed line says what would be here (playbook 5b).

local _, ns = ...
local K = ns.K

local R = {}
ns.Recruits = R

R.ADDON = "BiS> Nebbinator"

--- Nebbinator's API when it is there and new enough (version 2: the guild's), else nil and why.
function R.API()
    local api = _G.NebbinatorAPI
    if type(api) ~= "table" or api.major ~= 1 then return nil, "missing" end
    if (tonumber(api.version) or 0) < 2 or type(api.Team) ~= "function" then return nil, "old" end
    local ok, ready = pcall(api.Ready)
    if not (ok and ready) then return nil, "not ready" end
    return api
end

local function Ago(at)
    local now = (GetServerTime and GetServerTime()) or time()
    local d = math.max(0, now - (tonumber(at) or now))
    if d < 3600 then return math.floor(d / 60) .. " min" end
    if d < 86400 then return math.floor(d / 3600) .. " h" end
    return math.floor(d / 86400) .. " d"
end

function K.BuildRecruits(page, bodyH)
    local ui = K.ui
    local leftW = 330
    page.needs = ui.Panel(page, "WHAT WE NEED", 8, 0, leftW, 250)
    page.needLines = {}
    for i = 1, 11 do
        local l = ui.Text(page.needs, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 18)
        l:SetWidth(leftW - 16)
        page.needLines[i] = l
    end
    page.needsBy = ui.Text(page.needs, 11, "muted")
    page.needsBy:SetPoint("BOTTOMLEFT", 8, 8)
    page.needsBy:SetWidth(leftW - 16)
    -- an officer's way to the setting: Nebbinator's Team page (the API never sends to the guild itself)
    local set = CreateFrame("Button", nil, page.needs)
    set:SetPoint("TOPRIGHT", -2, -1)
    set:SetSize(90, 16)
    local bg = set:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ui.Fill(bg, "sunken")
    local hi = K.Pop(set)
    set.fs = ui.Text(set, 11, "gold", "CENTER")
    set.fs:SetPoint("CENTER", 0, 0)
    set.fs:SetText("SET THEM")
    set:SetScript("OnClick", function()
        local api = R.API()
        if api then pcall(api.Open, "Team") end
    end)
    page.setNeeds = set

    page.works = ui.Panel(page, "WHAT WORKS", 8, 256, leftW, bodyH - 260)
    page.workLines = {}
    for i = 1, 8 do
        local l = ui.Text(page.works, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 18)
        l:SetWidth(leftW - 16)
        page.workLines[i] = l
    end

    page.list = ui.Panel(page, "RECRUITS", leftW + 16, 0, K.W - leftW - 24, bodyH - 4)
    page.grid = ui.Grid(page.list, { "NAME", "STATUS", "TALKING", "WHEN", "NOTE" },
        { { 140, "LEFT" }, { 70, "LEFT" }, { 90, "LEFT" }, { 50, "RIGHT" }, { 100, "LEFT" } }, K.LIST_ROWS, 22,
        function() end)
    page.hint = ui.Text(page.list, 12, "muted")
    page.hint:SetPoint("TOPLEFT", 10, -40)
    page.hint:SetWidth(K.W - leftW - 44)
    if page.hint.SetWordWrap then page.hint:SetWordWrap(true) end
    return page
end

function K.PaintRecruits(p)
    local ui = K.ui
    local api, why = R.API()
    local officer = ns.X and ns.X.IsOfficer and ns.X.IsOfficer(ns.X.Me()) or false
    for _, l in ipairs(p.needLines) do l:SetText("") end
    for _, l in ipairs(p.workLines) do l:SetText("") end
    if not api then
        -- the greyed hint: what would be here, and which addon brings it
        p.needLines[1]:SetText(why == "old" and ("Update " .. R.ADDON .. " - this needs its newer copy")
            or (R.ADDON .. " keeps the guild's recruits"))
        p.needLines[1]:SetTextColor(ui.rgb("muted"))
        p.needsBy:SetText(why == "not ready" and "it is still loading" or "install it and they show here")
        p.setNeeds:Hide()
        p.list.right:SetText("")
        p.hint:SetText("Who the guild is talking to, how far along, and who is talking to them - from "
            .. R.ADDON .. ".")
        p.hint:Show()
        ui.Scroll(p.grid, 0)
        for _, row in ipairs(p.grid.rows) do ui.SetRow(row, nil, {}) end
        return
    end

    local needs = api.Needs() or { list = {} }
    local colours = _G.RAID_CLASS_COLORS
    if #needs.list == 0 then
        p.needLines[1]:SetText("nothing - the guild needs nobody right now")
        p.needLines[1]:SetTextColor(ui.rgb("muted"))
    end
    for i, n in ipairs(needs.list) do
        local l = p.needLines[i]
        if not l then break end
        local cc = colours and colours[n.classFile]
        l:SetText(("%d  %s %s"):format(n.count, n.spec, n.class))
        if cc then l:SetTextColor(cc.r, cc.g, cc.b) else l:SetTextColor(ui.rgb("ink")) end
    end
    p.needsBy:SetText(needs.by and ("set by %s, %s ago"):format(needs.by, Ago(needs.at))
        or "no officer has sent the guild any yet")
    if officer then p.setNeeds:Show() else p.setNeeds:Hide() end

    if not officer then
        p.list.right:SetText("")
        p.hint:SetText("Officers see the guild's recruits here: who, how far along, who is talking to them.")
        p.hint:Show()
        ui.Scroll(p.grid, 0)
        for _, row in ipairs(p.grid.rows) do ui.SetRow(row, nil, {}) end
        p.workLines[1]:SetText("officers see this")
        p.workLines[1]:SetTextColor(ui.rgb("muted"))
        return
    end

    local st = api.Stats()
    if st and st.posts > 0 then
        p.workLines[1]:SetText(("%d posts brought %d whispers"):format(st.posts, st.whispers))
        p.workLines[1]:SetTextColor(ui.rgb("ink2"))
        for i, w in ipairs(st.where) do
            local l = p.workLines[i + 1]
            if not l then break end
            l:SetText(("%s  %d / %d"):format(w.key, w.whispers, w.posts))
            l:SetTextColor(ui.rgb(i == 1 and "good" or "ink"))
        end
    else
        p.workLines[1]:SetText("no posts from this client yet")
        p.workLines[1]:SetTextColor(ui.rgb("muted"))
    end

    local team = api.Team() or {}
    if #team == 0 then
        p.hint:SetText("Nobody yet. Every whisper an officer or raider with " .. R.ADDON
            .. " answers shows up here.")
        p.hint:Show()
    else
        p.hint:Hide()
    end
    p.list.right:SetText(#team == 0 and "" or (#team .. " on the list" .. ui.Showing(p.grid)))
    local off = ui.Scroll(p.grid, #team)
    local TONE = { new = "gold", contacted = "slate", invited = "accent", trial = "accent", accepted = "good", declined = "warn" }
    for i, row in ipairs(p.grid.rows) do
        local r = team[i + off]
        if r then
            local cc = r.class and colours and colours[r.class]
            ui.SetRow(row, r.name, { r.name, r.status, r.by or "", Ago(r.at), r.note or "" },
                { cc and { cc.r, cc.g, cc.b } or "ink", TONE[r.status] or "ink2", "ink2", "muted", "muted" })
            row.who = r.name
        else
            ui.SetRow(row, nil, {})
        end
    end
end
