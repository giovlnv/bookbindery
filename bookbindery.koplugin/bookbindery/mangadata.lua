--[[--
MangaData: KOReader side of the manga model. Reads rakuyomi's database.db read-only
(2 s busy timeout, always closed), lists its downloads folder, and keeps the cover
cache in settings/bookbindery/manga-covers, filled by a check.
rakuyomi itself is never changed or started.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local sha2 = require("ffi/sha2")
local Http = require("bookbindery/http")
local Manga = require("bookbindery/manga")

local MangaData = {}

local COVERS = DataStorage:getSettingsDir() .. "/bookbindery/manga-covers"
local COVER_TIMEOUT = 5
local COVERS_PER_REFRESH = 10
local memo

-- rakuyomi's Paths when it's loaded; it resolves to the same place
function MangaData.dir(plugin)
    local paths = (plugin or package.loaded["Backend"]) and package.loaded["Paths"]
    if type(paths) == "table" and type(paths.getHomeDirectory) == "function" then
        local ok, dir = pcall(paths.getHomeDirectory)
        if ok and type(dir) == "string" then
            return dir
        end
    end
    return DataStorage:getDataDir() .. "/rakuyomi"
end

local function downloads_dir(dir)
    local f = io.open(dir .. "/settings.json", "rb")
    if f then
        local ok, settings = pcall(rapidjson.decode, f:read("*a"))
        f:close()
        if ok and type(settings) == "table" and type(settings.storage_path) == "string" then
            return settings.storage_path
        end
    end
    return dir .. "/downloads"
end

local function names_in(dir)
    local names = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            names[#names + 1] = name
        end
    end
    return Manga.file_set(names)
end

local function value(v)
    if type(v) == "cdata" then
        return tonumber(v)
    end
    return v
end

local function query(conn, sql, columns)
    local res, n = conn:exec(sql)
    local out = {}
    for i = 1, res and n or 0 do
        local row = {}
        for j, name in ipairs(columns) do
            row[name] = value(res[j][i])
        end
        out[i] = row
    end
    return out
end

local QUERIES = {
    { "library", "SELECT source_id, manga_id FROM manga_library;", { "source_id", "manga_id" } },
    { "informations", "SELECT i.source_id, i.manga_id, i.title, i.cover_url FROM manga_informations i "
        .. "JOIN manga_library l ON l.source_id = i.source_id AND l.manga_id = i.manga_id;",
        { "source_id", "manga_id", "title", "cover_url" } },
    { "details", "SELECT d.source_id, d.id, d.title, d.cover_url FROM manga_details d "
        .. "JOIN manga_library l ON l.source_id = d.source_id AND l.manga_id = d.id;",
        { "source_id", "id", "title", "cover_url" }, true },
    { "chapters", "SELECT c.source_id, c.manga_id, c.chapter_id, c.manga_order, c.chapter_number "
        .. "FROM chapter_informations c "
        .. "JOIN manga_library l ON l.source_id = c.source_id AND l.manga_id = c.manga_id;",
        { "source_id", "manga_id", "chapter_id", "manga_order", "chapter_number" } },
    { "state", "SELECT source_id, manga_id, chapter_id, read, last_read FROM chapter_state;",
        { "source_id", "manga_id", "chapter_id", "read", "last_read" } },
    { "notifications", "SELECT source_id, manga_id, chapter_id, is_read FROM notifications;",
        { "source_id", "manga_id", "chapter_id", "is_read" }, true },
}

local function read_rows(path)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local ok, res = pcall(function()
        conn:set_busy_timeout(2000)
        local rows = {}
        for _, q in ipairs(QUERIES) do
            local qok, r = pcall(query, conn, q[2], q[3])
            if not qok then
                -- optional tables (older rakuyomi) only; a busy database fails the read
                if not (q[4] and tostring(r):find("no such table", 1, true)) then
                    error(r, 0)
                end
                r = {}
            end
            rows[q[1]] = r
        end
        return rows
    end)
    conn:close()
    assert(ok, res)
    return res
end

-- the library (Manga.list), or nil and why (Manga.failure); memoized on the database's and the downloads
-- folder's modification times, failures never
function MangaData.library(plugin)
    local dir = MangaData.dir(plugin)
    local db = dir .. "/database.db"
    local dbattr = lfs.attributes(db)
    if not dbattr then
        return nil, Manga.failure(false)
    end
    local downloads = downloads_dir(dir)
    local stamp = table.concat({ db, dbattr.modification, dbattr.size,
        lfs.attributes(downloads, "modification") or 0 }, "|")
    if memo and memo.stamp == stamp then
        return memo.list
    end
    local ok, rows = pcall(read_rows, db)
    if not ok then
        logger.warn("bookbindery: rakuyomi's database didn't read:", rows)
        return nil, Manga.failure(true, rows)
    end
    local list = Manga.list(rows, names_in(downloads), sha2.sha256)
    memo = { stamp = stamp, list = list }
    return list
end

-- the cached cover's path for a manga, or nil (a grey box then)
function MangaData.cover(m)
    if not m.cover_url then
        return nil
    end
    local path = COVERS .. "/" .. Manga.cover_name(m.cover_url, sha2.sha1)
    return lfs.attributes(path, "mode") == "file" and path or nil
end

local FAILED = COVERS .. "/failed.lua"

local function load_failed(now)
    local chunk = loadfile(FAILED)
    local ok, t = pcall(chunk or error)
    return Manga.prune_failed(ok and type(t) == "table" and t or {}, now)
end

local function save_failed(failed)
    local f = io.open(FAILED .. ".new", "wb")
    local ok = f and f:write(Manga.failed_source(failed)) and f:close()
    if ok then
        os.rename(FAILED .. ".new", FAILED)
    end
end

-- off unless bookbindery_manga_covers is set (the sources are the user's call): then no
-- network at all. Missing covers only, 5 s each, at most 10, jpeg or png; returns
-- how many were saved
function MangaData.fetch_covers(http_request, enabled)
    if enabled == nil then
        enabled = G_reader_settings:isTrue("bookbindery_manga_covers")
    end
    local list = enabled and MangaData.library()
    local now = os.time()
    local failed = enabled and load_failed(now) or {}
    local missing = list
        and Manga.missing_covers(list, names_in(COVERS), sha2.sha1, COVERS_PER_REFRESH, enabled, failed, now) or {}
    if #missing == 0 then
        return 0
    end
    if lfs.attributes(COVERS, "mode") ~= "directory" then
        lfs.mkdir(COVERS)
    end
    http_request = http_request or Http.request
    local saved, dirty = 0, false
    for _, c in ipairs(missing) do
        local ok, status, _, body = http_request({ url = c.url, method = "GET", timeout = COVER_TIMEOUT,
            headers = { ["User-Agent"] = "Mozilla/5.0 (KOReader)" } })
        if not ok then
            logger.info("bookbindery: manga covers stopped, no answer:", c.url, status)
            break
        elseif status == 200 and Manga.image_kind(body) then
            local path = COVERS .. "/" .. c.name
            local f = io.open(path .. ".new", "wb")
            local written = f and f:write(body)
            local closed = f and f:close()
            if written and closed and os.rename(path .. ".new", path) then
                saved = saved + 1
            else
                os.remove(path .. ".new")
            end
        else
            logger.info("bookbindery: manga cover not fetched:", c.url, status)
            failed[c.url], dirty = now, true
        end
    end
    if dirty then
        save_failed(failed)
    end
    return saved
end

return MangaData
