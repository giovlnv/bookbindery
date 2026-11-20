local Fanfic = {}

local FANFIC = "fanfic/"

local function in_fanfic(lpath)
    return lpath:sub(1, #FANFIC) == FANFIC
end

local function fandom_of(lpath)
    return lpath:match("^fanfic/([^/]+)/") or "other"
end

local function parse_name(lpath)
    local name = lpath:match("([^/]+)$"):gsub("%.[^.]*$", "")
    local title, author = name:match("^(.*) %- (.*)$")
    if title then
        return title, { author }
    end
    return name, {}
end

-- every work on the device: from `files` when given, else from the index alone
function Fanfic.entries(index, files)
    local out = {}
    local function add(lpath)
        local b = index.books[lpath]
        local title, authors
        if b then
            title, authors = b.title, b.authors
        else
            title, authors = parse_name(lpath)
        end
        out[#out + 1] = { lpath = lpath, fandom = fandom_of(lpath), title = title, authors = authors, id = b and b.id }
    end
    if files then
        for _, l in ipairs(files) do
            if in_fanfic(l) then
                add(l)
            end
        end
    else
        for _, b in ipairs(index.list) do
            if in_fanfic(b.lpath) then
                add(b.lpath)
            end
        end
    end
    return out
end

local function new_chapters()
    return 0
end

function Fanfic.fandoms(index, works, files)
    local map, list = {}, {}
    for _, e in ipairs(Fanfic.entries(index, files)) do
        local f = map[e.fandom]
        if not f then
            f = { name = e.fandom, n = 0, new = 0 }
            map[e.fandom] = f
            list[#list + 1] = f
        end
        f.n = f.n + 1
        if new_chapters(e, works) > 0 then
            f.new = f.new + 1
        end
    end
    table.sort(list, function(a, b)
        if (a.new > 0) ~= (b.new > 0) then
            return a.new > 0
        end
        if a.n ~= b.n then
            return a.n > b.n
        end
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then
            return x < y
        end
        return a.name < b.name
    end)
    return list
end

function Fanfic.works(index, fandom, works, files, status_of)
    local list = {}
    for _, e in ipairs(Fanfic.entries(index, files)) do
        if e.fandom == fandom then
            list[#list + 1] = {
                title = e.title,
                authors = e.authors,
                lpath = e.lpath,
                new_chapters = new_chapters(e, works),
                status = status_of and status_of(e.lpath) or nil,
            }
        end
    end
    table.sort(list, function(a, b)
        if (a.new_chapters > 0) ~= (b.new_chapters > 0) then
            return a.new_chapters > 0
        end
        local x, y = a.title:lower(), b.title:lower()
        if x ~= y then
            return x < y
        end
        if a.title ~= b.title then
            return a.title < b.title
        end
        return a.lpath < b.lpath
    end)
    return list
end

-- info: { status, percent } from the sidecar (status "complete" is finished)
function Fanfic.status(info)
    if not info then
        return nil
    end
    if info.status == "complete" then
        return "read"
    end
    if info.status == "reading" or (info.percent or 0) > 0 then
        return "reading"
    end
    return nil
end

return Fanfic
