local InfoText = require("bookbindery/infotext")

describe("InfoText#html", function()
    it("keeps paragraphs, splits at <br>, decodes entities", function()
        local s = InfoText.html("<div><p>Tom &amp; Jerry&#8217;s &quot;day&quot;&nbsp;out<br/>next   line</p>"
            .. "<p><em>Two</em> &#x2014; &lt;b&gt; &hellip;</p></div>")
        assert.equal("Tom & Jerry’s \"day\" out\n\nnext line\n\nTwo — <b> …", s)
    end)

    it("is empty for nothing", function()
        assert.equal("", InfoText.html(nil))
        assert.equal("", InfoText.html(""))
    end)
end)

describe("InfoText#about", function()
    it("cuts at a word and says so", function()
        local text, more = InfoText.about("one two three\n\nfour", 9)
        assert.equal("one two…", text)
        assert.is_true(more)
        assert.same({ "one four", true }, { InfoText.about("one\n\nfour", 50) })
    end)
end)
