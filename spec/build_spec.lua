-- the models and screens as they ship; made-up fixtures only
local cjson = require("cjson")

local LIBRARY = cjson.encode({
    { lpath = "Austen, Jane/Pride and Prejudice.epub", title = "Pride and Prejudice", authors = { "Jane Austen" },
        tags = { "fiction.classics", "romance" }, application_id = 1 },
    { lpath = "Melville, Herman/Moby Dick.epub", title = "Moby Dick", authors = { "Herman Melville" },
        tags = { "fiction.classics" }, application_id = 2 },
    { lpath = "Darwin, Charles/On the Origin of Species.epub", title = "On the Origin of Species",
        authors = { "Charles Darwin" }, tags = { "science" }, application_id = 3 },
    { lpath = "Shelley, Mary/Frankenstein.epub", title = "Frankenstein", authors = { "Mary Shelley" },
        tags = {}, application_id = 4 },
    { lpath = "fanfic/Sherlock Holmes/A Study in Tea - anon.epub", title = "A Study in Tea", authors = { "anon" },
        tags = { "Sherlock Holmes" }, application_id = 5 },
})

local KOREADER = {
    ["Austen, Jane/Pride and Prejudice.epub"] = "reading",
    ["Melville, Herman/Moby Dick.epub"] = "complete",
    ["Darwin, Charles/On the Origin of Species.epub"] = "abandoned",
}

describe("build", function()

    it("every model loads", function()
        for _, m in ipairs({ "articles", "bookinfo", "build", "callable", "comeback", "fanfic", "ficinfo", "home",
            "hometext", "http", "infotext", "library", "manga", "markas", "menus", "readerbook", "readstate", "search",
            "settings", "shelves", "shelvestext", "themepatch", "updates" }) do
            assert.is_not_nil(require("bookbindery/" .. m), m)
        end
    end)

    describe("statuses and shelves", function()
        local Library, Shelves, index
        local OPENED = { ["Shelley, Mary/Frankenstein.epub"] = true }

        local function koreader(lpath)
            return KOREADER[lpath], KOREADER[lpath] ~= nil or OPENED[lpath] or false
        end

        setup(function()
            Library = require("bookbindery/library")
            Shelves = require("bookbindery/shelves")
            index = Library.fallbacks(assert(Library.parse(LIBRARY, cjson.decode)), koreader, {})
        end)

        it("takes KOReader's own status; opened without one is reading, never opened to read", function()
            assert.equal("reading", index.books["Austen, Jane/Pride and Prejudice.epub"].status)
            assert.equal("read", index.books["Melville, Herman/Moby Dick.epub"].status)
            assert.equal("dnf", index.books["Darwin, Charles/On the Origin of Species.epub"].status)
            assert.equal("reading", index.books["Shelley, Mary/Frankenstein.epub"].status)
            assert.equal("tbr", index.books["fanfic/Sherlock Holmes/A Study in Tea - anon.epub"].status)
            assert.same({ reading = 2, tbr = 0, read = 1, dnf = 1 }, Shelves.status_counts(index))
        end)

        it("a book marked to read stays to read, opened or not", function()
            Library.fallbacks(index, koreader, { ["Shelley, Mary/Frankenstein.epub"] = true })
            assert.equal("tbr", index.books["Shelley, Mary/Frankenstein.epub"].status)
            Library.fallbacks(index, koreader, {})
            assert.equal("reading", index.books["Shelley, Mary/Frankenstein.epub"].status)
        end)

        it("builds the tree from the first tag", function()
            local tree = Shelves.tree(index)
            assert.equal(3, tree.count)
            local names = {}
            for _, c in ipairs(tree.children) do
                names[#names + 1] = c.name .. " " .. c.count
            end
            assert.same({ "fiction 2", "science 1" }, names)
            assert.equal(2, #Shelves.books(index, "fiction.classics", "none")[1].books)
        end)

        it("KOReader's own status wins over #workflow, which wins over KOReader's default", function()
            local function um(workflow)
                return { ["#workflow"] = { ["#value#"] = { workflow } }, ["#type"] = { ["#value#"] = { "poetry" } } }
            end
            local own = assert(Library.parse(cjson.encode({
                { lpath = "a.epub", title = "a", tags = { "x" }, user_metadata = um("READ") },
                { lpath = "b.epub", title = "b", tags = { "y" }, user_metadata = um("DNF") },
                { lpath = "c.epub", title = "c", tags = { "z" } },
            }), cjson.decode))
            local states = { ["a.epub"] = { own = "reading", opened = true }, ["b.epub"] = { opened = true } }
            local function koreader_of(l)
                local st = states[l] or {}
                return st.own, st.opened or false
            end
            Library.fallbacks(own, koreader_of, {})
            assert.equal("reading", own.books["a.epub"].status)
            assert.equal("dnf", own.books["b.epub"].status)
            assert.equal("tbr", own.books["c.epub"].status)
            assert.same({}, own.books["c.epub"].types)
            states["a.epub"] = { opened = true }
            Library.fallbacks(own, koreader_of, {})
            assert.equal("read", own.books["a.epub"].status)
        end)
    end)

    describe("to read", function()
        local ToRead = require("bookbindery/toread")

        local function fake_io(files)
            return {
                read = function(p) return files[p] end,
                write = function(p, s) files[p] = s return true end,
                rename = function(a, b) files[b], files[a] = files[a], nil return true end,
                serialize = function(t)
                    local keys = {}
                    for k in pairs(t) do
                        keys[#keys + 1] = string.format("[%q] = true", k)
                    end
                    table.sort(keys)
                    return "return {" .. table.concat(keys, ", ") .. "}"
                end,
                deserialize = function(s) return setfenv(assert(loadstring(s)), {})() end,
            }
        end

        it("marks and clears a book, saved through a tmp file", function()
            local files = {}
            local io_ = fake_io(files)
            local map = ToRead.load("/d/toread.lua", io_)
            assert.same({}, map)
            assert.is_true(ToRead.set(map, "a.epub", true))
            assert.is_false(ToRead.set(map, "a.epub", true))
            assert.truthy(ToRead.save("/d/toread.lua", io_, map))
            assert.is_nil(files["/d/toread.lua.new"])
            assert.same({ ["a.epub"] = true }, ToRead.load("/d/toread.lua", io_))
            assert.is_true(ToRead.set(map, "a.epub", false))
            assert.same({}, map)
        end)

        it("starts empty on a broken file", function()
            assert.same({}, ToRead.load("/d/toread.lua", fake_io({ ["/d/toread.lua"] = "return {" })))
        end)
    end)

    describe("wording", function()
        it("has the default words", function()
            local Wording = require("bookbindery/wording")
            assert.equal("#pages", Wording.pages_column)
            assert.equal("this device", Wording.device)
            assert.equal("folder", Wording.folder_label)
            assert.is_nil(Wording.books_root)
            assert.is_true(Wording.is_book("Austen, Jane/Emma.epub"))
            assert.is_false(Wording.is_book("fanfic/x/y.epub"))
        end)
    end)

    describe("home", function()
        it("has the reading books and nothing else", function()
            local Home = require("bookbindery/home")
            local m = Home.model({ { title = "Moby Dick", percent = 0.5 } }, 2000)
            assert.same({ "current", "now", "reading_count" }, (function()
                local keys = {}
                for k in pairs(m) do
                    keys[#keys + 1] = k
                end
                table.sort(keys)
                return keys
            end)())
            assert.equal("Moby Dick", m.current.title)
        end)

        it("counts fandoms on the fanfic tile", function()
            local HomeText = require("bookbindery/hometext")
            assert.equal("1 fandom", HomeText.fandoms(1))
            assert.equal("3 fandoms", HomeText.fandoms(3))
        end)
    end)

    describe("mark as", function()
        it("offers the four statuses, to read clears KOReader's", function()
            local MarkAs = require("bookbindery/markas")
            local rows = MarkAs.statuses("tbr")
            assert.equal(4, #rows)
            assert.is_true(rows[1].checked)
            assert.is_nil(MarkAs.koreader("TBR"))
            assert.equal("complete", MarkAs.koreader("READ"))
            assert.equal("abandoned", MarkAs.koreader("DNF"))
        end)
    end)

    describe("search", function()
        it("offers the offline scopes and the handoffs", function()
            local Search = require("bookbindery/search")
            assert.same({ "library", "fanfic", "manga", "dictionary" }, Search.scopes(false, false))
        end)

        it("searches the library", function()
            local Library = require("bookbindery/library")
            local Search = require("bookbindery/search")
            local index = assert(Library.parse(LIBRARY, cjson.decode))
            local r = Search.run("moby", "library", index, nil)
            assert.equal(1, #r)
            assert.equal("Moby Dick", r[1].title)
        end)
    end)

    describe("menus", function()
        it("place KOReader's entries under bookbindery's rows", function()
            local Menus = require("bookbindery/menus")
            local tabs = Menus.place({
                { id = "main", text = "main", tab = "main", kind = "sub", depth = 0 },
                { id = "history", text = "History", tab = "main", kind = "callback", depth = 1, parent = "main" },
                { id = "opds", text = "OPDS catalog", tab = "main", kind = "callback", depth = 1, parent = "main" },
            })
            assert.equal("opds catalog", tabs[2].rows[1].label)
            local library = tabs[1].rows
            assert.same({ "home", "shelves", "history" }, { library[1].label, library[2].label, library[3].label })
        end)
    end)

    describe("settings", function()
        it("shows covers, pins and the build", function()
            local Settings = require("bookbindery/settings")
            local texts = {}
            for _, r in ipairs(Settings.rows({ covers = false, pinned = 0, build = "b" })) do
                texts[#texts + 1] = r.text or r.note
            end
            assert.same({ "manga covers", "covers come from rakuyomi's sources", "clear pinned shelves", "build" },
                texts)
        end)
    end)

    describe("updates", function()
        it("words manga and articles", function()
            local Updates = require("bookbindery/updates")
            assert.equal("no unread articles", Updates.articles({}))
            assert.equal("rakuyomi isn't installed", Updates.manga(nil, Updates.missing("rakuyomi")))
        end)
    end)

    describe("book info", function()
        it("has calibre's and KOReader's rows only", function()
            local BookInfo = require("bookbindery/bookinfo")
            local book = { title = "Frankenstein", authors = { "Mary Shelley" }, tags = {} }
            local m = BookInfo.model(book, {}, nil, 2000)
            local labels = {}
            for _, r in ipairs(m.rows) do
                labels[#labels + 1] = r.label
            end
            assert.same({ "progress", "highlights" }, labels)
        end)
    end)

    describe("navigation", function()
        it("installs with the tabs it has", function()
            package.loaded["ui/uimanager"] = { show = function() end, close = function() end }
            package.loaded["ui/event"] = {}
            package.loaded["ui/time"] = {}
            package.loaded["logger"] = {}
            package.loaded["libs/libkoreader-lfs"] = {}
            package.loaded["ffi/util"] = { template = function(s) return s end }
            package.loaded["gettext"] = function(s) return s end
            local B = {}
            require("bookbindery/bbui/navigation")(B, { state = {}, toast = function() end,
                logger = { err = function() end } })
            assert.is_function(B.route)
            assert.is_nil(B.showList)
        end)
    end)

    describe("screens", function()
        local function fake_koreader()
            local stub = setmetatable({}, { __index = function() return function() end end })
            for _, m in ipairs({ "ui/widget/container/framecontainer", "ui/widget/horizontalgroup",
                "bookbindery/bbui/cover", "bookbindery/bbui/pagedlist", "ui/uimanager", "logger", "ui/time" }) do
                package.loaded[m] = stub
            end
            package.loaded["ui/widget/verticalgroup"] = { new = function(_, t) return t end }
            package.loaded["device"] = { screen = { getWidth = function() return 600 end } }
            package.loaded["gettext"] = function(t) return t end
            package.loaded["ffi/util"] = { template = function(t, a) return (t:gsub("%%1", tostring(a))) end }
            package.loaded["bookbindery/bbui/theme"] = { space = { 0, 0, 0, 0 } }
            local function mark(kind) return function(a) return { kind = kind, text = a } end end
            package.loaded["bookbindery/bbui/parts"] = { px = function(n) return n end, text = mark("text"),
                button = mark("button"), hspan = mark("span"), vspan = mark("span"), menu_button = mark("menu"),
                spread = function(_, a, b) return { kind = "spread", a, b } end }
        end

        it("updates: manga and articles", function()
            fake_koreader()
            local UpdatesScreen = require("bookbindery/bbui/updatesscreen")
            local rows = UpdatesScreen.rows({ manga = "2 new chapters", rakuyomi = true, articles = "3 unread",
                wallabag = true, on_manga = function() end, on_sync = function() end })
            local labels = {}
            for _, r in ipairs(rows) do
                if r.label then
                    labels[#labels + 1] = r.label
                end
            end
            assert.same({ "manga · rakuyomi", "articles · wallabag" }, labels)
            local header = UpdatesScreen.header({ on_check_all = function() end })
            assert.equal(1, #header)
        end)

        it("mark as sets KOReader's status, creating a sidecar", function()
            fake_koreader()
            local sheet
            package.loaded["bookbindery/bbui/sheet"] = { new = function(_, opts)
                sheet = { opts = opts, onClose = function() end }
                return sheet
            end }
            local calls, marks = {}, {}
            local B = { ui = {} }
            require("bookbindery/bbui/infonavigation")(B, {
                books_root = function() return "/books/" end,
                toast = function() end,
                library = function() return nil end,
                koreader_status = function(...) calls[#calls + 1] = { ... } end,
                to_read = function(lpath, on) marks[#marks + 1] = { lpath, on } end,
            })
            function B:safely(_, fn) fn() return true end
            function B:showOverlay() end
            function B:markStale() end
            local changed = 0
            local entry = { lpath = "Shelley, Mary/Frankenstein.epub", title = "Frankenstein", status = "tbr" }
            B:showMarkAs(entry, function() changed = changed + 1 end)
            assert.is_nil(sheet.opts.button)
            assert.equal("sets koreader's reading status", sheet.opts.note)
            sheet.opts.rows[1].callback()
            sheet.opts.rows[3].callback()
            entry.status = "read"
            B:showMarkAs(entry, function() changed = changed + 1 end)
            sheet.opts.rows[1].callback()
            local file = "/books/Shelley, Mary/Frankenstein.epub"
            assert.same({ { file, "complete", true }, { file, nil, true } }, calls)
            assert.same({ { entry.lpath, false }, { entry.lpath, true } }, marks)
            assert.equal(2, changed)
        end)
    end)
end)
