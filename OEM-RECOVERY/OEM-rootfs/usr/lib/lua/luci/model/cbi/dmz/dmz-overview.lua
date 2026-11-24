-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2010-2012 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local ds = require "luci.dispatcher"
local ft = require "luci.tools.firewall"

local m,s,o

m = Map("firewall", translate("DMZ"),
	translate("DMZ allows remote computers on the Internet to \
	           connect to a specific computer or service within the \
	           private LAN."))

--
-- IP VALIDATION
--
function ip_validate(ip)
	local R = {ERROR = 0, IPV4 = 1, STRING = 2}
	if type(ip) ~= "string" then return R.ERROR end

	local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
		if #chunks == 4 then
			for _,v in pairs(chunks) do
				if tonumber(v) > 255 then return R.STRING end
				end
		return R.IPV4
	end
	return R.STRING
end

--
-- DMZ
--
m.uci:foreach("firewall", "redirect",
	function(x)
		local sid = x['.name']
		if x["name"] == "DMZ" or x["_name"] == "DMZ" then
			s = m:section(NamedSection, sid, "redirect", nil)
			
			s.addremove = false
			s.anonymous = true

			FormatString ='%-10s%-10s\n'
			local file = io.open( "/root/testout.txt", "w" )
			file:write(string.format(FormatString, sid, type(sid)))
			file:write(string.format(FormatString, x["name"], type(x["name"])))
			file:close()

			-- ft.opt_enabled(s, Flag, translate("Enable")).width = "1%"
			enable_dmz = s:option(Flag, "enabled", translate("Enable"))
			enable_dmz.default = enable_dmz.disabled
			enable_dmz.rmempty = false

			o = s:option(Value, "dest_ip", translate("Destination IP"))
			o.nocreate = true
			o:depends("enabled", "1")

			luci.sys.net.ipv4_hints(function(ip, name)
				o:value(ip, "%s (%s)" %{ ip, name })
			end)
				
			function o.cfgvalue(self, section)
				return self.map:get(section, "dest_ip") or
					self.map:get(section, "_dest_ip") or "-"
			end

			function o.validate(self, value, section)
				local ip_check =  ip_validate(value)
				nixio.syslog("debug", "[sonnh68] dmz dst_ip = "..value.."   ip_type = "..ip_check )
				if ip_check == 0 or ip_check == 2 then
						return nil, "Invalid IP"
				end
				return value
			end
			
			function o.write(self, section, value)
				if value ~= "-" then
					self.map:set(section, "dest_ip", value)
					self.map:del(section, "_dest_ip")
				else
					self:remove(section)
				end
			end

			function o.remove(self, section)
				self.map:del(section, "dest_ip")
				self.map:del(section, "_dest_ip")
			end
		end
	end
	)
return m
