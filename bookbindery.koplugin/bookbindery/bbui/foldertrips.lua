--[[--
Folder trips: KOReader's deliberate "show folder" and "go to folder" actions raise a flag
while they run (runtime wraps, once each, every function checked first). Only a path change
under that flag closes bookbindery; any other (opds after a download, the file manager's own
setup) keeps it. A file manager started by a trip from the reader doesn't show home.
]]

local UIManager = require("ui/uimanager")
local Comeback = require("bookbindery/comeback")
local callable = require("bookbindery/callable")

-- env: state, shown(), logger
return function(Bookbindery, env)
    local state = env.state

    -- closes bookbindery when a trip is under way and it is shown
    local function close_for_trip(bb)
        if not (bb and Comeback.close_for_folder({ shown = env.shown(), trip = state.folder_trip })) then
            return
        end
        state.return_home = false
        local ok, err = pcall(bb.closeAll, bb)
        if ok then
            env.logger.info("bookbindery: closed for a folder")
        else
            env.logger.err("bookbindery: closing for a folder failed:", err)
        end
    end

    local function live()
        local fm = require("apps/filemanager/filemanager").instance
        return fm and fm.bookbindery
    end

    -- orig with the flag up while it runs (down again on the next tick); after: close once it
    -- returned (wallabag and news rebuild the file manager without a path change)
    local function tripping(orig, after, when)
        return function(...)
            if when and not when(...) then
                return orig(...)
            end
            state.folder_trip = true
            UIManager:nextTick(function() state.folder_trip = false end)
            local result = orig(...)
            if after then
                local ok, err = pcall(function() close_for_trip(live()) end)
                if not ok then
                    env.logger.err("bookbindery: closing for a folder failed:", err)
                end
            end
            return result
        end
    end

    local function wrap(t, key, after, when)
        local mark = "bookbindery_trip_" .. key
        if type(t) == "table" and not rawget(t, mark) and callable(t[key]) then
            t[mark] = true
            t[key] = tripping(t[key], after, when)
        end
    end

    local function loaded(name)
        local ok, m = pcall(require, name)
        return ok and m or nil
    end

    -- KOReader's own: "show folder" buttons (search results, history, collections), a folder in
    -- file search results, a collection's folder list
    local function wrap_koreader()
        local util = loaded("apps/filemanager/filemanagerutil")
        if type(util) == "table" and not rawget(util, "bookbindery_trip")
            and callable(util.genShowFolderButton) then
            util.bookbindery_trip = true
            local orig = util.genShowFolderButton
            util.genShowFolderButton = function(...)
                local button = orig(...)
                if type(button) == "table" and callable(button.callback) then
                    button.callback = tripping(button.callback)
                end
                return button
            end
        end
        wrap(loaded("apps/filemanager/filemanagerfilesearcher"), "onMenuSelect", false,
            function(_self, item) return type(item) == "table" and not item.is_file end)
        wrap(loaded("apps/filemanager/filemanagercollection"), "onCollFolderListChoice")
    end

    -- plugins exist only once the ui has made them all: their classes, through an instance
    local function wrap_plugins(ui)
        local plugins = {
            { ui.wallabag, "onGoToWallabagDirectory" },
            { ui.newsdownloader or ui.news_downloader, "openDownloadsFolder" },
        }
        for _i, p in ipairs(plugins) do
            local class = type(p[1]) == "table" and getmetatable(p[1])
            if type(class) == "table" and rawget(class, p[2]) ~= nil then
                wrap(class, p[2], true)
            end
        end
    end

    function Bookbindery:hookFolderTrips()
        local ok, err = pcall(wrap_koreader)
        if not ok then
            env.logger.err("bookbindery: folder trip hooks failed:", err)
        end
        local ui = self.ui
        local function plugins()
            local pok, perr = pcall(wrap_plugins, ui)
            if not pok then
                env.logger.err("bookbindery: folder trip hooks failed:", perr)
            end
        end
        if type(ui.postInitCallback) == "table" and callable(ui.registerPostInitCallback) then
            ui:registerPostInitCallback(plugins)
        else
            UIManager:nextTick(plugins)
        end
    end

    function Bookbindery:onPathChanged()
        close_for_trip(self)
    end
end
