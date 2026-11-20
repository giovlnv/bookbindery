local ThemePatch = require("bookbindery/themepatch")

local function guard()
    local lines = {}
    return ThemePatch.guard(function(m) lines[#lines + 1] = m end), lines
end

describe("ThemePatch.guard", function()
    it("install logs one off line and keeps going", function()
        local g, lines = guard()
        assert.is_false(g.install("fonts", function() error("boom", 0) end))
        assert.is_true(g.install("sizes", function() end))
        assert.same({ "bookbindery-theme: fonts off: boom" }, lines)
    end)

    it("wrap runs the original once with its results, before and after hooks", function()
        local g = guard()
        local seen = {}
        local t = { f = function(self, a) seen[#seen + 1] = "orig " .. a; return a * 2, "x" end }
        g.wrap("part", t, "f", function(self, a)
            seen[#seen + 1] = "before " .. a
            return function() seen[#seen + 1] = "after" end
        end)
        local r1, r2 = t:f(3)
        assert.equals(6, r1)
        assert.equals("x", r2)
        assert.same({ "before 3", "orig 3", "after" }, seen)
    end)

    it("a raising hook falls back to the original and turns the part off once", function()
        local g, lines = guard()
        local calls, hooks = 0, 0
        local t = { f = function() calls = calls + 1; return "ok" end }
        g.wrap("touchmenu", t, "f", function() hooks = hooks + 1; error("bad", 0) end)
        assert.equals("ok", t.f())
        assert.equals("ok", t.f())
        assert.equals(2, calls)
        assert.equals(1, hooks)
        assert.same({ "bookbindery-theme: touchmenu off: bad" }, lines)
    end)

    it("a raising after() keeps the original's results", function()
        local g, lines = guard()
        local t = { f = function() return 1 end }
        g.wrap("keyboard", t, "f", function() return function() error("late", 0) end end)
        assert.equals(1, t.f())
        assert.equals(1, #lines)
    end)

    it("the original's error still raises, after() still runs", function()
        local g, lines = guard()
        local restored = false
        local t = { f = function() error("koreader's", 0) end }
        g.wrap("keyboard", t, "f", function() return function() restored = true end end)
        local ok, err = pcall(t.f)
        assert.is_false(ok)
        assert.equals("koreader's", err)
        assert.is_true(restored)
        assert.same({}, lines)
    end)

    it("wrap refuses a missing method", function()
        local g = guard()
        assert.has_error(function() g.wrap("p", {}, "nope", function() end) end)
    end)
end)

describe("ThemePatch.fonts", function()
    local all = function() return true end

    it("maps UI keys to Inter, bold keys to SemiBold", function()
        local m = ThemePatch.fonts(nil, all)
        assert.equals(ThemePatch.REGULAR, m.cfont)
        assert.equals(ThemePatch.REGULAR, m.smallinfofont)
        assert.equals(ThemePatch.BOLD, m.tfont)
        assert.is_nil(m.infont)
        assert.is_nil(m.scfont)
    end)

    it("keeps keys set in settings", function()
        local m = ThemePatch.fonts({ cfont = "Mine.ttf" }, all)
        assert.is_nil(m.cfont)
        assert.equals(ThemePatch.REGULAR, m.ffont)
    end)

    it("nothing without the font files", function()
        assert.same({}, ThemePatch.fonts(nil, function() return false end))
        assert.same({}, ThemePatch.fonts(nil, function(f) return f == ThemePatch.REGULAR end))
    end)
end)

describe("ThemePatch.primaries", function()
    it("is_enter_default and the ok text", function()
        local rows = { { { text = "cancel" }, { text = "add", is_enter_default = true } } }
        assert.same({ add = true }, ThemePatch.primaries(rows))
        assert.same({ clear = true }, ThemePatch.primaries({ { { text = "cancel" }, { text = "clear" } } }, "clear"))
        assert.same({}, ThemePatch.primaries({ { { text = "cancel" } } }, "OK"))
        assert.same({}, ThemePatch.primaries(nil))
    end)

    it("the ok text once, plus every is_enter_default", function()
        local rows = {
            { { text = "OK" }, { text = "OK" } },
            { { text = "go", is_enter_default = true }, { text = "save", is_enter_default = true } },
        }
        local p = ThemePatch.primaries(rows, "OK")
        assert.same({ OK = true, go = true, save = true }, p)
    end)

    it("an ok text that isn't in the table marks nothing", function()
        assert.same({}, ThemePatch.primaries({ { { text = "cancel" }, { text = "close" } } }, "OK"))
    end)
end)
