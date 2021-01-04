local lunatest = package.loaded.lunatest
local assert_true = lunatest.assert_true
local assert_false = lunatest.assert_false
local assert_equal = lunatest.assert_equal
local format = string.format

local irc = require("irc")
local inspect = require("inspect")
local util = require("util")
local M = {}

local function _assert_table_eq(a, b)
    assert_true(util.table_eq(a, b),
        format("Expected \n\t%s, got \n\t%s", inspect(a), inspect(b)))
end

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

function M.test_field_parsing()
    local cases = {
        { ":meacha!~meacha@215.67.742.16 PRIVMSG #kisslinux :hey ", { "PRIVMSG", "#kisslinux" }, "hey", "#kisslinux" },
        { ":rms!~rms@eewf.erawfots JOIN #team", { "JOIN", "#team" }, "", "#team" },
        { ":team.tilde.chat 314 nsa nak ~nak 2601:100:151:3dbc:96ff:a11:e34b:2f1c * :nak", { "314", "nsa", "nak", "~nak", "2601:100:151:3dbc:96ff:a11:e34b:2f1c", "*" }, "nak" },
        { ":jihuu!~jihuu@minete.st PRIVMSG #niam :#whoosh", { "PRIVMSG", "#niam" }, "#whoosh", "#niam" },
        { ":chet!nikah@tilde.team PRIVMSG #meat :*was", { "PRIVMSG", "#meat" }, "*was", "#meat" },
        { ":team.tilde.chat 353 nsa = #chaos :exef enuu Civan Oyster nsa", { "353", "nsa", "=", "#chaos" }, "exef enuu Civan Oyster nsa", "#chaos" },
        { ":team.tilde.chat 353 nsa @ #nsa :@nsa", { "353", "nsa", "@", "#nsa" }, "@nsa", "#nsa" },
    }

    for _, case in ipairs(cases) do
        local parsed = irc.parse(case[1])
        if case[3] then assert_equal(case[3], parsed.msg) end
        if case[4] then assert_equal(case[4], parsed.dest) end
        _assert_table_eq(case[2], parsed.fields)
    end
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
    local cases = {
        { ":k!i@e.dtl PRIVMSG #meat :\1ACTION cries\1", { "CTCPQ_ACTION", "#meat" }, "cries" },
        { ":k!i@e.dtl PRIVMSG nsa :\1VERSION\1", { "CTCPQ_VERSION", "nsa" }, "" },
        { ":tildebot!nib@tilde.chat NOTICE nsa :\1PING \1", { "CTCPR_PING", "nsa" }, "" },
    }

    for _, case in ipairs(cases) do
        local parsed = irc.parse(case[1])
        if case[3] then assert_equal(case[3], parsed.msg) end
        _assert_table_eq(case[2], parsed.fields)
    end
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
        _assert_table_eq(irc.parse(consd), irc.parse(case))
        assert_equal(consd, case)
    end
end

function M.test_normalise_nick()
    local cases = {
        { "Nav|C",                     "Nav|C" },
        { "|",                             "|" },
        { "||",                           "||" },
        { "inebriate|lurch",       "inebriate" },
        { "inebriate|lurch_",      "inebriate" },
        { "inebriate_",            "inebriate" },
        { "inebriate__",           "inebriate" },
        { "_",                             "_" },
        { "_DEFAULT_SOURCE", "_DEFAULT_SOURCE" },
        { "cpcpcm[m]",                "cpcpcm" },
        { "[m][m]",                      "[m]" }
    }

    for _, case in ipairs(cases) do
        assert_equal(case[2], irc.normalise_nick(case[1]))
    end
end

return M
