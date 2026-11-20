local ReadState = require("bookbindery/readstate")

local history = {
    { time = 1790000000, file = "/koreader/help/quickstart.html" },
    { time = 1789900000, file = "/books/Dickens, Charles/Bleak House.epub" },
    { time = 1789800000, file = "/books/Austen, Jane/Persuasion.epub" },
    { time = 1789700000, file = "/books/Eliot, George/Middlemarch.epub" },
    { time = 1789600000, file = "/books/fanfic/the glass orchard/a quiet harvest - inkmoth.epub" },
    { time = 1789000000, file = "/koreader/rakuyomi/downloads/QmFzZTY0VXJsTmFtZU9mQUNoYXB0ZXI.cbz" },
}

local index = { books = {
    ["Austen, Jane/Persuasion.epub"] = { title = "Persuasion", status = "reading" },
    ["Dickens, Charles/Bleak House.epub"] = { title = "Bleak House", status = "read" },
}, list = {} }

local function sidecar() return { percent = 0.4, page = 40, pages = 100 } end

describe("readstate.reading", function()
    it("newest first", function()
        local r = ReadState.reading({
            { file = "/books/a.epub", time = 1 },
            { file = "/books/b.epub", time = 3 },
            { file = "/books/c.epub", time = 2 },
        }, sidecar, index, "/books/")
        assert.same({ "/books/b.epub", "/books/c.epub", "/books/a.epub" },
            { r[1].file, r[2].file, r[3].file })
    end)

    it("skips rakuyomi downloads and koreader help", function()
        for _, e in ipairs(ReadState.reading(history, sidecar, index, "/books/")) do
            assert.is_nil(e.file:find("/koreader/", 1, true))
        end
    end)

    it("skips finished", function()
        local r = ReadState.reading({
            { file = "/books/a.epub", time = 1 },
            { file = "/books/b.epub", time = 2 },
            { file = "/books/c.epub", time = 3 },
        }, function(f)
            if f:find("a.epub") then return { status = "complete", percent = 0.5 } end
            if f:find("b.epub") then return { percent = 1 } end
            return { percent = 0.2 }
        end, index, "/books/")
        assert.equals(1, #r)
        assert.equals("/books/c.epub", r[1].file)
    end)

    it("skips books marked read or dnf in calibre and links the book otherwise", function()
        local r = ReadState.reading(history, sidecar, index, "/books/")
        local titles = {}
        for _, e in ipairs(r) do titles[e.title] = e end
        assert.is_nil(titles["Bleak House"])
        assert.equals("Persuasion", titles["Persuasion"].book.title)
        assert.equals(40, titles["Persuasion"].page)
    end)

    it("honours a custom books root", function()
        local file = "/x/Austen, Jane/Persuasion.epub"
        local r = ReadState.reading({ { file = file, time = 1 } }, sidecar, index, "/x/")
        assert.equals("Persuasion", r[1].title)
    end)

    it("unknown file keeps a title from its filename", function()
        local file = "/books/A Quiet Harvest - inkmoth.epub"
        local r = ReadState.reading({ { file = file, time = 1 } }, sidecar, index, "/books/")
        assert.equals("A Quiet Harvest", r[1].title)
        assert.is_nil(r[1].book)
    end)
end)

describe("readstate.days_read", function()
    it("counts distinct days in the month", function()
        local rows = { { day = "2026-11-01" }, { day = "2026-11-01" }, { day = "2026-11-05" }, { day = "2026-10-31" } }
        assert.equals(2, ReadState.days_read(rows, "2026-11"))
    end)
end)
