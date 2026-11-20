--[[--
InfoText: what book info and fic info share, pure Lua: descriptions from
calibre's HTML, status words, progress and dates.
]]

local InfoText = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ", hellip = "…",
    mdash = "—", ndash = "–", rsquo = "’", lsquo = "‘", rdquo = "”", ldquo = "“" }

local function utf8_char(n)
    if n < 0x80 then
        return string.char(n)
    elseif n < 0x800 then
        return string.char(0xC0 + math.floor(n / 0x40), 0x80 + n % 0x40)
    elseif n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 0x1000), 0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40)
    end
    return string.char(0xF0 + math.floor(n / 0x40000), 0x80 + math.floor(n / 0x1000) % 0x40,
        0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40)
end

local function entity(name)
    local n = name:match("^#[xX](%x+)$")
    if n then
        return utf8_char(tonumber(n, 16))
    end
    n = name:match("^#(%d+)$")
    if n then
        return utf8_char(tonumber(n))
    end
    return ENTITIES[name] or "&" .. name .. ";"
end

-- paragraphs of plain text, separated by a blank line
function InfoText.html(s)
    if type(s) ~= "string" or s == "" then
        return ""
    end
    s = s:gsub("<[bB][rR]%s*/?>", "\n"):gsub("</?[pP][^>]*>", "\n\n"):gsub("</?[dD][iI][vV][^>]*>", "\n\n")
        :gsub("<[^>]*>", ""):gsub("&(#?%w+);", entity)
    local paras = {}
    for block in (s .. "\n\n"):gmatch("(.-)\n%s*\n") do
        for line in (block .. "\n"):gmatch("(.-)\n") do
            line = line:gsub("[ \t\r\194\160]+", " "):gsub("^ ", ""):gsub(" $", "")
            if line ~= "" then
                paras[#paras + 1] = line
            end
        end
    end
    return table.concat(paras, "\n\n")
end

-- the first ~n characters on one line, cut at a word; more is true when cut
function InfoText.about(text, n)
    local flat = text:gsub("%s*\n\n%s*", " ")
    if #flat <= n then
        return flat, flat ~= text
    end
    local cut = flat:sub(1, n):match("^(.*)%s") or flat:sub(1, n)
    return cut:gsub("[%s%p]+$", "") .. "…", true
end

local CALIBRE = { tbr = "to read", reading = "reading", read = "read", dnf = "did not finish" }

function InfoText.word(status)
    return CALIBRE[status]
end

-- calibre's status first, then the sidecar's
function InfoText.status(calibre, read)
    if calibre and CALIBRE[calibre] then
        return CALIBRE[calibre]
    end
    read = read or {}
    if read.status == "complete" then
        return "read"
    elseif read.status == "abandoned" then
        return "did not finish"
    elseif read.status == "reading" or (read.percent or 0) > 0 then
        return "reading"
    end
    return "not started"
end

function InfoText.progress(read)
    if not (read and read.opened and read.percent) then
        return "not started"
    end
    local pct = math.floor(read.percent * 100 + 0.5) .. "%"
    if read.page and read.pages then
        return "page " .. read.page .. " of " .. read.pages .. " · " .. pct
    end
    return pct
end

local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }

function InfoText.date(t)
    if not t then
        return nil
    end
    local d = os.date("*t", t)
    return d.day .. " " .. MONTHS[d.month] .. " " .. d.year
end

function InfoText.plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

return InfoText
