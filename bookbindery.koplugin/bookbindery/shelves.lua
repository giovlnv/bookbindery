local Shelves = {}

local FANFIC = "fanfic/"

local function in_scope(lpath)
    return lpath:sub(1, #FANFIC) ~= FANFIC
end

function Shelves.status_counts(index)
    local c = { reading = 0, tbr = 0, read = 0, dnf = 0 }
    for _, b in ipairs(index.list) do
        if b.status and c[b.status] and in_scope(b.lpath) then
            c[b.status] = c[b.status] + 1
        end
    end
    return c
end

local function by_count_then_name(a, b)
    if a.count ~= b.count then
        return a.count > b.count
    end
    return a.name < b.name
end

local function sort_tree(node)
    node.children = {}
    for _, c in pairs(node.map) do
        node.children[#node.children + 1] = c
        sort_tree(c)
    end
    node.map = nil
    table.sort(node.children, by_count_then_name)
end

function Shelves.tree(index)
    local root = { name = "", path = "", count = 0, map = {} }
    for _, b in ipairs(index.list) do
        if in_scope(b.lpath) and #b.types > 0 then
            root.count = root.count + 1
            local seen = {}
            for _, t in ipairs(b.types) do
                local node, path = root, nil
                for seg in t:gmatch("[^.]+") do
                    path = path and (path .. "." .. seg) or seg
                    local child = node.map[seg]
                    if not child then
                        child = { name = seg, path = path, count = 0, map = {} }
                        node.map[seg] = child
                    end
                    if not seen[path] then
                        seen[path] = true
                        child.count = child.count + 1
                    end
                    node = child
                end
            end
        end
    end
    sort_tree(root)
    return root
end

local function matches(types, path)
    if path == nil or path == "" then
        return types[1]
    end
    for _, t in ipairs(types) do
        if t == path or t:sub(1, #path + 1) == path .. "." then
            return t
        end
    end
end

local function title_order(a, b)
    local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
    if ta ~= tb then
        return ta < tb
    end
    return a.lpath < b.lpath
end

local function volume_order(a, b)
    local ka, kb = (a.series or a.title or ""):lower(), (b.series or b.title or ""):lower()
    if ka ~= kb then
        return ka < kb
    end
    local ia, ib = a.series_index or math.huge, b.series_index or math.huge
    if ia ~= ib then
        return ia < ib
    end
    return title_order(a, b)
end

-- items: { book, type } pairs; groups by shelf (the type), author, series or nothing
function Shelves.group(items, group_by)
    local groups, by_label = {}, {}
    for _, it in ipairs(items) do
        local b = it[1]
        local label = ""
        if group_by == "shelf" then
            label = it[2] or ""
        elseif group_by == "author" then
            label = b.authors[1] or ""
        elseif group_by == "series" then
            label = b.series or ""
        end
        if not by_label[label] then
            by_label[label] = { label = label, books = {} }
            groups[#groups + 1] = by_label[label]
        end
        local list = by_label[label].books
        list[#list + 1] = b
    end
    table.sort(groups, function(a, b)
        if (a.label == "") ~= (b.label == "") then
            return b.label == ""
        end
        return a.label:lower() < b.label:lower()
    end)
    for _, g in ipairs(groups) do
        table.sort(g.books, volume_order)
    end
    return groups
end

function Shelves.books(index, path, group_by, status)
    local items = {}
    for _, b in ipairs(index.list) do
        if in_scope(b.lpath) and (not status or b.status == status) then
            local type_ = matches(b.types, path)
            if type_ or (path == nil or path == "") then
                items[#items + 1] = { b, type_ }
            end
        end
    end
    return Shelves.group(items, group_by)
end

function Shelves.find(root, path)
    if not path or path == "" then
        return root
    end
    local node = root
    for seg in path:gmatch("[^.]+") do
        local found
        for _, c in ipairs(node.children) do
            if c.name == seg then
                found = c
                break
            end
        end
        if not found then
            return nil
        end
        node = found
    end
    return node
end

local function pinned_first(children, pinned)
    local out = {}
    for _, c in ipairs(children) do
        if pinned[c.path] then
            out[#out + 1] = c
        end
    end
    for _, c in ipairs(children) do
        if not pinned[c.path] then
            out[#out + 1] = c
        end
    end
    return out
end

function Shelves.rows(node, open, pinned, order)
    local out = {}
    local function walk(n, depth)
        local children = order and order(n) or n.children
        for _, c in ipairs(pinned_first(children, pinned or {})) do
            local is_open = open[c.path] and #c.children > 0 or false
            out[#out + 1] = { node = c, depth = depth, open = is_open, pinned = (pinned or {})[c.path] or false }
            if is_open then
                walk(c, depth + 1)
            end
        end
    end
    walk(node, 0)
    return out
end

return Shelves
