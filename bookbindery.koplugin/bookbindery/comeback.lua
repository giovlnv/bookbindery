--[[--
Comeback: when bookbindery steps back in or out around the file manager. Closing
rakuyomi's views comes back home; only a deliberate trip to a folder ("show folder",
"go to folder") closes bookbindery, any other path change keeps it.
]]

local M = {}

-- a rakuyomi view closed; s: starts_home, shown (home or a screen), stack: what is shown,
-- topmost first, each "toast", "file_manager" or "other"
function M.home_after_rakuyomi(s)
    if not s.starts_home or s.shown then
        return false
    end
    for _i, kind in ipairs(s.stack or {}) do
        if kind ~= "toast" then
            return kind == "file_manager"
        end
    end
    return false
end

-- the file manager's path changed; s: shown, trip (a deliberate folder trip is under way)
function M.close_for_folder(s)
    return (s.shown and s.trip) and true or false
end

-- a new file manager starts; s: trip, return_home, starts_home, first, leftover
function M.home_on_init(s)
    if s.trip then
        return false
    end
    return (s.return_home or (s.starts_home and (s.first or s.leftover))) and true or false
end

return M
