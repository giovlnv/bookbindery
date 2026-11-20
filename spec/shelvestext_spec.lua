local ShelvesText = require("bookbindery/shelvestext")

local function node(path, kids)
    local n = { path = path, children = {} }
    for i, k in ipairs(kids or {}) do
        n.children[i] = { name = k[1], count = k[2], children = {} }
    end
    return n
end

describe("ShelvesText", function()
    it("paths and names split on dots", function()
        assert.equals("fiction › series › barsetshire", ShelvesText.path("fiction.series.barsetshire"))
        assert.equals("barsetshire", ShelvesText.name("fiction.series.barsetshire"))
        assert.equals("fiction", ShelvesText.name("fiction"))
    end)

    it("status labels", function()
        assert.equals("to read", ShelvesText.status("tbr"))
        assert.equals("reading", ShelvesText.status("reading"))
    end)

    it("hints at the children", function()
        assert.equals("series 157 · standalones 18",
            ShelvesText.hint(node("fiction", { { "series", 157 }, { "standalones", 18 } })))
        assert.equals("science · essays · history · 3 more", ShelvesText.hint(node("nonfiction",
            { { "science", 9 }, { "essays", 4 }, { "history", 4 }, { "misc", 5 }, { "travel", 2 }, { "food", 3 } })))
        assert.equals("the strand", ShelvesText.hint(node("periodicals", { { "the strand", 2 } })))
        assert.equals("", ShelvesText.hint(node("x")))
    end)

    it("byline with volume", function()
        assert.equals("Anthony Trollope · vol. 2",
            ShelvesText.byline({ authors = { "Anthony Trollope" }, series = "Barsetshire", series_index = 2.0 }))
        assert.equals("Leo Tolstoy", ShelvesText.byline({ authors = { "Leo Tolstoy" } }))
        assert.equals("X · vol. 1.5", ShelvesText.byline({ authors = { "X" }, series = "S", series_index = 1.5 }))
    end)

    it("shelves count and next note", function()
        assert.equals("14 shelves", ShelvesText.shelves(14))
        assert.equals("1 shelf", ShelvesText.shelves(1))
        assert.equals("austen, dickens, gothic, standalones next",
            ShelvesText.next_note({ "austen", "dickens", "gothic", "standalones" }))
        assert.equals("a, b, c, d… next", ShelvesText.next_note({ "a", "b", "c", "d", "e" }))
        assert.is_nil(ShelvesText.next_note({}))
    end)
end)
