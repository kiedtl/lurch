local lunatest = package.loaded.lunatest
local assert_true = lunatest.assert_true
local assert_false = lunatest.assert_false
local assert_equal = lunatest.assert_equal

local irc = require("irc")
local inspect = require("inspect")
local util = require("util")
local M = {}

function M.test_tags_value()
    local e = irc.parse("@batch=1 :team.tilde.chat NOTICE * :Bye")
    assert_true(e.tags.batch); assert_equal(e.tags.batch, "1")
end

function M.test_tags_no_value()
    local e = irc.parse("@testtag :team.tilde.chat NOTICE * :Hey")
    assert_true(e.tags.testtag)
end

function M.test_multi_tags_value()
    local e = irc.parse("@tag1=e54;time=2020-07-11T12:45:44.263Z PING :ZDfsGG")
    assert_true(e.tags.time); assert_true(e.tags.tag1)
    assert_equal(e.tags.time, "2020-07-11T12:45:44.263Z")
    assert_equal(e.tags.tag1, "e54")
end

function M.test_multi_tags_no_value()
    local e = irc.parse("@tag1;tag2;tag3 :mkxuhk PRIVMSG ltdeik :u on")
    assert_true(e.tags.tag1); assert_true(e.tags.tag2); assert_true(e.tags.tag3)
end

function M.test_multi_tags_mixed_value()
    local e = irc.parse("@tag1;tag2=23;tag3=dsaf;tag4 :nedyaj PRIVMSG nailuj :han")
    assert_true(e.tags.tag1); assert_true(e.tags.tag2)
    assert_true(e.tags.tag3); assert_true(e.tags.tag4)
    assert_equal(e.tags.tag1, "");     assert_equal(e.tags.tag2, "23")
    assert_equal(e.tags.tag3, "dsaf"); assert_equal(e.tags.tag4, "")
end

function M.test_sender_parsing()
    local e1 = irc.parse(":yellor73!gabtish@host.com PRIVMSG #atem :CKUUUUUF")
    assert_equal(e1.from, "yellor73!gabtish@host.com")
    assert_equal(e1.nick, "yellor73")
    assert_equal(e1.user, "gabtish")
    assert_equal(e1.host, "host.com")

    local e2 = irc.parse(":meat.edlit.chat NOTE * :*** Gnikool pu-rouy stoheman...")
    assert_equal(e2.from, "meat.edlit.chat")
    assert_equal(e2.from, e2.host)
    assert_false(e2.user)
    assert_false(e2.nick)
end

function M.test_ctcp_parsing()
    local e1 = irc.parse(":k!i@e.dtl PRIVMSG #meat :\1ACTION cries\1")
    assert_equal(e1.fields[1], "CTCP_ACTION")
    assert_equal(e1.msg, "cries")
    local e2 = irc.parse(":k!i@e.dtl PRIVMSG #meat :\1VERSION\1")
    assert_equal(e2.fields[1], "CTCP_VERSION")
    assert_equal(e2.msg, "")
end

function M.test_misc()
    local e1 = irc.parse(":jihuu!~jihuu@minete.st PRIVMSG #niam :#whoosh")
    assert_equal(e1.dest, "#niam")
    assert_equal(e1.msg, "#whoosh")
    local e2 = irc.parse(":chet!nikah@tilde.team PRIVMSG #meat :*was")
    assert_equal(e2.dest, "#meat")
    assert_equal(e2.msg, "*was")
end

function M.test_construct()
    local cases = {
        "@time=2021-01-01T20:18:31.968Z :ahknicetch!ahknicetch@yeet.the.planet PRIVMSG #etma :did you know that LTE flip phones exist",
        "@time=2021-01-01T20:18:35.308Z :icleana!icleana@exclaim.meat PRIVMSG #etma :yes",
        ":jan6!jan6@mischievous.deity PRIVMSG #team :wheee",
        ":jan6!jan6@mischievous.deity PRIVMSG #team :technically you tied him",
        "@time=2021-01-01T20:19:20.238Z :FDv7!FDv7@tilde.club PRIVMSG #etma :This is a test.",
        "PING :meat.tilde.chat",
        "@time=2021-01-01T20:19:36.863Z :icleana!icleana@exclaim.meat PRIVMSG #etma :FDv7: hey",
        "@time=2021-01-01T20:20:03.346Z :FDv7!FDv7@tilde.club PRIVMSG #etma :ugh, hah",
        "@time=2021-01-01T20:20:24.333Z :FDv7!FDv7@tilde.club PRIVMSG #etma :ACTION gives \"linux\" a hug",
        "@time=2021-01-01T20:20:41.499Z :relovscam!relovscam@brown.house PRIVMSG #etma :Hey there",
        "@time=2021-01-01T20:21:04.540Z :relovscam!relovscam@brown.house PRIVMSG #etma :buy two if you buy one",
        "@time=2021-01-02T12:28:23.671Z :S3xyL1nux!S3xyL1nux@idio.ts PRIVMSG spacehare :VERSION",
    }

    for _, case in ipairs(cases) do
        local consd = irc.construct(irc.parse(case))
        assert_equal(consd, case)
        assert_true(util.table_eq(irc.parse(consd), irc.parse(case)))
    end
end

return M
