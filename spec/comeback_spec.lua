local Comeback = require("bookbindery/comeback")

local function with(base, o)
    local s = {}
    for k, v in pairs(base) do
        s[k] = v
    end
    for k, v in pairs(o or {}) do
        s[k] = v
    end
    return s
end

local BARE = { starts_home = true, shown = false, stack = { "file_manager" } }

describe("Comeback.home_after_rakuyomi", function()
    it("shows home when a rakuyomi view left the file manager bare", function()
        assert.is_true(Comeback.home_after_rakuyomi(BARE))
    end)

    it("looks past toasts on top", function()
        assert.is_true(Comeback.home_after_rakuyomi(with(BARE, { stack = { "toast", "toast", "file_manager" } })))
    end)

    it("leaves bookbindery's own screens alone", function()
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { shown = true })))
    end)

    it("waits while another view is on top (the next rakuyomi view, a dialog, the reader)", function()
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { stack = { "other", "file_manager" } })))
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { stack = { "toast", "other", "file_manager" } })))
    end)

    it("does nothing without a file manager", function()
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { stack = { "toast" } })))
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { stack = {} })))
    end)

    it("follows start_with", function()
        assert.is_false(Comeback.home_after_rakuyomi(with(BARE, { starts_home = false })))
    end)
end)

describe("Comeback.close_for_folder", function()
    it("closes bookbindery for a deliberate folder trip", function()
        assert.is_true(Comeback.close_for_folder({ shown = true, trip = true }))
    end)

    it("keeps bookbindery for any other path change (opds after a download, setup)", function()
        assert.is_false(Comeback.close_for_folder({ shown = true, trip = false }))
    end)

    it("does nothing when bookbindery isn't shown", function()
        assert.is_false(Comeback.close_for_folder({ shown = false, trip = true }))
    end)
end)

describe("Comeback.home_on_init", function()
    local START = { trip = false, return_home = false, starts_home = true, first = false, leftover = false }

    it("shows home at boot and after a book", function()
        assert.is_true(Comeback.home_on_init(with(START, { first = true })))
        assert.is_true(Comeback.home_on_init(with(START, { return_home = true, starts_home = false })))
    end)

    it("shows home again over a rebuilt file manager", function()
        assert.is_true(Comeback.home_on_init(with(START, { leftover = true })))
    end)

    it("stays away on a plain file manager", function()
        assert.is_false(Comeback.home_on_init(START))
        assert.is_false(Comeback.home_on_init(with(START, { starts_home = false, first = true })))
    end)

    it("lets a folder trip from the reader land on the folder", function()
        assert.is_false(Comeback.home_on_init(with(START, { trip = true, return_home = true, leftover = true })))
    end)
end)
