local ReaderBook = require("bookbindery/readerbook")

describe("ReaderBook#entry", function()
    local emma = { lpath = "Austen, Jane/Emma.epub", id = 7, library = "books" }
    local index = { books = { [emma.lpath] = emma } }

    it("finds the index entry by the path under the books root", function()
        assert.equal(7, ReaderBook.entry("/books/Austen, Jane/Emma.epub", "/books/", index).id)
    end)

    it("builds a stub for a file the index doesn't know", function()
        local e = ReaderBook.entry("/books/fanfic/the glass orchard/a quiet harvest - inkmoth.epub",
            "/books/", index)
        assert.equal("fanfic/the glass orchard/a quiet harvest - inkmoth.epub", e.lpath)
        assert.equal("a quiet harvest - inkmoth", e.title)
        assert.equal("fanfic", e.library)
        assert.is_nil(e.id)
    end)

    it("builds a stub without an index, a book by default", function()
        local e = ReaderBook.entry("/books/x/y.epub", "/books/", nil)
        assert.equal("books", e.library)
        assert.equal("y", e.title)
    end)

    it("is nil outside the root or without a file", function()
        assert.is_nil(ReaderBook.entry("/documents/y.epub", "/books/", index))
        assert.is_nil(ReaderBook.entry(nil, "/books/", index))
    end)
end)

describe("ReaderBook#first", function()
    it("moves the item to the head of the first tab", function()
        local tabs = { { { id = "a" }, { id = "b" }, { id = "me" } }, { { id = "c" } } }
        assert.is_true(ReaderBook.first(tabs, "me"))
        assert.same({ "me", "a", "b" }, { tabs[1][1].id, tabs[1][2].id, tabs[1][3].id })
        assert.equal(1, #tabs[2])
    end)

    it("is idempotent", function()
        local tabs = { { { id = "me" }, { id = "a" } } }
        ReaderBook.first(tabs, "me")
        ReaderBook.first(tabs, "me")
        assert.same({ "me", "a" }, { tabs[1][1].id, tabs[1][2].id })
    end)

    it("leaves tabs without the item alone", function()
        local tabs = { { { id = "a" } } }
        assert.is_false(ReaderBook.first(tabs, "me"))
        assert.is_false(ReaderBook.first(nil, "me"))
    end)
end)

describe("ReaderBook#wrap_sorter", function()
    local function sorter()
        return { mergeAndSort = function() return { { { id = "a" }, { id = "me" } } } end }
    end

    it("puts the item first for the reader menu only", function()
        local s = sorter()
        ReaderBook.wrap_sorter(s, "me")
        assert.equal("me", s:mergeAndSort("reader", {}, {})[1][1].id)
        assert.equal("a", s:mergeAndSort("filemanager", {}, {})[1][1].id)
    end)

    it("wraps once", function()
        local s = sorter()
        assert.is_true(ReaderBook.wrap_sorter(s, "me"))
        local wrapped = s.mergeAndSort
        assert.is_false(ReaderBook.wrap_sorter(s, "me"))
        assert.equal(wrapped, s.mergeAndSort)
    end)
end)

describe("ReaderBook#entry without a file part", function()
    it("falls back to the lpath", function()
        assert.equal("x", ReaderBook.entry("/r/x", "/r/", nil).title)
        assert.equal("", ReaderBook.entry("/r/", "/r/", nil).title)
    end)
end)
