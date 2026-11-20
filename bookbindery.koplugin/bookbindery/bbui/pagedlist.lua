--[[--
Full-screen paged list for e-ink, never scrolling: rows fill pages by measured
height, swipe or tap the screen edges (16 px) to turn, "page x of y" footer,
optional top bar, bottom widget (above the pager) and bottom tab bar; menu_in_header:
the header has its own menu button. rows: { callback(row, x), hold_callback(row, x),
header, line, ... } drawn by row_widget(row, width); x is the tap's offset in the
row, header or line = false draw no rule under it, a header row stays with
the next. Widgets are built only for the pages shown; give row_height(row,
width) -> px (the widget's exact height, nil to measure) so pagination doesn't
build every row, e.g. rows with covers.
]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local P = require("bookbindery/bbui/parts")
local TabBar = require("bookbindery/bbui/tabbar")
local Timing = require("bookbindery/timing")
local theme = require("bookbindery/bbui/theme")
local Screen = Device.screen

local Item = InputContainer:extend({ row = nil, list = nil })

function Item:init()
    self.dimen = Geom:new({ x = 0, y = 0, w = self[1]:getSize().w, h = self[1]:getSize().h })
    local range = function() return self.dimen end
    self.ges_events = {}
    if self.row.callback then
        self.ges_events.TapRow = { GestureRange:new({ ges = "tap", range = range }) }
    end
    if self.row.hold_callback then
        self.ges_events.HoldRow = { GestureRange:new({ ges = "hold", range = range }) }
    end
end

function Item:onTapRow(arg, ges)
    if self.list:isEdge(ges.pos) then
        return false
    end
    self.row.callback(self.row, ges.pos.x - self.dimen.x)
    return true
end

function Item:onHoldRow(arg, ges)
    self.row.hold_callback(self.row, ges.pos.x - self.dimen.x)
    return true
end

local PagedList = InputContainer:extend({
    rows = nil,
    row_widget = nil,
    row_height = nil,
    header = nil,
    top = nil,
    pad_top = nil,
    footer_hint = nil,
    pager_note = nil,
    bottom = nil,
    tab = nil,
    on_tab = nil,
    on_menu = nil,
    close_callback = nil,
    menu_in_header = false,
    covers_fullscreen = true,
})

-- leaves room on the right for the menu button, unless full (a top bar has it)
function PagedList.heading(title, aside, full)
    local w = Screen:getWidth() - 2 * theme.space[4] - (full and 0 or P.MENU_W + theme.space[2])
    local t = TextWidget:new({ text = title, face = theme.face("title"), fgcolor = theme.ink })
    local h = t:getSize().h
    local group = OverlapGroup:new({ dimen = Geom:new({ w = w, h = h }), t })
    if aside then
        local a = TextWidget:new({ text = aside, face = theme.face("small"), fgcolor = theme.secondary,
            max_width = w - t:getSize().w - theme.space[3] })
        local aligned = VerticalGroup:new({ VerticalSpan:new({ width = t:getBaseline() - a:getBaseline() }), a })
        local ah = aligned:getSize().h
        table.insert(group, RightContainer:new({ dimen = Geom:new({ w = w, h = ah }), aligned }))
        group.dimen.h = math.max(h, ah)
    end
    return group
end

function PagedList:init()
    self.dimen = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
    self.edge = theme.space[3]
    self.ges_events = {
        SwipePage = { GestureRange:new({ ges = "swipe", range = self.dimen }) },
        TapEdge = { GestureRange:new({ ges = "tap", range = function() return self.body_dimen end }) },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.header = self:withMenu(self.header)
    self.page = 1
    self:paginate()
    self:build()
end

-- without a top bar (which has its own), the menu button sits right of the header
function PagedList:withMenu(header)
    if not header or not self.on_menu or self.top or self.menu_in_header then
        return header
    end
    local h = header:getSize().h
    local dimen = Geom:new({ w = self.dimen.w - 2 * theme.space[4], h = h })
    return OverlapGroup:new({ dimen = dimen,
        LeftContainer:new({ dimen = dimen:copy(), header }),
        RightContainer:new({ dimen = dimen:copy(), P.menu_button(self.on_menu, h) }),
    })
end

function PagedList:paginate()
    local pad = theme.space[4]
    local w = self.dimen.w - 2 * pad
    self.inner_w = w
    self.tab_h = self.tab and TabBar.height or 0
    self.pager_h = TextWidget:new({ text = "page", face = theme.face("small") }):getSize().h
    self.body_dimen = Geom:new({ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h - self.tab_h })
    local top_h = self.top and self.top:getSize().h or 0
    local avail = self.body_dimen.h - top_h - (self.pad_top or pad) - pad - self.pager_h - theme.space[2]
    if self.header then
        avail = avail - self.header:getSize().h - theme.space[2]
    end
    if self.bottom then
        avail = avail - self.bottom:getSize().h - theme.space[3]
    end
    self:freeItems()
    self.items = {}
    self.pages = { {} }
    local rows = self.rows or {}
    local function height(i)
        local r = rows[i]
        local h = self.row_height and self.row_height(r, w) or self:item(i):getSize().h
        return h + (self:ruled(r) and theme.line or 0)
    end
    local used = 0
    for i, r in ipairs(rows) do
        local h = height(i)
        local keep = r.header and rows[i + 1] and height(i + 1) or 0
        if used + h + keep > avail and #self.pages[#self.pages] > 0 then
            table.insert(self.pages, {})
            used = 0
        end
        table.insert(self.pages[#self.pages], i)
        used = used + h
    end
    self.page = math.max(1, math.min(self.page, #self.pages))
end

function PagedList:ruled(r)
    return not r.header and r.line ~= false
end

function PagedList:item(i)
    if not self.items[i] then
        local r = self.rows[i]
        self.items[i] = Item:new({ row = r, list = self, self.row_widget(r, self.inner_w) })
    end
    return self.items[i]
end

function PagedList:build()
    local pad = theme.space[4]
    local w = self.inner_w
    local col = VerticalGroup:new({ align = "left" })
    if self.header then
        table.insert(col, self.header)
        table.insert(col, VerticalSpan:new({ width = theme.space[2] }))
    end
    for _, i in ipairs(self.pages[self.page]) do
        local item = self:item(i)
        table.insert(col, item)
        if self:ruled(item.row) then
            table.insert(col, LineWidget:new({ background = theme.rule, dimen = Geom:new({ w = w, h = theme.line }) }))
        end
    end
    local bottom = VerticalGroup:new({ align = "left" })
    if self.bottom then
        table.insert(bottom, FrameContainer:new({ bordersize = 0, padding = 0, padding_left = pad,
            padding_right = pad, padding_bottom = theme.space[3], self.bottom }))
    end
    local dimen = Geom:new({ w = w, h = self.pager_h })
    local pager = OverlapGroup:new({ dimen = dimen, LeftContainer:new({ dimen = dimen, TextWidget:new({
        text = "page " .. self.page .. " of " .. #self.pages
            .. (self.pager_note and self:note() or ""),
        face = theme.face("small"), fgcolor = theme.secondary }) }) })
    if self.footer_hint then
        table.insert(pager, RightContainer:new({ dimen = dimen, TextWidget:new({
            text = self.footer_hint, face = theme.face("small"), fgcolor = theme.secondary }) }))
    end
    table.insert(bottom, FrameContainer:new({ bordersize = 0, padding = 0, padding_left = pad,
        padding_right = pad, padding_bottom = pad, pager }))
    if self.tab then
        table.insert(bottom, TabBar:new({ current = self.tab, width = self.dimen.w, on_select = function(tab)
            if self.on_tab then
                self.on_tab(tab)
            end
        end }))
    end
    self[1] = FrameContainer:new({
        background = theme.white,
        bordersize = 0,
        padding = 0,
        OverlapGroup:new({
            dimen = self.dimen:copy(),
            VerticalGroup:new({ align = "left", self.top or VerticalSpan:new({ width = 0 }),
                FrameContainer:new({ bordersize = 0, padding = pad, padding_top = self.pad_top or pad,
                    padding_bottom = 0, col }) }),
            BottomContainer:new({ dimen = self.dimen:copy(), bottom }),
        }),
    })
end

function PagedList:note()
    local s = self.pager_note(self.page, self.pages, self.rows)
    return s and s ~= "" and " · " .. s or ""
end

function PagedList:isEdge(pos)
    return pos.y < self.body_dimen.h and (pos.x < self.edge or pos.x >= self.dimen.w - self.edge)
end

function PagedList:turn(page)
    if page < 1 or page > #self.pages or page == self.page then
        return
    end
    local t0 = Timing.start()
    self.page = page
    self:build()
    UIManager:setDirty(self, "ui")
    Timing.drawn("page", t0)
end

function PagedList:update(rows, header)
    self.rows = rows
    if header then
        self.header = self:withMenu(header)
    end
    self:paginate()
    self:build()
    UIManager:setDirty(self, "ui")
end

function PagedList:onTapEdge(arg, ges)
    if self:isEdge(ges.pos) then
        self:turn(self.page + (ges.pos.x < self.edge and -1 or 1))
    end
    return true
end

function PagedList:onSwipePage(arg, ges)
    if ges.direction == "south" and self.on_menu and ges.pos.y < self.dimen.h / 8 then
        self.on_menu()
    elseif ges.direction == "west" then
        self:turn(self.page + 1)
    elseif ges.direction == "east" then
        self:turn(self.page - 1)
    end
    return true
end

function PagedList:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function PagedList:freeItems()
    for _, item in pairs(self.items or {}) do
        item:free()
    end
end

function PagedList:onCloseWidget()
    self:freeItems()
    UIManager:setDirty(nil, "full")
end

function PagedList:onShow()
    UIManager:setDirty(self, "full")
    return true
end

return PagedList
