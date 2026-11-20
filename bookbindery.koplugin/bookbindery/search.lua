--[[--
Offline search, pure Lua. library: books by title, author and series.
fanfic: fics by title, author, fandom and ship.
Case- and accent-insensitive; ranked title prefix, title, author, the rest.
]]

local Fanfic = require("bookbindery/fanfic")
local FicInfo = require("bookbindery/ficinfo")
local InfoText = require("bookbindery/infotext")
local Wording = require("bookbindery/wording")

local Search = {}

local ACCENTS = {}
for plain, list in pairs({
    a = "áàâãäåąÁÀÂÃÄÅĄ", e = "éèêëěęÉÈÊËĚĘ", i = "íìîïÍÌÎÏ", o = "óòôõöøőÓÒÔÕÖØŐ", u = "úùûüűÚÙÛÜŰ",
    c = "çčćÇČĆ", n = "ñńÑŃ", y = "ýÿÝ", s = "šśŠŚ", z = "žźżŽŹŻ", l = "łŁ", r = "řŘ",
}) do
    for ch in list:gmatch("[\192-\223][\128-\191]") do
        ACCENTS[ch] = plain
    end
end

local folded = {}

function Search.fold(s)
    if not s then
        return ""
    end
    local f = folded[s]
    if not f then
        f = s:gsub("[\195-\197][\128-\191]", ACCENTS):lower()
        folded[s] = f
    end
    return f
end

local function joined(authors)
    return table.concat(authors or {}, ", ")
end

local function any(q, list)
    for _, v in ipairs(list) do
        if Search.fold(v):find(q, 1, true) then
            return v
        end
    end
end

-- 1 title prefix, 2 title contains, 3 author, 4 the rest; nil for no match
local function rank(q, title, author, rest)
    local t = Search.fold(title)
    local at = t:find(q, 1, true)
    if at == 1 then
        return 1
    elseif at then
        return 2
    elseif Search.fold(author):find(q, 1, true) then
        return 3
    end
    local hit = any(q, rest)
    return hit and 4, hit
end

local function library(q, index, groups)
    local section_of, hits, out = {}, {}, {}
    for _, b in ipairs(index.list) do
        if b.library == "books" then
            local r = rank(q, b.title, joined(b.authors), { b.series }) or hits[b]
            if r then
                out[#out + 1] = { rank = r, title = b.title, author = joined(b.authors), status = b.status,
                    section = section_of[b], lpath = b.lpath, entry = b, place = "library" }
            end
        end
    end
    return out
end

local function fanfic(q, index, files)
    local out = {}
    for _, e in ipairs(Fanfic.entries(index, files)) do
        local b = index.books[e.lpath]
        local t = FicInfo.tags(b and b.tags)
        local rest = { e.fandom }
        for _, list in ipairs({ t.fandoms, t.ships }) do
            for _, v in ipairs(list) do
                rest[#rest + 1] = v
            end
        end
        local r, hit = rank(q, e.title, joined(e.authors), rest)
        if r then
            out[#out + 1] = { rank = r, title = e.title, author = joined(e.authors), status = b and b.status,
                section = hit or t.fandoms[1] or e.fandom, lpath = e.lpath, entry = b, place = "fanfic" }
        end
    end
    return out
end

-- query, "library" or "fanfic", the index, groups (nil), the fanfic files on disk (lpaths, optional)
function Search.run(query, scope, index, groups, files)
    local q = Search.fold(query):match("^%s*(.-)%s*$")
    if q == "" or not index then
        return {}
    end
    local out = scope == "fanfic" and fanfic(q, index, files) or library(q, index, groups)
    for _, r in ipairs(out) do
        r.key = Search.fold(r.title)
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if a.key ~= b.key then
            return a.key < b.key
        end
        return (a.lpath or "") < (b.lpath or "")
    end)
    return out
end

-- the chips: offline scopes, then the handoffs
function Search.scopes()
    return { "library", "fanfic", "manga", "dictionary" }
end

function Search.subline(r)
    local parts = {}
    local status = InfoText.word(r.status) or r.status or ""
    for _, v in ipairs({ r.author or "", status, r.section or "" }) do
        if v ~= "" then
            parts[#parts + 1] = v
        end
    end
    return table.concat(parts, " · ")
end

function Search.summary(n, scope)
    if not n then
        return "works offline"
    end
    return n .. (scope == "fanfic" and " in fanfic" or " in " .. Wording.library_place) .. " · works offline"
end

return Search
