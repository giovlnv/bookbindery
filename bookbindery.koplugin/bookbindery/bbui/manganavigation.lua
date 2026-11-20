--[[--
Manga screen and the ways into rakuyomi: its chapter list, its library view and
its sources, reached only through its loaded plugin and modules. rakuyomi's
views show over bookbindery's screens; closing them comes back to the manga screen.
]]

local Event = require("ui/event")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local callable = require("bookbindery/callable")
local Comeback = require("bookbindery/comeback")
local MangaData = require("bookbindery/mangadata")
local Timing = require("bookbindery/timing")
local Updates = require("bookbindery/updates")

local WHY = {
    none = "rakuyomi has no library yet",
    busy = "manga busy, try again",
    error = "manga didn't read, see crash.log",
}

-- env: toast(text), logger, shown(), starts_home()
return function(Bookbindery, env)
    local toast = env.toast

    -- rakuyomi's loaded module when it has fn, else a toast
    local function rakuyomi(self, name, fn)
        local m = package.loaded[name]
        if self.ui.rakuyomi and type(m) == "table" and type(m[fn]) == "function" then
            return m
        end
        toast(Updates.missing("rakuyomi", self.ui.rakuyomi))
    end

    -- MangaData.library(), or nil and why, worded
    function Bookbindery:mangaLibrary()
        if not self.ui.rakuyomi then
            return nil, Updates.missing("rakuyomi")
        end
        local list, why = MangaData.library(self.ui.rakuyomi)
        return list, why and _(WHY[why])
    end

    -- missing manga covers (with bookbindery_manga_covers on) under "fetching manga covers…"
    function Bookbindery:fetchCovers()
        if not G_reader_settings:isTrue("bookbindery_manga_covers") then
            return
        end
        local busy = require("ui/widget/infomessage"):new({ text = _("fetching manga covers…") })
        UIManager:show(busy)
        UIManager:forceRePaint()
        local ok, saved = pcall(MangaData.fetch_covers)
        UIManager:close(busy)
        if not ok then
            env.logger.warn("bookbindery: manga covers failed:", saved)
        elseif saved > 0 then
            env.logger.info("bookbindery: manga covers saved:", saved)
        end
    end

    function Bookbindery:showManga()
        self:safely("manga", function()
            local t0 = Timing.start()
            local widget
            widget = self:subScreen(require("bookbindery/bbui/mangascreen").new({
                load = function() return self:mangaLibrary() end,
                cover_of = MangaData.cover,
                on_manga = function(m) self:openManga(m, widget) end,
                on_rakuyomi = function() self:openRakuyomi() end,
                on_sources = function() self:browseSources(widget) end,
                on_menu = function() self:showMenu() end,
            }))
            self:push(widget)
            Timing.drawn("manga", t0)
        end)
    end

    -- back from a rakuyomi view: the manga screen again, also after a chapter was
    -- read (opening the reader closed bookbindery's screens)
    -- the reader recreates the file manager: act on the live plugin instance
    function Bookbindery:mangaReturned(widget)
        if UIManager:isWidgetShown(widget) then
            self:safely("manga", widget.bb_refresh)
            return
        end
        local fm = require("apps/filemanager/filemanager").instance
        local bb = fm and fm.bookbindery or self
        bb:route("shelves")
        bb:showManga()
    end

    -- rakuyomi's own error dialog when its backend didn't start (read only, never started here)
    local function backend_up(self)
        local Backend = package.loaded["Backend"]
        if type(Backend) == "table" and Backend.server ~= nil then
            return true
        end
        self:openRakuyomi()
        return false
    end

    -- rakuyomi's chapter list or library on top (home waits under them after a manga chapter)
    function Bookbindery.rakuyomiOnTop()
        local top = UIManager:getTopmostVisibleWidget()
        local views = { "ChapterListing", "LibraryView" }
        local mt = type(top) == "table" and getmetatable(top)
        while mt do
            for _i, name in ipairs(views) do
                if package.loaded[name] and mt == package.loaded[name] then
                    return true
                end
            end
            mt = getmetatable(mt)
        end
        return false
    end

    local function is_a(w, class)
        local mt = type(class) == "table" and getmetatable(w)
        while mt do
            if mt == class then
                return true
            end
            mt = getmetatable(mt)
        end
        return false
    end

    -- the window stack, topmost first: the file manager, toasts (invisible widgets, notifications,
    -- timed info messages) or anything else
    local function stack(fm)
        local kinds, windows = {}, UIManager._window_stack or {}
        local Notification = package.loaded["ui/widget/notification"]
        local InfoMessage = package.loaded["ui/widget/infomessage"]
        for i = #windows, 1, -1 do
            local w = type(windows[i]) == "table" and windows[i].widget
            kinds[#kinds + 1] = not w and "toast" or w == fm and "file_manager"
                or (w.invisible or is_a(w, Notification) or (w.timeout and is_a(w, InfoMessage))) and "toast"
                or "other"
        end
        return kinds
    end

    -- a rakuyomi view closed (after a chapter its return callbacks don't reach bookbindery):
    -- home again on the live file manager when it was left bare
    local function rakuyomi_closed()
        local fm = require("apps/filemanager/filemanager").instance
        if not (fm and not fm.tearing_down and fm.bookbindery) then
            return
        end
        local s = { starts_home = env.starts_home(), shown = env.shown(), stack = stack(fm) }
        if Comeback.home_after_rakuyomi(s) then
            fm.bookbindery:showHome()
        end
    end

    -- rakuyomi's library view and search results close every way through onCloseWidget; a tick
    -- after each close (once whatever comes next is shown) rakuyomi_closed decides. rakuyomi's
    -- files stay as they are: its loaded classes are wrapped once.
    function Bookbindery.hookRakuyomi()
        for _i, name in ipairs({ "LibraryView", "MangaSearchResults" }) do
            local view = package.loaded[name]
            if type(view) == "table" and not rawget(view, "bookbindery_hooked") and callable(view.onCloseWidget) then
                local orig = view.onCloseWidget
                view.bookbindery_hooked = true
                view.onCloseWidget = function(...)
                    UIManager:nextTick(function()
                        local ok, err = pcall(rakuyomi_closed)
                        if not ok then
                            env.logger.err("bookbindery: after", name, "closed:", err)
                        end
                    end)
                    return orig(...)
                end
            end
        end
    end

    -- the Manga table rakuyomi's LibraryView gets from its backend, from our row
    function Bookbindery:openManga(m, widget)
        local ChapterListing = rakuyomi(self, "ChapterListing", "fetchAndShow")
        if not ChapterListing or not backend_up(self) then
            return
        end
        local manga = { id = m.manga_id, source = { id = m.source_id, name = m.source }, title = m.title,
            last_read = m.last_read, unread_chapters_count = m.unread, in_library = true }
        Trapper:wrap(function()
            ChapterListing:fetchAndShow(manga, function() self:mangaReturned(widget) end, true)
        end)
    end

    function Bookbindery:openRakuyomi()
        local rk = self.ui.rakuyomi
        if not rk then
            toast(Updates.missing("rakuyomi"))
        elseif not callable(rk.onStartLibraryView) then
            toast(Updates.missing("rakuyomi", true))
        else
            self.ui:handleEvent(Event:new("StartLibraryView"))
        end
    end

    -- rakuyomi's update check (as its library view's "refresh mangas"), waited for under its own job
    -- dialog; done() once it finished. Without its modules or backend it opens rakuyomi, or with
    -- quiet only logs.
    function Bookbindery:checkManga(done, quiet)
        local Backend, Job, Dialog = package.loaded["Backend"], package.loaded["jobs/RefreshLibraryChapters"],
            package.loaded["BasicJobDialog"]
        local ready = self.ui.rakuyomi and type(Backend) == "table" and Backend.server ~= nil
            and type(Job) == "table" and type(Job.new) == "function"
            and type(Dialog) == "table" and type(Dialog.new) == "function"
        if not ready then
            if quiet then
                env.logger.info("bookbindery: manga check skipped, rakuyomi isn't running")
            else
                self:openRakuyomi()
            end
            return
        end
        Trapper:wrap(function()
            local ok, err = pcall(function()
                local job = Job:new()
                if not job then
                    toast(_("manga check didn't start, see crash.log"))
                    return done()
                end
                Dialog:new({
                    job = job,
                    title = _("checking manga…"),
                    success_message = _("manga checked"),
                    error_prefix = _("some manga didn't update"),
                    format_progress = function(data)
                        if type(data) == "table" and data.type == "REFRESHING" then
                            return (data.current or 0) .. " / " .. (data.total or "?")
                        end
                    end,
                    dismiss_callback = done,
                }):show()
            end)
            if not ok then
                env.logger.err("bookbindery: manga check failed:", err)
                toast(_("manga check failed, see crash.log"))
                done()
            end
        end)
    end

    -- rakuyomi's own search results over the search screen (all its sources); true when it went
    function Bookbindery:searchManga(query)
        local Results = rakuyomi(self, "MangaSearchResults", "searchAndShow")
        if not (Results and backend_up(self)) then
            return false
        end
        Trapper:wrap(function()
            Results:searchAndShow(query, nil, function() end)
        end)
        return true
    end

    function Bookbindery:browseSources(widget)
        local Sources = rakuyomi(self, "InstalledSourcesListing", "fetchAndShow")
        if Sources and backend_up(self) then
            Trapper:wrap(function()
                Sources:fetchAndShow(function() self:mangaReturned(widget) end)
            end)
        end
    end
end
