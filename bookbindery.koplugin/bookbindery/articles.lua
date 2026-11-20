local Articles = {}

local function title_of(name)
    local t = name:gsub("^%[w%-id_%d+%] ", ""):gsub("%.[^.]*$", "")
    return t
end

-- entries: { { name, time } } from wallabag's folder; newest first
function Articles.list(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
        out[#out + 1] = { title = title_of(e.name), file = e.name, time = e.time }
    end
    table.sort(out, function(a, b)
        if a.time ~= b.time then
            return a.time > b.time
        end
        return a.title < b.title
    end)
    return out
end

return Articles
