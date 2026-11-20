local cjson = require("cjson")
local Library = require("bookbindery/library")
local BookInfo = require("bookbindery/bookinfo")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local index = assert(Library.parse(slurp("spec/fixtures/metadata.calibre.json"), cjson.decode))

local function book(id)
    for _, b in ipairs(index.list) do
        if b.id == id and b.library == "books" then
            return b
        end
    end
end

local function value(rows, label)
    for _, r in ipairs(rows) do
        if r.label == label then
            return r.value
        end
    end
end

local NOW = os.time({ year = 2026, month = 11, day = 19, hour = 12 })
local DAY = 86400

describe("BookInfo#stats", function()
    it("totals time, counts sessions split by 30 min gaps, caps the pace per page", function()
        local t = NOW - 10 * DAY
        local rows = {
            { page = 1, start_time = t, duration = 60, total_pages = 100 },
            { page = 2, start_time = t + 60, duration = 600, total_pages = 100 },
            { page = 3, start_time = t + 3 * 3600, duration = 60, total_pages = 100 },
            { page = 3, start_time = t + 3 * 3600 + 60, duration = 30, total_pages = 100 },
            { page = 8, start_time = t + 2 * DAY, duration = 90, total_pages = 200 },
        }
        local s = BookInfo.stats(rows, 200)
        assert.equal(840, s.time)
        assert.equal(3, s.sessions)
        assert.equal(t, s.first)
        -- as statistics' page_stat view: rows rescaled to 200 pages, durations split, capped at 120 s a page
        assert.equal((30 + 30 + 120 + 120 + 45 + 45 + 90) / 7, s.pace)
    end)

    it("handles a long read: 10000 rows", function()
        local rows = {}
        for i = 1, 10000 do
            rows[i] = { page = i % 500 + 1, start_time = NOW - 20000 * 60 + i * 60, duration = 30, total_pages = 500 }
        end
        local s = BookInfo.stats(rows, 500)
        assert.equal(300000, s.time)
        assert.equal(1, s.sessions)
        assert.equal(120, s.pace)
    end)

    it("rows without total_pages fall back to the book's pages, or count only time", function()
        local t = NOW - DAY
        local s = BookInfo.stats({ { page = 1, start_time = t, duration = 50, total_pages = 0 },
            { page = 2, start_time = t + 50, duration = 70 } }, 100)
        assert.equal(120, s.time)
        assert.equal(60, s.pace)
        local none = BookInfo.stats({ { page = 1, start_time = t, duration = 50, total_pages = 0 } }, nil)
        assert.equal(50, none.time)
        assert.is_nil(none.pace)
    end)

    it("is nil without rows", function()
        assert.is_nil(BookInfo.stats({}, 100))
        assert.is_nil(BookInfo.stats(nil, 100))
    end)
end)

describe("BookInfo#model", function()
    it("a rated book: rating out of 5, year, pages, shelf chip, no rows of its own", function()
        local m = BookInfo.model(book(4), nil, nil, NOW)
        assert.equal("Great Expectations", m.title)
        assert.equal("Charles Dickens", m.authors)
        assert.equal("★ 4 · 1861 · 505 pages", m.meta)
        assert.equal("to read", m.status)
        assert.equal("fiction · classics · dickens", m.shelf)
        assert.equal("not started", value(m.rows, "progress"))
        assert.is_nil(value(m.rows, "time read"))
        assert.is_nil(value(m.rows, "left"))
        assert.equal("none", value(m.rows, "highlights"))
        assert.equal("start reading", m.action)
        assert.equal(0, m.highlights)
        assert.equal("none", value(m.details, "series"))
        assert.equal("#4", value(m.details, "calibre"))
    end)

    it("cuts a long about short, without markup", function()
        local m = BookInfo.model(book(1), nil, nil, NOW)
        assert.equal("★ 5 · 1813 · 432 pages", m.meta)
        assert.equal("read", m.status)
        assert.is_true(#m.about <= 303)
        assert.is_true(m.about_more)
        assert.is_nil(m.about:find("<"))
        assert.truthy(m.full:find("\n\n", 1, true))
    end)

    it("names the series and the volume", function()
        assert.equal("Chronicles of Barsetshire #2", value(BookInfo.model(book(9), nil, nil, NOW).details,
            "series"))
    end)

    it("half stars keep one decimal", function()
        local rated = setmetatable({ rating = 7 }, { __index = book(4) })
        assert.equal("★ 3.5 · 1861 · 505 pages", BookInfo.model(rated, nil, nil, NOW).meta)
    end)

    it("an unrated book hides the rating; reading with progress, time and pace", function()
        local t = os.time({ year = 2026, month = 9, day = 1, hour = 20 })
        local read = { opened = true, percent = 0.02, pages = 1577, page = 33, highlights = 4, notes = 1,
            ext = "epub", size = 2.1 * 1024 * 1024, language = "en",
            added = os.time({ year = 2026, month = 11, day = 10 }) }
        local stats = { time = 2 * 3600 + 600, sessions = 3, first = t, pace = 72 }
        local m = BookInfo.model(book(13), read, stats, NOW)
        assert.equal("1859 · 502 pages", m.meta)
        assert.equal("reading", m.status)
        assert.equal("nonfiction · science", m.shelf)
        assert.equal("page 33 of 1577 · 2%", value(m.rows, "progress"))
        assert.equal("2h 10m · 3 sessions", value(m.rows, "time read"))
        assert.equal("about 31h at your pace", value(m.rows, "left"))
        assert.equal("4 · 1 note", value(m.rows, "highlights"))
        assert.equal("continue reading", m.action)
        assert.equal(4, m.highlights)
        assert.equal("none", value(m.details, "series"))
        assert.equal("english", value(m.details, "language"))
        assert.equal("epub · 2.1 MB", value(m.details, "file"))
        assert.equal("10 nov 2026", value(m.details, "added"))
        assert.equal("1 sep 2026", value(m.details, "first opened"))
        assert.equal("#13", value(m.details, "calibre"))
    end)

    it("short time and pace; a finished book has no time left", function()
        local read = { opened = true, percent = 1, pages = 85, page = 85, status = "complete" }
        local m = BookInfo.model(book(13), read, { time = 45 * 60, sessions = 1, pace = 60 }, NOW)
        assert.equal("45m · 1 session", value(m.rows, "time read"))
        assert.is_nil(value(m.rows, "left"))
        local m2 = BookInfo.model(book(13), { opened = true, percent = 0.5, pages = 100, page = 50 },
            { time = 600, sessions = 2, pace = 60 }, NOW)
        assert.equal("about 50m at your pace", value(m2.rows, "left"))
    end)

    it("falls back to the sidecar status without a calibre status", function()
        local b = setmetatable({ status = false }, { __index = book(13) })
        local m = BookInfo.model(b, { opened = true, status = "complete", percent = 1 }, nil, NOW)
        assert.equal("read", m.status)
        local never = BookInfo.model(b, nil, nil, NOW)
        assert.equal("not started", never.status)
    end)
end)
