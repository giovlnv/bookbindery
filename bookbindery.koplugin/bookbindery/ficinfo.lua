--[[--
FicInfo: the fic info screen's model, pure Lua. From calibre: title, author,
fandom (a tag with " - ", shown before it), ships (tags with "/"), AO3's rating
tag and the summary. read is what the sidecar says, as for book info.
]]

local InfoText = require("bookbindery/infotext")
local Wording = require("bookbindery/wording")

local FicInfo = {}

local ABOUT = 300
local RATINGS = { ["General Audiences"] = "general", ["Teen And Up Audiences"] = "teen and up",
    Mature = "mature", Explicit = "explicit", ["Not Rated"] = "not rated" }

function FicInfo.tags(list)
    local out = { fandoms = {}, ships = {}, other = {} }
    for _, t in ipairs(list or {}) do
        if RATINGS[t] then
            out.rating = out.rating or RATINGS[t]
        elseif t:find("/", 1, true) then
            out.ships[#out.ships + 1] = t
        elseif t:find(" - ", 1, true) then
            out.fandoms[#out.fandoms + 1] = t:match("^(.-) %- ")
        elseif t ~= "fanfic" then
            out.other[#out.other + 1] = t
        end
    end
    -- AO3 fandoms without an author (TV, films) carry no " - "
    if #out.fandoms == 0 and #out.other > 0 then
        out.fandoms[1] = table.remove(out.other, 1)
    end
    return out
end

local function add(rows, label, value)
    if value and value ~= "" then
        rows[#rows + 1] = { label = label, value = value }
    end
end

function FicInfo.model(entry, read, now)
    read = read or {}
    local t = FicInfo.tags(entry.tags)
    local rows, details = {}, {}
    add(rows, "fandom", table.concat(t.fandoms, " · "))
    add(rows, "ship", table.concat(t.ships, " · "))
    add(rows, "progress", InfoText.progress(read))

    local ao3 = tonumber(entry.ao3)
    add(details, "ao3 work", ao3 and "#" .. ao3)
    add(details, "tags", table.concat(t.other, ", "))
    add(details, Wording.folder_label, "books/" .. (entry.lpath:match("^(.*)/[^/]*$") or ""))
    add(details, "highlights", (read.highlights or 0) > 0 and tostring(read.highlights) or "none")
    add(details, "calibre", entry.id and "fanfic #" .. entry.id)

    local full = InfoText.html(entry.comments)
    local summary, more = InfoText.about(full, ABOUT)
    return {
        title = entry.title or "",
        authors = table.concat(entry.authors or {}, ", "),
        status = InfoText.status(entry.status, read),
        rating = t.rating,
        rows = rows,
        summary = summary,
        summary_more = more,
        full = full,
        details = details,
        ao3 = ao3,
        action = "read",
        now = now,
    }
end

return FicInfo
