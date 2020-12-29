local lunatest = package.loaded.lunatest
local assert_true = lunatest.assert_true
local assert_false = lunatest.assert_false
local assert_equal = lunatest.assert_equal

local irc = require("irc")
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

return M
