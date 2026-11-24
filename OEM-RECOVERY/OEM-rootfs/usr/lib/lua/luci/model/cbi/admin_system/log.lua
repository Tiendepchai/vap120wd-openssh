-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local sys   = require "luci.sys"
local zones = require "luci.sys.zoneinfo"
local fs    = require "nixio.fs"
local conf  = require "luci.config"

local m, s, o

m = Map("system", translate("System Log"), translate("Here you can see logs as long as configure how logs are saved."))
m:chain("luci")


s = m:section(TypedSection, "system")
s.anonymous = true
s.addremove = false

s:tab("syslog",  translate("System Log"))
s:tab("wifilog",  translate("WiFi Log"))
s:tab("meshlog",  translate("Mesh Log"))
-- s:tab("dmesg",  translate("Kernel Log"))
-- s:tab("setting", translate("Settings"))

--
-- System Log
--

o = s:taboption("syslog", DummyValue, "_syslog", translate(""))
o.log_type = "syslog"
o.template = "cbi/syslog"

--
-- WiFi Log
--

o = s:taboption("wifilog", DummyValue, "_wifilog", translate(""))
o.log_type = "wifilog"
o.template = "cbi/syslog"

--
-- Mesh Log
--

o = s:taboption("meshlog", DummyValue, "_meshlog", translate(""))
o.log_type = "meshlog"
o.template = "cbi/syslog"

-- --
-- -- kernel Log
-- --

-- o = s:taboption("dmesg", DummyValue, "_dmesg", translate(""))
-- o.log_type = "dmesg"
-- o.template = "cbi/syslog"


--
-- Logging
--

-- o = s:taboption("setting", Value, "log_size", translate("System log buffer size"), "kiB")
-- o.optional    = true
-- o.placeholder = 16
-- o.datatype    = "uinteger"

-- o = s:taboption("setting", Value, "log_ip", translate("External system log server"))
-- o.optional    = true
-- o.placeholder = "0.0.0.0"
-- o.datatype    = "ip4addr"

-- o = s:taboption("setting", Value, "log_port", translate("External system log server port"))
-- o.optional    = true
-- o.placeholder = 514
-- o.datatype    = "port"

-- o = s:taboption("setting", ListValue, "conloglevel", translate("Log output level"))
-- o:value(8, translate("Debug"))
-- o:value(7, translate("Info"))
-- o:value(6, translate("Notice"))
-- o:value(5, translate("Warning"))
-- o:value(4, translate("Error"))
-- o:value(3, translate("Critical"))
-- o:value(2, translate("Alert"))
-- o:value(1, translate("Emergency"))

-- o = s:taboption("setting", ListValue, "cronloglevel", translate("Cron Log Level"))
-- o.default = 8
-- o:value(5, translate("Debug"))
-- o:value(8, translate("Normal"))
-- o:value(9, translate("Warning"))
return m
