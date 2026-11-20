local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FontList = require("fontlist")
local Screen = require("device").screen

local ROLES = {
    title = { "Fraunces-Medium.ttf", 28, "cfont" },
    heading = { "Fraunces-Medium.ttf", 20, "cfont" },
    cover = { "Fraunces-Regular.ttf", 12, "cfont" },
    body = { "Inter-Regular.ttf", 14, "smallinfofont" },
    small = { "Inter-Regular.ttf", 13, "smallinfofont" },
    name = { "Inter-SemiBold.ttf", 17, "smalltfont" },
    item = { "Inter-Regular.ttf", 17, "smallinfofont" },
    button = { "Inter-Medium.ttf", 16, "smallinfofont" },
    label = { "Inter-SemiBold.ttf", 12, "smalltfont" },
    tab = { "Inter-Regular.ttf", 12, "smallinfofont" },
    tab_on = { "Inter-SemiBold.ttf", 12, "smalltfont" },
    number = { "Inter-SemiBold.ttf", 13, "smalltfont" },
}

local installed

local function has(file)
    if not installed then
        installed = {}
        for _, path in ipairs(FontList:getFontList()) do
            installed[path:match("[^/]+$")] = true
        end
    end
    return installed[file]
end

local theme = {
    ink = Blitbuffer.Color8(0x1a),
    secondary = Blitbuffer.Color8(0x55),
    panel = Blitbuffer.Color8(0xed),
    rule = Blitbuffer.Color8(0xc8),
    track = Blitbuffer.Color8(0xe2),
    cover = Blitbuffer.Color8(0xd6),
    white = Blitbuffer.COLOR_WHITE,
    space = {},
    radius = Screen:scaleBySize(10),
    line = math.max(1, Screen:scaleBySize(1)),
    border = math.max(1, Screen:scaleBySize(1.5)),
}

for i, s in ipairs({ 4, 8, 16, 24 }) do
    theme.space[i] = Screen:scaleBySize(s)
end

function theme.face(role, size)
    local r = ROLES[role] or ROLES.body
    local name = has(r[1]) and r[1] or r[3]
    return Font:getFace(name, size or r[2])
end

function theme.fonts_installed()
    return has("Fraunces-Medium.ttf") and has("Inter-Regular.ttf") and true or false
end

return theme
