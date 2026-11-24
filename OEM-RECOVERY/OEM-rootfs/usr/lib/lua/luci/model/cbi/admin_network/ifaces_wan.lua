local fs = require "nixio.fs"
local ut = require "luci.util"
local pt = require "luci.tools.proto"
local nw = require "luci.model.network"
local fw = require "luci.model.firewall"
local ip = require "luci.ip"
require("luci.http")


m = Map("network", translate("WAN Interface Configuration"), translate("<br>"))
m.redirect = luci.dispatcher.build_url("admin/network/network")
m:chain("wireless")
arg[1] = arg[1] or ""

local param = m.param

nw.init(m.uci)
fw.init(m.uci)

local net
local net6

net = nw:get_network(arg[1])
net6 = nw:get_network(arg[1].."_ip6")

-- redirect to overview page if network does not exist anymore (e.g. after a revert)
if not net then
    luci.http.redirect(luci.dispatcher.build_url("admin/status/overview"))
    return
end
local ifc = net:get_interface()
local deps_type_route = {}
local deps_type_bridge = {}
local deps_prot_dhcp = {}
local deps_prot_pppoe = {}
local deps_prot_static = {}
local deps_enable_ipv6 = {}
deps_type_route["opt"] = "type"
deps_type_route["val"] = ""
deps_type_bridge["opt"] = "type"
deps_type_bridge["val"] = "bridge"
deps_prot_dhcp["opt"] = "proto"
deps_prot_dhcp["val"] = "dhcp"
deps_prot_pppoe["opt"] = "proto"
deps_prot_pppoe["val"] = "pppoe"
deps_prot_static["opt"] = "proto"
deps_prot_static["val"] = "static"
deps_enable_ipv6["opt"] = "ipv6"
deps_enable_ipv6["val"] = "1"

function is_same_subnet(ip1, ip2, netmask)
    local range = luci.ip.new(ip1.."/"..netmask)
    return range:contains(ip2) 
end

if m:formvalue("cbi.apply") then
    for k, v in pairs(m:get(net:name())) do
        if k:sub(1, 1) ~= "." and k ~= "type" and k ~= "ifname" and k ~= "_conn_name" and
            k ~= "_service" and k ~= "_vlanid" and k~= "defaultroute" then
            m:del(net:name(), k)
        end
    end
    if net6 ~= nil then
        for k, v in pairs(m:get(net6:name())) do
            if k:sub(1, 1) ~= "." and k ~= "type" and k ~= "ifname" and k ~= "reqaddress"
            and k ~= "reqprefix" and k ~= "_vlanid" and k~= "defaultroute" then
            m:del(net6:name(), k)
            end
        end
    end
    m.uci:save("network")
    m.uci:save("wireless")
end

s = m:section(NamedSection, arg[1], "interface", translate(""))
s.addremove = false

conn_name = s:option(Value, "_conn_name", translate("Connection Name"))

conn_type = s:option(ListValue, "type", translate("Type"))
conn_type:value("", "Route")
conn_type:value("bridge", "Bridge")
conn_type.rmempty = true
conn_type.forcewrite = true

-- function conn_type.write(self, section, value)
--     local lan_if = m:get("lan", "ifname")
--     local vlanid = conn_vlan:formvalue(section)
--     local new_if = "eth1"
--     if vlanid and #vlanid > 0 then
--         new_if = new_if.."."..vlanid
--     end
--     m:set(section, "type", value)
--     if value == "bridge" then
--         nixio.syslog("debug", "[fanwar] conn_type: vlanid="..vlanid)
--         if lan_if and #lan_if > 0 then
--             new_if = new_if..lan_if
--         end
--     end
--     m:set(section, "ifname", new_if)
-- end

conn_serv = s:option(ListValue, "_service", translate("Service"))
conn_serv:value("_internet", "INTERNET")
conn_serv:value("_iptv", "IPTV")
-- AP-409
function write_mac(str)
    local ret = ""
    
    local macaddr = luci.util.exec("cat /sys/class/net/eth1/address")
	macaddr=luci.util.trim(macaddr)
    local tailmac = tonumber(macaddr:sub(16,17),16) + tonumber(str:sub(4))
    ret=string.format("%02x",tailmac > 255 and (tailmac - 255) or tailmac)
    ret=string.gsub(macaddr,macaddr:sub(16,17),ret)
    return ret 
end
--
conn_vlan = s:option(Value, "_vlanid", translate("VLAN ID"))
conn_vlan.forcewrite = true
conn_vlan.datatype = "uinteger"

function conn_vlan.formvalue(self, section)
	local tmp = self.map:formvalue(self:cbid(section))
    if tmp and #tmp > 0 then
        return tmp
    else
        return "0"
    end
end

function conn_vlan.write(self, section, value)
    if value == nil then
        nixio.syslog("debug", "[fanwar] write vlan=nil")
        m:del(section, "_vlanid")
    else    
        nixio.syslog("debug", "[fanwar] write vlan="..value)
        m:set(section, "_vlanid", value)
    end
    if value == "0" then
        value = ""
    end
    local ifname_list = {} 
    local cur_ifname = m:get(section, "ifname")

    if cur_ifname:find(" ") ~= nil then
        for word in string.gmatch(cur_ifname, "%S+") do
            ifname_list[#ifname_list+1] = word
        end
    end
    if value and #value > 0 then
        ifname_list[1] = "eth1."..value
    else
        ifname_list[1] = "eth1"
    end
    local new_ifname = ifname_list[1]
    m:set(section.."_ip6", "ifname", new_ifname)
    -- TO DO: Rewrite this block when port binding is available
    if conn_type:formvalue(section) == "bridge" then
        if #ifname_list > 1 then
            for i=2,#ifname_list do
                new_ifname = new_ifname.." "..ifname_list[i]
            end
        end
    end
    nixio.syslog("debug", "[fanwar] ifname before write="..new_ifname)
    m:set(section, "ifname", new_ifname)
    -- AP-409
    local wanstr = section
    if tonumber(wanstr:sub(4)) > 0 then
        m:set(section, "macaddr", write_mac(wanstr))
    end 
    --
end
function conn_vlan.cfgvalue(self, section)
    -- local ifname_list = {}
    -- local cur_ifname = m:get(section, "ifname")
    -- if cur_ifname:find(" ") ~= nil then
    --     for word in string.gmatch(cur_ifname, "%S+") do
    --         ifname_list[#ifname_list+1] = word
    --         -- nixio.syslog("debug", "[fanwar] ifname="..ifname_list[1])
    --     end
    -- else 
    --     ifname_list[1] = cur_ifname
    -- end

    -- local orig_if, vlan_num = ifname_list[1]:match("([^.]*).(.*)")
    -- -- if vlan_num and #vlan_num > 0 then
    -- --     nixio.syslog("debug", "[fanwar] read vlan cfgvalue="..vlan_num)
    -- -- else 
    -- --     nixio.syslog("debug", "[fanwar] read vlan cfgvalue=nil")
    -- -- end
    local tmp = m:get(section, "_vlanid")
    if tmp and #tmp > 0 then
        if tmp ~= "0" then
            return tmp
        end
    end
    return ""
end

function conn_vlan.validate(self, value)
    if value and #value > 0 then
        for _, lnet in ipairs(nw:get_networks()) do
            if lnet:name() ~= net:name() and lnet:name():find("wan") ~= nil then
                local tmp_vlan = m:get(lnet:name(), "_vlanid")
                if tmp_vlan and #tmp_vlan > 0 then
                    if tmp_vlan == value then
                        return nil, "Duplicated VLAN ID, please select a new one"
                    end
                end
            end
        end
        return value
    else
        return ""
    end
end


p = s:option(ListValue, "proto", translate("Protocol"))
p.default = net:proto()
p.forcewrite = true
p:value("pppoe", "PPPoE")
p:value("dhcp", "DHCP Client")
p:value("static", "Static IP")
-- p:depends("type", "")
table.insert(deps_type_route, p)
function p.write(self, section, value)
    if value and #value > 0 then
        m:set(section, "proto", value)
        if value == "static" then
            m:set(section.."_ip6", "proto", "static")
        elseif value == "pppoe" or value == "dhcp" then
            m:set(section.."_ip6", "proto", "dhcpv6")
        end
    else
        m:del(section, "proto")
        m:del(section.."_ip6", "proto")
    end
end

function if_lanport_binded(iface)
	local lnet
	for _, lnet in ipairs(nw:get_networks()) do
		if lnet:name() ~= net:name() and lnet:name():find("wan") ~= nil  and lnet:name():find("_ip6") == nil then
			if lnet:type() == "bridge" then
				local bind = m:get(lnet:name(), "binding")
				if bind ~= nil and bind:find(iface) ~= nil then
					return true
				end
			end
		end
	end
	
	return false
end
conn_binding = s:option(MultiValue, "binding", translate("Port binding"))
conn_binding.default = ""
-- conn_binding:depends("type","bridge")
conn_binding:value("eth0.1", "LAN1", if_lanport_binded("eth0.1"))
conn_binding:value("eth0.2", "LAN2", if_lanport_binded("eth0.2"))
conn_binding.forcewrite = true
table.insert(deps_type_bridge, conn_binding)


function conn_binding.write(self, section, value)
	if value == nil then
        nixio.syslog("debug", "[huhu] write binding=nil")
    else    
        nixio.syslog("debug", "[huhu] write binding="..value)
    end
    local ifname_list = {} 
    local cur_ifname = m:get(section, "ifname")
	local binding_list = {} 

	-- get first ifname as wan ifname
	for word in string.gmatch(cur_ifname, "%S+") do
		ifname_list[#ifname_list+1] = word
	end
	
    if conn_type:formvalue(section) == "bridge" then
		local new_ifname = ifname_list[1]
		local lanports
	-- append the lan interfaces
		if value ~= nil then
			new_ifname = new_ifname.." "..value
		end
		new_ifname = new_ifname:trim()
		m:set(section, "ifname", new_ifname)
	-- remove binding ports from br-lan
		lanports = m:get("lan", "ifname")
		
		if lanports == nil then
			lanports = ""
		end	
		
		if value ~= nil then
			for word in string.gmatch(value, "%S+") do
				lanports = lanports:gsub(word, "")
			end
			lanports = lanports:trim()
			m:set("lan", "ifname", lanports)
		end
		
		m:set(net:name(), "binding", value)
	-- release ports to lan if no one uses
		if (not if_lanport_binded("eth0.1")) and (value:find("eth0.1") == nil) then
			if lanports:find("eth0.1") == nil then
				lanports = lanports.." eth0.1"
			end
		end
		if (not if_lanport_binded("eth0.2")) and (value:find("eth0.2") == nil) then
			if lanports:find("eth0.2") == nil then
				lanports = lanports.." eth0.2"
			end
		end
		lanports = lanports:trim()
		m:set("lan", "ifname", lanports)
	end
	
end

conn_def_route = s:option(Flag, "defaultroute", translate("Enable default route"))
conn_def_route.rmempty = false
-- conn_def_route:depends("type", "")
table.insert(deps_type_route, conn_def_route)
function conn_def_route.write(self, section, value)
    if value and #value > 0 then
        if value == "1" then
            
            m:set("globals", "wan_df_route", section)
            ut.exec("uci delete firewall.zone_wan_df_route.network")
            ut.exec("uci add_list firewall.zone_wan_df_route.network=".."\'"..section.."\'")
            ut.exec("uci add_list firewall.zone_wan_df_route.network=".."\'"..section.."_ip6".."\'")
            ut.exec("uci commit firewall")
            ut.exec("/etc/init.d/firewall reload")

            for _, lnet in ipairs(nw:get_networks()) do
                if lnet:name() == section or lnet:name() == section.."_ip6" then
                    m:set(lnet:name(), "defaultroute", "1")
                else
                    m:set(lnet:name(), "defaultroute", "0")
                end
            end
        else
            m:set(section, "defaultroute", "0")
            m:set(section.."_ip6", "defaultroute", "0")
        end
    else
        nixio.syslog("debug", "[fanwar] conn_def_route write invalid value")
    end
end

conn_ip6_enable = s:option(Flag, "ipv6", translate("Enable IPv6"))
conn_ip6_enable.rmempty = false
table.insert(deps_type_route, conn_ip6_enable)
function conn_ip6_enable.write(self, section, value)
    if value and #value > 0 then
        if value == "1" then
            m:set(section, "ipv6", "auto")
        else
            m:set(section, "ipv6", "0")
        end
    else 
        nixio.syslog("debug", "[fanwar] conn_ip6_enable write invalid value")
    end
end
function conn_ip6_enable.cfgvalue(self, section)
    local value = m:get(section, "ipv6")
    if value and #value > 0 then
        if value == "auto" then
            return "1"
        elseif value == "0" then
            return "0"
        end
    else 
        return "1"
    end
end

---------------------------------------------------------------------
----------------------This block for PPPoE Config--------------------
------all config in this block depends on {proto:"pppoe"}------------
ds_pppoe = s:option(DummyValue, "_dummy_pppoe", translate("PPPoE Config"))
username = s:option(Value, "username", translate("PAP/CHAP username"))
password = s:option(Value, "password", translate("PAP/CHAP password"))
password.password = true
table.insert(deps_prot_pppoe, ds_pppoe)
table.insert(deps_prot_pppoe, username)
table.insert(deps_prot_pppoe, password)
---------------------------------------------------------------------
---------------------------------------------------------------------

---------------------------------------------------------------------
----------------------This block for DHCP Config--------------------
------all config in this block depends on {proto:"dhcp"}------------

---------------------------------------------------------------------
---------------------------------------------------------------------

---------------------------------------------------------------------
----------------This block for Static IPv4 Config--------------------
------all config in this block depends on {proto:"static"}-----------
ds_ip4 = s:option(DummyValue, "_dummy_IPv4", translate("Static IPv4 Config"))

ipaddr = s:option(Value, "ipaddr", translate("IPv4 address"))
ipaddr.datatype = "ip4addr"

netmask = s:option(Value, "netmask", translate("IPv4 netmask"))
netmask.datatype = "ip4addr"
netmask:value("255.255.255.0")
netmask:value("255.255.0.0")
netmask:value("255.0.0.0")

dns = s:option(DynamicList, "dns", translate("Use custom DNS servers"))
dns.datatype = "ipaddr"
dns.cast = "string"

gateway = s:option(Value, "gateway", translate("IPv4 gateway"))
gateway.datatype = "ip4addr"

function gateway.validate(self, value, section)
    local ipv4_addr = ipaddr:formvalue(section)
    local netmask = netmask:formvalue(section)
    if value and #value > 0 then
        if ipv4_addr and #ipv4_addr > 0 and netmask and #netmask > 0 then
            if is_same_subnet(ipv4_addr, value, netmask) then
                return value
            else
                return nil, "IPv4 gateway and IPv4 address are not in the same subnet"
            end
        end
    else
        return nil, "IPv4 gateway is empty, please config again"
    end
end

table.insert(deps_prot_static, ds_ip4)
table.insert(deps_prot_static, ipaddr)
table.insert(deps_prot_static, netmask)
table.insert(deps_prot_static, dns)
table.insert(deps_prot_static, gateway)
---------------------------------------------------------------------
---------------------------------------------------------------------

---------------------------------------------------------------------
----------------------This block for IPv6 Auto Config--------------------
------all config in this block depends on {proto:"dhcp", proto:"pppoe", ipv6:conn_ip6_enable.enabled}------------
ds_ip6 = s:option(DummyValue, "_dummy_IPv6", translate("IPv6 Config"))

ip6_acquire = s:option(ListValue, "reqaddress", translate("IPv6 acquire mode"))
ip6_acquire:value("try", "DHCPv6")
ip6_acquire:value("none", "SLAAC")
function ip6_acquire.cfgvalue(self, section)
    local value = m:get(net:name().."_ip6", "reqaddress")
    if value == nil or value == "try" then
        return "try"
    elseif value == "none" then
        return "none"
    end
end
function ip6_acquire.write(self, section, value)
    if value and #value > 0 then
        return m:set(net:name().."_ip6", "reqaddress", value)
    end
end

ip6_req_pd = s:option(Flag, "reqprefix", translate("Request PD"))
ip6_req_pd.rmempty = false
ip6_req_pd.forcewrite = true
function ip6_req_pd.cfgvalue(self, section)
    local value = m:get(net:name().."_ip6", "reqprefix")
    if value and #value > 0 then
        if value == "auto" then
            return "1"
        else
            return "0"
        end
    end
end
function ip6_req_pd.write(self, section, value)
    if value == "1" then
        m:set(net:name().."_ip6", "reqprefix", "auto")
    elseif value == "0" then
        nixio.syslog("debug", "[fanwar] write reqprefix = no")
        m:set(net:name().."_ip6", "reqprefix", "no")
    else
        nixio.syslog("debug", "[fanwar][error] ip6_req_pd write invalid value")
    end
end
table.insert(deps_prot_dhcp, ds_ip6)
table.insert(deps_prot_dhcp, ip6_acquire)
table.insert(deps_prot_dhcp, ip6_req_pd)
table.insert(deps_prot_pppoe, ds_ip6)
table.insert(deps_prot_pppoe, ip6_acquire)
table.insert(deps_prot_pppoe, ip6_req_pd)
table.insert(deps_enable_ipv6, ds_ip6)
table.insert(deps_enable_ipv6, ip6_acquire)
table.insert(deps_enable_ipv6, ip6_req_pd)
---------------------------------------------------------------------
---------------------------------------------------------------------

---------------------------------------------------------------------
----------------------This block for IPv6 Static Config--------------------
------all config in this block depends on {proto:"static", ipv6:conn_ip6_enable.enabled}------------
ds_ip6_static = s:option(DummyValue, "_dummy_IPv6_static", translate("Static IPv6 Config"))

ip6_addr = s:option(Value, "ip6addr", translate("IPv6 address"))
ip6_addr.datatype = "ip6addr"

ip6_gw = s:option(Value, "ip6gw", translate("IPv6 gateway"))
ip6_gw.datatype = "ip6addr"

ip6_prefix = s:option(Value, "ip6prefix",translate("IPv6 routed prefix"))
ip6_prefix.datatype = "ip6addr"

ip6_dns = s:option(DynamicList, "_dns6", translate("Use custom DNS servers"))
ip6_dns.datatype = "ip6addr"
ip6_dns.cast = "string"
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
table.insert(deps_prot_static, ds_ip6_static)
table.insert(deps_prot_static, ip6_addr)
table.insert(deps_prot_static, ip6_gw)
table.insert(deps_prot_static, ip6_prefix)
table.insert(deps_prot_static, ip6_dns)
table.insert(deps_enable_ipv6, ds_ip6_static)
table.insert(deps_enable_ipv6, ip6_addr)
table.insert(deps_enable_ipv6, ip6_gw)
table.insert(deps_enable_ipv6, ip6_prefix)
table.insert(deps_enable_ipv6, ip6_dns)
---------------------------------------------------------------------
---------------------------------------------------------------------


---------------------------------------------------------------------
----------------------This block assigns all dependencies--------------------
function create_new_dep(dep, key, value)
    local new_dep = {}
    for k,v in pairs(dep.deps) do
        new_dep[k] = v
    end
    new_dep[key] = value
    return new_dep
end

local all_deps_tbl = {}
local tmp_tbl = {}
table.insert(all_deps_tbl, deps_type_bridge)
table.insert(all_deps_tbl, deps_type_route)
table.insert(all_deps_tbl, deps_prot_dhcp)
table.insert(all_deps_tbl, deps_prot_pppoe)
table.insert(all_deps_tbl, deps_prot_static)
table.insert(all_deps_tbl, deps_enable_ipv6)
for _,tbl in pairs(all_deps_tbl) do
    for k,opt in pairs(tbl) do
        if k~= "opt" and k~= "val" then
            if next(opt.deps) then
                local _, dep
                local len = #opt.deps
                local count = 0
                for _, dep in ipairs(opt.deps) do
                    if count == len then
                        break
                    end
                    if dep.deps[tbl["opt"]] == nil then
                        dep.deps[tbl["opt"]] = tbl["val"]
                    else
                        local new_dep = {}
                        new_dep = create_new_dep(dep, tbl["opt"], tbl["val"])
                        opt:depends(new_dep)
                    end
                    count = count + 1
                end
            else
                opt:depends(tbl["opt"], tbl["val"])
            end
        end
    end
end
---------------------------------------------------------------------
---------------------------------------------------------------------
return m, m2
