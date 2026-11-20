-- KOReader wraps a plugin's event handlers in callable tables
return function(f)
    local mt = type(f) == "table" and getmetatable(f)
    return type(f) == "function" or (mt and mt.__call ~= nil) or false
end
