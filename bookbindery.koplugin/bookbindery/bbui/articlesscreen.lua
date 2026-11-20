--[[--
Articles: wallabag's downloaded articles, newest first, with reading status.
]]

local FrameContainer = require("ui/widget/container/framecontainer")
local PagedList = require("bookbindery/bbui/pagedlist")
local P = require("bookbindery/bbui/parts")
local theme = require("bookbindery/bbui/theme")

local px = P.px

local ArticlesScreen = {}

local function row_widget(row, w)
    local a = row.article
    local right = a.status and P.text(a.status, "small", 13, theme.secondary) or nil
    local title_w = w - (right and right:getSize().w + px(16) or 0)
    local title = P.text(a.title, "button", 15, theme.ink, title_w)
    local pad = px(11)
    return FrameContainer:new({ bordersize = 0, padding = 0, padding_top = pad, padding_bottom = pad,
        P.spread(w, title, right) })
end

-- opts: articles (Articles.list, each with status), back, on_article(file), on_menu, close_callback
function ArticlesScreen.new(opts)
    local rows = {}
    for _, a in ipairs(opts.articles) do
        rows[#rows + 1] = { article = a, callback = function() opts.on_article(a.file) end }
    end
    if #rows == 0 then
        rows[1] = { article = { title = "no articles downloaded yet" }, line = false }
    end
    local n = #opts.articles
    local list
    list = PagedList:new({
        top = P.topbar(opts.back or "shelves", nil, function() list:onClose() end, opts.on_menu),
        pad_top = px(16),
        header = PagedList.heading("articles", n .. (n == 1 and " article" or " articles"), true),
        rows = rows,
        row_widget = row_widget,
        on_menu = opts.on_menu,
        close_callback = opts.close_callback,
    })
    return list
end

return ArticlesScreen
