--[[--
Shelf tree: one level per dot of calibre's #type under a top-level shelf.
Tap the chevron to open or close a shelf, the rest of the row to see its books;
long-press pins a shelf to the top.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local PagedList = require("bookbindery/bbui/pagedlist")
local Shelves = require("bookbindery/shelves")
local ShelvesText = require("bookbindery/shelvestext")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local ShelfTreeScreen = {}

local INDENT = 24
local NOTE = "calibre’s type column, one level per dot: fiction › series › pjo. "

local function tree_row(row, w)
    local n = row.item.node
    local depth = row.item.depth
    local count_w = px(36)
    local hint
    if #n.children > 0 then
        hint = ShelvesText.shelves(#n.children)
    end
    if row.item.pinned then
        hint = hint and "pinned · " .. hint or "pinned"
    end
    local hint_w = hint and P.text(hint, "small", 13):getSize().w + px(16) or 0
    local name_w = w - px(INDENT * depth) - px(36) - count_w - hint_w
    local name = depth == 0 and P.text(n.name, "button", 17, theme.ink, name_w)
        or P.text(n.name, "item", 16, theme.ink, name_w)
    local right = HorizontalGroup:new({ align = "center" })
    if hint then
        table.insert(right, P.text(hint, "small", 13, theme.secondary))
        table.insert(right, P.hspan(px(16)))
    end
    table.insert(right, P.spread(count_w, P.hspan(0), P.text(tostring(n.count), "name", 16)))
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(11), padding_bottom = px(11),
        P.spread(w, HorizontalGroup:new({ align = "center",
            P.hspan(px(INDENT * depth)),
            P.icon(row.item.open and "expanded" or "open", 18),
            P.hspan(px(18)),
            name,
        }), right) })
end

local function row_widget(row, w)
    if row.kind == "title" then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_bottom = px(6), P.title(row.text, row.count) })
    elseif row.kind == "note" then
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_bottom = px(6),
            P.lines(row.text, "small", 13, w, 3, theme.secondary, false, 0.1) })
    end
    return tree_row(row, w)
end

-- opts: node (Shelves.tree node), pinned (list of paths),
-- on_pin(path, on), on_shelf(path), on_menu, close_callback
function ShelfTreeScreen.new(opts)
    local node = opts.node
    local open, pinned = {}, {}
    for _, c in ipairs(node.children) do
        open[c.path] = true
    end
    for _, p in ipairs(opts.pinned or {}) do
        pinned[p] = true
    end
    local order, first = false, "Biggest first; "
    local list
    local function rows()
        local out = {
            { kind = "title", text = ShelvesText.name(node.path), count = node.count, line = false,
                callback = function() opts.on_shelf(node.path) end },
            { kind = "note", line = false, text = NOTE .. first
                .. "long-press to pin a shelf to the top." },
        }
        for _, item in ipairs(Shelves.rows(node, open, pinned, order)) do
            local path = item.node.path
            out[#out + 1] = {
                item = item,
                callback = function(_row, x)
                    if #item.node.children > 0 and x < px(INDENT * item.depth + 44) then
                        open[path] = not open[path]
                        list:update(rows())
                    else
                        opts.on_shelf(path)
                    end
                end,
                hold_callback = function()
                    pinned[path] = not pinned[path] or nil
                    opts.on_pin(path, pinned[path] or false)
                    list:update(rows())
                end,
            }
        end
        return out
    end
    local all = rows()
    list = PagedList:new({
        top = P.topbar("shelves", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        rows = all,
        row_widget = row_widget,
        pager_note = function(page, pages, shown)
            local names = {}
            for _, i in ipairs(pages[page + 1] or {}) do
                local r = shown[i]
                if r.item then
                    names[#names + 1] = r.item.node.name
                end
            end
            return ShelvesText.next_note(names)
        end,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    return list
end

return ShelfTreeScreen
