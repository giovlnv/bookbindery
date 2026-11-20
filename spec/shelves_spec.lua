local cjson = require("cjson")
local Library = require("bookbindery/library")
local Shelves = require("bookbindery/shelves")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local index = assert(Library.parse(slurp("spec/fixtures/metadata.calibre.json"), cjson.decode))

local function child(node, name)
    for _, c in ipairs(node.children) do
        if c.name == name then
            return c
        end
    end
end

local function labels(groups)
    local out = {}
    for _, g in ipairs(groups) do
        out[#out + 1] = g.label
    end
    return out
end

describe("Shelves#status_counts", function()
    it("counts books by status, fanfic left out", function()
        local c = Shelves.status_counts(index)
        assert.same({ reading = 3, tbr = 8, read = 3, dnf = 1 }, {
            reading = c.reading, tbr = c.tbr, read = c.read, dnf = c.dnf,
        })
    end)
end)

describe("Shelves#tree", function()
    local root = Shelves.tree(index)

    it("splits on dots", function()
        local classics = child(child(root, "fiction"), "classics")
        assert.equals(5, classics.count)
        assert.equals("fiction.classics", classics.path)
        local austen = child(classics, "austen")
        assert.equals(3, austen.count)
        assert.equals("fiction.classics.austen", austen.path)
    end)

    it("sorts children by count desc then name", function()
        local fiction = child(root, "fiction")
        assert.same({ "classics", "series", "gothic" },
            { fiction.children[1].name, fiction.children[2].name, fiction.children[3].name })
        local series = child(fiction, "series")
        assert.equals("barsetshire", series.children[1].name)
        assert.equals("leatherstocking", series.children[2].name)
    end)

    it("leaves fanfic out and keeps periodicals", function()
        assert.is_nil(child(root, "fanfic"))
        assert.equals(2, child(root, "periodicals").count)
    end)

    it("counts a book once per node even with two types under it", function()
        assert.equals(3, child(root, "nonfiction").count)
        assert.equals(2, child(child(root, "nonfiction"), "history").count)
    end)

    it("orders the top level by count", function()
        assert.same({ "fiction", "nonfiction", "periodicals" },
            { root.children[1].name, root.children[2].name, root.children[3].name })
    end)
end)

describe("Shelves#books", function()
    it("filters by path prefix and skips fanfic", function()
        local g = Shelves.books(index, "fiction.series", "none")
        assert.equals(1, #g)
        assert.equals(5, #g[1].books)
        assert.equals(0, #Shelves.books(index, "fanfic", "none"))
    end)

    it("does not match a path by string prefix alone", function()
        assert.equals(0, #Shelves.books(index, "fiction.ser", "none"))
    end)

    it("series sorted by index", function()
        local g = Shelves.books(index, "fiction.series.barsetshire", "series")
        assert.equals(1, #g)
        assert.equals("Chronicles of Barsetshire", g[1].label)
        assert.same({ 1, 2, 3 }, { g[1].books[1].series_index, g[1].books[2].series_index,
            g[1].books[3].series_index })
    end)

    it("puts books without a series in a last, unlabeled group", function()
        local g = Shelves.books(index, "fiction", "series")
        assert.equals("", g[#g].label)
    end)

    it("groups by shelf", function()
        local g = Shelves.books(index, "fiction", "shelf")
        assert.same({
            "fiction.classics.austen", "fiction.classics.dickens", "fiction.gothic", "fiction.series.barsetshire",
            "fiction.series.leatherstocking",
        }, labels(g))
    end)

    it("groups by author", function()
        local g = Shelves.books(index, "fiction.classics.dickens", "author")
        assert.equals(1, #g)
        assert.equals("Charles Dickens", g[1].label)
    end)

    it("none gives one group of all books", function()
        local g = Shelves.books(index, "", "none")
        assert.equals(1, #g)
        assert.equals(18, #g[1].books)
    end)
end)

describe("Shelves extras", function()
    local root = Shelves.tree(index)

    it("filters by status", function()
        local g = Shelves.books(index, "", "none", "tbr")
        assert.equals(Shelves.status_counts(index).tbr, #g[1].books)
        for _, b in ipairs(g[1].books) do
            assert.equals("tbr", b.status)
        end
    end)

    it("keeps series in volume order whatever the grouping", function()
        local books = Shelves.books(index, "fiction.series.leatherstocking", "shelf")[1].books
        assert.equals(2, #books)
        for i = 2, #books do
            assert.is_true(books[i - 1].series_index <= books[i].series_index)
        end
    end)

    it("finds a node by path", function()
        assert.equals("fiction.classics.austen", Shelves.find(root, "fiction.classics.austen").path)
        assert.equals(root, Shelves.find(root, ""))
        assert.is_nil(Shelves.find(root, "fiction.nope"))
    end)

    it("flattens open nodes, pinned first", function()
        local fiction = Shelves.find(root, "fiction")
        local rows = Shelves.rows(fiction, { ["fiction.classics"] = true }, { ["fiction.classics.dickens"] = true })
        assert.equals("fiction.classics", rows[1].node.path)
        assert.is_true(rows[1].open)
        assert.equals("fiction.classics.dickens", rows[2].node.path)
        assert.is_true(rows[2].pinned)
        assert.equals(1, rows[2].depth)
        assert.equals("fiction.classics.austen", rows[3].node.path)
        local closed = Shelves.rows(fiction, {}, {})
        assert.equals(#fiction.children, #closed)
    end)
end)
