-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local sys   = require "luci.sys"
local zones = require "luci.sys.zoneinfo"
local fs    = require "nixio.fs"
local conf  = require "luci.config"

local m, s, o
local has_ntpd = fs.access("/usr/sbin/ntpd")

m = Map("system", translate("System"), translate("Here you can configure the basic aspects of your device like its hostname, time, or administration password."))
m:chain("luci")
m2 = Map("firewall", "", "")
m3 = Map("lighttpd", "", "")

s = m:section(TypedSection, "system", translate("General"))
s.anonymous = true
s.addremove = false

--s:tab("logging",  translate("Logging"))
--s:tab("language", translate("Language and Style"))


--
-- System Properties
--

--o = s:option( Value, "hostname", translate("Hostname"))
--o.datatype = "hostname"

--function o.write(self, section, value)
--	Value.write(self, section, value)
--	sys.hostname(value)
--end

o = s:option( DummyValue, "_systime", translate("Local Time"))
o.template = "admin_system/clock_status"


o = s:option(ListValue, "zonename", translate("Timezone"))
o:value("UTC")

for i, zone in ipairs(zones.TZ) do
	o:value(zone[1])
end

function o.write(self, section, value)
	local function lookup_zone(title)
		for _, zone in ipairs(zones.TZ) do
			if zone[1] == title then return zone[2] end
		end
	end

	AbstractValue.write(self, section, value)
	local timezone = lookup_zone(value) or "GMT0"
	self.map.uci:set("system", section, "timezone", timezone)
	fs.writefile("/etc/TZ", timezone .. "\n")
end

-- AP-117
--
-- Logging
--

-- o = s:taboption("logging", Value, "log_size", translate("System log buffer size"), "kiB")
-- o.optional    = true
-- o.placeholder = 16
-- o.datatype    = "uinteger"

-- o = s:taboption("logging", Value, "log_ip", translate("External system log server"))
-- o.optional    = true
-- o.placeholder = "0.0.0.0"
-- o.datatype    = "ip4addr"

-- o = s:taboption("logging", Value, "log_port", translate("External system log server port"))
-- o.optional    = true
-- o.placeholder = 514
-- o.datatype    = "port"

-- o = s:taboption("logging", ListValue, "conloglevel", translate("Log output level"))
-- o:value(8, translate("Debug"))
-- o:value(7, translate("Info"))
-- o:value(6, translate("Notice"))
-- o:value(5, translate("Warning"))
-- o:value(4, translate("Error"))
-- o:value(3, translate("Critical"))
-- o:value(2, translate("Alert"))
-- o:value(1, translate("Emergency"))

-- o = s:taboption("logging", ListValue, "cronloglevel", translate("Cron Log Level"))
-- o.default = 8
-- o:value(5, translate("Debug"))
-- o:value(8, translate("Normal"))
-- o:value(9, translate("Warning"))


-- --
-- -- Langauge & Style
-- --

-- o = s:taboption("language", ListValue, "_lang", translate("Language"))
-- o:value("auto")

-- local i18ndir = luci.i18n.i18ndir .. "base."
-- for k, v in luci.util.kspairs(conf.languages) do
-- 	local file = i18ndir .. k:gsub("_", "-")
-- 	if k:sub(1, 1) ~= "." and fs.access(file .. ".lmo") then
-- 		o:value(k, v)
-- 	end
-- end

-- function o.cfgvalue(...)
-- 	return m.uci:get("luci", "main", "lang")
-- end

-- function o.write(self, section, value)
-- 	m.uci:set("luci", "main", "lang", value)
-- end


-- o = s:taboption("language", ListValue, "_mediaurlbase", translate("Design"))
-- for k, v in pairs(conf.themes) do
-- 	if k:sub(1, 1) ~= "." then
-- 		o:value(v, k)
-- 	end
-- end

-- function o.cfgvalue(...)
-- 	return m.uci:get("luci", "main", "mediaurlbase")
-- end

-- function o.write(self, section, value)
-- 	m.uci:set("luci", "main", "mediaurlbase", value)
-- end


--
-- NTP
--

if has_ntpd then

	-- timeserver setup was requested, create section and reload page
	if m:formvalue("cbid.system._timeserver._enable") then
		m.uci:section("system", "timeserver", "ntp",
			{
                	server = { "0.openwrt.pool.ntp.org", "1.openwrt.pool.ntp.org", "2.openwrt.pool.ntp.org", "3.openwrt.pool.ntp.org" }
			}
		)

		m.uci:save("system")
		luci.http.redirect(luci.dispatcher.build_url("admin/system", arg[1]))
		return
	end

	local has_section = false
	m.uci:foreach("system", "timeserver", 
		function(s) 
			has_section = true 
			return false
	end)

	if not has_section then

		s = m:section(TypedSection, "timeserver", translate("Time Synchronization"))
		s.anonymous   = true
		s.cfgsections = function() return { "_timeserver" } end

		x = s:option( Button, "_enable")
		x.title      = translate("Time Synchronization is not configured yet.")
		x.inputtitle = translate("Set up Time Synchronization")
		x.inputstyle = "apply"

	else
		
		s = m:section(TypedSection, "timeserver", translate("Time Synchronization"))
		s.anonymous = true
		s.addremove = false

		o = s:option( Flag, "enable", translate("Enable NTP client"))
		o.rmempty = false

		function o.cfgvalue(self)
			return sys.init.enabled("sysntpd")
				and self.enabled or self.disabled
		end

		function o.write(self, section, value)
			if value == self.enabled then
				sys.init.enable("sysntpd")
				sys.call("env -i /etc/init.d/sysntpd start >/dev/null")
			else
				sys.call("env -i /etc/init.d/sysntpd stop >/dev/null")
				sys.init.disable("sysntpd")
			end
		end


		--o = s:option( Flag, "enable_server", translate("Provide NTP server"))
		--o:depends("enable", "1")


		o = s:option( DynamicList, "server", translate("NTP server candidates"))
		o.datatype = "host"
		o:depends("enable", "1")

		-- retain server list even if disabled
		function o.remove() end

	end
end


s = m:section(TypedSection, "_dummy", "Administration")
s.addremove = false
s.anonymous = true

pw0 = s:option(Value, "pw0", translate("Old Password"))
pw0.password = true

pw1 = s:option(Value, "pw1", translate("New Password"))
pw1.password = true

pw2 = s:option(Value, "pw2", translate("Confirmation"))
pw2.password = true

function s.cfgsections()
	return { "_pass" }
end

--AP-263
function check_spacepasswd(pass)
	local check_space = 0
	local char_tmp = ""
	for i = 1, #pass
	do	
		char_tmp = pass:sub(i,i)
		if char_tmp == ' ' then
			return true
		end
	end
	return false
end

function check_strongpasswd(pass)
	local check_special = 0
	local check_uppercase = 0
	local check_lowercase = 0
	local check_number = 0
	local check_length = 0
	local char_tmp = ""

	if #pass >= 8 then
		check_length = 1
	end
	
	for i = 1, #pass
	do	
		char_tmp = pass:sub(i,i)
	
		-- check have special char
		local char_byte = string.byte(char_tmp)
		if (char_byte > 32 and char_byte < 48) 
		or (char_byte > 57 and char_byte < 65) 
		or (char_byte > 90 and char_byte < 97) 
		or (char_byte > 122 and char_byte < 127) then
			check_special = 1
		end
	
		-- check have uppercase
		if char_tmp >= 'A' and char_tmp <= 'Z' then
			check_uppercase = 1
		end
	
		-- check have lowercase
		if char_tmp >= 'a' and char_tmp <= 'z' then
			check_lowercase = 1
		end
			
		-- check have number
		if char_tmp >= '0' and char_tmp <= '9' then
			check_number = 1
		end
	end
	if check_length == 1 and check_special == 1 and check_uppercase == 1 and check_lowercase == 1 and check_number == 1 then
		return true
	else
		return false
	end

end

function m.on_commit(map)
	local v0 = pw0:formvalue("_pass")
	local v1 = pw1:formvalue("_pass")
	local v2 = pw2:formvalue("_pass")

	pw = s:option(DummyValue, "pw", translate(""))
	pw.template = "admin_system/pass"

	-- empty password => no action
	if #v0 == 0 and #v1 == 0 and #v2 == 0 then
		do return end
	end

	-- wrong old password => notice
	if luci.sys.user.checkpasswd(luci.dispatcher.context.authuser, v0) == false	then
		pw.message1 = "<p style=\"color:red;\">You entered the wrong old password!</p>"
		do return end
	end

	-- new pass or confirm is empty
	if #v1 == 0 or #v2 == 0 then
		pw.message1 = "<p style=\"color:red;\">New password can not be blank!</p>"
		do return end
	end

	-- check pass and confirm
	if v1 and v2 and #v1 > 0 and #v2 > 0 then

		-- check space character
		if check_spacepasswd(v1) == true or check_spacepasswd(v2) == true then
			pw.message1 = "<p style=\"color:red;\">Password does not include spaces</p>"
			do return end
		end

		-- 
		if v1 == v2 then
			if v1 == v0 then
				pw.message1 = "<p style=\"color:red;\">Old and new password are the same!</p>"
				do return end
			end
			
			if check_strongpasswd(v1) == false then
				if luci.sys.user.setpasswd(luci.dispatcher.context.authuser, v1) == 0 then
					pw.message2 = "Password successfully changed!"
					pw.message1 = "<p style=\"color:red;\">WARNING:Strong password must be more than 08 characters, using combination of uppercase,\
					lowercase, number and special characters</p>"
				end

			elseif luci.sys.user.setpasswd(luci.dispatcher.context.authuser, v1) == 0 then
				pw.message1= "Password successfully changed!"
			else
				pw.message1 = "Unknown Error, password not changed!"
			end
		else
			pw.message1 = "<p style=\"color:red;\">Given password confirmation did not match, password not changed!</p>"
		end
	end
end

manage_from_wan = m2:section(NamedSection, "access_from_wan", "rule", translate("Access Management"))
manage_from_wan.addremove = false

opt_enable_mng_from_wan = manage_from_wan:option(Flag, "target", translate("Enable Access From WAN"))
opt_enable_mng_from_wan.forcewrite = true
opt_enable_mng_from_wan.rmempty = false

function opt_enable_mng_from_wan.write(self, section, value)
	if value and #value > 0 then
		if value == "1" then
			m2:set(section, "enabled", "1")
		elseif value == "0" then
			m2:set(section, "enabled", "0")
		end
	end
end

function opt_enable_mng_from_wan.cfgvalue(self, section)
	local value = m2:get(section, "enabled")
	if value and #value > 0 then
		if value == "1" then
			return "1"
		elseif value == "0" then
			return "0"
		end
	else 
		return "0"
	end
end

-- m3.save = true
-- m3.apply_on_parse = true
local is_ports_valid = false
function is_restricted_port(port)
local rest_port={"0", "1", "5", "7", "9", "11", "13", "15", "17", "19", "20", "21", "22", "23", "25", "37", "42", "43", "53", "67", "68", "77", "79", "87", "95", "101", "102", "103", "104", "109", "110", "111", "113", "115", "117", "119", "123", "135", "139", "143", "161", "179", "389", "465", "512", "513", "514", "515", "526", "530", "531", "532", "540", "556", "563", "587", "601", "636", "993", "995", "1900", "2049", "3659", "4045", "5060", "5555", "6000", "6665", "6666", "6667", "6668", "6669", "8081", "8082", "8888"}
	local ret = false
	for _, value in ipairs(rest_port) do
		if port == value then
			ret = true
			break
		end
	end
	return ret
end

cfg_http_port = manage_from_wan:option(Value, "_listen_http", translate("Config HTTP port"))
cfg_http_port.forcewrite = true
cfg_http_port.rmempty = false
cfg_http_port.datatype = "uinteger"

function cfg_http_port.cfgvalue(self, section)
	return m3:get("main", "listen_http")
end
-- function cfg_http_port.cfgvalue(self, section)
-- 	local value = m3:get("main", "listen_http")
-- 	local http_port
-- 	for word in string.gmatch(value, "%S+") do
-- 		http_port = string.match(word, ":(.*)")
-- 		break
-- 	end
-- 	if http_port and #http_port > 0 then
-- 		return http_port
-- 	end
-- end

function cfg_http_port.validate(self, value, section)
	local https_port = m2:formvalue("cbid.firewall.access_from_wan._listen_https")
	local http_port = m2:formvalue("cbid.firewall.access_from_wan._listen_http")
	local http_port_n = tonumber(http_port)
	local https_port_n = tonumber(https_port)
	nixio.syslog("debug", "[fanwar]https_port="..https_port.."  http_port="..http_port)
	if http_port and #http_port > 0 and https_port and #https_port > 0 then
		if http_port_n < 0 or http_port_n >65535 or https_port_n < 0 or https_port_n >65535  then
			return nil, "The port number must be between 0 and 65535"
		end
		if is_restricted_port(http_port) == true or is_restricted_port(https_port) == true then
			return nil, "The port you set is well known port or used by another service, please try with another port!"
		end
		if http_port == https_port then
			return nil, "HTTP port and HTTPS port are the same"
		end
	else
		return nil, "Port values are empty"
	end
	nixio.syslog("debug", "[fanwar] validate ok")
	is_ports_valid = true
	return value
end

function cfg_http_port.write(self, section, value)
	if is_ports_valid == true then 
		local uci = require("luci.model.uci").cursor()
		local https_port = m2:formvalue("cbid.firewall.access_from_wan._listen_https")
		local http_port = m2:formvalue("cbid.firewall.access_from_wan._listen_http")
		if http_port and #http_port > 0 and https_port and #https_port > 0 then
			m3:set("main", "listen_http", http_port)
			m3:set("main", "listen_https", https_port)
			uci:delete("firewall", "access_from_wan", "dest_port")
			uci:set_list("firewall", "access_from_wan", "dest_port", {http_port, https_port})
			uci:commit("firewall")
		end
	end
end
-- function cfg_http_port.write(self, section, value)
-- 	if is_ports_valid == true then 
-- 		local uci = require("luci.model.uci").cursor()
-- 		local https_port = m2:formvalue("cbid.firewall.access_from_wan._listen_https")
-- 		local http_port = m2:formvalue("cbid.firewall.access_from_wan._listen_http")
-- 		if http_port and #http_port > 0 and https_port and #https_port > 0 then
-- 			m3:set("main", "listen_http", "0.0.0.0:"..http_port.." ".."[::]:"..http_port)
-- 			m3:set("main", "listen_https", "0.0.0.0:"..https_port.." ".."[::]:"..https_port)
-- 			uci:delete("firewall", "access_from_wan", "dest_port")
-- 			uci:set_list("firewall", "access_from_wan", "dest_port", {http_port, https_port})
-- 			uci:commit("firewall")
-- 		end
-- 	end
-- end

cfg_https_port = manage_from_wan:option(Value, "_listen_https", translate("Config HTTPS port"))
cfg_https_port.write = cfg_http_port.write
cfg_https_port.datatype = "uinteger"
function cfg_https_port.validate(self, value, section)
	local https_port = m2:formvalue("cbid.firewall.access_from_wan._listen_https")
	local http_port = m2:formvalue("cbid.firewall.access_from_wan._listen_http")
	nixio.syslog("debug", "[fanwar]https_port="..https_port.."  http_port="..http_port)
	if http_port and #http_port > 0 and https_port and #https_port > 0 then
		if http_port == https_port then
			return nil, "Please config again"
		end
	else
		return nil, "Please config again"
	end
	nixio.syslog("debug", "[fanwar] validate ok")
	return value
end
function cfg_https_port.cfgvalue(self, section)
	return m3:get("main", "listen_https")
end
-- function cfg_https_port.cfgvalue(self, section)
-- 	local value = m3:get("main", "listen_https")
-- 	local https_port
-- 	for word in string.gmatch(value, "%S+") do
-- 		https_port = string.match(word, ":(.*)")
-- 		break
-- 	end
-- 	if https_port and #https_port > 0 then
-- 		return https_port
-- 	end
-- end

return m,m2,m3
