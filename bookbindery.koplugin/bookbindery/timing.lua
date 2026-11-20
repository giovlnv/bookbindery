--[[--
Draw timing: logs "bookbindery: <what> drawn in <ms> ms" once the screen that
was just shown has been painted. Cheap enough to stay on.
]]

local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")

local Timing = {}

function Timing.start()
    return time.monotonic()
end

function Timing.drawn(what, t0)
    UIManager:tickAfterNext(function()
        logger.info("bookbindery: " .. what .. " drawn in", math.floor(time.to_ms(time.since(t0))), "ms")
    end)
end

return Timing
