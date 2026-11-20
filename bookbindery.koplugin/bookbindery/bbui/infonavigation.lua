--[[--
Book info and fic info, opened by holding a book or fic row. showInfo(entry,
back) is the hook for every row that has an index entry (search too);
installed on the plugin by main.lua with its io helpers.
]]

local _ = require("gettext")
local BookInfo = require("bookbindery/bookinfo")
local FicInfo = require("bookbindery/ficinfo")
local MarkAs = require("bookbindery/markas")
local Timing = require("bookbindery/timing")
local px = require("bookbindery/bbui/parts").px

local KOREADER = "sets koreader's reading status"

-- env: library(root), books_root(), toast(text), info_read(file), info_stats(md5, title),
-- koreader_status(file, status, create) (the sidecar's, only when it exists unless create; a nil status
-- clears it), to_read(lpath, on) ("to read" over KOReader's default)
return function(Bookbindery, env)
    local books_root, toast = env.books_root, env.toast

    -- the menu screen belongs to the file manager: in the reader its button is left out
    local function menu(self)
        if self.ui.document then
            return nil
        end
        return function() self:showMenu() end
    end

    -- in the reader the open book is already there: close the screens, then its bookmark list
    local function opener(self, file, after)
        return function()
            local doc = self.ui.document
            if doc and doc.file == file then
                self:closeScreens()
                if after == "bookmarks" and self.ui.bookmark then
                    self.ui.bookmark:onShowBookmark()
                end
                return
            end
            self:openBook(file, nil, after)
        end
    end

    -- the index entry as the library has it now; the screens below redraw when shown
    function Bookbindery:entryChanged(entry)
        local index = env.library(books_root())
        self:markStale()
        return index and index.books[entry.lpath] or entry
    end

    -- any file in the library folder
    function Bookbindery:markable(entry)
        if entry and entry.lpath then
            return true
        end
        toast(_("calibre doesn't know this book yet"))
    end

    function Bookbindery:showSheet(opts)
        local sheet
        opts.close_callback = function() self:overlayClosed(sheet) end
        sheet = require("bookbindery/bbui/sheet"):new(opts)
        self:showOverlay(sheet)
        return sheet
    end

    -- on_change(entry) after a change, with the entry as the index has it now. KOReader's own status is
    -- set (to read clears it and marks the book in toread.lua)
    function Bookbindery:showMarkAs(entry, on_change)
        if not self:markable(entry) then
            return
        end
        self:safely("mark as", function()
            local sheet
            local rows = MarkAs.statuses(entry.status)
            for _i, r in ipairs(rows) do
                r.callback = function()
                    sheet:onClose()
                    if r.checked then
                        return
                    end
                    self:safely("mark as", function()
                        local status = MarkAs.koreader(r.value)
                            env.koreader_status(books_root() .. entry.lpath, status, true)
                            env.to_read(entry.lpath, status == nil)
                        on_change(self:entryChanged(entry))
                    end)
                end
            end
            sheet = self:showSheet({
                title = _("mark as"),
                note = _(KOREADER),
                rows = rows,
            })
        end)
    end

    -- entry: an index entry, or { lpath, title, authors, library } for a fic calibre doesn't know
    function Bookbindery:showInfo(entry, back)
        if not (entry and entry.lpath) then
            return
        end
        if entry.library == "fanfic" then
            self:showFicInfo(entry, back)
        else
            self:showBookInfo(entry, back)
        end
    end

    function Bookbindery:showFull(back, title, text)
        self:safely("description", function()
            self:push(self:subScreen(require("bookbindery/bbui/infoscreen").full({
                back = back, title = title, text = text, on_menu = menu(self) })))
        end)
    end

    -- replacing: the info screen this one takes the place of, after a change
    function Bookbindery:showBookInfo(entry, back, replacing)
        self:safely("book info", function()
            local t0 = Timing.start()
            local file = books_root() .. entry.lpath
            local widget
            local read = env.info_read(file)
            local raw = env.info_stats(read.md5, read.doc_title)
            local stats = raw and BookInfo.stats(raw.rows, read.pages or raw.pages)
            local m = BookInfo.model(entry, read, stats, os.time())
            local buttons = {
                { label = _(m.action), primary = true, callback = opener(self, file) },
                { label = _("mark as…"), callback = function()
                    self:showMarkAs(entry, function(fresh) self:showBookInfo(fresh, back, widget) end)
                end },
            }
            if m.highlights > 0 then
                buttons[#buttons + 1] = { label = _("highlights"), callback = opener(self, file, "bookmarks") }
            end
            local chips = { m.status }
            if m.shelf then
                chips[2] = m.shelf
            end
            widget = self:subScreen(require("bookbindery/bbui/infoscreen"):new({
                back = back or "back",
                cover = { file = file, w = px(150), h = px(225) },
                title = m.title,
                authors = m.authors,
                meta = m.meta,
                chips = chips,
                rows = m.rows,
                strong = "progress",
                about = m.about ~= "" and m.about or "no description",
                on_full = m.about_more and function() self:showFull("book info", m.title, m.full) end or nil,
                details = m.details,
                buttons = buttons,
                on_menu = menu(self),
            }))
            self:pushReplacing(widget, replacing)
            Timing.drawn("bookinfo", t0)
        end)
    end

    function Bookbindery:showFicInfo(entry, back, replacing)
        self:safely("fic info", function()
            local t0 = Timing.start()
            local file = books_root() .. entry.lpath
            local widget
            local m = FicInfo.model(entry, env.info_read(file), os.time())
            local buttons = { { label = _(m.action), primary = true, callback = opener(self, file) } }
            buttons[#buttons + 1] = { label = _("mark as…"), callback = function()
                self:showMarkAs(entry, function(fresh) self:showFicInfo(fresh, back, widget) end)
            end }
            local chips = { m.status }
            chips[#chips + 1] = m.rating
            widget = self:subScreen(require("bookbindery/bbui/infoscreen"):new({
                back = back or "fanfic",
                cover = { file = file, w = px(130), h = px(195), title_size = 26 },
                title = m.title,
                authors = m.authors,
                chips = chips,
                rows = m.rows,
                about_label = "summary",
                about = m.summary ~= "" and m.summary or "no summary",
                on_full = m.summary_more and function() self:showFull("fic info", m.title, m.full) end or nil,
                details = m.details,
                buttons = buttons,
                on_menu = menu(self),
            }))
            self:pushReplacing(widget, replacing)
            Timing.drawn("ficinfo", t0)
        end)
    end
end
