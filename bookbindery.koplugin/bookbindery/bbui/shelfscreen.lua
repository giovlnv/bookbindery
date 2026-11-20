--[[--
Shelf detail: a shelf's books (or a status's), grouped by shelf, author, series
or none, as a grid of covers or a list. Rows have fixed heights so paging only
builds the covers of the page shown.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local Cover = require("bookbindery/bbui/cover")
local PagedList = require("bookbindery/bbui/pagedlist")
local Shelves = require("bookbindery/shelves")
local ShelvesText = require("bookbindery/shelvestext")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local ShelfScreen = {}

local COLS = 3
local GROUPS = { "shelf", "author", "series", "none" }
local EMPTY = { shelf = "no shelf", author = "no author", series = "no series", none = "" }
local STATUS = { reading = "reading", read = "read", dnf = "dnf" }

local metrics

local function measure()
    if not metrics then
        local t = P.lines("x", "label", 13, px(100), 1, nil, nil, 0.23)
        local a = P.text("x", "small", 12)
        local l1 = P.text("x", "button", 15)
        local l2 = P.text("x", "small", 13)
        metrics = { title = math.ceil(t:getLineHeight() * 2), author = a:getSize().h,
            line1 = l1:getSize().h, line2 = l2:getSize().h }
        t:free()
    end
    return metrics
end

local function cell_w(w)
    return math.floor((w - (COLS - 1) * px(14)) / COLS)
end

local function heights()
    local m = measure()
    local cover = px(104) + px(2) + m.title + px(2) + m.author + px(14)
    local list = px(8) + m.line1 + px(2) + m.line2 + px(8)
    return cover, list
end

local function cover_row(row, w, books_root)
    local m = measure()
    local cw = cell_w(w)
    local g = HorizontalGroup:new({ align = "top" })
    for i, b in ipairs(row.books) do
        if i > 1 then
            table.insert(g, P.hspan(px(14)))
        end
        table.insert(g, VerticalGroup:new({ align = "left",
            Cover.widget({ file = books_root .. b.lpath, title = b.title }, cw, px(104)),
            P.vspan(px(2)),
            P.lines(b.title, "label", 13, cw, 2, theme.ink, true, 0.23),
            P.vspan(px(2)),
            P.text(ShelvesText.byline(b), "small", 12, theme.secondary, cw),
        }))
    end
    local h = heights()
    local content = px(104) + px(2) + m.title + px(2) + m.author
    return VerticalGroup:new({ align = "left", g, P.vspan(h - content) })
end

local function list_row(row, w)
    local b = row.book
    local status = STATUS[b.status] and P.text(STATUS[b.status], "small", 13, theme.secondary)
    local col_w = w - (status and status:getSize().w + px(16) or 0)
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(8), padding_bottom = px(8),
        P.spread(w, VerticalGroup:new({ align = "left",
            P.text(b.title, "button", 15, theme.ink, col_w),
            P.vspan(px(2)),
            P.text(ShelvesText.byline(b), "small", 13, theme.secondary, col_w),
        }), status) })
end

-- opts: index, path, status (or source(group_by) -> groups, title, group_by, empty for other books),
-- books_root, on_book(file), on_info(book), on_shelf(path), on_menu, close_callback
function ShelfScreen.new(opts)
    local self = { mode = "covers", group_by = opts.group_by or "shelf" }
    local title = opts.title or opts.status and ShelvesText.status(opts.status) or ShelvesText.name(opts.path)
    local list

    local function build_rows()
        local groups = opts.source and opts.source(self.group_by)
            or Shelves.books(opts.index, opts.path, self.group_by, opts.status)
        local rows, total = {}, 0
        for _, g in ipairs(groups) do
            total = total + #g.books
            if self.group_by ~= "none" then
                local label = g.label ~= "" and g.label or nil
                local shelf = self.group_by == "shelf" and label and label ~= opts.path and label or nil
                local text = self.group_by == "shelf" and label and ShelvesText.path(label) or label
                rows[#rows + 1] = { kind = "group", header = true, text = text or EMPTY[self.group_by],
                    all = shelf ~= nil, callback = shelf and function() opts.on_shelf(shelf) end or nil }
            end
            if self.mode == "covers" then
                for i = 1, #g.books, COLS do
                    local chunk = { unpack(g.books, i, math.min(i + COLS - 1, #g.books)) }
                    local function at(x)
                        local w = require("device").screen:getWidth() - 2 * theme.space[4]
                        return chunk[math.floor(x / (cell_w(w) + px(14))) + 1]
                    end
                    rows[#rows + 1] = { kind = "covers", books = chunk, line = false,
                        callback = function(_row, x)
                            local b = at(x)
                            if b then
                                opts.on_book(opts.books_root .. b.lpath)
                            end
                        end,
                        hold_callback = function(_row, x)
                            local b = at(x)
                            if b then
                                opts.on_info(b)
                            end
                        end }
                end
            else
                for _, b in ipairs(g.books) do
                    rows[#rows + 1] = { kind = "book", book = b,
                        callback = function() opts.on_book(opts.books_root .. b.lpath) end,
                        hold_callback = function() opts.on_info(b) end }
                end
            end
        end
        if total == 0 and opts.empty then
            rows = { { kind = "empty", text = opts.empty } }
        end
        return rows, total
    end

    local function header(total)
        local function set(field, value)
            return function()
                self[field] = value
                local rows, n = build_rows()
                list:update(rows, header(n))
            end
        end
        local w = require("device").screen:getWidth() - 2 * theme.space[4]
        local modes = P.chips({ P.chip("covers", self.mode == "covers", set("mode", "covers")),
            P.chip("list", self.mode == "list", set("mode", "list")) })
        local by = { P.text("group by", "small", 13, theme.secondary) }
        for _, g in ipairs(GROUPS) do
            by[#by + 1] = P.chip(g, self.group_by == g, set("group_by", g))
        end
        return VerticalGroup:new({ align = "left",
            P.spread(w, P.title(title, total), modes),
            P.vspan(px(8)),
            P.chips(by),
        })
    end

    local function row_widget(row, w)
        if row.kind == "group" then
            return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(6), padding_bottom = px(6),
                P.spread(w, P.label(row.text, w - px(40)), row.all and P.link("all") or nil) })
        elseif row.kind == "empty" then
            return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(11), padding_bottom = px(11),
                P.text(row.text, "small", 13, theme.secondary, w) })
        elseif row.kind == "covers" then
            return cover_row(row, w, opts.books_root)
        end
        return list_row(row, w)
    end

    local function row_height(row)
        if row.kind == "covers" then
            return (heights())
        elseif row.kind == "book" then
            return select(2, heights())
        end
    end

    local rows, total = build_rows()
    list = PagedList:new({
        top = P.topbar("shelves", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(14),
        header = header(total),
        rows = rows,
        row_widget = row_widget,
        row_height = row_height,
        footer_hint = "series in volume order",
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    list.bb_refresh = function()
        local r, n = build_rows()
        list:update(r, header(n))
    end
    return list
end

return ShelfScreen
