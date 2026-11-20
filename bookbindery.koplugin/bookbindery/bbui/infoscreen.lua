--[[--
Book info and fic info: cover, title, author, chips and a short table on top,
the description, a grey details panel and the buttons at the bottom. One
screen, never paged; the full description is its own paged screen.
]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Cover = require("bookbindery/bbui/cover")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")
local Screen = Device.screen

local px = P.px

local InfoScreen = InputContainer:extend({
    back = "",
    cover = nil,
    title = "",
    authors = "",
    meta = nil,
    chips = nil,
    rows = nil,
    strong = nil,
    about_label = "about",
    about = "",
    on_full = nil,
    details = nil,
    buttons = nil,
    note = nil,
    on_menu = nil,
    close_callback = nil,
    covers_fullscreen = true,
})

function InfoScreen:init()
    self.dimen = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.ges_events = { SwipeMenu = { GestureRange:new({ ges = "swipe", range = Geom:new({
        x = 0, y = 0, w = self.dimen.w, h = math.floor(self.dimen.h / 8) }) }) } }
    self:build()
end

-- label and value columns
function InfoScreen:table(w)
    local label_w = 0
    local labels = {}
    for i, r in ipairs(self.rows) do
        labels[i] = P.text(r.label, "body", 14, theme.secondary)
        label_w = math.max(label_w, labels[i]:getSize().w)
    end
    local g = VerticalGroup:new({ align = "left" })
    for i, r in ipairs(self.rows) do
        if i > 1 then
            table.insert(g, P.vspan(px(4)))
        end
        local strong = r.label == self.strong
        table.insert(g, HorizontalGroup:new({ align = "top",
            P.spread(label_w, labels[i]),
            P.hspan(px(14)),
            P.text(r.value, strong and "name" or "body", 14, theme.ink, w - label_w - px(14)),
        }))
    end
    return g
end

function InfoScreen:top(w)
    local cw, ch = self.cover.w, self.cover.h
    local col_w = w - cw - px(20)
    local head = VerticalGroup:new({ align = "left",
        P.lines(self.title, "title", self.cover.title_size or 25, col_w, 3, theme.ink, false, 0.1),
        P.vspan(px(6)),
        P.text(self.authors, "item", 16, theme.ink, col_w),
    })
    if self.meta and self.meta ~= "" then
        table.insert(head, P.vspan(px(6)))
        table.insert(head, P.text(self.meta, "small", 13, theme.secondary, col_w))
    end
    if #self.chips > 0 then
        local chips = {}
        for i, c in ipairs(self.chips) do
            chips[i] = P.chip(c, i == 1)
        end
        table.insert(head, P.vspan(px(8)))
        table.insert(head, P.chips(chips))
    end
    local dl = self:table(col_w)
    local fill = math.max(px(10), ch - head:getSize().h - dl:getSize().h)
    return HorizontalGroup:new({ align = "top",
        Cover.widget({ file = self.cover.file, title = self.title }, cw, ch),
        P.hspan(px(20)),
        VerticalGroup:new({ align = "left", head, P.vspan(fill), dl }),
    })
end

function InfoScreen:description(w)
    local g = VerticalGroup:new({ align = "left", P.label(self.about_label, w), P.vspan(px(6)),
        P.lines(self.about, "item", 16, w, 4, theme.ink, false, 0.25) })
    if self.on_full then
        table.insert(g, P.vspan(px(4)))
        table.insert(g, P.hit(P.link("full description"), self.on_full))
    end
    return g
end

function InfoScreen:panel(w)
    local pad, gap = px(16), px(16)
    local inner = w - 2 * pad
    local cell = math.floor((inner - 2 * gap) / 3)
    local g = VerticalGroup:new({ align = "left" })
    local line
    for i, d in ipairs(self.details) do
        if (i - 1) % 3 == 0 then
            if line then
                table.insert(g, P.vspan(px(10)))
            end
            line = HorizontalGroup:new({ align = "top" })
            table.insert(g, line)
        else
            table.insert(line, P.hspan(gap))
        end
        table.insert(line, VerticalGroup:new({ align = "left",
            P.spread(cell, P.text(d.label, "small", 13, theme.secondary, cell)),
            P.lines(d.value, "body", 14, cell, 2, theme.ink, false, 0.15, theme.panel),
        }))
    end
    return FrameContainer:new({ bordersize = 0, background = theme.panel, radius = theme.radius, padding = pad,
        width = w, g })
end

function InfoScreen:buttonRow(w)
    local gap = px(12)
    local total = 0
    for _, b in ipairs(self.buttons) do
        total = total + (b.primary and 2 or 1)
    end
    local unit = (w - gap * (#self.buttons - 1)) / total
    local g = HorizontalGroup:new({ align = "center" })
    for i, b in ipairs(self.buttons) do
        if i > 1 then
            table.insert(g, P.hspan(gap))
        end
        table.insert(g, P.button(b.label, math.floor(unit * (b.primary and 2 or 1)), b.primary, b.callback))
    end
    return g
end

function InfoScreen:build()
    local pad = px(24)
    local w = self.dimen.w - 2 * pad
    local col = VerticalGroup:new({ align = "left", self:top(w), P.vspan(px(20)), self:description(w) })
    if #self.details > 0 then
        table.insert(col, P.vspan(px(20)))
        table.insert(col, self:panel(w))
    end
    local bottom = VerticalGroup:new({ align = "center", self:buttonRow(w) })
    if self.note then
        table.insert(bottom, P.vspan(px(14)))
        table.insert(bottom, P.text(self.note, "small", 13, theme.secondary, w))
    end
    self[1] = FrameContainer:new({
        background = theme.white, bordersize = 0, padding = 0,
        OverlapGroup:new({
            dimen = self.dimen:copy(),
            VerticalGroup:new({ align = "left",
                P.topbar(self.back, nil, function() self:onClose() end, self.on_menu),
                FrameContainer:new({ bordersize = 0, padding = pad, col }),
            }),
            BottomContainer:new({ dimen = self.dimen:copy(),
                FrameContainer:new({ bordersize = 0, padding = pad, padding_top = 0, bottom }) }),
        }),
    })
end

function InfoScreen:onSwipeMenu(arg, ges)
    if ges.direction == "south" and self.on_menu then
        self.on_menu()
        return true
    end
end

function InfoScreen:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function InfoScreen:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function InfoScreen:onShow()
    UIManager:setDirty(self, "full")
    return true
end

-- long paragraphs split at sentences so a page can hold them
local function chunks(text, max)
    local out = {}
    for para in (text .. "\n\n"):gmatch("(.-)\n\n") do
        while #para > max do
            local cut = para:sub(1, max):match("^.*[%.!?…]%s") or para:sub(1, max):match("^.*%s") or para:sub(1, max)
            out[#out + 1] = cut:gsub("%s+$", "")
            para = para:sub(#cut + 1)
        end
        if para ~= "" then
            out[#out + 1] = para
        end
    end
    return out
end

-- opts: back, title, text (paragraphs), on_menu, close_callback
function InfoScreen.full(opts)
    local rows = {}
    for _, p in ipairs(chunks(opts.text, 900)) do
        rows[#rows + 1] = { text = p, line = false }
    end
    local list
    list = PagedList:new({
        top = P.topbar(opts.back, nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        header = P.lines(opts.title, "title", 25, Screen:getWidth() - 2 * theme.space[4], 2, theme.ink, false, 0.1),
        rows = rows,
        row_widget = function(row, w)
            return FrameContainer:new({ bordersize = 0, padding = 0, padding_bottom = px(12),
                P.lines(row.text, "item", 16, w, 40, theme.ink, false, 0.25) })
        end,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    return list
end

return InfoScreen
