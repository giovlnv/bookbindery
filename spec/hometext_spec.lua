local HomeText = require("bookbindery/hometext")

local function at(y, m, d, h, mi)
    return os.time({ year = y, month = m, day = d, hour = h, min = mi })
end

local now = at(2026, 11, 19, 2, 32)

describe("HomeText", function()
    it("date line with days read", function()
        assert.equals("thursday, 19 nov · 02:32 · 8 days read this month", HomeText.date_line(now, 8))
        assert.equals("thursday, 19 nov · 02:32 · 1 day read this month", HomeText.date_line(now, 1))
        assert.equals("thursday, 19 nov · 02:32", HomeText.date_line(now, nil))
    end)

    it("last read is today, yesterday or a date", function()
        assert.equals("today 01:05", HomeText.when(at(2026, 11, 19, 1, 5), now))
        assert.equals("yesterday 22:09", HomeText.when(at(2026, 11, 18, 22, 9), now))
        assert.equals("16 nov", HomeText.when(at(2026, 11, 16, 9, 0), now))
        assert.equals("yesterday 23:00", HomeText.when(at(2026, 11, 30, 23, 0), at(2026, 12, 1, 8, 0)))
    end)

    it("progress line", function()
        local row = { page = 33, pages = 1577, percent = 0.021, last_read = at(2026, 11, 18, 22, 9) }
        assert.equals("page 33 of 1577 · 2% · yesterday 22:09", HomeText.progress(row, now))
        assert.equals("0%", HomeText.progress({}, now))
    end)

    it("byline from author and shelf", function()
        local book = { authors = { "Jane Austen" }, types = { "fiction.classics" } }
        assert.equals("Jane Austen · fiction · classics", HomeText.byline({ book = book }))
        assert.equals("fiction · classics", HomeText.shelf({ types = { "fiction.classics" } }))
        assert.equals("", HomeText.byline({}))
        assert.equals("Jane Austen · page 12 of 135 · 9%",
            HomeText.more({ book = book, page = 12, pages = 135, percent = 0.09 }))
    end)

    it("saved time", function()
        assert.equals("01:00", HomeText.saved(at(2026, 11, 19, 1, 0), now))
        assert.equals("18 nov 23:40", HomeText.saved(at(2026, 11, 18, 23, 40), now))
    end)

    it("clock hands", function()
        assert.same({ 0, 0 }, { HomeText.clock(12, 0) })
        assert.same({ 76, 192 }, { HomeText.clock(2, 32) })
        assert.same({ 345, 180 }, { HomeText.clock(23, 30) })
        local x, y = HomeText.hand(28, 28, 10, 90)
        assert.is_true(math.abs(x - 38) < 1e-9 and math.abs(y - 28) < 1e-9)
    end)
end)
