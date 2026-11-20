--[[--
Manga: rakuyomi's library from its database, filtered by chip (library, downloaded,
new chapters). A tap opens rakuyomi's chapter list; reading and downloads stay in
rakuyomi. Rows have a fixed height so paging only builds the covers shown.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local Cover = require("bookbindery/bbui/cover")
local Manga = require("bookbindery/manga")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local MangaScreen = {}

local COVER_W, COVER_H, PAD = 64, 92, 10

local function row_h()
    return px(COVER_H) + 2 * px(PAD)
end

local function manga_row(m, w, cover_of)
    local cw = px(COVER_W)
    local chevron = P.icon("open", 18)
    local col_w = w - cw - px(16) - chevron:getSize().w - px(24)
    local text = VerticalGroup:new({ align = "left",
        P.text(m.title, "name", 16, theme.ink, col_w),
        P.vspan(px(2)),
        P.text(Manga.line(m), "small", 13, theme.secondary, col_w),
        P.vspan(px(8)),
        P.bar(col_w, Manga.progress(m)),
    })
    local left = HorizontalGroup:new({ align = "center",
        Cover.widget({ image = cover_of(m), title = m.title }, cw, px(COVER_H)), P.hspan(px(16)), text })
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(PAD), padding_bottom = px(PAD),
        P.spread(w, left, chevron) })
end

local function note(w)
    return FrameContainer:new({ bordersize = 0, background = theme.panel, radius = theme.radius,
        padding = px(16), width = w,
        P.lines("reading and downloads stay in rakuyomi.", "small", 13, w - px(32), 3, theme.ink, false, 0.3,
            theme.panel) })
end

-- opts: load() -> list or nil, message; cover_of(m) -> path or nil; on_manga(m), on_rakuyomi(),
-- on_sources(), on_menu, close_callback
function MangaScreen.new(opts)
    local chip = "library"
    local list, build_header

    local function build()
        local all, message = opts.load()
        local shown = all and Manga.filter(all, chip) or {}
        local rows = {}
        for _, m in ipairs(shown) do
            rows[#rows + 1] = { kind = "manga", manga = m, callback = function() opts.on_manga(m) end }
        end
        if #rows == 0 then
            rows[1] = { kind = "empty", text = message or Manga.empty(chip) }
        end
        rows[#rows + 1] = { kind = "note", line = false }
        return rows, all and #all or nil
    end

    local function header(n)
        local chips = {}
        for _, c in ipairs(Manga.CHIPS) do
            chips[#chips + 1] = P.chip(c, c == chip, function()
                chip = c
                list:update(build_header())
            end)
        end
        return VerticalGroup:new({ align = "left", P.title("manga", n), P.vspan(px(12)), P.chips(chips) })
    end

    build_header = function()
        local rows, n = build()
        return rows, header(n)
    end

    local function row_widget(row, w)
        if row.kind == "manga" then
            return manga_row(row.manga, w, opts.cover_of)
        elseif row.kind == "note" then
            return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(16), note(w) })
        end
        return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(11), padding_bottom = px(11),
            P.text(row.text, "small", 13, theme.secondary, w) })
    end

    local w = require("device").screen:getWidth() - 2 * theme.space[4]
    local half = math.floor((w - px(12)) / 2)
    local rows, head = build_header()
    list = PagedList:new({
        top = P.topbar("shelves", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        header = head,
        rows = rows,
        row_widget = row_widget,
        row_height = function(row) return row.kind == "manga" and row_h() or nil end,
        bottom = HorizontalGroup:new({
            P.button("open rakuyomi", half, true, opts.on_rakuyomi),
            P.hspan(w - 2 * half),
            P.button("browse sources", half, false, opts.on_sources),
        }),
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    list.bb_refresh = function()
        list:update(build_header())
    end
    return list
end

return MangaScreen
