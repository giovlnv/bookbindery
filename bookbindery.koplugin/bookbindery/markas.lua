--[[--
MarkAs: the mark-as sheet's status rows, pure Lua. They use calibre's #workflow
values.
]]

local Library = require("bookbindery/library")

local MarkAs = {}

local STATUSES = {
    { value = "TBR", label = "to read", note = "tbr" },
    { value = "ONGOING", label = "reading", note = "ongoing" },
    { value = "READ", label = "read", note = "finished" },
    { value = "DNF", label = "did not finish", note = "dnf" },
}
local KOREADER = { ONGOING = "reading", READ = "complete", DNF = "abandoned" }

-- current: the entry's status in library.lua's words
function MarkAs.statuses(current)
    local rows = {}
    for i, s in ipairs(STATUSES) do
        rows[i] = { value = s.value, label = s.label, note = s.note,
            checked = current ~= nil and Library.STATUS[s.value] == current }
    end
    return rows
end

function MarkAs.koreader(value)
    return KOREADER[value]
end

return MarkAs
