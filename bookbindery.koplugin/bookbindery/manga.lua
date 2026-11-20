--[[--
Manga: rakuyomi's library from rows of its database.db (read by the adapter), the
names of its downloaded chapters and of bookbindery's cached covers. Hash functions
are passed in (KOReader's ffi/sha2 on the device) and return hex digests.
]]

local Manga = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

function Manga.base64url(hex)
    local bytes = {}
    for h in hex:gmatch("%x%x") do
        bytes[#bytes + 1] = tonumber(h, 16)
    end
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = b and (c and 4 or 3) or 2
        for j = 1, chars do
            local v = math.floor(n / 64 ^ (4 - j)) % 64
            out[#out + 1] = ALPHABET:sub(v + 1, v + 1)
        end
    end
    return table.concat(out)
end

-- rakuyomi's file name for a downloaded chapter
function Manga.download_name(source_id, manga_id, chapter_id, sha256)
    return Manga.base64url(sha256(source_id .. manga_id .. chapter_id)) .. ".cbz"
end

function Manga.cover_name(url, sha1)
    return sha1(url) .. ".jpg"
end

local function key(source_id, manga_id)
    return source_id .. "\0" .. manga_id
end

-- rows: { library, informations, details, chapters, state, notifications } as the
-- tables' rows;
-- files: set of names in rakuyomi's downloads folder. Most recently read first.
function Manga.list(rows, files, sha256)
    local info, details, chapters, state = {}, {}, {}, {}
    for _, r in ipairs(rows.informations or {}) do
        info[key(r.source_id, r.manga_id)] = r
    end
    for _, r in ipairs(rows.details or {}) do
        details[key(r.source_id, r.id)] = r
    end
    for _, r in ipairs(rows.chapters or {}) do
        local k = key(r.source_id, r.manga_id)
        chapters[k] = chapters[k] or {}
        table.insert(chapters[k], r)
    end
    for _, r in ipairs(rows.state or {}) do
        state[key(r.source_id, r.manga_id) .. "\0" .. r.chapter_id] = r
    end
    -- unread notifications whose chapter wasn't read since don't count
    local fresh, seen = {}, {}
    for _, r in ipairs(rows.notifications or {}) do
        local k = key(r.source_id, r.manga_id)
        local ck = k .. "\0" .. r.chapter_id
        local s = state[ck]
        if r.is_read == 0 and not seen[ck] and not (s and s.read == 1) then
            seen[ck] = true
            fresh[k] = (fresh[k] or 0) + 1
        end
    end
    local out = {}
    for _, l in ipairs(rows.library or {}) do
        local k = key(l.source_id, l.manga_id)
        local d, i = details[k] or {}, info[k] or {}
        local m = {
            source_id = l.source_id, manga_id = l.manga_id,
            title = d.title or i.title or l.manga_id,
            source = l.source_id:gsub("^%a+%.", ""),
            cover_url = d.cover_url or i.cover_url,
            chapters = 0, read = 0, unread = 0, downloaded = 0, new = fresh[k] or 0,
        }
        for _, c in ipairs(chapters[k] or {}) do
            local s = state[k .. "\0" .. c.chapter_id]
            m.chapters = m.chapters + 1
            if s and s.read == 1 then
                m.read = m.read + 1
            end
            if s and s.last_read and s.last_read > (m.last_read or -math.huge) then
                m.last_read = s.last_read
            end
            if next(files) and files[Manga.download_name(l.source_id, l.manga_id, c.chapter_id, sha256)] then
                m.downloaded = m.downloaded + 1
            end
        end
        m.unread = m.chapters - m.read
        out[#out + 1] = m
    end
    table.sort(out, function(a, b)
        if (a.last_read or 0) ~= (b.last_read or 0) then
            return (a.last_read or 0) > (b.last_read or 0)
        end
        return a.title < b.title
    end)
    return out
end

function Manga.new_total(list)
    local n = 0
    for _, m in ipairs(list) do
        n = n + (m.new or 0)
    end
    return n
end

Manga.FAILED_FOR = 24 * 3600

-- failed: { [url] = unix time of the failure }; skipped for a day
function Manga.cover_failed(failed, url, now)
    local at = failed and failed[url]
    return at ~= nil and now ~= nil and now - at < Manga.FAILED_FOR
end

-- the failed set without the entries older than a day
function Manga.prune_failed(failed, now)
    local out = {}
    for url, at in pairs(failed or {}) do
        if now - at < Manga.FAILED_FOR then
            out[url] = at
        end
    end
    return out
end

-- the failed set as a lua file (sorted, dated)
function Manga.failed_source(failed)
    local urls = {}
    for url in pairs(failed) do
        urls[#urls + 1] = url
    end
    table.sort(urls)
    local lines = { "return {" }
    for _, url in ipairs(urls) do
        lines[#lines + 1] = string.format("    [%q] = %d, -- %s", url, failed[url], os.date("!%Y-%m-%d", failed[url]))
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

-- covers not in the cache (have: set of file names), each url once, at most max;
-- none unless enabled (bookbindery_manga_covers: the sources are the user's call)
function Manga.missing_covers(list, have, sha1, max, enabled, failed, now)
    local out, seen = {}, {}
    if not enabled then
        return out
    end
    for _, m in ipairs(list) do
        local url = m.cover_url
        if url and not seen[url] and #out < max then
            seen[url] = true
            local name = Manga.cover_name(url, sha1)
            if not have[name] and not Manga.cover_failed(failed, url, now) then
                out[#out + 1] = { url = url, name = name }
            end
        end
    end
    return out
end

-- only jpeg and png are cached, so KOReader never gets a webp
function Manga.image_kind(bytes)
    if type(bytes) ~= "string" then
        return nil
    end
    if bytes:sub(1, 3) == "\255\216\255" then
        return "jpeg"
    end
    if bytes:sub(1, 8) == "\137PNG\r\n\26\n" then
        return "png"
    end
    return nil
end

-- names in a folder as a set, without "." entries (so an empty folder is empty)
function Manga.file_set(names)
    local set = {}
    for _, name in ipairs(names) do
        if name:sub(1, 1) ~= "." then
            set[name] = true
        end
    end
    return set
end

-- why the library didn't read: "none" (no database), "busy" (locked past the busy
-- timeout) or "error"
function Manga.failure(exists, err)
    if not exists then
        return "none"
    end
    local msg = tostring(err)
    return (msg:find("locked", 1, true) or msg:find("busy", 1, true)) and "busy" or "error"
end

Manga.CHIPS = { "library", "downloaded", "new chapters" }

local KEEP = {
    downloaded = function(m) return m.downloaded > 0 end,
    ["new chapters"] = function(m) return m.new > 0 end,
}

function Manga.filter(list, chip)
    local keep = KEEP[chip]
    if not keep then
        return list
    end
    local out = {}
    for _, m in ipairs(list) do
        if keep(m) then
            out[#out + 1] = m
        end
    end
    return out
end

local EMPTY = {
    library = "no manga in rakuyomi's library yet",
    downloaded = "nothing downloaded in rakuyomi",
    ["new chapters"] = "no new chapters",
}

function Manga.empty(chip)
    return EMPTY[chip] or EMPTY.library
end

function Manga.line(m)
    return m.chapters .. (m.chapters == 1 and " chapter" or " chapters") .. " · " .. m.read .. " read · " .. m.source
end

function Manga.progress(m)
    return m.chapters > 0 and m.read / m.chapters or 0
end

return Manga
