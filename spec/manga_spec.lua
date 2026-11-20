local cjson = require("cjson")
local Manga = require("bookbindery/manga")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local fixture = cjson.decode(slurp("spec/fixtures/rakuyomi.json"))
for _, rows in pairs(fixture) do
    for _, r in ipairs(rows) do
        for k, v in pairs(type(r) == "table" and r or {}) do
            if v == cjson.null then
                r[k] = nil
            end
        end
    end
end

-- sha256 hex digests of source_id .. manga_id .. chapter_id (python hashlib), keyed by that string
local digests = {
    ["en.inkwell/series/101/the-lantern-keeper/chapters/101-0002/the-lantern-keeper-chapter-2"] =
        "4c4f58f7bc182b9d5a6f5319aeb27f57ed6976f62a171087430d8d87331df4ea",
    ["en.inkwell/series/202/salt-and-iron/chapters/202-0001/salt-and-iron-chapter-1"] =
        "da16f49fe30c09a18e6287d5744a9169ec4ac39ae4f54c83bc602e693cdc7bac",
}
local function sha256(s)
    return digests[s] or string.rep("0", 64)
end

local function downloads()
    local set = {}
    for _, name in ipairs(fixture.downloads) do
        set[name] = true
    end
    return set
end

describe("manga", function()
    it("encodes a hex digest as base64url without padding", function()
        assert.equal("", Manga.base64url(""))
        assert.equal("Zg", Manga.base64url("66"))
        assert.equal("Zm8", Manga.base64url("666f"))
        assert.equal("Zm9v", Manga.base64url("666f6f"))
        assert.equal("-_8", Manga.base64url("fbff"))
    end)

    it("names a download like rakuyomi", function()
        local s = fixture.state
        assert.equal("TE9Y97wYK51ab1MZrrJ_V-1pdvYqFxCHQw2NhzMd9Oo.cbz",
            Manga.download_name(s[2].source_id, s[2].manga_id, s[2].chapter_id, sha256))
        assert.equal("2hb0n-MMCaGOYofVdEqRaexKw5rk9UyDvGAuaTzce6w.cbz",
            Manga.download_name(s[3].source_id, s[3].manga_id, s[3].chapter_id, sha256))
    end)

    it("builds the library from rakuyomi's database rows", function()
        local list = Manga.list(fixture, downloads(), sha256)
        assert.equal(2, #list)
        local k, h = list[1], list[2]
        assert.same({ source_id = "en.inkwell", manga_id = "/series/101/the-lantern-keeper",
            title = "The Lantern Keeper", source = "inkwell",
            cover_url = "https://example.org/inkwell/covers/101.jpg",
            chapters = 12, read = 1, unread = 11, downloaded = 1, new = 0, last_read = 1780000000 }, k)
        assert.equal("Salt and Iron", h.title)
        assert.equal(30, h.chapters)
        assert.equal(30, h.unread)
        assert.equal(1, h.downloaded)
        assert.equal(1, h.new)
        assert.equal(1779000000, h.last_read)
    end)

    local function rows(chapters, state, extra)
        local r = {
            library = { { source_id = "s.x", manga_id = "m" } },
            informations = { { source_id = "s.x", manga_id = "m", title = "info title", cover_url = "c1" } },
            details = {},
            chapters = chapters,
            state = state or {},
        }
        for key, v in pairs(extra or {}) do
            r[key] = v
        end
        return r
    end
    local function ch(id, order, number)
        return { source_id = "s.x", manga_id = "m", chapter_id = id, manga_order = order, chapter_number = number }
    end
    local function st(id, read, last_read)
        return { source_id = "s.x", manga_id = "m", chapter_id = id, read = read, last_read = last_read }
    end
    local function note(id, is_read, manga)
        return { source_id = "s.x", manga_id = manga or "m", chapter_id = id, is_read = is_read }
    end

    it("has no new chapters without notifications (or an older rakuyomi without the table)", function()
        local m = Manga.list(rows({ ch("c2", 0, 2), ch("c1", 1, 1) }), {}, sha256)[1]
        assert.same({ chapters = 2, read = 0, unread = 2, new = 0, title = "info title", cover_url = "c1" },
            { chapters = m.chapters, read = m.read, unread = m.unread, new = m.new, title = m.title,
                cover_url = m.cover_url })
        assert.is_nil(m.last_read)
    end)

    it("counts rakuyomi's unread notifications as new chapters", function()
        local r = rows({ ch("c3", 0, 3), ch("c2", 1, 2), ch("c1", 2, 1) }, { st("c1", 1, 10), st("c2", 0, 20) },
            { notifications = { note("c3", 0), note("c3", 0), note("c2", 0), note("c1", 1), note("c9", 0, "other") } })
        local m = Manga.list(r, {}, sha256)[1]
        assert.equal(2, m.new)
        assert.equal(1, m.read)
        assert.equal(2, m.unread)
        assert.equal(20, m.last_read)
    end)

    it("prefers details over informations and sorts by last read, then title", function()
        local r = rows({ ch("c1", 0, 1) }, { st("c1", 0, 3) }, {
            library = { { source_id = "s.x", manga_id = "m" }, { source_id = "s.x", manga_id = "b" },
                { source_id = "s.x", manga_id = "a" } },
            details = { { source_id = "s.x", id = "m", title = "Zed", cover_url = "c2" },
                { source_id = "s.x", id = "b", title = "Bee" }, { source_id = "s.x", id = "a", title = "Ant" } },
        })
        local list = Manga.list(r, {}, sha256)
        assert.same({ "Zed", "Ant", "Bee" }, { list[1].title, list[2].title, list[3].title })
        assert.equal("c2", list[1].cover_url)
        assert.equal("x", list[1].source)
        assert.equal(0, list[2].chapters)
    end)

    it("a notification whose chapter was read is not new", function()
        local r = {
            library = { { source_id = "s.x", manga_id = "m" } },
            chapters = { { source_id = "s.x", manga_id = "m", chapter_id = "c1" },
                { source_id = "s.x", manga_id = "m", chapter_id = "c2" } },
            state = { { source_id = "s.x", manga_id = "m", chapter_id = "c1", read = 1 },
                { source_id = "s.x", manga_id = "m", chapter_id = "c2", read = 0 } },
            notifications = { { source_id = "s.x", manga_id = "m", chapter_id = "c1", is_read = 0 },
                { source_id = "s.x", manga_id = "m", chapter_id = "c2", is_read = 0 } },
        }
        assert.equal(1, Manga.list(r, {}, sha256)[1].new)
    end)

    it("skips covers that failed in the last day, and prunes older ones", function()
        local function sha1(s) return "h" .. s end
        local list = { { cover_url = "a" }, { cover_url = "b" } }
        local failed = { a = 1000, b = 1000 - Manga.FAILED_FOR }
        assert.same({ { url = "b", name = "hb.jpg" } },
            Manga.missing_covers(list, {}, sha1, 10, true, failed, 1000))
        assert.same({ a = 1000 }, Manga.prune_failed(failed, 1000))
        assert.same({}, Manga.prune_failed(nil, 1000))
        assert.truthy(Manga.failed_source({ a = 0 }):find('["a"] = 0, -- 1970-01-01', 1, true))
    end)

    it("totals new chapters", function()
        assert.equal(1, Manga.new_total(Manga.list(fixture, downloads(), sha256)))
        assert.equal(5, Manga.new_total({ { new = 2 }, { new = 3 } }))
        assert.equal(0, Manga.new_total({}))
    end)

    it("picks no covers unless covers are switched on", function()
        local list = { { cover_url = "a" } }
        assert.same({}, Manga.missing_covers(list, {}, function(u) return u end, 10))
        assert.same({}, Manga.missing_covers(list, {}, function(u) return u end, 10, false))
    end)

    it("caches jpeg and png bytes only", function()
        assert.equal("jpeg", Manga.image_kind("\255\216\255\224rest"))
        assert.equal("png", Manga.image_kind("\137PNG\r\n\26\nrest"))
        assert.is_nil(Manga.image_kind("RIFF\0\0\0\0WEBPVP8 "))
        assert.is_nil(Manga.image_kind(""))
        assert.is_nil(Manga.image_kind(nil))
    end)

    it("picks missing covers, at most the limit", function()
        local function sha1(s)
            return "h" .. s
        end
        local list = { { cover_url = "a" }, {}, { cover_url = "b" }, { cover_url = "c" }, { cover_url = "a" } }
        assert.equal("ha.jpg", Manga.cover_name("a", sha1))
        assert.same({ { url = "b", name = "hb.jpg" }, { url = "c", name = "hc.jpg" } },
            Manga.missing_covers(list, { ["ha.jpg"] = true }, sha1, 10, true))
        assert.same({ { url = "a", name = "ha.jpg" } }, Manga.missing_covers(list, {}, sha1, 1, true))
    end)
    it("filters by chip: library, downloaded, new chapters", function()
        local a = { title = "a", downloaded = 0, new = 2 }
        local b = { title = "b", downloaded = 3, new = 0 }
        local c = { title = "c", downloaded = 1, new = 1 }
        local list = { a, b, c }
        assert.same({ a, b, c }, Manga.filter(list, "library"))
        assert.same({ b, c }, Manga.filter(list, "downloaded"))
        assert.same({ a, c }, Manga.filter(list, "new chapters"))
        assert.same({ a, b, c }, Manga.filter(list, nil))
        assert.same({}, Manga.filter({}, "downloaded"))
        assert.same({ "library", "downloaded", "new chapters" }, Manga.CHIPS)
    end)

    it("says what an empty chip means", function()
        assert.equal("no manga in rakuyomi's library yet", Manga.empty("library"))
        assert.equal("nothing downloaded in rakuyomi", Manga.empty("downloaded"))
        assert.equal("no new chapters", Manga.empty("new chapters"))
    end)

    it("writes a row's line and progress", function()
        local k = Manga.list(fixture, downloads(), sha256)[1]
        assert.equal("12 chapters · 1 read · inkwell", Manga.line(k))
        assert.equal("1 chapter · 1 read · x", Manga.line({ chapters = 1, read = 1, source = "x" }))
        assert.equal(1 / 12, Manga.progress(k))
        assert.equal(0.25, Manga.progress({ chapters = 8, read = 2 }))
        assert.equal(0, Manga.progress({ chapters = 0, read = 0 }))
    end)

    it("keeps a folder's file names, without dot entries", function()
        assert.same({}, Manga.file_set({ ".", "..", ".hidden" }))
        assert.same({ ["a.cbz"] = true }, Manga.file_set({ ".", "a.cbz", ".." }))
        assert.is_nil(next(Manga.file_set({ ".", ".." })))
    end)
    it("classifies why the database didn't read", function()
        assert.equal("none", Manga.failure(false))
        assert.equal("busy", Manga.failure(true,
            "mangadata.lua:115: common/lua-ljsqlite3/init.lua:60: ljsqlite3[busy] database is locked"))
        assert.equal("busy", Manga.failure(true, "database table is locked"))
        assert.equal("error", Manga.failure(true, "ljsqlite3[corrupt] database disk image is malformed"))
        assert.equal("error", Manga.failure(true, nil))
    end)
end)
