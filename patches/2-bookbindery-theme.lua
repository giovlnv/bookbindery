--[[--
bookbindery theme: KOReader's touch menus, button tables, confirm and input
dialogs and the keyboard in bookbindery's look (Inter, 4/8/16/24, radius 10,
black and white, the current menu tab black). Every part is wrapped: a part
that fails logs "bookbindery-theme: <part> off: <err>" and leaves KOReader's own.
]]

local ok_all, err_all = pcall(function()
    local logger = require("logger")
    local lfs = require("libs/libkoreader-lfs")
    local DataStorage = require("datastorage")

    local helper = "/bookbindery.koplugin/bookbindery/themepatch.lua"
    local ThemePatch
    for _i, dir in ipairs({ DataStorage:getDataDir() .. "/plugins", "plugins" }) do
        if not ThemePatch and lfs.attributes(dir .. helper, "mode") == "file" then
            ThemePatch = dofile(dir .. helper)
        end
    end
    if not ThemePatch then
        logger.warn("bookbindery-theme: off: bookbindery plugin not found")
        return
    end
    local g = ThemePatch.guard(function(msg) logger.warn(msg) end)

    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Screen = require("device").screen
    local Size = require("ui/size")
    local userpatch = require("userpatch")

    local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    local GREY = Blitbuffer.COLOR_LIGHT_GRAY
    local RULE = Blitbuffer.Color8(0xc8)
    local S = function(n) return Screen:scaleBySize(n) end
    local RADIUS = S(10)
    local SPACE = { S(4), S(8), S(16), S(24) }
    local LINE = math.max(1, S(1))
    local BORDER = math.max(1, S(1.5))

    local inter = false
    g.install("fonts", function()
        local FontList = require("fontlist")
        local have = function(file)
            return lfs.attributes(FontList.fontdir .. "/" .. file, "mode") == "file"
        end
        local user = G_reader_settings and G_reader_settings:readSetting("fontmap")
        local map = ThemePatch.fonts(user, have)
        if next(map) == nil then
            return
        end
        Font.bold_font_variant[ThemePatch.REGULAR] = ThemePatch.BOLD
        Font.regular_font_variant[ThemePatch.BOLD] = ThemePatch.REGULAR
        for key, file in pairs(map) do
            Font.fontmap[key] = file
        end
        inter = true
    end)

    g.install("sizes", function()
        Size.radius.window = RADIUS
        Size.radius.button = RADIUS
    end)

    g.install("touchmenu", function()
        local TouchMenu = require("ui/widget/touchmenu")
        local TouchMenuItem = userpatch.getUpValue(TouchMenu.updateItems, "TouchMenuItem")
        local TouchMenuBar = userpatch.getUpValue(TouchMenu.init, "TouchMenuBar")
        assert(TouchMenuItem and TouchMenuBar, "touchmenu internals changed")
        if inter then
            TouchMenuItem.face = Font:getFace("smallinfofont", 17)
            TouchMenu.fface = Font:getFace("ffont", 14)
        end
        TouchMenu.padding = SPACE[2]
        TouchMenu.split_color = RULE
        TouchMenu.split_height = LINE
        -- one rule under the tabs, the current tab a black cell
        g.wrap("touchmenu", TouchMenuBar, "paintTo", function(self, bb, x, y)
            if self.bar_sep then
                self.bar_sep.empty_segments = nil
            end
            for _i, sep in ipairs(self.icon_seps or {}) do
                sep.style = "none"
            end
            return function()
                local ib = self.menu and self.icon_widgets[self.menu.cur_tab]
                if ib and ib.dimen and ib.dimen.x then
                    bb:invertRect(ib.dimen.x, y, ib.dimen.w, self.height)
                end
            end
        end)
    end)

    -- buttons built by a ButtonTable: outlined, radius 10, the primary one black
    local state = {}
    local function restyle(button)
        local frame = button[1]
        if not frame or not button._bb_style then
            return
        end
        frame.bordersize = BORDER
        frame.radius = RADIUS
        frame.color = BLACK
        frame.padding_top = math.max(0, button.padding_v - BORDER)
        frame.padding_bottom = frame.padding_top
        frame.padding_left = math.max(0, button.padding_h - BORDER)
        frame.padding_right = frame.padding_left
        local bg = button._bb_style == "primary" and BLACK or WHITE
        frame.background = bg
        button.background = bg -- so KOReader's tap highlight keeps the corners
        if button._bb_style == "primary" then
            local label = button.label_widget
            label.fgcolor = button.enabled and WHITE or GREY
            if label.bgcolor then
                label.bgcolor = BLACK
            end
            if label.update then
                label:update()
            end
        end
    end

    g.install("buttons", function()
        local Button = require("ui/widget/button")
        local ButtonTable = require("ui/widget/buttontable")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local LineWidget = require("ui/widget/linewidget")
        ButtonTable.sep_width = SPACE[2]

        -- the table is inset by 8 on each side (and 4 below) inside the same width
        g.wrap("buttons", ButtonTable, "init", function(self)
            local prev = state.primary
            state.primary = ThemePatch.primaries(self.buttons, state.confirm_ok)
            local outer = not self._bb_inset and self.width and self.width > 4 * SPACE[3]
            if outer then
                self._bb_inset = true
                self.width = self.width - 2 * SPACE[2]
            end
            return function()
                state.primary = prev
                if outer then
                    self._bb_inset = nil
                    self.width = self.width + 2 * SPACE[2]
                    if self[1] == self.container then
                        self[1] = FrameContainer:new({
                            bordersize = 0, padding = 0, padding_bottom = SPACE[1],
                            padding_left = SPACE[2], padding_right = SPACE[2],
                            self.container,
                        })
                    end
                end
                local function whiten(w)
                    if getmetatable(w) == LineWidget and w.background ~= BLACK then
                        w.background = WHITE
                    end
                end
                for _i, w in ipairs(self.container or {}) do
                    whiten(w)
                    for _j, c in ipairs(w) do
                        whiten(c)
                    end
                end
            end
        end)

        g.wrap("buttons", Button, "init", function(self)
            local primary = state.primary
            return function()
                if not self._bb_style and primary and self.text and not self.menu_style
                        and not self.background and self.align ~= "left" then
                    self._bb_style = primary[self.text] and "primary" or "outline"
                end
                restyle(self)
            end
        end)

        for _i, name in ipairs({ "enable", "disable", "disableWithoutDimming" }) do
            g.wrap("buttons", Button, name, function(self)
                return function()
                    if self._bb_style == "primary" then
                        restyle(self)
                    end
                end
            end)
        end

        -- KOReader drops the radius after its tap highlight: put it back
        g.wrap("buttons", Button, "_undoFeedbackHighlight", function(self)
            return function()
                if self._bb_style and self[1].radius ~= RADIUS then
                    self[1].radius = RADIUS
                    if self[1].dimen then
                        require("ui/uimanager"):widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                    end
                end
            end
        end)
    end)

    -- with "buttons" off, a styled button re-init (setText) goes back to KOReader's own
    g.install("buttons-fallback", function()
        g.wrap("buttons-fallback", require("ui/widget/button"), "init", function(self)
            if g.off.buttons and self._bb_style then
                self._bb_style = nil
                self.background = nil
            end
        end)
    end)

    g.install("confirmbox", function()
        local ConfirmBox = require("ui/widget/confirmbox")
        if inter then
            ConfirmBox.face = Font:getFace("infofont")
        end
        g.wrap("confirmbox", ConfirmBox, "init", function(self)
            local prev = state.confirm_ok
            state.confirm_ok = not self.no_ok_button and self.ok_text or nil
            return function()
                state.confirm_ok = prev
            end
        end)
    end)

    g.install("inputtext", function()
        local InputText = require("ui/widget/inputtext")
        if inter then
            InputText.face = Font:getFace("smallinfofont")
        end
        g.wrap("inputtext", InputText, "initTextBox", function(self)
            return function()
                if self._frame_textwidget then
                    self._frame_textwidget.radius = RADIUS
                end
            end
        end)
    end)

    g.install("keyboard", function()
        local VirtualKeyboard = require("ui/widget/virtualkeyboard")
        local VirtualKey = userpatch.getUpValue(VirtualKeyboard.addKeys, "VirtualKey")
        assert(VirtualKey, "keyboard internals changed")
        VirtualKeyboard.key_padding = SPACE[1]
        VirtualKeyboard.padding = SPACE[1]

        -- Inter labels, white keys with a black outline, black when on (shift, symbols)
        g.wrap("keyboard", VirtualKey, "init", function(self)
            self.bordersize = LINE
            self.radius = SPACE[1]
            local infont = Font.fontmap.infont
            if inter then
                Font.fontmap.infont = ThemePatch.REGULAR
            end
            return function()
                Font.fontmap.infont = infont
                local frame = self[1]
                frame.radius = SPACE[1]
                if frame.background == GREY then
                    frame.background = WHITE
                    self._bb_on = true
                end
                frame.invert = self._bb_on or false
            end
        end)

        -- pressed: black (white when the key is on), no inner border
        g.wrap("keyboard", VirtualKey, "invert", function(self, invert)
            self[1].invert = (invert and true or false) ~= (self._bb_on or false)
            local focused = self.focused_bordersize
            self.focused_bordersize = 0
            return function()
                self.focused_bordersize = focused
            end
        end)

        g.wrap("keyboard", VirtualKeyboard, "addKeys", function(self)
            return function()
                local frame = self[1] and self[1][1]
                if frame and frame.background then
                    frame.background = WHITE
                end
            end
        end)
    end)

    logger.info("bookbindery-theme: on, Inter " .. (inter and "on" or "off (fonts missing)"))
end)

if not ok_all then
    pcall(function() require("logger").warn("bookbindery-theme: patch off: " .. tostring(err_all)) end)
end
