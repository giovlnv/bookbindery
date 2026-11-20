--[[--
KOReader adapter: io for the models, the home screen, start_with = "bookbindery".
Home is shown on top of the file manager; holding its header shows the file
manager, and with start_with every closed book comes back home.
]]

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local T = require("ffi/util").template
local _ = require("gettext")
local Comeback = require("bookbindery/comeback")
local Fanfic = require("bookbindery/fanfic")
local Home = require("bookbindery/home")
local Library = require("bookbindery/library")
local Wording = require("bookbindery/wording")
local ReaderBook = require("bookbindery/readerbook")
local ReadState = require("bookbindery/readstate")
local ToRead = require("bookbindery/toread")
local Timing = require("bookbindery/timing")

local START = "bookbindery"
local DIR = DataStorage:getSettingsDir() .. "/bookbindery"
local state = { booted = false, return_home = false, refreshing = false }

local function denull(v)
    if v == rapidjson.null then
        return nil
    end
    if type(v) == "table" then
        for k, x in pairs(v) do
            v[k] = denull(x)
        end
    end
    return v
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

local function write(path, s)
    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end
    local ok, werr = f:write(s)
    local cok, cerr = f:close()
    if not ok or not cok then
        return nil, werr or cerr or "write failed"
    end
    return true
end

-- fsynced before the rename
local function write_durable(path, s)
    local ok, err = require("util").writeToFile(s, path, true)
    return ok and true or nil, err or "write failed"
end

local json = {
    decode = function(s) return denull(rapidjson.decode(s)) end,
    encode = rapidjson.encode,
}

local fileio = {
    read = read,
    write = write,
    write_durable = write_durable,
    rename = os.rename,
    attributes = function(path) return lfs.attributes(path) end,
    decode = json.decode,
    encode = json.encode,
    serialize = function(t) return "return " .. dump(t) end,
    deserialize = function(s) return setfenv(assert(loadstring(s)), {})() end,
}

local function toast(text)
    UIManager:show(InfoMessage:new({ text = text, timeout = 2 }))
end

local function books_root()
    local root = G_reader_settings:readSetting("bookbindery_books_root") or Wording.books_root
        or G_reader_settings:readSetting("home_dir") or require("apps/filemanager/filemanagerutil").getDefaultDir()
    return root:sub(-1) == "/" and root or root .. "/"
end

local function ensure_dir()
    if lfs.attributes(DIR, "mode") ~= "directory" then
        lfs.mkdir(DIR)
    end
end

-- BookList keeps what the sidecars hold in memory (ReaderUI updates it on close);
-- percent_finished * pages is also last_page for paged documents.
local function book_info(file)
    local info = require("ui/widget/booklist").getBookInfo(file)
    local percent, pages = info.percent_finished, info.pages
    return { percent = percent, status = info.status, pages = pages,
        page = percent and pages and math.floor(percent * pages + 0.5) }
end

local function status_of(file)
    local info = book_info(file)
    return Fanfic.status({ status = info.status, percent = info.percent })
end

-- book and fic info: the sidecar (never created here) and the file, read once per screen open
local function info_read(file)
    local attrs = lfs.attributes(file) or {}
    local out = { ext = file:match("%.([^./]+)$"), size = attrs.size, added = attrs.modification }
    if not require("docsettings"):hasSidecarFile(file) then
        return out
    end
    -- one open: it also fills BookList's cache that book_info reads, unless that is already set
    local ds = require("ui/widget/booklist").getDocSettings(file)
    local info = book_info(file)
    out.opened, out.percent, out.pages, out.page, out.status = true, info.percent, info.pages, info.page, info.status
    local props = ds:readSetting("doc_props") or {}
    out.md5, out.language, out.doc_title = ds:readSetting("partial_md5_checksum"), props.language, props.title
    local n, notes = 0, 0
    for _i, a in ipairs(ds:readSetting("annotations") or {}) do
        n = n + 1
        if a.note and a.note ~= "" then
            notes = notes + 1
        end
    end
    out.highlights, out.notes = n, notes
    return out
end

-- as KOReader's own status buttons (filemanagerutil.genStatusButtonsRow): summary.status,
-- saveSummary, then BookList's cache; only on a book whose sidecar exists, unless create
-- A nil status clears it.
local function koreader_status(file, status, create)
    local BookList = require("ui/widget/booklist")
    -- the open book's own settings: a second DocSettings would be overwritten when the reader flushes
    local reader = require("apps/reader/readerui").instance
    local open = reader and reader.document and reader.document.file == file and reader.doc_settings
    if not open and not require("docsettings"):hasSidecarFile(file) then
        if not (create and status) then
            return false
        end
        require("apps/filemanager/filemanagerutil").saveSummary(file, { status = status })
        BookList.resetBookInfoCache(file)
        return true
    end
    local ds = open or BookList.getDocSettings(file)
    local summary = ds:readSetting("summary") or {}
    summary.status = status
    require("apps/filemanager/filemanagerutil").saveSummary(ds, summary)
    if status then
        BookList.setBookInfoCacheProperty(file, "status", status)
    else
        BookList.resetBookInfoCache(file)
    end
    return true
end

-- statistics' rows for the book with this md5 (and its title, as statistics matches
-- it, when one does: partial md5s collide), read-only; nil when there are none
local function info_stats(md5, title)
    if not (md5 and md5:match("^%x+$")) then
        return nil
    end
    local SQ3 = require("lua-ljsqlite3/init")
    local opened, conn = pcall(SQ3.open, DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
    if not opened then
        logger.dbg("bookbindery: no statistics:", conn)
        return nil
    end
    local ok, res = pcall(function()
        local books = conn:exec(string.format("SELECT id, pages, title FROM book WHERE md5 = '%s';", md5))
        if not books then
            return nil
        end
        local titled = false
        for i = 1, #books[1] do
            titled = titled or books[3][i] == title
        end
        local ids, pages = {}, 0
        for i, id in ipairs(books[1]) do
            if not titled or books[3][i] == title then
                ids[#ids + 1] = tostring(tonumber(id))
                pages = math.max(pages, tonumber(books[2][i]) or 0)
            end
        end
        local r = conn:exec("SELECT page, start_time, duration, total_pages FROM page_stat_data WHERE id_book IN ("
            .. table.concat(ids, ",") .. ");")
        local rows = {}
        for i = 1, r and #r[1] or 0 do
            rows[i] = { page = tonumber(r[1][i]), start_time = tonumber(r[2][i]), duration = tonumber(r[3][i]),
                total_pages = tonumber(r[4][i]) }
        end
        return { rows = rows, pages = pages }
    end)
    conn:close()
    if not ok then
        logger.dbg("bookbindery: no statistics:", res)
        return nil
    end
    return res
end

local function query_days(now)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
    local t = os.date("*t", now)
    local start = os.time({ year = t.year, month = t.month, day = 1, hour = 0 })
    local ok_q, res = pcall(conn.exec, conn, string.format("SELECT DISTINCT strftime('%%Y-%%m-%%d', start_time, "
        .. "'unixepoch', 'localtime') FROM page_stat_data WHERE start_time >= %d;", start))
    conn:close()
    assert(ok_q, res)
    local rows = {}
    for i, d in ipairs(res and res[1] or {}) do
        rows[i] = { day = tostring(d) }
    end
    return rows
end

-- statistics.sqlite3 is read once a day; a book opened later today adds today
local function days_read(now, hist)
    local today = os.date("%Y-%m-%d", now)
    local memo = state.days
    if not memo or memo.date ~= today then
        local ok, rows = pcall(query_days, now)
        if not ok then
            logger.dbg("bookbindery: no days read:", rows)
            return nil
        end
        memo = { date = today, n = ReadState.days_read(rows, os.date("%Y-%m", now)) }
        for _i, r in ipairs(rows) do
            memo.today = memo.today or r.day == today
        end
        state.days = memo
    end
    if not memo.today then
        local t = os.date("*t", now)
        local midnight = os.time({ year = t.year, month = t.month, day = t.day, hour = 0 })
        for _i, h in ipairs(hist) do
            if (h.time or 0) >= midnight then
                memo.today, memo.n = true, memo.n + 1
                break
            end
        end
    end
    return memo.n
end

-- KOReader's own summary.status (nil when none was set; BookList says "reading" then) and whether the
-- book was opened. Each sidecar is opened once and fills BookList's cache too; read again only when
-- BookList's entry changed (a status set, a book closed)
local own = {}
local function koreader_own(file)
    local BookList = require("ui/widget/booklist")
    local info = BookList.book_info_cache[file]
    local m = own[file]
    if m and info and m.info == info and m.status_seen == info.status then
        return m.status, m.opened
    end
    local status, opened = nil, false
    if not (info and info.been_opened == false) then
        local DocSettings = require("docsettings")
        if DocSettings:hasSidecarFile(file) then
            local ds = DocSettings:open(file)
            local summary = ds:readSetting("summary")
            status, opened = summary and summary.status, true
            if not BookList.hasBookInfoCache(file) then
                BookList.setBookInfoCache(file, ds)
            end
        else
            BookList.setBookInfoCacheProperty(file, "been_opened", false)
        end
        info = BookList.book_info_cache[file]
    else
        opened = false
    end
    own[file] = { info = info, status_seen = info and info.status, status = status, opened = opened }
    return status, opened
end

-- books marked to read (ToRead)
local function to_read()
    if not state.toread then
        state.toread = ToRead.load(DIR .. "/toread.lua", fileio)
    end
    return state.toread
end

local function set_to_read(lpath, on)
    if ToRead.set(to_read(), lpath, on) then
        ensure_dir()
        local ok, err = ToRead.save(DIR .. "/toread.lua", fileio, state.toread)
        if not ok then
            logger.warn("bookbindery: toread.lua didn't save:", err)
        end
    end
end

local function library(root)
    local path = root .. ".metadata.calibre"
    local attrs = lfs.attributes(path) or {}
    local key = tostring(attrs.size) .. ":" .. tostring(attrs.modification)
    local index = state.index
    if not (index and state.index_key == key) then
        index = Library.load(path, DIR .. "/library.lua", fileio)
        state.index, state.index_key, state.overlay_rev = index, index and key, nil
    end
        Library.fallbacks(index, function(lpath) return koreader_own(root .. lpath) end, to_read())
    return index
end

-- the fandom folders under books/fanfic, nil without the folder
local function fandom_folders(root)
    local dir = root .. "fanfic"
    if lfs.attributes(dir, "mode") ~= "directory" then
        return nil
    end
    local n = 0
    for name in lfs.dir(dir) do
        local path = dir .. "/" .. name
        if name:sub(1, 1) ~= "." and not name:match("%.sdr$") and lfs.attributes(path, "mode") == "directory" then
            n = n + 1
        end
    end
    return n
end

local function view()
    local root = books_root()
    local index = library(root)
    local ReadHistory = require("readhistory")
    ReadHistory:reload()
    local hist = {}
    for _i, h in ipairs(ReadHistory.hist) do
        if not h.dim then
            hist[#hist + 1] = h
        end
    end
    local now = os.time()
    local reading = ReadState.reading(hist, book_info, index, root)
    return {
        model = Home.model(reading, now),
        books_root = root,
        days = days_read(now, hist),
        fandoms = fandom_folders(root),
    }
end

local function shown()
    return state.home ~= nil or #(state.screens or {}) > 0
end

local function starts_home()
    return G_reader_settings:readSetting("start_with") == START
end

local Bookbindery = WidgetContainer:extend({
    name = "bookbindery",
    is_doc_only = false,
})

local function online()
    return NetworkMgr:isOnline()
end

require("bookbindery/bbui/navigation")(Bookbindery, {
    state = state, library = library, books_root = books_root, toast = toast,
    logger = logger, status_of = status_of, online = online,
})
require("bookbindery/bbui/manganavigation")(Bookbindery, {
    toast = toast, logger = logger, shown = shown, starts_home = starts_home,
})
require("bookbindery/bbui/foldertrips")(Bookbindery, { state = state, shown = shown, logger = logger })
require("bookbindery/bbui/menunavigation")(Bookbindery, {
    state = state, toast = toast,
})
require("bookbindery/bbui/updatesnavigation")(Bookbindery, {
    library = library, books_root = books_root, toast = toast,
})
require("bookbindery/bbui/infonavigation")(Bookbindery, {
    library = library, books_root = books_root, toast = toast, info_read = info_read,
    info_stats = info_stats, koreader_status = koreader_status, to_read = set_to_read,
})

function Bookbindery:init()
    self.ui.menu:registerToMainMenu(self)
    self:patchStartMenu()
    local first = not state.booted
    state.booted = true
    self.hookRakuyomi()
    self:hookFolderTrips()
    -- booting straight into a book broadcasts ShowingReader before any plugin exists
    if self.ui.document then
        if starts_home() then
            state.return_home = true
        end
        return
    end
    -- home and screens left over from a previous file manager sit under the new one
    local leftover = shown()
    if leftover then
        self:closeAll()
    end
    local home = Comeback.home_on_init({ trip = state.folder_trip, return_home = state.return_home,
        starts_home = starts_home(), first = first, leftover = leftover })
    state.return_home = false
    if home then
        UIManager:nextTick(function()
            -- after a manga chapter rakuyomi shows its chapter list again: home stays under it
            if not self.rakuyomiOnTop() then
                self:showHome()
            end
        end)
    end
end

function Bookbindery:patchStartMenu()
    local FMMenu = require("apps/filemanager/filemanagermenu")
    if FMMenu.bookbindery_patched then
        return
    end
    FMMenu.bookbindery_patched = true
    local orig = FMMenu.getStartWithMenuTable
    FMMenu.getStartWithMenuTable = function(menu)
        local t = orig(menu)
        table.insert(t.sub_item_table, {
            text = _("bookbindery home"),
            radio = true,
            checked_func = starts_home,
            callback = function() G_reader_settings:saveSetting("start_with", START) end,
        })
        local text_func = t.text_func
        t.text_func = function()
            if starts_home() then
                return T(_("Start with: %1"), _("bookbindery home"))
            end
            return text_func()
        end
        return t
    end
end

local BOOK_ID = "bookbindery_book"

-- the tab's sorting_hint only appends: wrap the sorter once (reader menu only) to put "book" first
local function put_book_first()
    ReaderBook.wrap_sorter(require("ui/menusorter"), BOOK_ID)
end

local function go_home(self)
    if self.ui.document then
        self:closeScreens()
        state.return_home = true
        self.ui:onHome()
    else
        self:showHome()
    end
end

local function status_word(status)
    for _i, r in ipairs(require("bookbindery/markas").statuses(status)) do
        if r.checked then
            return r.label
        end
    end
    return "not marked"
end

function Bookbindery:bookMenu()
    local file = self.ui.document and self.ui.document.file
    local function entry()
        return ReaderBook.entry(file, books_root(), library(books_root()))
    end
    -- any file in the library folder can be marked
    local function known()
        local e = entry()
        return e
    end
    local function highlights()
        local ok, n = pcall(function() return #self.ui.annotation.annotations end)
        return ok and n or 0
    end
    -- "label · note" (the touch menu has no right-hand column)
    local function with(label, note)
        return note and _(label) .. " · " .. _(note) or _(label)
    end
    local function show(fn, name)
        return function()
            self:safely(name, function() fn(entry()) end)
        end
    end
    local rows = {
        {
            text_func = function() return with("book info", entry() == nil and "not in the library folder") end,
            enabled_func = function() return entry() ~= nil end,
            callback = show(function(e) self:showInfo(e, _("book")) end, "book info"),
        },
        {
            text_func = function()
                local e = entry()
                if not e then
                    return with("mark as…", "not in the library folder")
                end
                return with("mark as…", status_word(e.status))
            end,
            enabled_func = function() return known() and true or false end,
            callback = show(function(e)
                self:showMarkAs(e, function() end)
            end, "mark as"),
        },
        {
            text_func = function() return with("highlights & notes", tostring(highlights())) end,
            enabled_func = function() return self.ui.bookmark ~= nil end,
            callback = function()
                self:safely("highlights", function() self.ui.bookmark:onShowBookmark() end)
            end,
        },
    }
    rows[#rows + 1] = {
        text = _("back to home"),
        callback = function() go_home(self) end,
    }
    return rows
end

function Bookbindery:addToMainMenu(menu_items)
    menu_items.bookbindery_home = {
        text = _("bookbindery home"),
        sorting_hint = "tools",
        callback = function() go_home(self) end,
    }
    if self.ui.document then
        put_book_first()
        menu_items[BOOK_ID] = {
            text = _("book"),
            sorting_hint = "navi",
            sub_item_table_func = function() return self:bookMenu() end,
        }
    end
end

function Bookbindery:showHome()
    if state.home and UIManager:isWidgetShown(state.home) then
        return
    end
    self:safely("home", function()
        local t0 = Timing.start()
        self:closeScreens()
        local HomeScreen = require("bookbindery/bbui/homescreen")
        local fields = view()
        fields.on_open = function(file, missing) self:openBook(file, missing) end
        fields.on_missing = T(_("not on %1 yet"), Wording.device)
        fields.on_tab = function(tab) self:route(tab) end
        fields.on_fanfic = function()
            self:showFanfic("home")
        end
        fields.on_menu = function() self:showMenu() end
        fields.on_info = function(book) self:showInfo(book, _("reading now")) end
        fields.on_close = function() state.home = nil end
        state.home = HomeScreen:new(fields)
        UIManager:show(state.home)
        Timing.drawn("home", t0)
    end)
end

function Bookbindery:rebuildHome()
    if state.home and UIManager:isWidgetShown(state.home) then
        self:safely("home", function() state.home:update(view()) end)
    end
end

-- after: "bookmarks" shows KOReader's bookmark list once this book is open
function Bookbindery:openBook(file, missing, after)
    if not file or lfs.attributes(file, "mode") ~= "file" then
        toast(missing or T(_("this book isn't on %1"), Wording.device))
        return
    end
    self:closeAll()
    state.return_home, state.after_open = true, after and { file = file, what = after }
    require("apps/reader/readerui"):showReader(file)
end

-- the flag goes with whichever book opens next, so a failed open can't leave it behind
function Bookbindery:onReaderReady()
    local after = state.after_open
    state.after_open = nil
    local doc = self.ui.document
    if after and after.what == "bookmarks" and doc and doc.file == after.file then
        UIManager:nextTick(function()
            if self.ui.bookmark then
                self.ui.bookmark:onShowBookmark()
            end
        end)
    end
end

-- a book opened from KOReader's menu (history, collections) closes only the
-- file manager: close bookbindery's screens too; with start_with, any book
-- (also one opened from the file browser) closes back home
function Bookbindery:onShowingReader()
    local leftover = shown()
    if leftover then
        self:closeAll()
    end
    if leftover or starts_home() then
        state.return_home = true
    end
end

return Bookbindery
