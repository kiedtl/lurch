#!/usr/bin/env lua

local dir = (debug.getinfo(1).source:sub(2)):match("(.*)/")
package.path = ("%s/../rt/?.lua;"):format(dir) .. package.path
package.path = ("%s/../conf/?.lua;"):format(dir) .. package.path
package.path = ("%s/?.lua;"):format(dir) .. package.path

local lunatest = require("lunatest")

lunatest.suite("irc_test")
lunatest.suite("util_test")
lunatest.run()
