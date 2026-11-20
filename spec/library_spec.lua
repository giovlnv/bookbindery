local cjson = require("cjson")
local Library = require("bookbindery/library")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local text = slurp("spec/fixtures/metadata.calibre.json")
local decode = cjson.decode

local function find(index, f)
    for _, b in ipairs(index.list) do
        if f(b) then
            return b
        end
    end
end

local function fake_io(file_text, attrs)
    local fs = { ["/m"] = file_text }
    local io_ = { reads = 0, fs = fs, attrs = attrs or { size = #file_text, modification = 100 } }
    io_.attributes = function() return io_.attrs end
    io_.read = function(p)
        if p == "/m" then
            io_.reads = io_.reads + 1
        end
        return fs[p]
    end
    io_.write = function(p, s) fs[p] = s end
    io_.decode = decode
    io_.serialize = cjson.encode
    io_.deserialize = function(t)
        io_.decoded = (io_.decoded or 0) + 1
        return cjson.decode(t)
    end
    return io_
end

describe("Library#parse", function()
    local index = assert(Library.parse(text, decode))

    it("indexes every entry by lpath", function()
        assert.equals(23, #index.list)
        local b = index.list[1]
        assert.equals(b, index.books[b.lpath])
    end)

    it("parses status from #workflow", function()
        local read = find(index, function(b) return b.status == "read" end)
        local reading = find(index, function(b) return b.status == "reading" end)
        local tbr = find(index, function(b) return b.status == "tbr" end)
        local dnf = find(index, function(b) return b.status == "dnf" end)
        assert.is_table(read)
        assert.is_table(reading)
        assert.is_table(tbr)
        assert.is_table(dnf)
    end)

    it("gives nil status for an empty #workflow", function()
        local b = find(index, function(x) return x.types[1] == "periodicals.strand" end)
        assert.is_nil(b.status)
    end)

    it("types keep dotted paths", function()
        local b = find(index, function(x) return x.series ~= nil and x.types[1] ~= nil end)
        assert.truthy(b.types[1]:find("fiction.series.", 1, true))
        assert.truthy(find(index, function(x) return x.types[1] == "periodicals.strand" end))
        assert.truthy(find(index, function(x) return x.types[1] == "fanfic.glass" end))
    end)

    it("reads book fields", function()
        local b = index.books["Austen, Jane/Pride and Prejudice.epub"]
        assert.equals("b00c0001-0000-4000-8000-000000000001", b.uuid)
        assert.equals(1, b.id)
        assert.equals("Pride and Prejudice", b.title)
        assert.same({ "Jane Austen" }, b.authors)
        assert.equals(432, b.pages)
        assert.equals(10, b.rating)
        assert.equals("1813-01-28", b.pubdate)
        assert.truthy(b.comments)
        assert.is_true(#b.tags > 0)
    end)

    it("keeps series and index", function()
        local b = find(index, function(x) return x.series ~= nil end)
        assert.is_number(b.series_index)
    end)

    it("missing user_metadata gives empty types", function()
        local b = index.list[18]
        assert.equals("The Time Machine", b.title)
        assert.same({}, b.types)
        assert.is_nil(b.status)
        assert.is_nil(b.pages)
    end)

    it("a top-level object is an error", function()
        local idx, err = Library.parse('{"a":1}', decode)
        assert.is_nil(idx)
        assert.is_string(err)
    end)

    it("bad json returns nil and an error", function()
        local idx, err = Library.parse("{not json", decode)
        assert.is_nil(idx)
        assert.is_string(err)
    end)
end)

describe("Library#parse library and ao3", function()
    local entries = cjson.encode({
        { lpath = "Austen, Jane/Emma.epub", application_id = 1,
            tags = { "classics" } },
        { lpath = "fanfic/1/b.epub", application_id = 1, identifiers = { ao3 = "12345" } },
    })
    local index = assert(Library.parse(entries, decode))

    it("the library comes from the lpath", function()
        assert.equals("books", index.list[1].library)
        assert.equals("fanfic", index.list[2].library)
    end)

    it("fics carry the ao3 work id", function()
        assert.is_nil(index.list[1].ao3)
        assert.equals(12345, index.list[2].ao3)
    end)

    it("reads the ao3 id from the library", function()
        local full = assert(Library.parse(text, decode))
        assert.equals(1000001, full.books["fanfic/the glass orchard/windfall - quietwren.epub"].ao3)
        assert.equals("fanfic", full.books["fanfic/the glass orchard/windfall - quietwren.epub"].library)
    end)
end)

describe("Library#load", function()
    it("parses and writes the cache on first load", function()
        local io_ = fake_io(text)
        local idx = Library.load("/m", "/c", io_)
        assert.equals(23, #idx.list)
        assert.is_string(io_.fs["/c"])
    end)

    it("uses the cache when size and mtime match", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        assert.equals(1, io_.reads)
        local idx = Library.load("/m", "/c", io_)
        assert.equals(1, io_.reads)
        assert.equals(23, #idx.list)
        assert.is_table(idx.books[idx.list[1].lpath])
    end)

    it("reparses when the file changed", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        io_.attrs = { size = #text, modification = 200 }
        Library.load("/m", "/c", io_)
        assert.equals(2, io_.reads)
    end)

    it("keeps the cache key in a small sidecar and comments in the cache", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        local meta = cjson.decode(io_.fs["/c.meta.lua"])
        assert.same({ version = 3, size = #text, mtime = 100 }, meta)
        local cached = cjson.decode(io_.fs["/c"])
        local with = 0
        for _, b in ipairs(cached.list) do
            with = with + (b.comments and 1 or 0)
        end
        assert.is_true(with > 0)
    end)

    it("a changed file is reparsed without deserializing the old cache", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        io_.decoded = 0
        io_.attrs = { size = #text, modification = 200 }
        assert.equals(23, #Library.load("/m", "/c", io_).list)
        assert.equals(1, io_.decoded)
    end)

    it("keeps the cache when the file is truncated", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        io_.fs["/m"] = text:sub(1, 5000)
        io_.attrs = { size = 5000, modification = 300 }
        local idx = Library.load("/m", "/c", io_)
        assert.equals(23, #idx.list)
    end)

    it("returns nil and an error without a cache on bad file", function()
        local idx, err = Library.load("/m", "/c", fake_io("{oops"))
        assert.is_nil(idx)
        assert.is_string(err)
    end)

    it("an empty parse keeps a non-empty cache", function()
        for _, empty in ipairs({ "[]", "{}" }) do
            local io_ = fake_io(text)
            Library.load("/m", "/c", io_)
            io_.fs["/m"] = empty
            io_.attrs = { size = #empty, modification = 400 }
            assert.equals(23, #Library.load("/m", "/c", io_).list)
        end
    end)

    it("a failing cache write does not raise", function()
        local io_ = fake_io(text)
        io_.write = function() error("read-only file system") end
        assert.equals(23, #Library.load("/m", "/c", io_).list)
    end)

    it("reparses when the cache version differs", function()
        local io_ = fake_io(text)
        Library.load("/m", "/c", io_)
        local cache = cjson.decode(io_.fs["/c"])
        cache.version = 0
        io_.fs["/c"] = cjson.encode(cache)
        Library.load("/m", "/c", io_)
        assert.equals(2, io_.reads)
    end)
end)
