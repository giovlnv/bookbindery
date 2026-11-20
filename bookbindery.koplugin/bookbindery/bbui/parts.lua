--[[--
Small widgets shared by the list screens: text, spans, chips, number discs,
progress bars, section labels and the top bar with its back button.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local theme = require("bookbindery/bbui/theme")

local P = {}

P.ICONS = debug.getinfo(1, "S").source:match("^@(.*)/bookbindery/bbui/[^/]+$") .. "/icons/"

function P.px(n)
    return Screen:scaleBySize(n)
end

local px = P.px

function P.text(s, role, size, color, max_width, height)
    return TextWidget:new({ text = s or "", face = theme.face(role, size), fgcolor = color or theme.ink,
        max_width = max_width, forced_height = height and px(height) })
end

function P.vspan(n)
    return VerticalSpan:new({ width = n })
end

function P.hspan(n)
    return HorizontalSpan:new({ width = n })
end

function P.box(w, h, color, radius)
    return FrameContainer:new({ bordersize = 0, padding = 0, background = color, radius = radius,
        Widget:new({ dimen = Geom:new({ w = w, h = h }) }) })
end

function P.bar(w, fraction)
    local h = px(6)
    local fill = math.max(h, math.floor(w * math.min(fraction or 0, 1)))
    return OverlapGroup:new({ dimen = Geom:new({ w = w, h = h }),
        P.box(w, h, theme.track, h / 2), P.box(fill, h, theme.ink, h / 2) })
end

function P.icon(name, size, invert)
    return ImageWidget:new({ file = P.ICONS .. name .. ".svg", width = px(size), height = px(size),
        is_icon = true, invert = invert })
end

-- text box of at most max_lines lines; with fixed = true it is always max_lines tall
function P.lines(s, role, size, w, max_lines, color, fixed, line_height, bgcolor)
    local opts = { text = s or "", face = theme.face(role, size), fgcolor = color or theme.ink, width = w,
        line_height = line_height or 0, bgcolor = bgcolor }
    local t = TextBoxWidget:new(opts)
    local line_h = t:getLineHeight()
    if fixed or t:getSize().h > line_h * max_lines then
        t:free()
        opts.height = math.ceil(line_h * max_lines)
        opts.height_overflow_show_ellipsis = true
        t = TextBoxWidget:new(opts)
    end
    return t
end

-- section label: small caps-like, secondary
function P.label(s, w)
    return P.text((s or ""):upper(), "label", 12, theme.secondary, w)
end

-- left and right widgets on one line, bottoms aligned to the baseline of left
function P.spread(w, left, right)
    local h = math.max(left:getSize().h, right and right:getSize().h or 0)
    local dimen = Geom:new({ w = w, h = h })
    local g = OverlapGroup:new({ dimen = dimen, LeftContainer:new({ dimen = dimen:copy(), left }) })
    if right then
        table.insert(g, RightContainer:new({ dimen = dimen:copy(), right }))
    end
    return g
end

function P.link(s)
    local t = P.text(s, "small", 13)
    return VerticalGroup:new({ t, LineWidget:new({ background = theme.ink,
        dimen = Geom:new({ w = t:getSize().w, h = theme.line }) }) })
end

local Hit = InputContainer:extend({ callback = nil, hold_callback = nil })

function Hit:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new({ x = 0, y = 0, w = size.w, h = size.h })
    local range = function() return self.dimen end
    self.ges_events = { TapBbPart = { GestureRange:new({ ges = "tap", range = range }) } }
    if self.hold_callback then
        self.ges_events.HoldBbPart = { GestureRange:new({ ges = "hold", range = range }) }
    end
end

function Hit:onTapBbPart()
    if self.callback then
        self.callback()
    end
    return true
end

-- the event passes through nested Hits first: only one with a hold_callback takes it
function Hit:onHoldBbPart()
    if not self.hold_callback then
        return false
    end
    self.hold_callback()
    return true
end

P.Hit = Hit

function P.hit(widget, callback)
    return Hit:new({ callback = callback, widget })
end

P.MENU_W = px(44)

-- KOReader's menu, top right of every screen
function P.menu_button(callback, h)
    return P.hit(CenterContainer:new({ dimen = Geom:new({ w = P.MENU_W, h = h or px(44) }), P.icon("menu", 24) }),
        callback)
end

function P.chip(s, on, callback)
    local t = P.text(s, on and "label" or "small", 13, on and theme.white or theme.ink)
    local chip = FrameContainer:new({
        bordersize = theme.border, color = theme.ink, background = on and theme.ink or theme.white,
        radius = px(14), padding = 0, padding_left = px(12), padding_right = px(12),
        padding_top = px(4), padding_bottom = px(4),
        t,
    })
    return callback and P.hit(chip, callback) or chip
end

function P.chips(list, gap)
    local g = HorizontalGroup:new({ align = "center" })
    for i, c in ipairs(list) do
        if i > 1 then
            table.insert(g, P.hspan(gap or px(8)))
        end
        table.insert(g, c)
    end
    return g
end

-- 48 px button: black (primary) or outlined
function P.button(label, w, primary, callback)
    local h = px(48)
    local text = TextBoxWidget:new({ text = label, face = theme.face(primary and "name" or "button", 16),
        fgcolor = primary and theme.white or theme.ink, bgcolor = primary and theme.ink or theme.white,
        width = w - px(16), alignment = "center", line_height = 0 })
    return P.hit(FrameContainer:new({
        bordersize = theme.border, color = theme.ink, background = primary and theme.ink or theme.white,
        radius = theme.radius, padding = 0,
        CenterContainer:new({ dimen = Geom:new({ w = w - 2 * theme.border, h = h - 2 * theme.border }), text }),
    }), callback)
end

-- 28 px number disc: filled (black), dashed, with a number, "now" or a check
local Disc = Widget:extend({ size = nil, filled = false, dashed = false, mark = "" })

function Disc:init()
    self.size = self.size or px(28)
    local fg = self.filled and theme.white or theme.ink
    if self.mark == "check" then
        self.inner = P.icon("check", 18, self.filled)
    elseif self.mark == "now" then
        self.inner = P.text("now", "label", 11, fg)
    else
        self.inner = P.text(self.mark, self.filled and "number" or "small", 13, fg)
    end
end

function Disc:getSize()
    return Geom:new({ w = self.size, h = self.size })
end

function Disc:paintTo(bb, x, y)
    local r = math.floor(self.size / 2)
    local cx, cy = x + r, y + r
    local bw = math.max(1, math.floor(theme.border + 0.5))
    if self.filled then
        bb:paintCircle(cx, cy, r, theme.ink)
    else
        bb:paintCircle(cx, cy, r, theme.ink, bw)
    end
    if self.dashed then
        local g = math.max(2, px(3))
        for i = 0, 11 do
            local a = math.rad(i * 30 + 15)
            local gx = cx + (r - bw / 2) * math.sin(a)
            local gy = cy - (r - bw / 2) * math.cos(a)
            bb:paintRect(math.floor(gx - g / 2), math.floor(gy - g / 2), g, g, theme.white)
        end
    end
    local s = self.inner:getSize()
    self.inner:paintTo(bb, x + math.floor((self.size - s.w) / 2), y + math.floor((self.size - s.h) / 2))
end

function Disc:free()
    self.inner:free()
end

P.Disc = Disc

-- 56 px bar with a back chevron and a title (both go back), optional right text and menu button
function P.topbar(title, right, on_back, on_menu)
    local w = Screen:getWidth()
    local h = px(56) - theme.border
    local left = P.hit(HorizontalGroup:new({ align = "center",
        P.hspan(px(16)),
        FrameContainer:new({ bordersize = 0, padding = px(10), P.icon("back", 24) }),
        P.hspan(px(8)),
        P.text(title, "button", 15),
        P.hspan(px(24)),
    }), on_back)
    local dimen = Geom:new({ w = w, h = h })
    local row = OverlapGroup:new({ dimen = dimen, LeftContainer:new({ dimen = dimen:copy(), left }) })
    local g = HorizontalGroup:new({ align = "center" })
    if right then
        table.insert(g, P.text(right, "small", 13, theme.secondary))
        table.insert(g, P.hspan(on_menu and px(4) or px(16)))
    end
    if on_menu then
        table.insert(g, P.menu_button(on_menu))
        table.insert(g, P.hspan(px(6)))
    end
    if #g > 0 then
        table.insert(row, RightContainer:new({ dimen = dimen:copy(), g }))
    end
    return VerticalGroup:new({ row, LineWidget:new({ background = theme.ink,
        dimen = Geom:new({ w = w, h = theme.border }) }) })
end

-- serif title with a soft count after it, as "fiction 175"
function P.title(s, count)
    local t = P.text(s, "title")
    if not count then
        return t
    end
    local c = P.text(" " .. count, "title", 20, theme.secondary)
    return HorizontalGroup:new({ align = "top", t,
        VerticalGroup:new({ P.vspan(t:getBaseline() - c:getBaseline()), c }) })
end

return P
