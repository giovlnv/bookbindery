--[[--
Updates tab: what changed in rakuyomi and in wallabag, and the checks. check now on manga is
rakuyomi's own update check; wallabag syncs only on its sync. check all now fetches manga covers,
then runs manga.
]]

local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local callable = require("bookbindery/callable")
local Updates = require("bookbindery/updates")

-- env: library(root), books_root(), toast(text)
return function(Bookbindery, env)

    -- the screen's words and flags, read fresh on every build
    function Bookbindery:updatesData()
        local manga, why = self:mangaLibrary()
        local wallabag = self.ui.wallabag
        local folder = wallabag and wallabag.directory and wallabag.directory ~= ""
        local articles = not wallabag and Updates.missing("wallabag")
            or not folder and _("wallabag has no download folder yet")
            or Updates.articles(self:articles())
        local data = {}
        data.manga = Updates.manga(manga, why)
        data.rakuyomi = self.ui.rakuyomi ~= nil
        data.articles = articles
        data.wallabag = folder and callable(wallabag.onSynchronizeWallabag) or false
        return data
    end

    function Bookbindery:updatesScreen()
        local UpdatesScreen = require("bookbindery/bbui/updatesscreen")
        local widget
        local function rebuild()
            if widget and UIManager:isWidgetShown(widget) then
                self:safely("updates", widget.bb_refresh)
            end
        end
        -- every action runs safely, also once the network is up
        local function safe(fn)
            return function(...)
                local args = { ... }
                self:safely("updates", function() fn(unpack(args)) end)
            end
        end
        local function online(fn)
            return safe(function() NetworkMgr:runWhenOnline(safe(fn)) end)
        end
        local function opts()
            local o = self:updatesData()
            o.on_manga = safe(function() self:checkManga(rebuild) end)
            o.on_sync = online(function()
                self.ui.wallabag:onSynchronizeWallabag()
                rebuild()
            end)
            o.on_check_all = online(function()
                    self:fetchCovers()
                rebuild()
                self:checkManga(rebuild, true)
            end)
            o.on_tab = function(tab) self:route(tab) end
            o.on_menu = function() self:showMenu() end
            return o
        end
        widget = self:tabScreen(UpdatesScreen.new(opts()))
        widget.bb_refresh = function()
            local o = opts()
            widget:update(UpdatesScreen.rows(o), UpdatesScreen.header(o))
        end
        return widget
    end
end
