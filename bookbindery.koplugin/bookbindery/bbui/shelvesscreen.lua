--[[--
Shelves: status tiles, the library tree's top level and
the places elsewhere (fanfic, manga, articles, all files).
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local ShelvesText = require("bookbindery/shelvestext")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local ShelvesScreen = {}

local TILES = { "reading", "tbr", "read", "dnf" }

local function tiles(row, w)
    local gap = px(8)
    local tile_w = math.floor((w - 3 * gap) / 4)
    local g = HorizontalGroup:new({ align = "top" })
    for i, s in ipairs(TILES) do
        local on = i == 1
        local fg = on and theme.white or theme.ink
        if i > 1 then
            table.insert(g, P.hspan(i == 4 and w - 4 * tile_w - 2 * gap or gap))
        end
        table.insert(g, FrameContainer:new({
            bordersize = 0, background = on and theme.ink or theme.panel, radius = theme.radius,
            padding = 0, padding_left = px(12), padding_right = px(12), padding_top = px(10), padding_bottom = px(10),
            LeftContainer:new({ dimen = Geom:new({ w = tile_w - 2 * px(12), h = px(44) }),
                VerticalGroup:new({ align = "left",
                    P.text(tostring(row.counts[s] or 0), "name", 20, fg),
                    P.text(ShelvesText.status(s), "small", 13, fg),
                }) }),
        }))
    end
    return g
end

local function shelf_row(row, w)
    local count_w = px(36)
    local hint = row.hint and row.hint ~= "" and P.text(row.hint, "small", 13, theme.secondary, math.floor(w * 0.55))
    local name_w = w - px(36) - count_w - (hint and hint:getSize().w + px(16) or 0)
    local right = HorizontalGroup:new({ align = "center" })
    if hint then
        table.insert(right, hint)
        table.insert(right, P.hspan(px(16)))
    end
    table.insert(right, P.spread(count_w, P.hspan(0), P.text(row.count and tostring(row.count) or "", "name", 16)))
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(9), padding_bottom = px(9),
        P.spread(w, HorizontalGroup:new({ align = "center",
            P.icon("open", 18), P.hspan(px(18)), P.text(row.name, "button", 17, theme.ink, name_w) }), right) })
end

local function row_widget(row, w)
    if row.kind == "tiles" then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_bottom = px(4), tiles(row, w) })
    elseif row.kind == "label" then
        local right = row.button and P.chip(row.button, true)
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(10),
            padding_bottom = right and 0 or px(2), P.spread(w, P.label(row.text), right) })
    elseif row.kind == "empty" then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(11), padding_bottom = px(11),
            P.text(row.text, "small", 13, theme.secondary, w) })
    end
    return shelf_row(row, w)
end

-- opts: counts, tree (Shelves.tree), fanfic_n, on_status(status), on_shelf(path), on_place(name), on_tab,
-- on_menu, close_callback
function ShelvesScreen.rows(opts)
    local w = require("device").screen:getWidth() - 2 * theme.space[4]
    local rows = {
        { kind = "tiles", counts = opts.counts, line = false, callback = function(_row, x)
            local i = math.min(4, math.max(1, math.floor(x / ((w + px(8)) / 4)) + 1))
            opts.on_status(TILES[i])
        end },
    }
    rows[#rows + 1] = { kind = "label", text = "library", header = true }
    for _, node in ipairs(opts.tree.children) do
        local n = nil
        rows[#rows + 1] = { name = ShelvesText.name(node.path), hint = ShelvesText.hint(node, n),
            count = node.count, callback = function() opts.on_shelf(node.path) end }
    end
    rows[#rows + 1] = { kind = "label", text = "elsewhere", header = true }
    local places = {
        { "fanfic", "by fandom", opts.fanfic_n },
        { "manga", "rakuyomi" },
        { "articles", "wallabag" },
        { "all files", "as on disk" },
    }
    for _, p in ipairs(places) do
        rows[#rows + 1] = { name = p[1], hint = p[2], count = p[3], callback = function() opts.on_place(p[1]) end }
    end
    return rows
end

function ShelvesScreen.new(opts)
    local rows = ShelvesScreen.rows(opts)
    return PagedList:new({
        header = P.text("shelves", "title"),
        rows = rows,
        row_widget = row_widget,
        tab = "shelves",
        on_tab = opts.on_tab,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
end

return ShelvesScreen
