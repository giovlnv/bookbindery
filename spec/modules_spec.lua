-- every module a file requires when it loads is in the plugin
local function files()
    local out = {}
    local p = assert(io.popen('find bookbindery.koplugin patches -name "*.lua" | sort'))
    for path in p:lines() do
        out[#out + 1] = path
    end
    p:close()
    return out
end

describe("plugin modules", function()
    it("every top-level bookbindery require resolves to a file", function()
        local missing, n = {}, 0
        for _, path in ipairs(files()) do
            local i = 0
            for line in io.lines(path) do
                i = i + 1
                for name in (line:match("^%S") and line or ""):gmatch('require%("bookbindery/([%w_/]+)"%)') do
                    n = n + 1
                    local f = io.open("bookbindery.koplugin/bookbindery/" .. name .. ".lua")
                    if f then
                        f:close()
                    else
                        missing[#missing + 1] = path .. ":" .. i .. ": " .. name
                    end
                end
            end
        end
        assert.is_true(n > 20)
        assert.same({}, missing)
    end)
end)
