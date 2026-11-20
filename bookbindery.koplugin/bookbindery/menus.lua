--[[--
Menus: bookbindery's five menu tabs (spec screen 14) over KOReader's file manager
menu, pure Lua. A row is a KOReader menu id (`id`) or a bookbindery screen (`bb`);
`covers` lists the KOReader ids a bookbindery row stands in for. `place` drops rows
whose id the live menu lacks (plugin off) and puts every id nothing placed reaches
under system's `more` (a submenu whole), so no entry is lost.

Reader menu: KOReader builds its tabs from `KOMenu:menu_buttons` merged with
settings/reader_menu_order.lua (readermenu.lua setUpdateItemTable, MenuSorter:mergeAndSort),
so a new tab needs no fork, only a runtime wrap of MenuSorter. That would make 9 tab icons,
so the reader gets a "book" entry instead.
]]

local Wording = require("bookbindery/wording")

local Menus = {}

-- names of KOReader's file manager tabs, for qualifying a repeated label
Menus.TAB_NAMES = {
    filemanager_settings = "file browser",
    setting = "settings",
    tools = "tools",
    search = "search",
    main = "main",
}

-- the entry's fixed name: its text without a current value after a colon ("Sort by: name")
local function name(e)
    local t = e and e.text
    t = type(t) == "string" and t ~= "" and t or tostring(e and e.id)
    return t:match("^(.-):%s") or t
end

Menus.LAYOUT = {
    { tab = "library", rows = {
        { bb = "home", label = "home", covers = { "bookbindery_home" } },
        { bb = "shelves", label = "shelves" },
        { id = "history", label = "history" },
        { id = "favorites", label = "favorites" },
        { id = "collections", label = "collections" },
    } },
    { tab = "sources", rows = {
        { id = "opds", menu = "opds" },
        { bb = "fanfic", label = "fanfic" },
        { bb = "manga", label = "manga (rakuyomi)", covers = { "rakuyomi" } },
        { bb = "articles", label = "articles (wallabag)" },
        { id = "calibre", label = "calibre wireless" },
    } },
    { tab = "reading", rows = {
        { id = "statistics", label = "statistics" },
        { id = "exporter", label = "highlights export" },
        { id = "dictionary_settings", label = "dictionary" },
        { id = "vocabbuilder", label = "vocab builder" },
        { id = "read_timer", label = "read timer" },
    } },
    { tab = "device", rows = {
        { id = "frontlight", label = "frontlight" },
        { id = "network", label = "wi-fi" },
        { id = "screen", label = "screen & sleep" },
        { id = "taps_and_gestures", label = "gestures" },
        { id = "synchronize_time", label = "time sync" },
        { id = "ssh", label = "ssh" },
        { id = "profiles", label = "profiles" },
    } },
    { tab = "system", rows = {
        { id = "plugin_management", label = "plugins" },
        { id = "patch_management", label = "patches" },
        { id = "advanced_settings", label = "advanced" },
        { id = "text_editor", label = "text editor" },
        { id = "terminal", label = "terminal" },
        { id = "help", label = "help" },
        { id = "exit_menu", label = "restart / exit" },
        { bb = "settings", label = "bookbindery settings" },
        { bb = "koreader_menu", label = "koreader menu" },
    } },
}

local function kind_of(item)
    local sub = item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
    local cb = item.callback ~= nil or item.callback_func ~= nil
    return sub and cb and "both" or sub and "sub" or cb and "callback" or "none"
end

-- an item's current text (text, else text_func), nil when it has none or text_func fails
function Menus.text(item)
    local t = item.text
    if t == nil and type(item.text_func) == "function" then
        local ok, v = pcall(item.text_func)
        t = ok and v or nil
    end
    return type(t) == "string" and t or nil
end

local function call(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn)
    if ok then
        return v
    end
end

-- a live item's row state: enabled (enabled / enabled_func), note ("on"/"off" for a checkbox,
-- else the current value after a colon in its text)
function Menus.status(item)
    if not item then
        return true, nil
    end
    local enabled = item.enabled ~= false and (item.enabled_func == nil or call(item.enabled_func) ~= false)
    if item.checked ~= nil or item.checked_func then
        local on = item.checked_func and call(item.checked_func) or item.checked
        return enabled, on and "on" or "off"
    end
    local t = Menus.text(item)
    return enabled, t and t:match("^.-:%s+(.+)$") or nil
end

-- KOReader's sorted file manager menu (FileManagerMenu.tab_item_table) → the inventory
-- (fixture shape: id, text, tab, kind, depth, parent) and its live items by id (tabs included).
-- Walks static sub_item_tables only, never calls sub_item_table_func.
function Menus.inventory(tab_item_table)
    local inv, items = {}, {}
    local function walk(list, tab, parent, depth)
        for _, item in ipairs(list) do
            if type(item) == "table" then
                local p, d = parent, depth
                if item.id and not items[item.id] then
                    items[item.id] = item
                    inv[#inv + 1] = { id = item.id, text = Menus.text(item) or tostring(item.id), tab = tab,
                        kind = kind_of(item), depth = depth, parent = parent }
                    p, d = item.id, depth + 1
                end
                if type(item.sub_item_table) == "table" then
                    walk(item.sub_item_table, tab, p, d)
                end
            end
        end
    end
    for _, t in ipairs(tab_item_table or {}) do
        if type(t) == "table" and t.id and not items[t.id] then
            items[t.id] = t
            inv[#inv + 1] = { id = t.id, text = t.id, tab = t.id, kind = "sub", depth = 0 }
            walk(t, t.id, t.id, 1)
        end
    end
    return inv, items
end

-- inventory: { {id, text, tab, kind, parent?} } from the live file manager menu
-- → { {tab, rows = { {id|bb, label, kind?, covers?} }, more? } }, more only on system
-- a row with menu takes its label from Wording.menu (nil: KOReader's text)
function Menus.place(inventory)
    local by_id, children = {}, {}
    for _, e in ipairs(inventory) do
        by_id[e.id] = e
    end
    for _, e in ipairs(inventory) do
        if e.parent and by_id[e.parent] then
            children[e.parent] = children[e.parent] or {}
            table.insert(children[e.parent], e)
        end
    end

    local tabs, placed = {}, {}
    for _, t in ipairs(Menus.LAYOUT) do
        local rows = {}
        for _, r in ipairs(t.rows) do
            local e = r.id and by_id[r.id]
            if r.bb or (e and not placed[r.id]) then
                local covers = {}
                for _, id in ipairs(r.covers or {}) do
                    if by_id[id] and not placed[id] then
                        placed[id], covers[#covers + 1] = true, id
                    end
                end
                if e then
                    placed[r.id] = true
                end
                local label = r.label or Wording.menu[r.menu] or (e and name(e):lower()) or r.menu
                rows[#rows + 1] = { id = r.id, bb = r.bb, label = label, kind = e and e.kind, covers = covers }
            end
        end
        tabs[#tabs + 1] = { tab = t.tab, rows = rows }
    end

    -- a submenu goes to more whole, even around a placed child: it may hold entries without ids
    local more = {}
    local function visit(e, is_tab)
        if placed[e.id] then
            return
        elseif is_tab then
            for _, c in ipairs(children[e.id] or {}) do
                visit(c)
            end
        else
            more[#more + 1] = { id = e.id, label = name(e), kind = e.kind, parent = e.parent }
        end
    end
    for _, e in ipairs(inventory) do
        if not (e.parent and by_id[e.parent]) then
            visit(e, e.id == e.tab)
        end
    end
    local count, used = {}, {}
    for _, t in ipairs(tabs) do
        for _, r in ipairs(t.rows) do
            used[r.label:lower()] = true
        end
    end
    for _, r in ipairs(more) do
        local l = r.label:lower()
        count[l] = (count[l] or 0) + 1
    end
    for _, r in ipairs(more) do
        local l = r.label:lower()
        if count[l] > 1 or used[l] then
            local p = by_id[r.parent]
            local pname = p and (Menus.TAB_NAMES[p.id] or name(p):lower()) or r.id
            r.label = pname .. " " .. l
        end
        if used[r.label:lower()] then
            r.label = r.label .. " (" .. r.id .. ")"
        end
        used[r.label:lower()], r.parent = true, nil
    end
    table.sort(more, function(a, b)
        local la, lb = a.label:lower(), b.label:lower()
        if la ~= lb then
            return la < lb
        end
        return a.id < b.id
    end)
    tabs[#tabs].more = more
    return tabs
end

return Menus
