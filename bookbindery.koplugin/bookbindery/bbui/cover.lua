local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local Widget = require("ui/widget/widget")
local theme = require("bookbindery/bbui/theme")

local Cover = {}

local function bookinfo(file)
    local ok, manager = pcall(require, "bookinfomanager")
    if not ok or not file then
        return nil
    end
    local got, info = pcall(manager.getBookInfo, manager, file, true)
    return got and info and info.cover_bb and info or nil, manager
end

local function placeholder(book, w, h)
    local pad = theme.space[2]
    local dimen = Geom:new({ w = w, h = h })
    local frame = FrameContainer:new({
        bordersize = 0,
        padding = 0,
        background = theme.cover,
        radius = Screen:scaleBySize(4),
        Widget:new({ dimen = dimen }),
    })
    if w < Screen:scaleBySize(72) then
        return frame
    end
    local opts = {
        text = book.title or "",
        face = theme.face("cover"),
        fgcolor = theme.ink,
        bgcolor = theme.cover,
        width = w - 2 * pad,
        line_height = 0.15,
    }
    local text = TextBoxWidget:new(opts)
    if text:getSize().h > h - 2 * pad then
        text:free()
        opts.height = h - 2 * pad
        opts.height_overflow_show_ellipsis = true
        text = TextBoxWidget:new(opts)
    end
    frame[1] = BottomContainer:new({ dimen = dimen, FrameContainer:new({ bordersize = 0, padding = pad, text }) })
    return frame
end

-- book: { file, title } or { image = path of a cached cover, title }
function Cover.widget(book, w, h)
    if book.image then
        return CenterContainer:new({ dimen = Geom:new({ w = w, h = h }),
            ImageWidget:new({ file = book.image, width = w, height = h, scale_factor = 0 }) })
    end
    local info, manager = bookinfo(book.file)
    if not info then
        return placeholder(book, w, h)
    end
    local scale = select(3, manager.getCachedCoverSize(info.cover_w, info.cover_h, w, h))
    return CenterContainer:new({
        dimen = Geom:new({ w = w, h = h }),
        ImageWidget:new({ image = info.cover_bb, scale_factor = scale }),
    })
end

return Cover
