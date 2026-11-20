--[[--
BookInfo: the book info screen's model, pure Lua. entry is the index entry;
read is what the sidecar and the file say ({ opened,
percent, pages, page, status, highlights, notes, ext, size, added, language });
stats is BookInfo.stats() of the book's statistics rows.
]]

local InfoText = require("bookbindery/infotext")

local BookInfo = {}

local ABOUT = 300
local SESSION_GAP = 30 * 60
local MAX_SEC = 120
local LANGUAGES = { en = "english", eng = "english", pt = "portuguese", por = "portuguese", es = "spanish",
    spa = "spanish", fr = "french", fra = "french", fre = "french", de = "german", deu = "german",
    ger = "german", it = "italian", ita = "italian", zh = "chinese", zho = "chinese", ja = "japanese" }

-- rows of page_stat_data { page, start_time, duration, total_pages }; pages is the
-- book's page count now. The pace is statistics' own: rows rescaled to pages as its
-- page_stat view does, at most MAX_SEC a page, over the distinct pages read.
function BookInfo.stats(rows, pages)
    if not rows or #rows == 0 then
        return nil
    end
    -- a loop, not unpack: a long read has more rows than unpack takes
    local sorted = {}
    for i, r in ipairs(rows) do
        sorted[i] = r
    end
    table.sort(sorted, function(a, b) return a.start_time < b.start_time end)
    local time, sessions, last_end, per_page = 0, 0, nil, {}
    for _, r in ipairs(sorted) do
        time = time + r.duration
        if not last_end or r.start_time - last_end > SESSION_GAP then
            sessions = sessions + 1
        end
        last_end = math.max(last_end or 0, r.start_time + r.duration)
        local total = (r.total_pages or 0) > 0 and r.total_pages or pages
        if total and total > 0 then
            local n = pages and pages > 0 and pages or total
            local first = math.floor((r.page - 1) * n / total) + 1
            local last = math.max(first, math.floor(r.page * n / total))
            local share = math.floor(r.duration / (last - first + 1))
            for p = first, last do
                per_page[p] = (per_page[p] or 0) + share
            end
        end
    end
    local count, capped = 0, 0
    for _, d in pairs(per_page) do
        count, capped = count + 1, capped + math.min(d, MAX_SEC)
    end
    local pace = count > 0 and capped / count or nil
    return { time = time, sessions = sessions, first = sorted[1].start_time, pace = pace }
end

local function duration(sec)
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h == 0 then
        return math.max(m, 1) .. "m"
    elseif h >= 10 then
        return math.floor(sec / 3600 + 0.5) .. "h"
    elseif m == 0 then
        return h .. "h"
    end
    return h .. "h " .. m .. "m"
end

local function meta(entry)
    local parts = {}
    local r = tonumber(entry.rating)
    if r and r > 0 then
        parts[#parts + 1] = "★ " .. (string.format("%.1f", r / 2):gsub("%.0$", ""))
    end
    local year = type(entry.pubdate) == "string" and entry.pubdate:match("^(%d%d%d%d)")
    if year then
        parts[#parts + 1] = year
    end
    local pages = tonumber(entry.pages)
    if pages and pages > 0 then
        parts[#parts + 1] = math.floor(pages) .. " pages"
    end
    return table.concat(parts, " · ")
end

-- the first #type, as "fiction · classics · austen"
local function shelf(types)
    local t = types and types[1]
    return t and (t:gsub("%.", " · "))
end

local function highlights(read)
    local n, notes = read.highlights or 0, read.notes or 0
    if n == 0 then
        return "none"
    end
    return notes > 0 and n .. " · " .. InfoText.plural(notes, "note", "notes") or tostring(n)
end

local function series(entry)
    if not entry.series or entry.series == "" then
        return "none"
    end
    local i = tonumber(entry.series_index)
    return i and entry.series .. " #" .. string.format("%g", i) or entry.series
end

local function file(read)
    if not read.ext then
        return nil
    end
    if not read.size then
        return read.ext
    end
    local mb = read.size / (1024 * 1024)
    local size = mb >= 1 and string.format("%.1f MB", mb) or math.max(1, math.floor(read.size / 1024 + 0.5)) .. " KB"
    return read.ext .. " · " .. size
end

local function add(rows, label, value)
    if value then
        rows[#rows + 1] = { label = label, value = value }
    end
end

function BookInfo.model(entry, read, stats, now)
    read = read or {}
    local rows, details = {}, {}
    add(rows, "progress", InfoText.progress(read))
    if stats then
        add(rows, "time read", duration(stats.time) .. " · " .. InfoText.plural(stats.sessions, "session", "sessions"))
        local left = read.pages and read.page and (read.pages - read.page) * (stats.pace or 0)
        if left and left > 0 and read.status ~= "complete" then
            add(rows, "left", "about " .. duration(left) .. " at your pace")
        end
    end
    add(rows, "highlights", highlights(read))

    add(details, "series", series(entry))
    local lang = read.language and read.language:lower()
    add(details, "language", lang and (LANGUAGES[lang] or LANGUAGES[lang:match("^(%a+)")] or lang))
    add(details, "file", file(read))
    add(details, "added", InfoText.date(read.added))
    add(details, "first opened", stats and InfoText.date(stats.first))
    add(details, "calibre", entry.id and "#" .. entry.id)

    local full = InfoText.html(entry.comments)
    local about, more = InfoText.about(full, ABOUT)
    return {
        title = entry.title or "",
        authors = table.concat(entry.authors or {}, ", "),
        meta = meta(entry),
        status = InfoText.status(entry.status, read),
        shelf = shelf(entry.types),
        rows = rows,
        about = about,
        about_more = more,
        full = full,
        details = details,
        highlights = read.highlights or 0,
        action = read.opened and "continue reading" or "start reading",
        now = now,
    }
end

return BookInfo
