--[[--
ToRead: books marked "to read", lpath → true, kept in settings/bookbindery/toread.lua
(KOReader has no such status: an opened book without one reads as reading). Pure; io is main.lua's
fileio (read, write or write_durable, rename, serialize, deserialize).
]]

local ToRead = {}

function ToRead.load(path, io)
    local text = io.read(path)
    local ok, map = pcall(io.deserialize, text or "")
    return ok and type(map) == "table" and map or {}
end

-- on: marks lpath, off clears it; true when the map changed
function ToRead.set(map, lpath, on)
    if (map[lpath] == true) == (on and true or false) then
        return false
    end
    map[lpath] = on and true or nil
    return true
end

-- tmp, then rename over the old file
function ToRead.save(path, io, map)
    local tmp = path .. ".new"
    local ok, err = (io.write_durable or io.write)(tmp, io.serialize(map))
    if ok then
        ok, err = io.rename(tmp, path)
    end
    return ok, err
end

return ToRead
