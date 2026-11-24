local fs = require "nixio.fs"
local ut = require "luci.util"
local pt = require "luci.tools.proto"
local nw = require "luci.model.network"
local fw = require "luci.model.firewall"
local ipc = require "luci.ip"

local has_dnsmasq  = fs.access("/etc/config/dhcp")
m = Map("network", translate("LAN Configuration"), translate("<br>"))
local param = m.param

nw.init(m.uci)
fw.init(m.uci)
m2 = Map("dhcp", "", "")

local net = nw:get_network("lan")
local ifc = net:get_interface()

s = m:section(NamedSection, "lan", "interface", translate("IP address configuration"))
s.addremove = false

-- local form, ferr = loadfile(ut.libpath() .. "/model/cbi/admin_network/proto_static.lua")
ipaddr = s:option(Value, "ipaddr", translate("IPv4 address"))
ipaddr.datatype = "ip4addr"

netmask = s:option(Value, "netmask", translate("IPv4 netmask"))
netmask.datatype = "ip4addr"
netmask:value("255.255.255.0")
netmask:value("255.255.0.0")
netmask:value("255.0.0.0")

f_toggle = s:option(Flag, "ipv6", translate("Enable IPv6"))
f_toggle.default = f_toggle.enabled
f_toggle.rmempty = false

local function isInteger(str)
	return not (str == nil or str == "" or str:find("%D"))  -- str:match("%D") also works
end
function Split(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end
if has_dnsmasq and net:proto() == "static" then
	local has_section = false

	m2.uci:foreach("dhcp", "dhcp", function(s)
		if s.interface == "lan" then
			has_section = true
			return false
		end
	end)

	if not has_section and has_dnsmasq then

		s = m2:section(TypedSection, "dhcp", translate("DHCP Server"))
		s.anonymous   = true
		s.cfgsections = function() return { "_enable" } end

		x = s:option(Button, "_enable")
		x.title      = translate("No DHCP Server configured for this interface")
		x.inputtitle = translate("Setup DHCP Server")
		x.inputstyle = "apply"

	elseif has_section then

		s = m2:section(TypedSection, "dhcp", translate("DHCP Configuration"))
		s.addremove = false
		s.anonymous = true

		function s.filter(self, section)
			return m2.uci:get("dhcp", section, "interface") == "lan"
		end

		local enable_dhcp = s:option(Flag, "ignore", translate("Enable DHCPv4"))
		enable_dhcp.rmempty = false
		enable_dhcp.forcewrite = true
		function enable_dhcp.write(self, section, value)
			if value and #value > 0 then
				if value == "1" then
					m2:set(section, "ignore", "0")
				else
					m2:set(section, "ignore", "1")
				end
			else
				nixio.syslog("debug", "[fanwar][dhcp-lan] write invalid value")
			end
		end
		function enable_dhcp.cfgvalue(self, section)
			local v = m2:get(section, "ignore")
			if v and #v > 0 then
				if v == "1" then
					return "0"
				else
					return "1"
				end
			else
				return "1"
			end
		end

		local start = s:option(Value, "start", translate("Start"))
		-- start.optional = true
		start.datatype = "uinteger"
		start.rmempty = true

		local _end = s:option(Value, "_end", translate("End"))
		_end.datatype = "uinteger"
		_end.rmempty = true

		function _end.write(self, section, value)
			local end_value = tonumber(value)
			local start_value = tonumber(start:formvalue(section))
			if end_value >= start_value then
				limit = end_value - start_value + 1
				m2:set(section, "limit", tostring(limit))
			end 
		end

		function _end.cfgvalue(self, section)
			local limit = m2:get(section, "limit")
			-- nixio.syslog("debug", "[fanwar]get limit="..limit)
			local start_value = m2:get(section, "start")
			-- nixio.syslog("debug", "[fanwar]get start="..start_value)
			if limit ~= nil and start_value ~= nil then
				local end_value = tonumber(start_value) + tonumber(limit) - 1
				return tostring(end_value)
			end
		end
		local IsError = 0
		function start.validate(self, value)
			local error_message
			local end_val = m2:formvalue("cbid.dhcp.lan._end")
			if isInteger(value) == false or isInteger(end_val) == false then
				error_message = "Start value and End value must be integer"
				IsError = 1
				return nil, error_message
			end
			local end_ip = tonumber(end_val)
			local start_ip = tonumber(value)
			if start_ip < 1 or start_ip > 254 then
				error_message = "Start value is invalid"
				IsError = 1
				return nil, error_message
			end
			if end_ip < 1 or end_ip > 254 then
				error_message = "End value is invalid"
				IsError = 1
				return nil, error_message
			end
			if start_ip >= end_ip then
				error_message = "Start value should be smaller than End value"
				IsError = 1
				return nil, error_message
			end
			return value
		end
		function _end.validate(self, value)
			if IsError == 1 then
				return nil, "Please input new value"
			else
				return value
			end
		end

		local ltime = s:option(Value, "leasetime", translate("Leasetime"),
			translate("Expiry time of leased addresses, minimum is 2 minutes (<code>2m</code>)."))
		ltime:value("2m")
		ltime:value("1h")
		ltime:value("1d")
			
		function ltime.validate(self, value, section)
			local ltime = string.match(value, "^%d*%d*%a?$")
			if ltime ~= nil then
				local num = string.match(ltime, "%d*%d*")
				num = tonumber(num)
				local unit = string.match(ltime, "%a")
				
				if(unit ~= nil and string.find(unit,"[sSmMhHdDwW]") ==  nil) then
					return nil, "Invalid time unit. Please enter one of following unit: s, m, h, d, w or leave blank"
				end
				if num == 0 then
					return nil, "Leasetime cannot be zero"
				end
				
				if (unit == nil or string.find(unit,"[sS]") ~= nil) and num <120 then
					return nil, "Leasetime must be greater than or equal to 120s"
				end
				if (string.find(unit,"[mM]") ~= nil) and num < 2 then
					return nil, "Leasetime must be greater than or equal to 2m"
				end
				
			else
				return nil, "Invalid leasetime format"
			end
		  return value
		end
		
		function ltime.write(self, section, value)
			if value and #value > 0 then
				m2:set(section, "leasetime", value)
			end
			return 1
		end
		local uci = require"luci.model.uci".cursor("/etc/config")
		local wan_dfroute = uci:get("network", "globals", "wan_df_route")
		local wan_prot = uci:get("network", wan_dfroute, "proto")
		local dnsv4_val = uci:get("dhcp","lan","dns_mode")
		local dnsv4 = s:option(ListValue, "dns_mode", translate("DNSv4 Mode"))
		dnsv4:value("Forwarder")
		dnsv4:value("Proxy")
		dnsv4:value("Static")
		
		function dnsv4.write(self, section, value)
			if value and #value > 0 then
				ut.perror_hieupt35("value"..value)
				if value == "Forwarder" then
					m2:set(section, "dns_mode", value)
					ut.perror_hieupt35("mode Forwarder")
				elseif value == "Proxy" then
					m2:set(section, "dns_mode", value)
					m2:del(section, "dhcp_option")
					ut.perror_hieupt35("mode Proxy and delete dhcp_option")

				elseif value == "Static" then
					m2:set(section, "dns_mode", value)
					ut.perror_hieupt35("mode Static")
				end
			end
			return 1
		end

		local custom_dns = s:option(DynamicList, "_custom_dns", translate("Use custom DNS servers"))
		custom_dns.nocreate = true
		custom_dns:depends("dns_mode","Static")
		custom_dns.datatype = "ipaddr"
		custom_dns.cast = "string"
		custom_dns.forcewrite = true
		custom_dns.rmempty = false
		
		function custom_dns.write(self, section, value)
			if value and #value > 0 then
				local dns_str = table.concat(value, ",")
				-- nixio.syslog("debug", "[fanwar] custom_dns = "..dns_str)
				m2:set(section, "_custom_dns", dns_str)
				m2:set(section, "dhcp_option", "6,"..dns_str)
			else
				if dnsv4_val == "Static" then
					m2:set(section, "_custom_dns", "")
					m2:del(section, "dhcp_option")
				end
				-- nixio.syslog("debug", "[fanwar]custom_dns: no value to write")
			end
			return 1
		end

		function custom_dns.cfgvalue(self, section)
			local dns_str = m2:get(section, "_custom_dns")
			local dns_tbl = {}
			if dns_str and #dns_str > 0 then
				dns_tbl = Split(dns_str, ",")
			end
			return dns_tbl
		end

		-- ut.perror_hieupt35("wan "..wan_prot)
		-- local dnsv6 = s:option(ListValue, "dnsv6_mode", translate("DNSv6 Mode"))
		
		-- if wan_prot == "dhcp" then
		-- 	dnsv6:value("Proxy")
		-- 	-- table.remove(dnsv6.keylist,1)
		-- 	-- table.remove(dnsv6.vallist,1)
		-- 	-- ut.print_table(dnsv6.keylist)
		-- 	-- ut.print_table(dnsv6.vallist)
		-- else
		-- 	dnsv6:value("Forwarder")
		-- 	dnsv6:value("Proxy")
		-- end
		-- -- ut.print_table(dnsv6.keylist)
		-- -- ut.print_table(dnsv6.vallist)
		-- function dnsv6.write(self, section, value)
		-- 	if value and #value > 0 then
		-- 		if wan_prot == "pppoe" then
		-- 			if value == "Forwarder" then
		-- 				m2:set(section, "dnsv6_mode", value)
		-- 			elseif value == "Proxy" then
		-- 				m2:set(section, "dnsv6_mode", value)
		-- 				m2:del(section, "dns")
		-- 			end
		-- 		elseif wan_prot == "dhcp" then
		-- 			if value == "Proxy" then
		-- 				m2:set(section, "dnsv6_mode", value)
		-- 				m2:del(section, "dns")
		-- 			end
		-- 		end
		-- 	end
		-- 	return 1
		-- end

        for i, n in ipairs(s.children) do
			if n ~= enable_dhcp and n~= custom_dns then
				n:depends("ignore", "1")
			end
		end


        s_static_list = m2:section(TypedSection, "host", translate("Static Leases"))

        s_static_list.addremove = true
        s_static_list.anonymous = true
        s_static_list.template = "cbi/tblsection"

        name = s_static_list:option(Value, "name", translate("Hostname"))
        name.datatype = "hostname"
        name.rmempty  = true

        mac = s_static_list:option(Value, "mac", translate("<abbr title=\"Media Access Control\">MAC</abbr>-Address"))
        mac.datatype = "list(macaddr)"
        mac.rmempty  = true

        ip =s_static_list:option(Value, "ip", translate("<abbr title=\"Internet Protocol Version 4\">IPv4</abbr>-Address"))
        ip.datatype = "or(ip4addr,'ignore')"

        -- hostid = s_static_list:option(Value, "hostid", translate("<abbr title=\"Internet Protocol Version 6\">IPv6</abbr>-Suffix (hex)"))

        ipc.neighbors({ family = 4 }, function(n)
            if n.mac and n.dest then
                ip:value(n.dest:string())
                mac:value(n.mac, "%s (%s)" %{ n.mac, n.dest:string() })
            end
        end)

        function ip.validate(self, value, section)
            local m = mac:formvalue(section) or ""
            local n = name:formvalue(section) or ""
            if value and #n == 0 and #m == 0 then
                return nil, translate("One of hostname or mac address must be specified!")
            end
            return Value.validate(self, value, section)
        end

	else
		m2 = nil
	end
end

return m, m2