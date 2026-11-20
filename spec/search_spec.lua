local Search = require("bookbindery/search")

local function book(lpath, title, authors, extra)
    local b = { lpath = lpath, title = title, authors = authors, tags = {},
        library = lpath:find("^fanfic/") and "fanfic" or "books" }
    for k, v in pairs(extra or {}) do
        b[k] = v
    end
    return b
end

local function index_of(list)
    local books = {}
    for _, b in ipairs(list) do
        books[b.lpath] = b
    end
    return { list = list, books = books }
end

local index = index_of({
    book("dickens/carol.epub", "A Christmas Carol", { "Charles Dickens" }, { id = 6, status = "reading" }),
    book("dickens/frozen.epub", "The Frozen Deep", { "Wilkie Collins", "Charles Dickens" },
        { id = 111, status = "read" }),
    book("dickens/bleak.epub", "Bleak House", { "Charles Dickens" }, { id = 397, status = "tbr" }),
    book("assis/bras cubas.epub", "Memórias Póstumas de Brás Cubas", { "Machado de Assis" }, { id = 20 }),
    book("trollope/warden.epub", "The Warden", { "Anthony Trollope" },
        { id = 30, series = "Chronicles of Barsetshire" }),
    book("x/dickensian.epub", "Dickensian Days", { "Ann Other" }, { id = 31 }),
    book("x/the dickens.epub", "Reading Dickens Today", { "Ann Other" }, { id = 32 }),
    book("fanfic/the glass orchard/windfall.epub", "Windfall", { "wanderer" },
        { id = 300, tags = { "The Glass Orchard - Ada Quill", "Rowan Vale/Elias Thorne", "fanfic" } }),
    book("fanfic/starfall academy/tea.epub", "Tea for Two", { "writer" },
        { id = 301, tags = { "Starfall Academy - B. Penn", "Ivy Lark/Juniper Moss", "fanfic" } }),
})

local groups = nil

local function titles(results)
    local out = {}
    for _, r in ipairs(results) do
        out[#out + 1] = r.title
    end
    return out
end

local function find(results, title)
    for _, r in ipairs(results) do
        if r.title == title then
            return r
        end
    end
end

describe("Search.fold", function()
    it("lowercases and strips latin accents", function()
        assert.equal("memorias postumas de bras cubas", Search.fold("Memórias Póstumas de Brás Cubas"))
        assert.equal("aaaaa eeee iiii ooooo uuuu c n", Search.fold("áàâãä éêèë íìîï óòôõö úùûü ç ñ"))
        assert.equal("aeiou c", Search.fold("ÁÉÍÓÚ Ç"))
        assert.equal("dickens", Search.fold("DICKENS"))
    end)

    it("survives truncated or invalid utf-8", function()
        assert.equal("\195", Search.fold("\195"))
        assert.equal("a\195", Search.fold("A\195"))
        assert.equal("\197\255", Search.fold("\197\255"))
        assert.equal("\195a", Search.fold("\195A"))
    end)

    it("leaves other utf-8 alone", function()
        assert.equal("—x 日本", Search.fold("—X 日本"))
    end)
end)

describe("Search.run, library", function()
    it("an empty or blank query has no results", function()
        assert.same({}, Search.run("", "library", index, groups))
        assert.same({}, Search.run("   ", "library", index, groups))
    end)

    it("is case-insensitive: dickens finds Dickens", function()
        local r = Search.run("dickens", "library", index, groups)
        assert.is_not_nil(find(r, "A Christmas Carol"))
        assert.is_not_nil(find(r, "The Frozen Deep"))
    end)

    it("is accent-insensitive both ways", function()
        local bras = { "Memórias Póstumas de Brás Cubas" }
        assert.same(bras, titles(Search.run("Memorias Postumas", "library", index, groups)))
        assert.same(bras, titles(Search.run("brás", "library", index, groups)))
        assert.same({ "A Christmas Carol" }, titles(Search.run("chrístmas", "library", index, groups)))
    end)

    it("ranks title prefix, then title contains, then author; ties by title", function()
        local r = titles(Search.run("dickens", "library", index, groups))
        local expected = { "Dickensian Days", "Reading Dickens Today", "A Christmas Carol", "Bleak House",
            "The Frozen Deep" }
        assert.same(expected, r)
    end)

    it("library rows carry author, status and the entry", function()
        local r = find(Search.run("dickens", "library", index, groups), "A Christmas Carol")
        assert.equal("Charles Dickens", r.author)
        assert.equal("reading", r.status)
        assert.equal("dickens/carol.epub", r.lpath)
        assert.equal(index.books[r.lpath], r.entry)
        assert.equal("library", r.place)
        assert.equal("Charles Dickens · reading", Search.subline(r))
    end)

    it("matches series after title and author", function()
        assert.same({ "The Warden" }, titles(Search.run("barsetshire", "library", index, groups)))
    end)

    it("never lists fanfic in the library scope", function()
        assert.same({}, Search.run("windfall", "library", index, groups))
    end)

    it("works without groups", function()
        assert.same({ "Memórias Póstumas de Brás Cubas" }, titles(Search.run("cubas", "library", index, nil)))
    end)

    it("doesn't expand abbreviations: pjo finds nothing", function()
        assert.same({}, Search.run("pjo", "library", index, groups))
    end)
end)

describe("Search.run, fanfic", function()
    local files = { "fanfic/the glass orchard/windfall.epub", "fanfic/lantern isles/Lost - nobody.epub" }

    it("finds a fic by ship, with its fandom", function()
        local r = Search.run("elias thorne", "fanfic", index, groups, files)
        assert.same({ "Windfall" }, titles(r))
        assert.equal("fanfic", r[1].place)
        assert.equal(index.books["fanfic/the glass orchard/windfall.epub"], r[1].entry)
        assert.equal("wanderer · Rowan Vale/Elias Thorne", Search.subline(r[1]))
    end)

    it("finds a fic by fandom tag and by title", function()
        assert.same({ "Tea for Two" }, titles(Search.run("starfall academy", "fanfic", index, groups)))
        assert.same({ "Windfall" }, titles(Search.run("wind", "fanfic", index, groups, files)))
    end)

    it("files on disk not in calibre are searchable by name, author and folder", function()
        local r = Search.run("lost", "fanfic", index, groups, files)
        assert.same({ "Lost" }, titles(r))
        assert.equal("fanfic/lantern isles/Lost - nobody.epub", r[1].lpath)
        assert.equal("nobody · lantern isles", Search.subline(r[1]))
        assert.same({ "Lost" }, titles(Search.run("lantern", "fanfic", index, groups, files)))
    end)

    it("only lists what is on disk when files are given", function()
        assert.same({}, Search.run("tea", "fanfic", index, groups, files))
    end)

    it("never lists library books", function()
        assert.same({}, Search.run("dickens", "fanfic", index, groups, files))
    end)
end)

describe("Search.summary", function()
    it("counts per scope", function()
        assert.equal("4 in your library · works offline", Search.summary(4, "library"))
        assert.equal("1 in fanfic · works offline", Search.summary(1, "fanfic"))
        assert.equal("works offline", Search.summary(nil, "library"))
    end)
end)

describe("Search.subline status words", function()
    it("uses the words info shows", function()
        assert.equal("a · to read", Search.subline({ author = "a", status = "tbr" }))
        assert.equal("a · did not finish", Search.subline({ author = "a", status = "dnf" }))
    end)
end)
