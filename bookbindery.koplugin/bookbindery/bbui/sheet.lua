--[[--
Bottom sheet over the current screen: a white panel with a rounded top rule,
a title and a note, check rows (disc, label, note on the right) and one
outlined button. Tap outside or Back closes it; more rows than fit page with
a swipe or a tap on the pager. rows: { label, note, checked, callback }, or action rows
{ action = true, label, note, callback } (no disc; greyed without a callback).
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")
local Screen = Device.screen

local px = P.px

local Sheet = InputContainer:extend({
    title = "",
    note = nil,
    rows = nil,
    button = nil,
    close_callback = nil,
    covers_fullscreen = false,
})

local ROW_H = 60
local PAD = 24
local TOP_GAP = 120

function Sheet:init()
    self.dimen = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
    self.page = 1
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.ges_events = {
        TapSheet = { GestureRange:new({ ges = "tap", range = self.dimen }) },
        SwipeSheet = { GestureRange:new({ ges = "swipe", range = self.dimen }) },
    }
    self:build()
end

function Sheet:row(r, w)
    local note = r.note and P.text(r.note, "small", 13, theme.secondary)
    local label_w = w - (r.action and 0 or px(44)) - (note and note:getSize().w + px(16) or 0)
    local line
    if r.action then
        line = P.text(r.label, "item", 17, r.callback and theme.ink or theme.secondary, label_w)
    else
        line = HorizontalGroup:new({ align = "center",
            P.Disc:new({ filled = r.checked, mark = r.checked and "check" or "" }),
            P.hspan(px(16)),
            P.text(r.label, r.checked and "name" or "item", 17, theme.ink, label_w),
        })
    end
    return P.hit(VerticalGroup:new({ align = "left",
        CenterContainer:new({ dimen = Geom:new({ w = w, h = px(ROW_H) - theme.line }), P.spread(w, line, note) }),
        LineWidget:new({ background = theme.rule, dimen = Geom:new({ w = w, h = theme.line }) }),
    }), r.callback)
end

function Sheet:buttonWidget(w)
    local h = px(48)
    local label = TextBoxWidget:new({ text = self.button.label, face = theme.face("button", 16),
        fgcolor = theme.ink, width = w - px(16), alignment = "center", line_height = 0 })
    return P.hit(FrameContainer:new({
        bordersize = theme.border, color = theme.ink, background = theme.white, radius = theme.radius, padding = 0,
        CenterContainer:new({ dimen = Geom:new({ w = w - 2 * theme.border, h = h - 2 * theme.border }), label }),
    }), self.button.callback)
end

function Sheet:build()
    local w = self.dimen.w - 2 * px(PAD)
    local head = VerticalGroup:new({ align = "left", P.text(self.title, "title", 22, theme.ink, w) })
    if self.note then
        table.insert(head, P.vspan(px(8)))
        table.insert(head, P.lines(self.note, "small", 13, w, 3, theme.secondary, false, 0.3))
    end
    local button = self.button and self:buttonWidget(w)
    local pager_h = P.text("1", "small", 13):getSize().h + px(12)
    local avail = self.dimen.h - px(TOP_GAP) - 2 * px(PAD) - head:getSize().h - px(8)
        - (button and button:getSize().h + px(20) or 0)
    local rows = self.rows or {}
    local per = math.max(1, math.floor(avail / px(ROW_H)))
    if #rows > per then
        per = math.max(1, math.floor((avail - pager_h) / px(ROW_H)))
    end
    self.pages = math.max(1, math.ceil(#rows / per))
    self.page = math.min(self.page, self.pages)
    local g = VerticalGroup:new({ align = "left", head, P.vspan(px(8)) })
    for i = (self.page - 1) * per + 1, math.min(#rows, self.page * per) do
        table.insert(g, self:row(rows[i], w))
    end
    if self.pages > 1 then
        table.insert(g, P.hit(P.spread(w, P.text("page " .. self.page .. " of " .. self.pages, "small", 13,
            theme.secondary), P.text("more ›", "small", 13)), function() self:turn(1, true) end))
        g[#g] = FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(12), g[#g] })
    end
    if button then
        table.insert(g, P.vspan(px(20)))
        table.insert(g, button)
    end
    self[1] = FrameContainer:new({
        bordersize = theme.line, color = theme.ink, background = theme.white,
        radius = theme.radius * 1.5, padding = px(PAD), width = self.dimen.w, g,
    })
    self.panel = Geom:new({ x = 0, y = self.dimen.h - self[1]:getSize().h, w = self.dimen.w,
        h = self[1]:getSize().h })
end

-- the panel sits on the bottom edge: its bottom corners and rule are painted over square
function Sheet:paintTo(bb, x, y)
    local p = self.panel
    self[1]:paintTo(bb, x, y + p.y)
    local r = math.ceil(theme.radius * 1.5)
    local bottom = y + p.y + p.h - r
    bb:paintRect(x, bottom, p.w, r, theme.white)
    bb:paintRect(x, bottom, theme.line, r, theme.ink)
    bb:paintRect(x + p.w - theme.line, bottom, theme.line, r, theme.ink)
end

function Sheet:refresh(rows)
    local old = self.panel
    self.rows = rows or self.rows
    self:build()
    local top = math.min(old.y, self.panel.y)
    UIManager:setDirty("all", "ui", Geom:new({ x = 0, y = top, w = self.dimen.w, h = self.dimen.h - top }))
end

function Sheet:turn(step, wrap)
    local page = self.page + step
    if wrap and page > self.pages then
        page = 1
    end
    if page >= 1 and page <= self.pages and page ~= self.page then
        self.page = page
        self:refresh()
    end
end

function Sheet:onTapSheet(arg, ges)
    if not ges.pos:intersectWith(self.panel) then
        self:onClose()
    end
    return true
end

function Sheet:onSwipeSheet(arg, ges)
    if ges.direction == "west" then
        self:turn(1)
    elseif ges.direction == "east" then
        self:turn(-1)
    end
    return true
end

function Sheet:onShow()
    UIManager:setDirty(self, "ui", self.panel)
    return true
end

function Sheet:onClose()
    UIManager:close(self, "ui", self.panel)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return Sheet
