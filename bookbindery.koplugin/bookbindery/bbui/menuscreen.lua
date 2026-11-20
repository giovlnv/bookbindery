--[[--
Menu screen: bookbindery's five menu tabs on top (current one black), the tab's rows
(KOReader entries or bookbindery screens) and on system the "more" rows. Back, "close"
or a swipe down from the top closes it.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local TabBar = require("bookbindery/bbui/tabbar")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local MenuScreen = {}

MenuScreen.TABS = { "library", "sources", "reading", "device", "system" }

local ABOUT = {
    library = "your books",
    sources = "where books come from",
    reading = "while you read",
    device = require("bookbindery/wording").device_tab,
    system = "koreader and bookbindery",
}

local function row_widget(row, w)
    if row.heading then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(20), padding_bottom = px(4),
            P.label(row.heading, w) })
    end
    local right = HorizontalGroup:new({ align = "center" })
    if row.note then
        table.insert(right, P.text(row.note, "small", 13, theme.secondary, math.floor(w / 3)))
        table.insert(right, P.hspan(px(8)))
    end
    table.insert(right, P.icon("open", 20))
    local label = P.text(row.label, "item", 17, row.enabled and theme.ink or theme.secondary,
        w - right:getSize().w - px(16))
    local pad = px(11)
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = pad, padding_bottom = pad,
        P.spread(w, label, right) })
end

-- tab: one of Menus.place's tabs; status(row) -> enabled, note
function MenuScreen.rows(tab, status, on_row)
    local out = {}
    local function add(r)
        local enabled, note = status(r)
        out[#out + 1] = { label = r.label:lower(), note = note, enabled = enabled,
            callback = enabled and function() on_row(r) end or nil }
    end
    for _, r in ipairs(tab.rows) do
        add(r)
    end
    if tab.more and #tab.more > 0 then
        out[#out + 1] = { heading = "more", header = true }
        for _, r in ipairs(tab.more) do
            add(r)
        end
    end
    return out
end

-- opts: tabs (Menus.place), tab, status(row) -> enabled, note, on_row(row), on_tab(name), close_callback
function MenuScreen.new(opts)
    local list, current
    local function find(name)
        for _, t in ipairs(opts.tabs) do
            if t.tab == name then
                return t
            end
        end
        return opts.tabs[1]
    end
    local function header(name)
        local w = list and list.inner_w or (require("device").screen:getWidth() - 2 * theme.space[4])
        local close = P.hit(P.text("close", "small", 13), function() list:onClose() end)
        return P.spread(w, P.label(name .. " · " .. ABOUT[name]), close)
    end
    local function tabbar(name)
        return TabBar:new({ tabs = MenuScreen.TABS, current = name, top = true,
            on_select = function(t) list.bb_show(t) end })
    end
    local function rows(name)
        return MenuScreen.rows(find(name), opts.status, opts.on_row)
    end
    current = find(opts.tab).tab
    list = PagedList:new({
        top = tabbar(current),
        pad_top = theme.space[3],
        header = header(current),
        rows = rows(current),
        row_widget = row_widget,
        on_menu = function() list:onClose() end,
        close_callback = opts.close_callback,
    })
    list.bb_show = function(name)
        current = name
        list.top = tabbar(name)
        list.page = 1
        list:update(rows(name), header(name))
        if opts.on_tab then
            opts.on_tab(name)
        end
    end
    list.bb_refresh = function()
        list:update(rows(current))
    end
    return list
end

return MenuScreen
