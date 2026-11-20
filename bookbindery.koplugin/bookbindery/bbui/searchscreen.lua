--[[--
Search: one field (KOReader's InputText; results come on Enter, not per key),
the scope chips, a count line and paged result rows. library and fanfic search
the device (tap opens, hold shows info); manga and dictionary hand the query to
their own screens.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputText = require("ui/widget/inputtext")
local VerticalGroup = require("ui/widget/verticalgroup")
local Cover = require("bookbindery/bbui/cover")
local PagedList = require("bookbindery/bbui/pagedlist")
local Search = require("bookbindery/search")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local SearchScreen = {}

local KIND = { manga = "handoff", dictionary = "handoff" }
local LABEL = { library = "title, author or series", fanfic = "title, author, fandom or ship",
    manga = "title", dictionary = "word" }
local HANDOFF = { manga = "results open in rakuyomi",
    dictionary = "the meaning opens in koreader's dictionary" }
local COVER_W, COVER_H, PAD = 36, 52, 10

local metrics

local function measure()
    if not metrics then
        metrics = { title = P.text("x", "item", 17):getSize().h, sub = P.text("x", "small", 13):getSize().h }
    end
    return metrics
end

local function row_height()
    local m = measure()
    return math.max(px(COVER_H), m.title + px(2) + m.sub) + 2 * px(PAD)
end

local function result_widget(r, w, books_root)
    local m = measure()
    local cover = r.lpath and Cover.widget({ file = books_root .. r.lpath, title = r.title }, px(COVER_W), px(COVER_H))
        or P.box(px(COVER_W), px(COVER_H), theme.cover, px(4))
    local place = P.text(r.place, "small", 13, theme.secondary)
    local col_w = w - px(COVER_W) - px(16) - place:getSize().w - px(12)
    local text_h = m.title + px(2) + m.sub
    local inner = row_height() - 2 * px(PAD)
    local col = VerticalGroup:new({ align = "left",
        P.vspan(math.floor((inner - text_h) / 2)),
        P.text(r.title, "item", 17, theme.ink, col_w),
        P.vspan(px(2)),
        P.text(r.subline or Search.subline(r), "small", 13, theme.secondary, col_w),
    })
    local left = HorizontalGroup:new({ align = "top", cover, P.hspan(px(16)), col })
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(PAD), padding_bottom = px(PAD),
        P.spread(w, left, VerticalGroup:new({ P.vspan(math.floor((inner - place:getSize().h) / 2)), place })) })
end

local function row_widget(row, w)
    if row.result then
        return result_widget(row.result, w, row.books_root)
    end
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = px(12), padding_bottom = px(4),
        P.lines(row.message, "small", 13, w, 3, theme.secondary, false, 0.2) })
end

local function chip_lines(scopes, scope, w, on_scope)
    local lines, line, used = VerticalGroup:new({ align = "left" }), nil, 0
    for _, s in ipairs(scopes) do
        local chip = P.chip(s, s == scope, function() on_scope(s) end)
        local cw = chip:getSize().w
        if not line or used + px(8) + cw > w then
            if line then
                table.insert(lines, line)
                table.insert(lines, P.vspan(px(8)))
            end
            line, used = HorizontalGroup:new({ align = "center", chip }), cw
        else
            table.insert(line, P.hspan(px(8)))
            table.insert(line, chip)
            used = used + px(8) + cw
        end
    end
    table.insert(lines, line)
    return lines
end

local function summary(scope, results, message)
    local kind = KIND[scope]
    if kind == "handoff" then
        return HANDOFF[scope]
    end
    return Search.summary(results and #results, scope)
end

-- opts: scope, run(query, scope) -> results, handoff(scope, query) -> true when it went, books_root,
-- on_book(r), on_info(r), on_tab, on_menu, close_callback, safe(fn) (runs fn, an error closes
-- the screens and is logged)
function SearchScreen.new(opts)
    local scopes = Search.scopes()
    local scope, query, results, message = "library", "", nil, nil
    for _, s in ipairs(scopes) do
        if s == opts.scope then
            scope = s
        end
    end
    local label = LABEL
    local safe = opts.safe or function(fn) fn() end
    local closed = false
    local list = PagedList:new({
        rows = {},
        pad_top = px(8),
        tab = "search",
        on_tab = opts.on_tab,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    local pad = theme.space[4]
    local w = list.inner_w
    local field_pad = px(12)
    local input
    local function top()
        local title = P.title("search")
        return FrameContainer:new({ bordersize = 0, padding = pad, padding_bottom = 0,
            VerticalGroup:new({ align = "left",
                P.spread(w, title, P.menu_button(opts.on_menu, title:getSize().h)),
                P.vspan(px(12)),
                P.label(label[scope], w),
                P.vspan(px(8)),
                FrameContainer:new({ bordersize = theme.line, color = theme.ink, radius = px(8),
                    padding = 0, input }),
                P.vspan(px(12)),
                chip_lines(scopes, scope, w, function(s) list.bb_scope(s) end),
                P.vspan(px(12)),
                P.text(summary(scope, results, message), "small", 13, theme.secondary, w),
            }) })
    end
    local function rows()
        local out = {}
        if message then
            out[1] = { message = message, line = false }
        elseif not results then
            out[1] = { message = "type a " .. label[scope] .. ", then enter", line = false }
        elseif #results == 0 then
            out[1] = { message = "nothing found for “" .. query .. "”", line = false }
        end
        for _, r in ipairs(message and {} or results or {}) do
            out[#out + 1] = { result = r, books_root = opts.books_root,
                callback = function() opts.on_book(r) end,
                hold_callback = r.lpath and function() opts.on_info(r) end or nil }
        end
        return out
    end
    local function show()
        list.top = top()
        list:update(rows())
    end
    local function run()
        query = input:getText():match("^%s*(.-)%s*$")
        results, message = nil, nil
        list.page = 1
        local kind = KIND[scope]
        if query == "" then
            results = nil
        elseif kind == "handoff" then
            message = opts.handoff(scope, query) and "“" .. query .. "” went there; closing it comes back here" or nil
        else
            results = opts.run(query, scope)
        end
        show()
    end
    input = InputText:new({
        parent = list,
        width = w - 2 * theme.line - 2 * field_pad,
        face = theme.face("item", 17),
        padding = field_pad,
        margin = 0,
        bordersize = 0,
        hint = "",
        -- InputText calls this 0.3 s after Enter: the screen may be gone by then
        enter_callback = function()
            if closed then
                return
            end
            input:onCloseKeyboard()
            safe(run)
        end,
    })
    -- InputText asks its parent for these: Back on a keyboard, focus on devices with a d-pad (the emulator)
    list.onCloseDialog = function() list:onClose() end
    list.getFocusableWidgetXY = function() end
    -- a keyboard still up when the screen closes (opened a book, went home) goes with it
    local input_closed = input.onCloseWidget
    input.onCloseWidget = function(self)
        closed = true
        self:onCloseKeyboard()
        input_closed(self)
    end
    -- after a mark-as change on an info screen opened from here
    list.bb_refresh = function()
        safe(function()
            if results and not KIND[scope] then
                results = opts.run(query, scope)
                show()
            end
        end)
    end
    -- local scopes run at once; online ones on Enter or a second tap on their chip
    list.bb_scope = function(s)
        if not KIND[s] or s == scope then
            scope = s
            return safe(run)
        end
        scope, results = s, nil
        local q = input:getText():match("^%s*(.-)%s*$")
        message = q ~= "" and "enter or a second tap on " .. s .. " searches “" .. q .. "”" or nil
        list.page = 1
        safe(show)
    end
    list.row_widget = row_widget
    list.row_height = function(row) return row.result and row_height() or nil end
    show()
    return list
end

return SearchScreen
