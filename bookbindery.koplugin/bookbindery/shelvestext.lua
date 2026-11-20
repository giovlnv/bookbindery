--[[--
ShelvesText: the strings of the shelves, shelf tree and shelf screens, pure Lua.
]]

local ShelvesText = {}

local STATUS = { reading = "reading", tbr = "to read", read = "read", dnf = "dnf" }

function ShelvesText.status(s)
    return STATUS[s] or s
end

function ShelvesText.segments(path)
    local out = {}
    for seg in (path or ""):gmatch("[^.]+") do
        out[#out + 1] = seg
    end
    return out
end

function ShelvesText.name(path)
    local segs = ShelvesText.segments(path)
    return segs[#segs] or ""
end

function ShelvesText.path(path)
    return table.concat(ShelvesText.segments(path), " › ")
end

function ShelvesText.hint(node, n)
    local kids = node.children or {}
    if #kids == 1 then
        return kids[1].name
    elseif #kids == 2 then
        return kids[1].name .. " " .. kids[1].count .. " · " .. kids[2].name .. " " .. kids[2].count
    elseif #kids > 2 then
        local more = #kids - 3
        local s = kids[1].name .. " · " .. kids[2].name .. " · " .. kids[3].name
        return more > 0 and s .. " · " .. more .. " more" or s
    end
    return ""
end

function ShelvesText.shelves(n)
    return n .. (n == 1 and " shelf" or " shelves")
end

function ShelvesText.volume(i)
    if not i then
        return nil
    end
    return "vol. " .. (i == math.floor(i) and string.format("%d", i) or tostring(i))
end

function ShelvesText.byline(book)
    local parts = {}
    parts[#parts + 1] = book.authors and book.authors[1]
    parts[#parts + 1] = book.series and ShelvesText.volume(book.series_index)
    return table.concat(parts, " · ")
end

function ShelvesText.next_note(names)
    if #names == 0 then
        return nil
    end
    local shown = {}
    for i = 1, math.min(4, #names) do
        shown[i] = names[i]
    end
    return table.concat(shown, ", ") .. (#names > 4 and "… next" or " next")
end

return ShelvesText
