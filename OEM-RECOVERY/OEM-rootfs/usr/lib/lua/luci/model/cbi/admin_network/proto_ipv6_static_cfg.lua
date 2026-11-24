-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.
local map, section, net = ...
local ifc = net:get_interface()
ds_ip6 = section:option(DummyValue, "_dummy_IPv6", translate("Static IPv6 Config"))
ds_ip6:depends("ipv6", conn_ip6_enable.enabled)

-- IPv6 Static Config block
ip6_addr = section:option(Value, "ip6addr", translate("IPv6 address"))
ip6_addr.datatype = "ip6addr"
ip6_addr:depends("ipv6", conn_ip6_enable.enabled)
-- function ip6_addr.write(self, section, value)
--     m:set(net:name().."_ip6", "ip6addr", value)
-- end
-- function ip6_addr.cfgvalue(self, section)
--     return m:get(net:name().."_ip6", "ip6addr")
-- end

ip6_gw = section:option(Value, "ip6gw", translate("IPv6 gateway"))
ip6_gw.datatype = "ip6addr"
ip6_gw:depends("ipv6", conn_ip6_enable.enabled)
-- function ip6_gw.write(self, section, value)
--     m:set(net:name().."_ip6", "ip6gw", value)
-- end
-- function ip6_gw.cfgvalue(self, section)
--     return m:get(net:name().."_ip6", "ip6gw")
-- end

ip6_prefix = section:option(Value, "ip6prefix",translate("IPv6 routed prefix"))
ip6_prefix.datatype = "ip6addr"
ip6_prefix:depends("ipv6", conn_ip6_enable.enabled)
-- function ip6_prefix.write(self, section, value)
--     m:set(net:name().."_ip6", "ip6prefix", value)
-- end
-- function ip6_prefix.cfgvalue(self, section)
--     return m:get(net:name().."_ip6", "ip6prefix")
-- end

ip6_dns = section:option(DynamicList, "_dns6", translate("Use custom DNS servers"))
ip6_dns.datatype = "ip6addr"
ip6_dns.cast = "string"
ip6_dns:depends("ipv6", conn_ip6_enable.enabled)
-- function ip6_dns.write(self, section, value)
--     DynamicList.write(self, net:name().."_ip6", value)
-- end
-- function ip6_dns.cfgvalue(self, section)
--     return DynamicList.cfgvalue(self, net:name().."_ip6")
-- end
function ip6_dns.write(self, section, value)
	local t = { }

	if type(value) == "table" then
		local x
		for _, x in ipairs(value) do
			if x and #x > 0 then
				t[#t+1] = x
			end
		end
	else
		t = { value }
	end

	if self.cast == "string" then
		value = table.concat(t, " ")
	else
		value = t
	end

	return m:set(net:name().."_ip6", "dns", value)
end

function ip6_dns.cfgvalue(self, section)
	local value = m:get(net:name().."_ip6", "dns")

	if type(value) == "string" then
		local x
		local t = { }
		for x in value:gmatch("%S+") do
			if #x > 0 then
				t[#t+1] = x
			end
		end
		value = t
	end

	return value
end
