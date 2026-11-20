--[[--
Settings rows, pure. The words and flags of bookbindery's settings screen.
]]

local Settings = {}

-- build: the release stamp (nil → "dev build")
function Settings.build(stamp)
    return type(stamp) == "string" and stamp ~= "" and stamp or "dev build"
end

-- s: covers (bool), pinned (n), build
-- → rows { id, text, right?, note?, action?, muted? } (ids are tappable)
function Settings.rows(s)
    local rows = {
        { id = "covers", text = "manga covers", action = s.covers and "on" or "off" },
        { note = "covers come from rakuyomi's sources" },
        { id = s.pinned > 0 and "pins" or nil, text = "clear pinned shelves", muted = s.pinned == 0,
            right = s.pinned == 0 and "none pinned" or s.pinned .. " pinned" },
    }
    rows[#rows + 1] = { text = "build", right = Settings.build(s.build) }
    return rows
end

return Settings
