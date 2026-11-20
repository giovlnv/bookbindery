--[[--
One fandom's works: title, author, new chapters and reading status.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local FandomScreen = {}

local function row_widget(row, w)
    local b = row.work
    local right = HorizontalGroup:new({ align = "center" })
    if b.new_chapters > 0 then
        table.insert(right, P.chip(b.new_chapters .. (b.new_chapters == 1 and " new chapter" or " new chapters"), true))
    end
    if b.status then
        if #right > 0 then
            table.insert(right, P.hspan(px(10)))
        end
        table.insert(right, P.text(b.status, "small", 13, theme.secondary))
    end
    local col_w = w - (#right > 0 and right:getSize().w + px(16) or 0)
    local author = table.concat(b.authors or {}, ", ")
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(8), padding_bottom = px(8),
        P.spread(w, VerticalGroup:new({ align = "left",
            P.text(b.title, "button", 15, theme.ink, col_w),
            P.vspan(px(2)),
            P.text(author, "small", 13, theme.secondary, col_w),
        }), #right > 0 and right or nil) })
end

-- opts: fandom, works (Fanfic.works), on_book(lpath), on_info(work), on_menu, close_callback
function FandomScreen.new(opts)
    local rows = {}
    for _, b in ipairs(opts.works) do
        rows[#rows + 1] = { work = b, callback = function() opts.on_book(b.lpath) end,
            hold_callback = function() opts.on_info(b) end }
    end
    local list
    list = PagedList:new({
        top = P.topbar("fanfic", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        header = PagedList.heading(opts.fandom, #rows .. (#rows == 1 and " work" or " works"), true),
        rows = rows,
        row_widget = row_widget,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    return list
end

return FandomScreen
