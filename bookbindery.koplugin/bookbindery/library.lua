local Wording = require("bookbindery/wording")

local Library = {}

-- bumped whenever the cached index changes shape
local CACHE_VERSION = 3

local STATUS = { ONGOING = "reading", TBR = "tbr", READ = "read", DNF = "dnf" }
Library.STATUS = STATUS

local function values(um, key)
    local col = um and um[key]
    return col and type(col["#value#"]) == "table" and col["#value#"] or {}
end

local function status_of(um)
    for _, w in ipairs(values(um, "#workflow")) do
        if STATUS[w] then
            return STATUS[w]
        end
    end
end

local function book_of(e)
    local um = e.user_metadata
    local pages = um and um[Wording.pages_column]
    local ids = type(e.identifiers) == "table" and e.identifiers or {}
    return {
        lpath = e.lpath,
        uuid = e.uuid,
        id = e.application_id,
        library = e.lpath:find("^fanfic/") and "fanfic" or "books",
        ao3 = tonumber(ids.ao3),
        title = e.title,
        authors = e.authors or {},
        series = e.series,
        series_index = e.series_index,
        types = values(um, "#type"),
        status = status_of(um),
        comments = e.comments,
        pubdate = e.pubdate,
        rating = e.rating,
        pages = pages and pages["#value#"],
        tags = e.tags or {},
    }
end

local function index_of(list)
    local books = {}
    for _, b in ipairs(list) do
        books[b.lpath] = b
    end
    return { books = books, list = list }
end

function Library.parse(json_text, decode)
    local ok, data = pcall(decode, json_text)
    if not ok or type(data) ~= "table" then
        return nil, "invalid metadata.calibre: " .. tostring(ok and "not a list" or data)
    end
    if data[1] == nil and next(data) ~= nil then
        return nil, "invalid metadata.calibre: not a list"
    end
    local list = {}
    for _, e in ipairs(data) do
        if type(e) == "table" and e.lpath then
            list[#list + 1] = book_of(e)
        end
    end
    return index_of(list)
end

local function read_cache(cache_path, io)
    local text = io.read(cache_path)
    if not text then
        return nil
    end
    local ok, cache = pcall(io.deserialize, text)
    if ok and type(cache) == "table" and cache.version == CACHE_VERSION and type(cache.list) == "table" then
        return cache
    end
end

local function meta_path(cache_path)
    return cache_path:gsub("%.lua$", "") .. ".meta.lua"
end

-- the cache key lives in a tiny sidecar so a changed metadata.calibre is
-- detected without deserializing the whole cached index
local function cache_fresh(cache_path, attrs, io)
    local text = attrs and io.read(meta_path(cache_path))
    local ok, meta = pcall(io.deserialize, text or "")
    return ok and type(meta) == "table" and meta.version == CACHE_VERSION
        and meta.size == attrs.size and meta.mtime == attrs.modification
end

function Library.load(path, cache_path, io)
    local attrs = io.attributes(path)
    if cache_fresh(cache_path, attrs, io) then
        local cache = read_cache(cache_path, io)
        if cache then
            return index_of(cache.list)
        end
    end
    local text = attrs and io.read(path)
    local index, err
    if text then
        index, err = Library.parse(text, io.decode)
    else
        err = "cannot read " .. tostring(path)
    end
    if not index or #index.list == 0 then
        local cache = read_cache(cache_path, io)
        if cache and #cache.list > 0 then
            return index_of(cache.list)
        end
        if not index then
            return nil, err
        end
    end
    pcall(function()
        io.write(cache_path, io.serialize({ version = CACHE_VERSION, list = index.list }))
        io.write(meta_path(cache_path), io.serialize({
            version = CACHE_VERSION,
            size = attrs.size,
            mtime = attrs.modification,
        }))
    end)
    return index
end

local KOREADER = { reading = "reading", complete = "read", abandoned = "dnf" }

-- each book's status: marked to read here (toread[lpath]), else KOReader's own
-- summary.status, else #workflow, else reading once opened and to read before; koreader(lpath) → its
-- summary.status (nil when none was set) and whether it has been opened. A library without #type values
-- takes its shelves from each book's first tag.
function Library.fallbacks(index, koreader, toread)
    if not index then
        return index
    end
    local types = false
    for _, b in ipairs(index.list) do
        types = types or (#b.types > 0 and not b.types_from_tag)
    end
    for _, b in ipairs(index.list) do
        if b.calibre_status == nil then
            b.calibre_status = b.status or false
        end
        local own, opened = koreader(b.lpath)
        b.status = (toread or {})[b.lpath] and "tbr" or KOREADER[own] or b.calibre_status
            or (opened and "reading" or "tbr")
        if not types and not b.types_from_tag and b.tags[1] then
            b.types, b.types_from_tag = { b.tags[1] }, true
        end
    end
    return index
end

return Library
