local MarkAs = require("bookbindery/markas")

describe("MarkAs#statuses", function()
    it("lists the four workflow values in order, the current one checked", function()
        local rows = MarkAs.statuses("reading")
        assert.same({ "TBR", "ONGOING", "READ", "DNF" },
            { rows[1].value, rows[2].value, rows[3].value, rows[4].value })
        assert.same({ "to read", "reading", "read", "did not finish" },
            { rows[1].label, rows[2].label, rows[3].label, rows[4].label })
        assert.same({ "tbr", "ongoing", "finished", "dnf" },
            { rows[1].note, rows[2].note, rows[3].note, rows[4].note })
        assert.same({ false, true, false, false },
            { rows[1].checked, rows[2].checked, rows[3].checked, rows[4].checked })
    end)

    it("checks nothing for a book without a status", function()
        for _, r in ipairs(MarkAs.statuses(nil)) do
            assert.is_false(r.checked)
        end
        assert.is_true(MarkAs.statuses("dnf")[4].checked)
        assert.is_true(MarkAs.statuses("tbr")[1].checked)
    end)
end)

describe("MarkAs#koreader", function()
    it("follows the workflow value, nothing for to read", function()
        assert.equal("reading", MarkAs.koreader("ONGOING"))
        assert.equal("complete", MarkAs.koreader("READ"))
        assert.equal("abandoned", MarkAs.koreader("DNF"))
        assert.is_nil(MarkAs.koreader("TBR"))
    end)
end)
