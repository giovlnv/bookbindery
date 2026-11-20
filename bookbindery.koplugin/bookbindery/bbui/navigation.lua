--[[--
Navigation between bookbindery's screens: the tab screens (shelves, updates, search)
replace each other and home; sub-screens stack on top and close back. Installed
on the plugin by main.lua with its io helpers.
]]

local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template
local _ = require("gettext")
local Articles = require("bookbindery/articles")
local callable = require("bookbindery/callable")
local logger = require("logger")
local time = require("ui/time")
local Fanfic = require("bookbindery/fanfic")
local Search = require("bookbindery/search")
local Shelves = require("bookbindery/shelves")
local Timing = require("bookbindery/timing")
local Wording = require("bookbindery/wording")

-- env: state, library(root), books_root(), toast(text), logger, status_of(file)
return function(Bookbindery, env)
    local state, library, books_root, toast = env.state, env.library, env.books_root, env.toast

    -- a screen that fails to build leaves the file manager, never a stopped KOReader
    function Bookbindery:safely(what, fn)
        local ok, err = xpcall(fn, debug.traceback)
        if ok then
            return true
        end
        env.logger.err("bookbindery:", what, "failed:", err)
        pcall(self.closeAll, self)
        toast(_("bookbindery hit an error, see crash.log"))
        return false
    end

    local function menu(self)
        return function() self:showMenu() end
    end

    -- sheets and dialogs over the screens, closed with them
    function Bookbindery:showOverlay(widget)
        state.overlays = state.overlays or {}
        table.insert(state.overlays, widget)
        -- a dialog that closes itself (ok, cancel, dismiss) leaves the list too
        local orig = widget.onCloseWidget
        widget.onCloseWidget = function(w, ...)
            self:overlayClosed(w)
            if callable(orig) then
                return orig(w, ...)
            end
        end
        UIManager:show(widget)
    end

    -- a sheet closed itself
    function Bookbindery:overlayClosed(widget)
        for i, w in ipairs(state.overlays or {}) do
            if w == widget then
                table.remove(state.overlays, i)
                return
            end
        end
    end

    function Bookbindery:closeOverlay(widget)
        self:overlayClosed(widget)
        UIManager:close(widget)
    end

    function Bookbindery:closeScreens()
        local overlays = state.overlays or {}
        state.overlays = {}
        for i = #overlays, 1, -1 do
            UIManager:close(overlays[i])
        end
        local screens = state.screens or {}
        state.screens = {}
        for i = #screens, 1, -1 do
            UIManager:close(screens[i])
        end
    end

    function Bookbindery:closeAll()
        self:closeScreens()
        if state.home then
            UIManager:close(state.home)
            state.home = nil
        end
    end

    function Bookbindery:push(widget)
        state.screens = state.screens or {}
        table.insert(state.screens, widget)
        UIManager:show(widget)
    end

    -- a screen made stale by a mark-as change redraws when it is on top again
    function Bookbindery:popped(widget)
        local screens = state.screens or {}
        for i, w in ipairs(screens) do
            if w == widget then
                table.remove(screens, i)
                break
            end
        end
        local top = screens[#screens]
        if top and top.bb_stale then
            top.bb_stale = nil
            self:safely("refresh", top.bb_refresh)
        elseif not top and state.home_stale then
            state.home_stale = nil
            self:rebuildHome()
        end
    end

    -- the top screen redraws now (a change made from a sheet over it)
    function Bookbindery:refreshTop()
        local screens = state.screens or {}
        local top = screens[#screens]
        if top and top.bb_refresh then
            top.bb_stale = nil
            self:safely("refresh", top.bb_refresh)
        end
    end

    function Bookbindery:markStale()
        for _i, w in ipairs(state.screens or {}) do
            w.bb_stale = w.bb_refresh ~= nil
        end
        state.home_stale = state.home ~= nil
    end

    -- shows widget in place of old (a rebuilt info screen)
    function Bookbindery:pushReplacing(widget, old)
        self:push(widget)
        if old then
            self:popped(old)
            UIManager:close(old)
        end
    end

    -- scope: the search tab's starting scope
    function Bookbindery:route(tab, scope)
        if tab == "home" then
            self:closeScreens()
            self:showHome()
        elseif tab == "shelves" or tab == "updates" or tab == "search" then
            self:safely(tab, function()
                local t0 = Timing.start()
                local widget = tab == "shelves" and self:shelvesScreen()
                    or tab == "updates" and self:updatesScreen() or self:searchScreen(scope)
                local old_home, old = state.home, state.screens or {}
                state.home, state.screens = nil, {}
                self:push(widget)
                for i = #old, 1, -1 do
                    UIManager:close(old[i])
                end
                if old_home then
                    UIManager:close(old_home)
                end
                Timing.drawn(tab, t0)
            end)
        end
    end

    function Bookbindery:tabScreen(widget)
        widget.close_callback = function()
            self:popped(widget)
            self:showHome()
        end
        return widget
    end

    function Bookbindery:subScreen(widget)
        widget.close_callback = function() self:popped(widget) end
        return widget
    end

    function Bookbindery:pushSub(what, module, opts)
        self:safely(what, function() self:push(self:subScreen(require(module).new(opts))) end)
    end

    local function pinned_shelves()
        return G_reader_settings:readSetting("bookbindery_pinned_shelves") or {}
    end

    function Bookbindery:shelvesScreen()
        local root = books_root()
        local index = library(root) or { list = {}, books = {} }
        local fanfic_n = 0
        for _i, b in ipairs(index.list) do
            if b.lpath:sub(1, 7) == "fanfic/" then
                fanfic_n = fanfic_n + 1
            end
        end
        local tree = Shelves.tree(index)
        local ShelvesScreen = require("bookbindery/bbui/shelvesscreen")
        local widget
        local function opts_of(idx)
            return {
                counts = Shelves.status_counts(idx),
                tree = tree,
                fanfic_n = fanfic_n > 0 and fanfic_n or nil,
                on_status = function(status) self:showShelf(index, "", status) end,
                on_shelf = function(path) self:showTree(index, tree, path) end,
                on_place = function(place) self:openPlace(place) end,
                on_tab = function(tab) self:route(tab) end,
                on_menu = menu(self),
            }
        end
        widget = self:tabScreen(ShelvesScreen.new(opts_of(index)))
        widget.bb_refresh = function()
            widget:update(ShelvesScreen.rows(opts_of(library(root) or index)))
        end
        return widget
    end

    function Bookbindery:showTree(index, tree, path)
        local node = Shelves.find(tree, path)
        if not node then
            return
        end
        if #node.children == 0 then
            return self:showShelf(index, path)
        end
        self:pushSub("shelf tree", "bookbindery/bbui/shelftreescreen", {
            node = node,
            pinned = pinned_shelves(),
            on_pin = function(p, on)
                local out = {}
                for _i, x in ipairs(pinned_shelves()) do
                    if x ~= p then
                        out[#out + 1] = x
                    end
                end
                if on then
                    out[#out + 1] = p
                end
                G_reader_settings:saveSetting("bookbindery_pinned_shelves", out)
                toast(on and _("pinned to the top") or _("unpinned"))
            end,
            on_shelf = function(p) self:showShelf(index, p) end,
            on_menu = menu(self),
        })
    end

    function Bookbindery:showShelf(index, path, status)
        self:pushSub("shelf", "bookbindery/bbui/shelfscreen", {
            index = index,
            path = path,
            status = status,
            books_root = books_root(),
            on_book = function(file) self:openBook(file) end,
            on_info = function(b) self:showInfo(b, _("shelves")) end,
            on_shelf = function(p) self:showShelf(index, p) end,
            on_menu = menu(self),
        })
    end

    -- documents under root .. rel as { name = relative path, time = mtime }
    local function documents(root, rel, recursive)
        local DocumentRegistry = require("document/documentregistry")
        local out = {}
        local function walk(sub)
            local ok, iter, d = pcall(lfs.dir, root .. sub)
            if not ok then
                return
            end
            for name in iter, d do
                if name:sub(1, 1) ~= "." then
                    local path = sub == "" and name or sub .. "/" .. name
                    local attr = lfs.attributes(root .. path)
                    if attr and attr.mode == "directory" and recursive and not name:match("%.sdr$") then
                        walk(path)
                    elseif attr and attr.mode == "file" and DocumentRegistry:hasProvider(root .. path) then
                        out[#out + 1] = { name = path, time = attr.modification }
                    end
                end
            end
        end
        walk(rel)
        return out
    end

    -- every document under books/fanfic, as lpaths
    local function fanfic_files()
        local out = {}
        for _i, d in ipairs(documents(books_root(), "fanfic", true)) do
            out[#out + 1] = d.name
        end
        return out
    end

    function Bookbindery:showFanfic(back)
        self:safely("fanfic", function()
            local t0 = Timing.start()
            local works = nil
            self.fanfic_files = fanfic_files()
            self:pushSub("fanfic", "bookbindery/bbui/fanficscreen", {
                fandoms = Fanfic.fandoms(library(books_root()) or { list = {}, books = {} }, works,
                    self.fanfic_files),
                back = back,
                on_fandom = function(name) self:showFandom(name) end,
                on_menu = menu(self),
            })
            Timing.drawn("fanfic", t0)
        end)
    end

    function Bookbindery:showFandom(name)
        self:safely("fandom", function()
            local t0 = Timing.start()
            local works = nil
            local index = library(books_root()) or { list = {}, books = {} }
            self:pushSub("fandom", "bookbindery/bbui/fandomscreen", {
                fandom = name,
                works = Fanfic.works(index, name, works, self.fanfic_files or fanfic_files(),
                    function(l) return env.status_of(books_root() .. l) end),
                on_book = function(lpath) self:openBook(books_root() .. lpath) end,
                on_info = function(w)
                    self:showInfo(index.books[w.lpath] or { lpath = w.lpath, title = w.title, authors = w.authors,
                        library = "fanfic", tags = {} }, "fanfic · " .. name)
                end,
                on_menu = menu(self),
            })
            Timing.drawn("fandom", t0)
        end)
    end

    function Bookbindery:searchScreen(start_scope)
        local files
        return self:tabScreen(require("bookbindery/bbui/searchscreen").new({
            scope = start_scope,
            books_root = books_root(),
            safe = function(fn) self:safely("search", fn) end,
            run = function(query, scope)
                local t0 = time.monotonic()
                local index = library(books_root()) or { list = {}, books = {} }
                if scope == "fanfic" and not files then
                    files = fanfic_files()
                end
                local groups = nil
                local results = Search.run(query, scope, index, groups, files)
                logger.info("bookbindery: search ran in", math.floor(time.to_ms(time.since(t0))), "ms")
                return results
            end,
            on_book = function(r)
                self:openBook(r.lpath and books_root() .. r.lpath, T(_("not on %1 yet"), Wording.device))
            end,
            on_info = function(r)
                local authors = r.author ~= "" and { r.author } or {}
                self:showInfo(r.entry or { lpath = r.lpath, title = r.title, authors = authors,
                    library = "fanfic", tags = {} }, _("search"))
            end,
            handoff = function(scope, query) return self:searchElsewhere(scope, query) end,
            on_tab = function(tab) self:route(tab) end,
            on_menu = menu(self),
        }))
    end

    -- manga and dictionary show their own results over the search screen; true when one went
    function Bookbindery:searchElsewhere(scope, query)
        if scope ~= "dictionary" and not env.online() then
            toast(_("needs wi-fi"))
        elseif scope == "manga" then
            return self:searchManga(query)
        elseif scope == "dictionary" then
            local fm = require("apps/filemanager/filemanager").instance or self.ui
            local dict = fm and fm.dictionary
            if dict and callable(dict.onLookupWord) then
                dict:onLookupWord(query)
                return true
            end
            toast(_("koreader's dictionary isn't available"))
        end
        return false
    end

    -- wallabag's downloaded articles (Articles.list, each with its status) and its folder
    function Bookbindery:articles()
        local dir = self.ui.wallabag.directory
        if dir:sub(-1) ~= "/" then
            dir = dir .. "/"
        end
        local articles = Articles.list(documents(dir, "", false))
        for _i, a in ipairs(articles) do
            a.status = env.status_of(dir .. a.file)
        end
        return articles, dir
    end

    function Bookbindery:showArticles(back)
        self:safely("articles", function()
            local t0 = Timing.start()
            local articles, dir = self:articles()
            self:pushSub("articles", "bookbindery/bbui/articlesscreen", {
                articles = articles,
                back = back,
                on_article = function(file) self:openBook(dir .. file) end,
                on_menu = menu(self),
            })
            Timing.drawn("articles", t0)
        end)
    end

    function Bookbindery:showFolder(dir)
        if lfs.attributes(dir, "mode") ~= "directory" then
            toast(T(_("%1 isn't on %2"), dir, Wording.device))
            return
        end
        self:closeAll()
        if self.ui.file_chooser then
            self.ui.file_chooser:changeToPath(dir)
        else
            require("apps/filemanager/filemanager"):showFiles(dir)
        end
    end

    function Bookbindery:openPlace(place)
        local root = books_root()
        if place == "fanfic" then
            self:showFanfic()
        elseif place == "all files" then
            self:showFolder(root:sub(1, -2))
        elseif place == "manga" then
            self:showManga()
        elseif place == "articles" then
            local wallabag = self.ui.wallabag
            if not wallabag then
                toast(_("wallabag isn't installed"))
            elseif not wallabag.directory or wallabag.directory == "" then
                toast(_("wallabag has no download folder yet"))
            else
                self:showArticles()
            end
        end
    end
end
