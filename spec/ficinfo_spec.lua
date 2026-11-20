local cjson = require("cjson")
local Library = require("bookbindery/library")
local FicInfo = require("bookbindery/ficinfo")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local index = assert(Library.parse(slurp("spec/fixtures/metadata.calibre.json"), cjson.decode))

local function fic(lpath)
    return assert(index.books[lpath])
end

local function value(rows, label)
    for _, r in ipairs(rows) do
        if r.label == label then
            return r.value
        end
    end
end

local NOW = os.time({ year = 2026, month = 11, day = 19, hour = 12 })
local WINDFALL = "fanfic/the glass orchard/windfall - quietwren.epub"
local HARVEST = "fanfic/the glass orchard/a quiet harvest - inkmoth.epub"

describe("FicInfo#model", function()
    it("a fic from calibre: fandom, ships, rating, progress, ao3 id", function()
        local e = fic(WINDFALL)
        local read = { opened = true, percent = 0.25, pages = 400, page = 100, highlights = 3 }
        local m = FicInfo.model(e, read, NOW)
        assert.equal("windfall", m.title)
        assert.equal("quietwren", m.authors)
        assert.equal("reading", m.status)
        assert.equal("explicit", m.rating)
        assert.is_nil(m.complete)
        assert.equal("The Glass Orchard", value(m.rows, "fandom"))
        assert.equal("Rowan Vale/Elias Thorne · Ivy Lark/Juniper Moss", value(m.rows, "ship"))
        assert.is_nil(value(m.rows, "length"))
        assert.equal("page 100 of 400 · 25%", value(m.rows, "progress"))
        assert.equal(1000001, m.ao3)
        assert.equal("#1000001", value(m.details, "ao3 work"))
        assert.equal("books/fanfic/the glass orchard", value(m.details, "folder"))
        assert.equal("3", value(m.details, "highlights"))
        assert.equal("fanfic #1", value(m.details, "calibre"))
        assert.is_nil(value(m.details, "tags"))
        assert.truthy(m.summary:find("Rowan has kept the orchard alone", 1, true))
        assert.is_nil(m.summary:find("<", 1, true))
        assert.equal("read", m.action)
    end)

    it("a fic without an ao3 id or a summary", function()
        local m = FicInfo.model(fic(HARVEST), nil, NOW)
        assert.equal("not started", m.status)
        assert.equal("to read", FicInfo.model(setmetatable({ status = "tbr" }, { __index = fic(HARVEST) }), nil, NOW)
            .status)
        assert.equal("teen and up", m.rating)
        assert.equal("not started", value(m.rows, "progress"))
        assert.equal("Rowan Vale/Elias Thorne", value(m.rows, "ship"))
        assert.is_nil(m.ao3)
        assert.is_nil(value(m.details, "ao3 work"))
        assert.equal("none", value(m.details, "highlights"))
    end)

    it("a fandom tag without \" - \" still counts; other tags are freeform", function()
        local e = setmetatable({ tags = { "Lighthouse Keepers (TV)", "Mara Quell/Odo Fenn", "Mature", "fluff",
            "fanfic" } }, { __index = fic(HARVEST) })
        local m = FicInfo.model(e, nil, NOW)
        assert.equal("Lighthouse Keepers (TV)", value(m.rows, "fandom"))
        assert.equal("mature", m.rating)
        assert.equal("fluff", value(m.details, "tags"))
    end)
end)
