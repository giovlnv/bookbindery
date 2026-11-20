--[[--
Http: one request through KOReader's socket stack, lazily loaded so busted never needs it.
Returns ok, status, headers and the body, or nil and the transport's reason.
]]

local Http = {}

local TIMEOUT = 5

function Http.request(opts)
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local transport = opts.url:match("^https:") and require("ssl.https") or require("socket.http")
    local t = opts.timeout or TIMEOUT
    socketutil:set_timeout(t, t)
    local chunks = {}
    local pok, ok, status, headers = pcall(transport.request, {
        url = opts.url,
        method = opts.method,
        headers = opts.headers,
        source = opts.body and ltn12.source.string(opts.body) or nil,
        sink = socketutil.table_sink(chunks),
    })
    socketutil:reset_timeout()
    if not pok then
        return nil, ok
    end
    return ok, status, headers or {}, table.concat(chunks)
end

return Http
