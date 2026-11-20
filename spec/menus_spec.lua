local cjson = require("cjson")
local Menus = require("bookbindery/menus")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local inventory = cjson.decode(slurp("spec/fixtures/fm-menu.json"))

local function without(inv, drop)
    local out = {}
    for _, e in ipairs(inv) do
        if not drop[e.id] and not drop[e.plugin or ""] then
            out[#out + 1] = e
        end
    end
    return out
end

local function tab(tabs, name)
    for _, t in ipairs(tabs) do
        if t.tab == name then
            return t
        end
    end
end

-- every id a row or "more" reaches, counted once per row, and the ids reached through an ancestor
local function reach(inv, tabs)
    local rows, count = {}, {}
    for _, t in ipairs(tabs) do
        for _, r in ipairs(t.rows) do
            rows[#rows + 1] = r
        end
        for _, r in ipairs(t.more or {}) do
            rows[#rows + 1] = r
        end
    end
    local direct = {}
    for _, r in ipairs(rows) do
        local list = { r.id }
        for _, id in ipairs(r.covers or {}) do
            list[#list + 1] = id
        end
        for _, id in pairs(list) do
            count[id] = (count[id] or 0) + 1
            direct[id] = true
        end
    end
    local parent = {}
    for _, e in ipairs(inv) do
        parent[e.id] = e.parent
    end
    local reached = {}
    for _, e in ipairs(inv) do
        local p = e.id
        while p do
            if direct[p] then
                reached[e.id] = true
                break
            end
            p = parent[p]
        end
    end
    return reached, count, rows
end

local function ids(inv)
    local out = {}
    for _, e in ipairs(inv) do
        out[e.id] = true
    end
    return out
end

describe("menus", function()
    it("has the five tabs in order", function()
        local names = {}
        for _, t in ipairs(Menus.place(inventory)) do
            names[#names + 1] = t.tab
        end
        assert.same({ "library", "sources", "reading", "device", "system" }, names)
    end)

    it("reaches every inventory id, each row id once", function()
        local tabs = Menus.place(inventory)
        local reached, count = reach(inventory, tabs)
        for _, e in ipairs(inventory) do
            if e.id ~= e.tab then
                assert.is_true(reached[e.id] or false, e.id .. " unreachable")
            end
        end
        for id, n in pairs(count) do
            assert.equal(1, n, id .. " placed twice")
        end
    end)

    it("puts in more only ids nothing placed reaches", function()
        local tabs = Menus.place(inventory)
        local placed = {}
        for _, t in ipairs(tabs) do
            for _, r in ipairs(t.rows) do
                if r.id then
                    placed[r.id] = true
                end
                for _, id in ipairs(r.covers or {}) do
                    placed[id] = true
                end
            end
        end
        local inv = ids(inventory)
        for _, r in ipairs(tab(tabs, "system").more) do
            assert.is_nil(placed[r.id])
            assert.is_true(inv[r.id])
        end
    end)

    it("places spec labels on koreader ids", function()
        local tabs = Menus.place(inventory)
        local function row(t, label)
            for _, r in ipairs(tab(tabs, t).rows) do
                if r.label == label then
                    return r
                end
            end
        end
        assert.equal("history", row("library", "history").id)
        assert.equal("home", row("library", "home").bb)
        assert.equal("opds", row("sources", "opds catalog").id)
        assert.equal("statistics", row("reading", "statistics").id)
        assert.equal("ssh", row("device", "ssh").id)
        assert.equal("exit_menu", row("system", "restart / exit").id)
        assert.equal("koreader_menu", row("system", "koreader menu").bb)
        assert.equal("sub", row("device", "wi-fi").kind)
        assert.equal("callback", row("library", "history").kind)
    end)

    it("sorts more by text", function()
        local more = tab(Menus.place(inventory), "system").more
        assert.is_true(#more > 0)
        for i = 2, #more do
            assert.is_true(more[i - 1].label:lower() <= more[i].label:lower())
        end
    end)

    it("puts an unknown new id in more", function()
        local inv = without(inventory, {})
        inv[#inv + 1] = {
            id = "shiny_new", text = "Shiny new", tab = "tools", kind = "callback", depth = 1, parent = "tools",
        }
        local found
        for _, r in ipairs(tab(Menus.place(inv), "system").more) do
            found = found or r.id == "shiny_new"
        end
        assert.is_true(found)
    end)

    it("puts an id with no parent in more", function()
        local inv = without(inventory, {})
        inv[#inv + 1] = { id = "orphan", text = "Orphan", tab = "main", kind = "callback" }
        local found
        for _, r in ipairs(tab(Menus.place(inv), "system").more) do
            found = found or r.id == "orphan"
        end
        assert.is_true(found)
    end)

    it("skips rows whose id is missing (plugin off), keeps bookbindery rows", function()
        local inv = without(inventory, { SSH = true, rakuyomi = true })
        local tabs = Menus.place(inv)
        for _, r in ipairs(tab(tabs, "device").rows) do
            assert.not_equal("ssh", r.id)
        end
        local manga
        for _, r in ipairs(tab(tabs, "sources").rows) do
            if r.bb == "manga" then
                manga = r
            end
        end
        assert.same({}, manga.covers)
        local reached = reach(inv, tabs)
        for _, e in ipairs(inv) do
            if e.id ~= e.tab then
                assert.is_true(reached[e.id] or false, e.id)
            end
        end
    end)

    it("keeps a submenu whole around a placed child", function()
        local more = tab(Menus.place(inventory), "system").more
        local got = {}
        for _, r in ipairs(more) do
            got[r.id] = true
        end
        assert.is_true(got.more_tools)
        assert.is_nil(got.battery_statistics)
        assert.is_nil(got.terminal)
    end)

    it("never repeats a label, within more or across all tabs", function()
        local seen = {}
        for _, t in ipairs(Menus.place(inventory)) do
            for _, list in ipairs({ t.rows, t.more or {} }) do
                for _, r in ipairs(list) do
                    local l = r.label:lower()
                    assert.is_nil(seen[l], "label twice: " .. r.label)
                    seen[l] = true
                end
            end
        end
    end)

    it("qualifies a repeated label by its parent", function()
        local labels = {}
        for _, r in ipairs(tab(Menus.place(inventory), "system").more) do
            labels[r.id] = r.label
        end
        assert.equal("file browser settings", labels.filebrowser_settings)
        assert.equal("search settings", labels.search_settings)
    end)

    it("uses fixed labels, not the current value after a colon", function()
        local labels = {}
        for _, r in ipairs(tab(Menus.place(inventory), "system").more) do
            labels[r.id] = r.label
        end
        assert.equal("Sort by", labels.sort_by)
        assert.equal("Start with", labels.start_with)
        assert.equal("Book status", labels.show_filter)
    end)

    it("survives entries with no or odd text", function()
        local inv = without(inventory, {})
        inv[#inv + 1] = { id = "no_text", tab = "tools", kind = "callback", depth = 1, parent = "tools" }
        inv[#inv + 1] = { id = "fn_text", text = function() end, tab = "tools", kind = "callback", depth = 1,
            parent = "tools" }
        local labels = {}
        for _, r in ipairs(tab(Menus.place(inv), "system").more) do
            labels[r.id] = r.label
        end
        assert.equal("no_text", labels.no_text)
        assert.equal("string", type(labels.fn_text))
    end)

    it("has bookbindery's own rows", function()
        local bb = {}
        for _, t in ipairs(Menus.place(inventory)) do
            for _, r in ipairs(t.rows) do
                if r.bb then
                    bb[#bb + 1] = r.bb
                end
            end
        end
        assert.same({ "home", "shelves", "fanfic", "manga", "articles", "settings", "koreader_menu" }, bb)
    end)

    it("never mutates the inventory", function()
        local before = cjson.encode(inventory)
        Menus.place(inventory)
        assert.equal(before, cjson.encode(inventory))
    end)
    describe("inventory", function()
        local called = false
        local function live()
            return {
                { id = "main", icon = "appbar.menu",
                    { id = "history", text = "History", callback = function() end },
                    { id = "sort_by", text_func = function() return "Sort by: name" end,
                        sub_item_table = { { text = "name", callback = function() end } } },
                    { id = "broken", text_func = function() error("boom") end, callback = function() end },
                    { id = "lazy", text = "Lazy", sub_item_table_func = function() called = true end },
                },
                { id = "setting", icon = "appbar.settings",
                    { id = "network", text = "Network", sub_item_table = {
                        { id = "ssh", text = "SSH", sub_item_table = { { id = "ssh_port", text = "Port",
                            callback = function() end } } },
                        { text = "inline", sub_item_table = { { id = "deep", text = "Deep", callback = function() end,
                            sub_item_table = {} } } },
                    } },
                    { id = "history", text = "History again", callback = function() end },
                    { text = "no id, no table" },
                },
            }
        end

        it("shapes the live menu like the fixture", function()
            local inv, items = Menus.inventory(live())
            local by = {}
            for _, e in ipairs(inv) do
                assert.is_nil(by[e.id], "twice: " .. e.id)
                by[e.id] = e
            end
            assert.same({ id = "main", text = "main", tab = "main", kind = "sub", depth = 0 }, by.main)
            assert.same({ id = "history", text = "History", tab = "main", kind = "callback", depth = 1,
                parent = "main" }, by.history)
            assert.equal("Sort by: name", by.sort_by.text)
            assert.equal("sub", by.sort_by.kind)
            assert.equal("broken", by.broken.text)
            assert.equal("sub", by.lazy.kind)
            assert.is_false(called)
            assert.same({ tab = "setting", parent = "ssh", depth = 3 },
                { tab = by.ssh_port.tab, parent = by.ssh_port.parent, depth = by.ssh_port.depth })
            assert.same({ parent = "network", kind = "both", depth = 2 },
                { parent = by.deep.parent, kind = by.deep.kind, depth = by.deep.depth })
            assert.equal("History", items.history.text)
            assert.equal("appbar.settings", items.setting.icon)
            assert.equal(10, #inv)
        end)

        it("places the shaped inventory with every id reachable", function()
            local inv = Menus.inventory(live())
            local tabs = Menus.place(inv)
            local reached = reach(inv, tabs)
            for _, e in ipairs(inv) do
                if e.id ~= e.tab then
                    assert.is_true(reached[e.id] or false, e.id)
                end
            end
        end)

        it("takes nothing", function()
            assert.same({}, (Menus.inventory(nil)))
        end)
    end)
    describe("status", function()
        it("greys disabled items and notes values", function()
            assert.same({ true, nil }, { Menus.status({ text = "History" }) })
            assert.same({ true, "name" }, { Menus.status({ text_func = function() return "Sort by: name" end }) })
            assert.same({ false, nil }, { Menus.status({ text = "x", enabled_func = function() return false end }) })
            assert.same({ false, nil }, { Menus.status({ text = "x", enabled = false }) })
            local night = { text = "Night mode", checked_func = function() return true end }
            assert.same({ true, "on" }, { Menus.status(night) })
            assert.same({ true, "off" }, { Menus.status({ text = "x", checked_func = function() error("no") end }) })
            assert.same({ true, nil }, { Menus.status(nil) })
        end)
    end)
end)
