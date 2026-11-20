--[[--
Theme patch helpers, pure. patches/2-bookbindery-theme.lua loads this with
dofile; nothing here requires KOReader, so a broken part only turns itself off.
]]

local ThemePatch = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

-- log(msg) gets one line per part that fails: "bookbindery-theme: <part> off: <err>"
function ThemePatch.guard(log)
    local g = { off = {} }

    function g.fail(part, err)
        if not g.off[part] then
            g.off[part] = true
            pcall(log, "bookbindery-theme: " .. part .. " off: " .. tostring(err))
        end
    end

    -- runs fn now; an error turns the part off
    function g.install(part, fn)
        local ok, err = pcall(fn)
        if not ok then
            g.fail(part, err)
        end
        return ok
    end

    -- target[name] still runs exactly once, with its own results and errors;
    -- hook(...) runs before it and may return an after() that runs once it's
    -- done (even when it raised). A hook or after() that raises turns the part off.
    function g.wrap(part, target, name, hook)
        local orig = target[name]
        if type(orig) ~= "function" then
            error(name .. " isn't a function", 2)
        end
        target[name] = function(...)
            if g.off[part] then
                return orig(...)
            end
            local ok, after = pcall(hook, ...)
            if not ok then
                g.fail(part, after)
                return orig(...)
            end
            if type(after) ~= "function" then
                return orig(...)
            end
            local res = pack(pcall(orig, ...))
            local ok2, err = pcall(after)
            if not ok2 then
                g.fail(part, err)
            end
            if not res[1] then
                error(res[2], 0)
            end
            return unpack(res, 2, res.n)
        end
        return orig
    end

    return g
end

ThemePatch.REGULAR = "bookbindery/Inter-Regular.ttf"
ThemePatch.BOLD = "bookbindery/Inter-SemiBold.ttf"

-- KOReader's UI font keys (never the reading fonts, never the mono ones)
local KEYS = {
    cfont = "regular", ffont = "regular", smallffont = "regular", largeffont = "regular",
    rifont = "regular", pgfont = "regular", hfont = "regular", infofont = "regular",
    smallinfofont = "regular", x_smallinfofont = "regular", xx_smallinfofont = "regular",
    tfont = "bold", smalltfont = "bold", x_smalltfont = "bold", smallinfofontbold = "bold",
}

-- fontmap keys to set: keys the user set in settings (user) stay, nothing when
-- the Inter files are missing (have(file) → bool)
function ThemePatch.fonts(user, have)
    if not (have(ThemePatch.REGULAR) and have(ThemePatch.BOLD)) then
        return {}
    end
    local out = {}
    for key, weight in pairs(KEYS) do
        if not (user and user[key]) then
            out[key] = weight == "bold" and ThemePatch.BOLD or ThemePatch.REGULAR
        end
    end
    return out
end

-- texts of a button table's primary buttons: is_enter_default entries, or the
-- confirm box's ok text (first match only)
function ThemePatch.primaries(rows, ok_text)
    local out, ok_seen = {}, false
    for _i, row in ipairs(rows or {}) do
        for _j, b in ipairs(row) do
            if b.text and (b.is_enter_default or (ok_text and not ok_seen and b.text == ok_text)) then
                out[b.text] = true
                ok_seen = ok_seen or b.text == ok_text
            end
        end
    end
    return out
end

return ThemePatch
