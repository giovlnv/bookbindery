--[[--
The menu: bookbindery's menu screen over KOReader's live file manager menu
(Menus.inventory + Menus.place, rebuilt on every open). A KOReader submenu opens
in KOReader's own TouchMenu over the menu screen, a tab row opens KOReader's menu
at that tab, a callback runs (checkboxes keep the screen and redraw it). In the
reader, KOReader's own menu. Installed on the plugin by main.lua.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Menus = require("bookbindery/menus")
local Timing = require("bookbindery/timing")

-- env: state, toast
return function(Bookbindery, env)
    local state, toast = env.state, env.toast

    local function fm_menu()
        local fm = require("apps/filemanager/filemanager").instance
        return fm and fm.menu
    end

    local function shown(widget)
        for _i, w in ipairs(state.screens or {}) do
            if w == widget then
                return true
            end
        end
        return false
    end

    function Bookbindery:showKoreaderMenu(tab_index)
        local menu = fm_menu() or (self.ui and self.ui.menu)
        if menu then
            menu:onShowMenu(tab_index)
        end
    end

    function Bookbindery:showMenu()
        local menu = fm_menu()
        if not menu then
            return self:showKoreaderMenu()
        end
        local screens = state.screens or {}
        local top = screens[#screens]
        if top and top.bb_menu then
            return top:onClose()
        end
        for i = #screens - 1, 1, -1 do
            if screens[i].bb_menu then
                -- already open below: close what's above it instead of opening a second
                while #screens > i do
                    local n, w = #screens, screens[#screens]
                    pcall(w.onClose, w)
                    if #screens == n then
                        table.remove(screens, n)
                        UIManager:close(w)
                    end
                end
                return
            end
        end
        self:safely("menu", function()
            local t0 = Timing.start()
            if menu.tab_item_table == nil then
                menu:setUpdateItemTable()
            end
            local inventory, items = Menus.inventory(menu.tab_item_table)
            local by_id = {}
            for _i, e in ipairs(inventory) do
                by_id[e.id] = e
            end
            local widget
            widget = self:subScreen(require("bookbindery/bbui/menuscreen").new({
                tabs = Menus.place(inventory),
                tab = G_reader_settings:readSetting("bookbindery_menu_tab"),
                status = function(r)
                    if r.id then
                        return Menus.status(items[r.id])
                    end
                    return true
                end,
                on_tab = function(name)
                    G_reader_settings:saveSetting("bookbindery_menu_tab", name)
                end,
                on_row = function(r)
                    self:safely("menu entry", function()
                        self:openMenuRow(widget, r, { menu = menu, items = items, by_id = by_id })
                    end)
                end,
            }))
            widget.bb_menu = true
            self:push(widget)
            Timing.drawn("menu", t0)
        end)
    end

    -- what KOReader's TouchMenu passes its callbacks, acting on the menu screen
    local function instance(widget)
        local function close()
            if widget and shown(widget) then
                widget:onClose()
            end
        end
        return {
            item_table = {},
            item_table_stack = {},
            page = 1,
            updateItems = function()
                if widget and shown(widget) then
                    widget.bb_refresh()
                end
            end,
            closeMenu = close,
            onClose = close,
            backToUpperMenu = close,
        }
    end

    -- KOReader's TouchMenu with one tab holding sub; Back at its top closes it to the menu screen
    function Bookbindery:showSubmenu(menu, sub, icon)
        local tab = {}
        for k, v in pairs(sub) do
            tab[k] = v
        end
        tab.icon = icon or "appbar.menu"
        local container = CenterContainer:new({ ignore = "height", dimen = Screen:getSize() })
        local tm = require("ui/widget/touchmenu"):new({
            width = Screen:getWidth(),
            tab_item_table = { tab },
            show_parent = container,
            last_index = 1,
        })
        -- KOReader's own close (onCloseFileManagerMenu) saves last_index as its menu's tab
        tm.last_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
        local function release()
            if menu.menu_container == container then
                menu.menu_container = nil
            end
        end
        tm.close_callback = function()
            release()
            UIManager:close(container)
        end
        -- a close that skips close_callback (rotation rebuilds the container, switchMenuTab
        -- swaps tabs) must not leave menu.menu_container pointing at this one
        local on_close = container.onCloseWidget
        container.onCloseWidget = function(this, ...)
            release()
            if on_close then
                return on_close(this, ...)
            end
        end
        container[1] = tm
        menu.menu_container = container
        UIManager:show(container)
    end

    local BB = {
        home = function(self) self:route("home") end,
        shelves = function(self) self:route("shelves") end,
        fanfic = function(self) self:showFanfic() end,
        manga = function(self) self:showManga() end,
        articles = function(self) self:openPlace("articles") end,
        koreader_menu = function(self) self:showKoreaderMenu() end,
    }

    -- rows that open over the menu screen, which stays under them
    local KEEP = { settings = function(self) self:showSettings() end }

    -- live: menu (FileManagerMenu), items and by_id (inventory entries) by id
    function Bookbindery:openMenuRow(widget, r, live)
        if r.bb and KEEP[r.bb] then
            return KEEP[r.bb](self)
        end
        if r.bb then
            if not BB[r.bb] then
                return
            end
            widget:onClose()
            BB[r.bb](self)
            return
        end
        local item, e = live.items[r.id], live.by_id[r.id]
        if not item then
            toast(_("not available"))
            return
        end
        if e.id == e.tab then
            for i, t in ipairs(live.menu.tab_item_table) do
                if t.id == e.id then
                    return live.menu:onShowMenu(i)
                end
            end
        end
        local sub = item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
        if sub then
            if #sub > 0 then
                local t = live.items[e.tab]
                self:showSubmenu(live.menu, sub, t and t.icon)
            end
            return
        end
        local callback = item.callback_func and item.callback_func() or item.callback
        if not callback then
            return
        end
        -- TouchMenu's own test for a row that keeps the menu open
        if item.checked or item.checked_func or item.keep_menu_open then
            callback(instance(widget))
            if shown(widget) then
                widget.bb_refresh()
            end
        else
            -- close the menu screen first so what the callback opens (KOReader dialogs,
            -- the file browser, a book) lands on bookbindery's stack, not under the menu screen
            widget:onClose()
            callback(instance(nil))
        end
    end

    -- bookbindery settings, a sub-screen over the menu screen
    function Bookbindery:showSettings()
        self:safely("settings", function()
            local t0 = Timing.start()
            local Settings = require("bookbindery/settings")
            local widget
            local function build()
                local rows = Settings.rows({
                    covers = G_reader_settings:isTrue("bookbindery_manga_covers"),
                    pinned = #(G_reader_settings:readSetting("bookbindery_pinned_shelves") or {}),
                    build = require("bookbindery/build").stamp,
                })
                local act = {
                    covers = function()
                        G_reader_settings:flipNilOrFalse("bookbindery_manga_covers")
                        widget.bb_refresh()
                    end,
                    pins = function() self:confirmClearPins(widget) end,
                }
                for _i, r in ipairs(rows) do
                    if r.id then
                        r.callback = function()
                            self:safely("settings", act[r.id])
                        end
                    end
                end
                return rows
            end
            widget = self:subScreen(require("bookbindery/bbui/settingsscreen").new({ rows = build() }))
            widget.bb_refresh = function()
                widget:update(require("bookbindery/bbui/settingsscreen").rows(build()))
            end
            self:push(widget)
            Timing.drawn("settings", t0)
        end)
    end

    function Bookbindery:confirmClearPins(widget)
        local ConfirmBox = require("ui/widget/confirmbox")
        self:showOverlay(ConfirmBox:new({
            text = _("clear all pinned shelves?"),
            ok_text = _("clear"),
            cancel_text = _("cancel"),
            ok_callback = function()
                G_reader_settings:saveSetting("bookbindery_pinned_shelves", {})
                toast(_("pins cleared"))
                if shown(widget) then
                    widget.bb_refresh()
                end
            end,
        }))
    end
end
