--[[--
Fanfic: the fandoms on the device, fandoms with new chapters first.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")
local Wording = require("bookbindery/wording")

local px = P.px

local FanficScreen = {}

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function row_widget(row, w)
    local f = row.fandom
    local right = HorizontalGroup:new({ align = "center" })
    if f.new > 0 then
        table.insert(right, P.chip(f.new .. " new", true))
        table.insert(right, P.hspan(px(12)))
    end
    if f.n > 0 then
        table.insert(right, P.text(plural(f.n, "work", "works"), "small", 13, theme.secondary))
    end
    local name_w = w - right:getSize().w - px(16)
    local name = P.text(f.name, "button", 17, theme.ink, name_w)
    local pad = px(11) - math.floor(math.max(0, right:getSize().h - name:getSize().h) / 2)
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = pad, padding_bottom = pad,
        P.spread(w, name, right) })
end

-- opts: fandoms (Fanfic.fandoms), back (label of the screen below), on_fandom(name), on_menu, close_callback
function FanficScreen.new(opts)
    local works = 0
    for _, f in ipairs(opts.fandoms) do
        works = works + f.n
    end
    local rows = {}
    for _, f in ipairs(opts.fandoms) do
        rows[#rows + 1] = { fandom = f, callback = function() opts.on_fandom(f.name) end }
    end
    if #rows == 0 then
        rows[1] = { fandom = { name = "no fanfic on " .. Wording.device .. " yet", n = 0, new = 0 }, line = false }
    end
    local list
    list = PagedList:new({
        top = P.topbar(opts.back or "shelves", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        header = PagedList.heading("fanfic", plural(works, "work", "works") .. " · "
            .. plural(#opts.fandoms, "fandom", "fandoms"), true),
        rows = rows,
        row_widget = row_widget,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    return list
end

return FanficScreen
