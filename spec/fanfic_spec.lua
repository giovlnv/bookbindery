local cjson = require("cjson")
local Library = require("bookbindery/library")
local Fanfic = require("bookbindery/fanfic")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local index = assert(Library.parse(slurp("spec/fixtures/metadata.calibre.json"), cjson.decode))

local GO = "fanfic/the glass orchard/"
local SA = "fanfic/starfall academy/"

local function names(list, key)
    local out = {}
    for _, x in ipairs(list) do
        out[#out + 1] = x[key]
    end
    return out
end

describe("Fanfic#fandoms", function()
    it("groups by fandom folder, biggest first, books excluded", function()
        local f = Fanfic.fandoms(index, nil, nil)
        assert.same({ { name = "the glass orchard", n = 3, new = 0 }, { name = "starfall academy", n = 2, new = 0 } },
            f)
    end)

    it("orders by count, then name", function()
        local files = {
            "fanfic/b/1 - x.epub", "fanfic/b/2 - x.epub", "fanfic/b/3 - x.epub",
            "fanfic/a/1 - x.epub", "fanfic/a/2 - x.epub",
            "fanfic/c/1 - x.epub", "fanfic/c/2 - x.epub",
            "fanfic/d/1 - x.epub",
        }
        assert.same({ "b", "a", "c", "d" }, names(Fanfic.fandoms({ list = {}, books = {} }, nil, files), "name"))
    end)

    it("files are the truth: unindexed files count, indexed files not on disk do not", function()
        local files = { GO .. "windfall - quietwren.epub", GO .. "loose one - nobody.epub", "fanfic/stray.epub" }
        local f = Fanfic.fandoms(index, nil, files)
        assert.same({ { name = "the glass orchard", n = 2, new = 0 }, { name = "other", n = 1, new = 0 } }, f)
    end)

    it("without files it still works", function()
        assert.same({}, Fanfic.fandoms({ list = {}, books = {} }, nil, nil))
        assert.same({}, Fanfic.fandoms(index, nil, {}))
    end)
end)

describe("Fanfic#works", function()
    it("lists one fandom, titles sorted, with authors and lpath", function()
        local w = Fanfic.works(index, "the glass orchard", nil, nil, nil)
        assert.same({ "a quiet harvest", "lanterns", "windfall" }, names(w, "title"))
        assert.same({ "inkmoth" }, w[1].authors)
        assert.equals(GO .. "a quiet harvest - inkmoth.epub", w[1].lpath)
        assert.equals(0, w[1].new_chapters)
        assert.is_nil(w[1].status)
    end)

    it("takes status from status_of by lpath", function()
        local st = { [SA .. "tea for two - quietwren.epub"] = "reading" }
        local w = Fanfic.works(index, "starfall academy", nil, nil, function(l) return st[l] end)
        assert.same({ "tea for two", "the long way round" }, names(w, "title"))
        assert.equals("reading", w[1].status)
        assert.is_nil(w[2].status)
    end)

    it("a file with no index entry is parsed from its name, split on the last ' - '", function()
        local files = {
            SA .. "a - b - c - the author.epub",
            SA .. "no author.epub",
            SA .. "tea for two - quietwren.epub",
        }
        local w = Fanfic.works(index, "starfall academy", nil, files, nil)
        assert.same({ "a - b - c", "no author", "tea for two" }, names(w, "title"))
        assert.same({ "the author" }, w[1].authors)
        assert.same({}, w[2].authors)
        assert.same({ "quietwren" }, w[3].authors)
        assert.equals(SA .. "no author.epub", w[2].lpath)
    end)

    it("files directly in fanfic/ are the fandom 'other'", function()
        local w = Fanfic.works(index, "other", nil, { "fanfic/stray - me.epub" }, nil)
        assert.same({ "stray" }, names(w, "title"))
    end)

    it("titles and fandom names sort case-insensitively", function()
        local files = { "fanfic/x/Zed - a.epub", "fanfic/x/alpha - a.epub", "fanfic/x/Beta - a.epub",
            "fanfic/Yy/q - a.epub", "fanfic/aa/q - a.epub", "fanfic/Bb/q - a.epub" }
        local empty = { books = {}, list = {} }
        assert.same({ "alpha", "Beta", "Zed" }, names(Fanfic.works(empty, "x", nil, files, nil), "title"))
        local f = Fanfic.fandoms(empty, nil, { "fanfic/Yy/q - a.epub", "fanfic/aa/q - a.epub", "fanfic/Bb/q - a.epub" })
        assert.same({ "aa", "Bb", "Yy" }, names(f, "name"))
    end)

    it("unknown fandom gives an empty list", function()
        assert.same({}, Fanfic.works(index, "nope", nil, nil, nil))
    end)
end)

describe("fanfic status", function()

    it("maps sidecar info", function()
        assert.is_nil(Fanfic.status(nil))
        assert.is_nil(Fanfic.status({}))
        assert.is_nil(Fanfic.status({ status = "abandoned", percent = 0 }))
        assert.equals("read", Fanfic.status({ status = "complete", percent = 1 }))
        assert.equals("reading", Fanfic.status({ status = "reading" }))
        assert.equals("reading", Fanfic.status({ percent = 0.3 }))
    end)
end)
