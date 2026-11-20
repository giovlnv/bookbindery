--[[--
Wording: names and words for the ui and calibre's columns.
]]

local Wording = {
    -- calibre's pages column
    pages_column = "#pages",
    -- lpaths of the books library (fanfic/ is the other one); "" is every book outside fanfic/
    books_prefix = "",
    -- the books folder; nil: KOReader's home folder
    books_root = nil,
    -- the device in sentences, the menu's device tab, the fic info row naming the folder
    device = "this device",
    device_tab = "device",
    folder_label = "folder",
    -- what library search covers, in its count line
    library_place = "your library",
    -- menu labels; nil keeps KOReader's own text
    menu = {},
}

-- an lpath in the books library
function Wording.is_book(lpath)
    return type(lpath) == "string" and lpath:sub(1, 7) ~= "fanfic/"
        and lpath:sub(1, #Wording.books_prefix) == Wording.books_prefix
end

return Wording
