local Wording = require("bookbindery/wording")

local ReadState = {}

local function title_of(file)
    local name = file:match("([^/]+)$") or file
    name = name:gsub("%.[^.]+$", "")
    return (name:gsub("%s+%-%s+[^%-]+$", ""))
end

-- books_root: the books folder main.lua works out (KOReader's home folder unless set)
function ReadState.reading(history, sidecar, index, books_root)
    local root = books_root or Wording.books_root or ""
    local out = {}
    for _, h in ipairs(history) do
        local file = h.file
        if file and not file:find("/koreader/", 1, true) then
            local lpath = file:sub(1, #root) == root and file:sub(#root + 1) or file
            local book = index and index.books[lpath]
            local sc = sidecar(file) or {}
            local percent = sc.percent or 0
            local hidden = sc.status == "complete" or percent >= 1
                or (book and (book.status == "read" or book.status == "dnf"))
            if not hidden then
                out[#out + 1] = {
                    file = file,
                    book = book,
                    title = book and book.title or title_of(file),
                    percent = percent,
                    page = sc.page,
                    pages = sc.pages,
                    last_read = h.time,
                }
            end
        end
    end
    table.sort(out, function(a, b) return (a.last_read or 0) > (b.last_read or 0) end)
    return out
end

function ReadState.days_read(rows, month)
    local seen, n = {}, 0
    for _, r in ipairs(rows) do
        local day = r.day
        if day and day:sub(1, 7) == month and not seen[day] then
            seen[day] = true
            n = n + 1
        end
    end
    return n
end

return ReadState
