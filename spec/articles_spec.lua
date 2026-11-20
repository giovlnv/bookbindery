local Articles = require("bookbindery/articles")

local function titles(list)
    local out = {}
    for _, a in ipairs(list) do
        out[#out + 1] = a.title
    end
    return out
end

describe("articles", function()
    it("strips wallabag's prefix and the extension", function()
        local list = Articles.list({ { name = "[w-id_2] A Walk Through the Old Harbour.epub", time = 10 } })
        assert.same({ { title = "A Walk Through the Old Harbour",
            file = "[w-id_2] A Walk Through the Old Harbour.epub", time = 10 } }, list)
    end)

    it("handles every extension and multi-digit ids", function()
        local list = Articles.list({
            { name = "[w-id_123] A page.html", time = 1 },
            { name = "[w-id_45] A paper.pdf", time = 2 },
        })
        assert.same({ "A paper", "A page" }, titles(list))
    end)

    it("keeps dots inside the title", function()
        local list = Articles.list({ { name = "[w-id_7] Why v1.2 matters.epub", time = 1 } })
        assert.equal("Why v1.2 matters", list[1].title)
    end)

    it("keeps the name of a file without the prefix, minus extension", function()
        local list = Articles.list({ { name = "notes.epub", time = 1 }, { name = "readme", time = 0 } })
        assert.same({ "notes", "readme" }, titles(list))
    end)

    it("sorts newest first, ties by title", function()
        local list = Articles.list({
            { name = "[w-id_1] B.epub", time = 5 },
            { name = "[w-id_2] C.epub", time = 9 },
            { name = "[w-id_3] A.epub", time = 5 },
        })
        assert.same({ "C", "A", "B" }, titles(list))
    end)

    it("is empty without entries", function()
        assert.same({}, Articles.list({}))
        assert.same({}, Articles.list(nil))
    end)
end)
