local Home = require("bookbindery/home")

local function rows(n)
    local out = {}
    for i = 1, n do
        out[i] = { title = "b" .. i, percent = 0.1, last_read = 100 - i }
    end
    return out
end

local function model(reading)
    return Home.model(reading, 2000)
end

describe("Home#model", function()
    it("reading_count is the total reading, the big card's book included", function()
        local m = model(rows(4))
        assert.equals("b1", m.current.title)
        assert.equals("b2", m.more.title)
        assert.equals(4, m.reading_count)
    end)

    it("handles nothing being read", function()
        local m = model({})
        assert.is_nil(m.current)
        assert.is_nil(m.more)
        assert.equals(0, m.reading_count)
    end)

    it("passes the time through", function()
        assert.equals(2000, model(rows(1)).now)
    end)
end)
