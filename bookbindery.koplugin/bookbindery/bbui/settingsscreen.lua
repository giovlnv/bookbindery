--[[--
bookbindery settings: manga covers, pinned shelves
and the build (bookbindery/settings.lua words them).
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local SettingsScreen = {}

local function row_widget(row, w)
    if row.note then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(2), padding_bottom = px(8),
            P.text(row.note, "small", 13, theme.secondary, w) })
    end
    local right
    if row.action then
        right = P.link(row.action)
    elseif row.right then
        right = P.text(row.right, "small", 13, theme.secondary, math.floor(w / 2))
    end
    local text_w = w - (right and right:getSize().w + px(16) or 0)
    local left = P.text(row.text, "item", 17, row.muted and theme.secondary or theme.ink, text_w)
    if row.action and row.right then
        left = P.text(row.text .. " · " .. row.right, "item", 17, theme.ink, text_w)
    end
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(10), padding_bottom = px(10),
        P.spread(w, left, right) })
end

-- the rows as the list wants them (notes without a rule)
function SettingsScreen.rows(rows)
    for _, r in ipairs(rows) do
        if r.note then
            r.line = false
        end
    end
    return rows
end

-- opts: rows (Settings.rows with a callback on each tappable one), back, close_callback
function SettingsScreen.new(opts)
    local list
    list = PagedList:new({
        top = P.topbar(opts.back or "system", nil, function() list:onClose() end),
        pad_top = px(16),
        header = PagedList.heading("bookbindery settings", nil, true),
        rows = SettingsScreen.rows(opts.rows),
        row_widget = row_widget,
        close_callback = opts.close_callback,
    })
    return list
end

return SettingsScreen
