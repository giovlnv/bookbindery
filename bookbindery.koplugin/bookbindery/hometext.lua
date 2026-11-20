--[[--
HomeText: the strings and clock geometry of the home screen, pure Lua.
Times are unix seconds, shown in local time.
]]

local HomeText = {}

local DAYS = { "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" }
local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }

local function day_key(t)
    return t.year * 10000 + t.month * 100 + t.day
end

local function hm(t)
    return string.format("%02d:%02d", t.hour, t.min)
end

local function day_month(t)
    return t.day .. " " .. MONTHS[t.month]
end

function HomeText.percent(p)
    return math.floor((p or 0) * 100 + 0.5) .. "%"
end

function HomeText.date_line(now, days)
    local t = os.date("*t", now)
    local s = DAYS[t.wday] .. ", " .. day_month(t) .. " · " .. hm(t)
    if days then
        s = s .. " · " .. days .. (days == 1 and " day" or " days") .. " read this month"
    end
    return s
end

function HomeText.when(ts, now)
    if not ts then
        return nil
    end
    local t, n = os.date("*t", ts), os.date("*t", now)
    if day_key(t) == day_key(n) then
        return "today " .. hm(t)
    end
    local y = os.date("*t", os.time({ year = n.year, month = n.month, day = n.day, hour = 12 }) - 86400)
    if day_key(t) == day_key(y) then
        return "yesterday " .. hm(t)
    end
    return day_month(t)
end

function HomeText.saved(ts, now)
    local t = os.date("*t", ts)
    if day_key(t) == day_key(os.date("*t", now)) then
        return hm(t)
    end
    return day_month(t) .. " " .. hm(t)
end

local function page(row)
    if row.page and row.pages then
        return "page " .. row.page .. " of " .. row.pages
    end
end

local function join(parts)
    local out = {}
    for i = 1, parts.n or #parts do
        if parts[i] and parts[i] ~= "" then
            out[#out + 1] = parts[i]
        end
    end
    return table.concat(out, " · ")
end

function HomeText.progress(row, now)
    return join({ page(row), HomeText.percent(row.percent), HomeText.when(row.last_read, now), n = 3 })
end

function HomeText.author(book)
    return book and book.authors and book.authors[1] or nil
end

function HomeText.shelf(book)
    local types = book and book.types or {}
    local pick = types[1]
    return pick and (pick:gsub("%.", " · ")) or nil
end

function HomeText.byline(row)
    return join({ HomeText.author(row.book), HomeText.shelf(row.book), n = 2 })
end

function HomeText.more(row)
    return join({ HomeText.author(row.book), page(row), HomeText.percent(row.percent), n = 3 })
end

-- the fanfic tile: the fandom folders under fanfic/
function HomeText.fandoms(n)
    return n == 1 and "1 fandom" or n .. " fandoms"
end

function HomeText.clock(hour, min)
    return ((hour % 12) + min / 60) * 30, min * 6
end

function HomeText.hand(cx, cy, length, deg)
    local a = math.rad(deg)
    return cx + length * math.sin(a), cy - length * math.cos(a)
end

return HomeText
