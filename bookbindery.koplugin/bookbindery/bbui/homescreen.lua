--[[--
Home: clock and date, the current book, the next one, and a fanfic tile when
there's a fanfic folder (its fandoms counted). The clock redraws once a minute
while home is on top.
]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local T = require("ffi/util").template
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Widget = require("ui/widget/widget")
local Cover = require("bookbindery/bbui/cover")
local HomeText = require("bookbindery/hometext")
local P = require("bookbindery/bbui/parts")
local TabBar = require("bookbindery/bbui/tabbar")
local theme = require("bookbindery/bbui/theme")
local Screen = Device.screen

local function px(n)
    return Screen:scaleBySize(n)
end

local function text(s, role, size, color, max_width, height)
    return TextWidget:new({ text = s or "", face = theme.face(role, size), fgcolor = color or theme.ink,
        max_width = max_width, forced_height = height and Screen:scaleBySize(height) })
end

local function vspan(n)
    return VerticalSpan:new({ width = n })
end

local function hspan(n)
    return HorizontalSpan:new({ width = n })
end

local function box(w, h, color, radius)
    return FrameContainer:new({ bordersize = 0, padding = 0, background = color, radius = radius,
        Widget:new({ dimen = Geom:new({ w = w, h = h }) }) })
end

local function bar(w, fraction)
    local h = px(6)
    local fill = math.max(h, math.floor(w * math.min(fraction or 0, 1)))
    return OverlapGroup:new({ dimen = Geom:new({ w = w, h = h }),
        box(w, h, theme.track, h / 2), box(fill, h, theme.ink, h / 2) })
end

local function lines(s, role, size, w, max_lines)
    local opts = { text = s or "", face = theme.face(role, size), fgcolor = theme.ink, width = w, line_height = 0 }
    local t = TextBoxWidget:new(opts)
    local line_h = t:getLineHeight()
    if t:getSize().h > line_h * max_lines then
        t:free()
        opts.height = line_h * max_lines
        opts.height_overflow_show_ellipsis = true
        t = TextBoxWidget:new(opts)
    end
    return t
end

local Hit = InputContainer:extend({ callback = nil, hold_callback = nil })

function Hit:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new({ x = 0, y = 0, w = size.w, h = size.h })
    local range = function() return self.dimen end
    self.ges_events = { TapHomeHit = { GestureRange:new({ ges = "tap", range = range }) } }
    if self.hold_callback then
        self.ges_events.HoldHomeHit = { GestureRange:new({ ges = "hold", range = range }) }
    end
end

function Hit:onTapHomeHit()
    if self.callback then
        self.callback()
    end
    return true
end

-- the event passes through nested Hits first: only one with a hold_callback takes it
function Hit:onHoldHomeHit()
    if not self.hold_callback then
        return false
    end
    self.hold_callback()
    return true
end

-- tap target taller than its line (4 px above and 12 px below), for e-ink fingers
-- own event name: the outer tile's Hit would otherwise pass its tap on to this one
local TallHit = InputContainer:extend({ callback = nil, width = nil })

function TallHit:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new({ x = 0, y = 0, w = size.w, h = size.h })
    self.ges_events = { TapHomeTall = { GestureRange:new({ ges = "tap", range = function() return self.dimen end }) } }
end

function TallHit:onTapHomeTall()
    self.callback()
    return true
end

function TallHit:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    local above, below = px(4), px(12)
    self.dimen = Geom:new({ x = x, y = y - above, w = self.width, h = self[1]:getSize().h + above + below })
end

local Clock = Widget:extend({ size = nil, time = nil })

function Clock:getSize()
    return Geom:new({ w = self.size, h = self.size })
end

local function hand(bb, cx, cy, length, deg, width)
    local w = math.max(1, math.floor(width + 0.5))
    for i = 0, math.ceil(length * 2) do
        local x, y = HomeText.hand(cx, cy, i / 2, deg)
        bb:paintRect(math.floor(x - w / 2 + 0.5), math.floor(y - w / 2 + 0.5), w, w, theme.ink)
    end
end

function Clock:paintTo(bb, x, y)
    self.dimen = Geom:new({ x = x, y = y, w = self.size, h = self.size })
    local s = self.size / 56
    local cx, cy = x + math.floor(self.size / 2), y + math.floor(self.size / 2)
    bb:paintCircle(cx, cy, math.floor(27 * s), theme.ink, math.max(1, math.floor(2 * s + 0.5)))
    local t = os.date("*t", self.time)
    local hour, min = HomeText.clock(t.hour, t.min)
    hand(bb, cx, cy, 13 * s, hour, 3 * s)
    hand(bb, cx, cy, 19 * s, min, 2 * s)
    bb:paintCircle(cx, cy, math.max(1, math.floor(2.5 * s + 0.5)), theme.ink)
end

local HomeScreen = InputContainer:extend({
    model = nil,
    books_root = "",
    days = nil,
    fandoms = nil,
    on_open = nil,
    on_tab = nil,
    on_fanfic = nil,
    on_menu = nil,
    on_info = nil,
    on_missing = nil,
    on_close = nil,
    covers_fullscreen = true,
})

function HomeScreen:init()
    self.dimen = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
    if Device:hasKeys() then
        self.key_events = { Stay = { { Device.input.group.Back } } }
    end
    self.ges_events = { SwipeMenu = { GestureRange:new({ ges = "swipe", range = Geom:new({
        x = 0, y = 0, w = self.dimen.w, h = math.floor(self.dimen.h / 8) }) }) } }
    self.tick_fn = function() self:tick() end
    self:build()
end

function HomeScreen:open(file, missing)
    return function()
        if (file or missing) and self.on_open then
            self.on_open(file, missing)
        end
    end
end

-- holding a book shows its info; only books calibre knows (not articles)
function HomeScreen:info(book)
    if book and self.on_info then
        return function() self.on_info(book) end
    end
end

function HomeScreen:onSwipeMenu(arg, ges)
    if ges.direction == "south" and self.on_menu then
        self.on_menu()
        return true
    end
end

function HomeScreen:tab(name)
    return function()
        if self.on_tab then
            self.on_tab(name)
        end
    end
end

function HomeScreen:header(w, now)
    self.clock = Clock:new({ size = px(56), time = now })
    self.date_text = text(HomeText.date_line(now, self.days), "small", nil, theme.secondary)
    local left = Hit:new({
        callback = self.on_menu,
        hold_callback = function() self:onClose() end,
        HorizontalGroup:new({ align = "center",
            self.clock,
            hspan(px(16)),
            VerticalGroup:new({ align = "left", text("reading now", "title", nil, nil, nil, 34), self.date_text }),
        }),
    })
    local dimen = Geom:new({ w = w, h = left:getSize().h })
    return OverlapGroup:new({ dimen = dimen,
        LeftContainer:new({ dimen = dimen:copy(), left }),
        RightContainer:new({ dimen = dimen:copy(), P.menu_button(self.on_menu) }),
    })
end

function HomeScreen:button(label, callback)
    local t = text(label, "name", 16, theme.white)
    return Hit:new({ callback = callback, FrameContainer:new({
        bordersize = 0, padding = 0, background = theme.ink, radius = theme.radius,
        CenterContainer:new({ dimen = Geom:new({ w = t:getSize().w + px(40), h = px(44) }), t }),
    }) })
end

function HomeScreen:card(w, now)
    local row = self.model.current
    local pad = px(16)
    local cw, ch = px(104), px(156)
    local col_w = w - 2 * theme.border - 2 * pad - cw - pad
    local top = VerticalGroup:new({ align = "left",
        lines(row.title, "heading", 22, col_w, 2),
        vspan(px(6)),
        text(HomeText.byline(row), "body", 15, theme.secondary, col_w),
    })
    local bottom = VerticalGroup:new({ align = "left",
        bar(col_w, row.percent),
        vspan(px(4)),
        text(HomeText.progress(row, now), "small", nil, theme.secondary, col_w, 17),
        vspan(px(6)),
        self:button("continue", self:open(row.file)),
    })
    local fill = math.max(px(6), ch - top:getSize().h - bottom:getSize().h)
    return Hit:new({ callback = self:open(row.file), hold_callback = self:info(row.book), FrameContainer:new({
        bordersize = theme.border, color = theme.ink, radius = theme.radius, padding = pad,
        HorizontalGroup:new({ align = "top",
            Cover.widget({ file = row.file, title = row.title }, cw, ch),
            hspan(pad),
            VerticalGroup:new({ align = "left", top, vspan(fill), bottom }),
        }),
    }) })
end

function HomeScreen:empty(w)
    local t = text("nothing open yet · pick a book in shelves", "body", 15, theme.secondary, w - 2 * px(16))
    return Hit:new({ callback = self:tab("shelves"), FrameContainer:new({
        bordersize = theme.border, color = theme.ink, radius = theme.radius, padding = px(16),
        CenterContainer:new({ dimen = Geom:new({ w = w - 2 * px(16) - 2 * theme.border, h = px(60) }), t }),
    }) })
end

function HomeScreen:more(w)
    local m = self.model
    local row = m.more
    local inner = w - 2 * px(16)
    local right = text(T(_("%1 reading"), m.reading_count), "small", nil, theme.secondary)
    local text_w = inner - px(30) - 2 * px(16) - right:getSize().w
    local col = VerticalGroup:new({ align = "left",
        text(row.title, "button", 16, theme.ink, text_w),
        text(HomeText.more(row), "small", nil, theme.secondary, text_w),
    })
    local dimen = Geom:new({ w = inner, h = math.max(px(52), col:getSize().h) })
    return Hit:new({ callback = self:open(row.file), hold_callback = self:info(row.book), FrameContainer:new({
        bordersize = 0, background = theme.panel, radius = theme.radius,
        padding = 0, padding_left = px(16), padding_right = px(16), padding_top = px(8), padding_bottom = px(8),
        OverlapGroup:new({ dimen = dimen,
            LeftContainer:new({ dimen = dimen:copy(), HorizontalGroup:new({ align = "center",
                Cover.widget({ file = row.file, title = row.title }, px(30), px(44)),
                hspan(px(16)),
                col,
            }) }),
            RightContainer:new({ dimen = dimen:copy(), right }),
        }),
    }) })
end

local TILE_LINES = { { "button", 15, theme.ink }, { "button", 13, theme.ink }, { "small", 12, theme.secondary } }

local function tile_content(label, texts, w, sub_callback)
    local g = VerticalGroup:new({ align = "left", text(label, "label", 12, theme.ink, w) })
    for i, spec in ipairs(TILE_LINES) do
        if texts[i] then
            table.insert(g, vspan(px(3)))
            local line = text(texts[i], spec[1], spec[2], spec[3], w)
            if i == 3 and sub_callback then
                line = TallHit:new({ callback = sub_callback, width = w, line })
            end
            table.insert(g, line)
        end
    end
    return g
end

function HomeScreen:tiles(w)
    local tile_w = math.floor((w - px(16)) / 2)
    local inner = tile_w - 2 * px(16)
    local contents, callbacks
    if self.fandoms then
        contents = { tile_content("FANFIC", { _("by fandom"), nil, _(HomeText.fandoms(self.fandoms)) }, inner) }
        callbacks = { self.on_fanfic }
    else
        return nil
    end
    local h = 0
    for _i, c in ipairs(contents) do
        h = math.max(h, c:getSize().h)
    end
    local row = HorizontalGroup:new({ align = "top" })
    for i, c in ipairs(contents) do
        if i > 1 then
            table.insert(row, hspan(w - 2 * tile_w))
        end
        table.insert(row, Hit:new({ callback = callbacks[i], FrameContainer:new({
            bordersize = 0, background = theme.panel, radius = theme.radius,
            padding = 0, padding_left = px(16), padding_right = px(16), padding_top = px(12), padding_bottom = px(12),
            LeftContainer:new({ dimen = Geom:new({ w = inner, h = h }),
                VerticalGroup:new({ align = "left", c, vspan(h - c:getSize().h) }) }),
        }) }))
    end
    return row
end

function HomeScreen:build()
    local m = self.model
    local now = m.now or os.time()
    local pad, gap = px(24), px(16)
    local w = self.dimen.w - 2 * pad
    local body_h = self.dimen.h - TabBar.height - 2 * pad
    local top = { self:header(w, now) }
    table.insert(top, m.current and self:card(w, now) or self:empty(w))
    if m.more then
        table.insert(top, self:more(w))
    end
    local used = 0
    for _i, wid in ipairs(top) do
        used = used + wid:getSize().h + gap
    end
    local tiles = self:tiles(w)
    local tiles_h = tiles and tiles:getSize().h or 0
    local up = false
    local col = VerticalGroup:new({ align = "left" })
    for i, wid in ipairs(top) do
        if i > 1 then
            table.insert(col, vspan(gap))
        end
        table.insert(col, wid)
    end
    if up then
        table.insert(col, vspan(gap))
        table.insert(col, up)
    end
    if tiles and used + tiles_h <= body_h then
        table.insert(col, vspan(body_h - used - tiles_h + gap))
        table.insert(col, tiles)
    end
    self.header_dimen = Geom:new({ x = 0, y = pad, w = self.dimen.w, h = top[1]:getSize().h })
    self[1] = FrameContainer:new({
        background = theme.white, bordersize = 0, padding = 0,
        OverlapGroup:new({
            dimen = self.dimen:copy(),
            FrameContainer:new({ bordersize = 0, padding = pad, col }),
            BottomContainer:new({ dimen = self.dimen:copy(), TabBar:new({
                current = "home", width = self.dimen.w, on_select = function(tab) self:tab(tab)() end }) }),
        }),
    })
end

function HomeScreen:update(fields)
    for k, v in pairs(fields) do
        self[k] = v
    end
    self:build()
    UIManager:setDirty(self, "ui")
end

function HomeScreen:setTime(now)
    self.clock.time = now
    self.date_text:setText(HomeText.date_line(now, self.days))
end

function HomeScreen:paintTo(bb, x, y)
    local now = os.time()
    if math.floor(now / 60) ~= math.floor(self.clock.time / 60) then
        self:setTime(now)
    end
    InputContainer.paintTo(self, bb, x, y)
    if not self.closed and not self.ticking then
        self.ticking = true
        UIManager:scheduleIn(61 - now % 60, self.tick_fn)
    end
end

function HomeScreen:tick()
    self.ticking = false
    if self.closed or UIManager:getTopmostVisibleWidget() ~= self then
        return
    end
    self:setTime(os.time())
    UIManager:setDirty(self, "ui", self.header_dimen)
end

function HomeScreen:onClose()
    UIManager:close(self)
    if self.on_close then
        self.on_close()
    end
    return true
end

-- Back does nothing on home: holding the header is the way out
function HomeScreen:onStay()
    return true
end

function HomeScreen:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.tick_fn)
    UIManager:setDirty(nil, "full")
end

function HomeScreen:onShow()
    UIManager:setDirty(self, "full")
    return true
end

return HomeScreen
