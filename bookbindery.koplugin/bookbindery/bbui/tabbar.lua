local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local theme = require("bookbindery/bbui/theme")

local ICONS = debug.getinfo(1, "S").source:match("^@(.*)/bookbindery/bbui/[^/]+$") .. "/icons/"

local TABS = { "home", "shelves", "updates", "search" }

local TabBar = InputContainer:extend({
    tabs = nil,
    current = nil,
    on_select = nil,
    width = nil,
    top = false,
})

TabBar.height = Screen:scaleBySize(64)

function TabBar:init()
    self.tabs = self.tabs or TABS
    local w = self.width or Screen:getWidth()
    local cell_w = math.floor(w / #self.tabs)
    local cell_h = TabBar.height - theme.border
    local icon = Screen:scaleBySize(24)
    local row = HorizontalGroup:new({})
    self.cells = {}
    for i, tab in ipairs(self.tabs) do
        local on = tab == self.current
        local cw = i == #self.tabs and w - cell_w * (#self.tabs - 1) or cell_w
        table.insert(row, FrameContainer:new({
            bordersize = 0,
            padding = 0,
            background = on and Blitbuffer.COLOR_BLACK or theme.white,
            CenterContainer:new({
                dimen = Geom:new({ w = cw, h = cell_h }),
                VerticalGroup:new({
                    align = "center",
                    ImageWidget:new({
                        file = ICONS .. tab .. ".svg",
                        width = icon,
                        height = icon,
                        is_icon = true,
                        invert = on,
                    }),
                    VerticalSpan:new({ width = Screen:scaleBySize(2) }),
                    TextWidget:new({
                        text = tab,
                        face = theme.face(on and "tab_on" or "tab"),
                        fgcolor = on and theme.white or theme.ink,
                    }),
                }),
            }),
        }))
        self.cells[i] = cw
    end
    local line = LineWidget:new({ background = theme.ink, dimen = Geom:new({ w = w, h = theme.border }) })
    self[1] = self.top and VerticalGroup:new({ row, line }) or VerticalGroup:new({ line, row })
    self.dimen = Geom:new({ x = 0, y = 0, w = w, h = TabBar.height })
    self.ges_events = { TapTab = { GestureRange:new({ ges = "tap", range = function() return self.dimen end }) } }
end

function TabBar:onTapTab(arg, ges)
    local x = ges.pos.x - self.dimen.x
    for i, cw in ipairs(self.cells) do
        if x < cw then
            if self.on_select and self.tabs[i] ~= self.current then
                self.on_select(self.tabs[i])
            end
            return true
        end
        x = x - cw
    end
    return true
end

return TabBar
