--[[--
The reader's "book" menu entry: which index entry the open file is, and putting
the entry first in the reader menu's first tab. Pure.
]]

local ReaderBook = {}

-- the index entry for file (under root), a stub built like a fic row's when the index doesn't
-- know it, nil when the file is outside root
function ReaderBook.entry(file, root, index)
    if not (file and root and #root > 0 and file:sub(1, #root) == root) then
        return nil
    end
    local lpath = file:sub(#root + 1)
    local known = index and index.books and index.books[lpath]
    if known then
        return known
    end
    local title = (lpath:match("([^/]+)$") or lpath):gsub("%.[^.]+$", "")
    return { lpath = lpath, title = title, authors = {}, tags = {},
        library = lpath:find("^fanfic/") and "fanfic" or "books" }
end

-- moves the item with this id to the head of the first tab; false when it isn't there
function ReaderBook.first(tabs, id)
    local tab = tabs and tabs[1]
    if type(tab) ~= "table" then
        return false
    end
    for i, item in ipairs(tab) do
        if type(item) == "table" and item.id == id then
            if i > 1 then
                table.remove(tab, i)
                table.insert(tab, 1, item)
            end
            return true
        end
    end
    return false
end

-- wraps sorter.mergeAndSort once so the reader menu (prefix "reader") gets id first; false when already wrapped
function ReaderBook.wrap_sorter(sorter, id)
    if sorter.bookbindery_patched then
        return false
    end
    sorter.bookbindery_patched = true
    local orig = sorter.mergeAndSort
    sorter.mergeAndSort = function(self, prefix, ...)
        local tabs = orig(self, prefix, ...)
        if prefix == "reader" then
            pcall(ReaderBook.first, tabs, id)
        end
        return tabs
    end
    return true
end

return ReaderBook
