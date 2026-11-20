--[[--
Updates: manga and articles, each section a label and its rows
(bookbindery/updates.lua words them). The header has "check all now".
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")
local Screen = require("device").screen

local px = P.px

local UpdatesScreen = {}

local function row_widget(row, w)
    if row.label then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = row.first and 0 or px(14),
            padding_bottom = px(2), P.label(row.label, w) })
    elseif row.note then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(6),
            P.text(row.note, "small", 13, theme.secondary, w) })
    end
    local right
    if row.action then
        right = P.link(row.action)
    elseif row.chevron then
        right = P.icon("open", 18)
    elseif row.right then
        right = P.text(row.right, "small", 13, theme.secondary)
    end
    local text_w = w - (right and right:getSize().w + px(16) or 0)
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(10), padding_bottom = px(10),
        P.spread(w, P.text(row.text, "item", 17, row.muted and theme.secondary or theme.ink, text_w), right) })
end

local function section(rows, label)
    rows[#rows + 1] = { label = label, header = true, first = #rows == 0 }
end

-- opts: manga, rakuyomi (check now offered), articles, wallabag (sync offered); on_manga, on_sync
function UpdatesScreen.rows(opts)
    local rows = {}
    section(rows, "manga · rakuyomi")
    rows[#rows + 1] = opts.rakuyomi
        and { text = opts.manga, action = "check now", callback = function() opts.on_manga() end }
        or { text = opts.manga, muted = true }
    section(rows, "articles · wallabag")
    rows[#rows + 1] = opts.wallabag
        and { text = opts.articles, action = "sync", callback = function() opts.on_sync() end }
        or { text = opts.articles, muted = true }
    return rows
end

-- "updates", check all now and the menu button
function UpdatesScreen.header(opts)
    local w = Screen:getWidth() - 2 * theme.space[4]
    local right = HorizontalGroup:new({ align = "center",
        P.button("check all now", px(148), true, opts.on_check_all), P.hspan(px(4)), P.menu_button(opts.on_menu) })
    local g = VerticalGroup:new({ align = "left", P.spread(w, P.text("updates", "title"), right) })
    return g
end

-- opts: as rows and header, with on_check_all, on_tab, on_menu, close_callback
function UpdatesScreen.new(opts)
    return PagedList:new({
        header = UpdatesScreen.header(opts),
        menu_in_header = true,
        rows = UpdatesScreen.rows(opts),
        row_widget = row_widget,
        tab = "updates",
        on_tab = opts.on_tab,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
end

return UpdatesScreen
