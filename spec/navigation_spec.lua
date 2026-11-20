-- KOReader's modules faked: navigation only needs UIManager's show and close here
local closed = {}
package.loaded["ui/uimanager"] = {
    show = function() end,
    close = function(_self, w) closed[#closed + 1] = w end,
}
package.loaded["ui/event"] = {}
package.loaded["ui/time"] = {}
package.loaded["logger"] = {}
package.loaded["libs/libkoreader-lfs"] = {}
package.loaded["ffi/util"] = { template = function(s) return s end }
package.loaded["gettext"] = function(s) return s end

local function plugin()
    local state = {}
    local Bookbindery = { rebuilt = 0 }
    require("bookbindery/bbui/navigation")(Bookbindery, { state = state, toast = function() end,
        logger = { err = function() end } })
    function Bookbindery:rebuildHome()
        self.rebuilt = self.rebuilt + 1
    end
    return Bookbindery, state
end

local function screen(name, refreshable)
    local w = { name = name, refreshed = 0 }
    if refreshable then
        w.bb_refresh = function() w.refreshed = w.refreshed + 1 end
    end
    return w
end

describe("navigation#stale", function()
    before_each(function()
        closed = {}
    end)

    it("refreshes only the screen that is on top again", function()
        local B, state = plugin()
        local shelves, shelf, info = screen("shelves", true), screen("shelf", true), screen("info")
        B:push(shelves)
        B:push(shelf)
        B:push(info)
        B:markStale()
        B:popped(info)
        assert.equal(1, shelf.refreshed)
        assert.equal(0, shelves.refreshed)
        assert.is_true(shelves.bb_stale)
        B:popped(shelf)
        assert.equal(1, shelves.refreshed)
        assert.same({ shelves }, state.screens)
    end)

    it("rebuilds home only when it is stale", function()
        local B, state = plugin()
        state.home = {}
        local info = screen("info")
        B:push(info)
        B:popped(info)
        assert.equal(0, B.rebuilt)
        B:push(info)
        B:markStale()
        B:popped(info)
        assert.equal(1, B.rebuilt)
    end)

    it("replaces a screen without refreshing the replacement", function()
        local B, state = plugin()
        local shelf, old, new = screen("shelf", true), screen("info"), screen("info", true)
        B:push(shelf)
        B:push(old)
        B:markStale()
        B:pushReplacing(new, old)
        assert.same({ shelf, new }, state.screens)
        assert.same({ old }, closed)
        assert.equal(0, new.refreshed)
        assert.equal(0, shelf.refreshed)
    end)

    it("closes sheets and dialogs with the screens", function()
        local B, state = plugin()
        local sheet, dialog = {}, {}
        B:push(screen("info"))
        B:showOverlay(sheet)
        B:showOverlay(dialog)
        B:overlayClosed(sheet)
        B:closeAll()
        assert.same({}, state.overlays)
        assert.equal(dialog, closed[1])
    end)
end)
