--[[--
Updates: the lines of the updates screen, one function per section, pure Lua.
Times are unix seconds, shown in local time.
]]

local Manga = require("bookbindery/manga")

local Updates = {}

local function count(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function chapters(n)
    return n > 0 and count(n, "new chapter", "new chapters") or "no new chapters"
end

-- list: MangaData.library(), or nil and why (already worded)
function Updates.manga(list, why)
    if not list then
        return why
    end
    return chapters(Manga.new_total(list))
end

-- articles: wallabag's downloads, each with its reading status
function Updates.articles(articles)
    local n = 0
    for _, a in ipairs(articles) do
        if a.status ~= "read" then
            n = n + 1
        end
    end
    return n > 0 and n .. " unread" or "no unread articles"
end

-- changed: the plugin is there but didn't take the call
function Updates.missing(plugin, changed)
    return plugin .. " isn't installed" .. (changed and " or changed" or "")
end

return Updates
