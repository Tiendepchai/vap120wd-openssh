-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.network", package.seeall)

function index()
	local uci = require("luci.model.uci").cursor()
	local page

	page = node("admin", "network")
	page.target = firstchild()
	page.title  = _("Network")
	page.order  = 30
	page.index  = true

		page = entry({"admin", "network", "lan_apply"}, call("handle_apply_lan"))
		page.leaf = true
		page = entry({"admin", "network", "lan_cfg_static_lease"}, call("cfg_static_lease"))
		page.leaf = true
		page = entry({"admin", "network", "wan_apply"}, call("wan_apply"), nil)
		page.leaf = true
		page = entry({"admin", "network", "wan_cfg"}, call("wan_cfg"), nil)
		page.leaf = true
		page = entry({"admin", "network", "ifc_uci_cfg"}, call("ifc_uci_cfg"), nil)
		page.leaf = true


		page = entry({"admin", "network", "iface_add"}, call("iface_add"), nil)
		page.leaf = true

		page = entry({"admin", "network", "iface_delete"}, call("iface_delete"), nil)
		page.leaf = true

		page = entry({"admin", "network", "iface_status"}, call("iface_status"), nil)
		page.leaf = true

		page = entry({"admin", "network", "iface_reconnect"}, call("iface_reconnect"), nil)
		page.leaf = true

		page = entry({"admin", "network", "iface_shutdown"}, call("iface_shutdown"), nil)
		page.leaf = true

		-- page = entry({"admin", "network", "network"}, arcombine(cbi("admin_network/network"), cbi("admin_network/ifaces_wan")), nil)
		-- page.leaf   = true
		-- page = entry({"admin", "network", "network"}, template("admin_network/config_wan"), nil)
		-- page.leaf   = true
		
		-- page.subindex = true
		-- page = entry({"admin", "network", "lanold"}, cbi("admin_network/ifaces_lan"), nil, nil)
		-- page.leaf = true
		page = entry({"admin", "network", "lan"}, template("admin_network/config_lan"), _"LAN Configuration", 1)
		page.leaf = true
		-- page = entry({"admin", "network", "wan"}, cbi("admin_network/ifaces_wan"), _"WAN", 2)
		-- page = entry({"admin", "network", "wan"}, cbi("admin_network/network"), _"WAN Configuration", 2)
		page = entry({"admin", "network", "wan"}, cbi("admin_network/network"), _"WAN Configuration", 2)
		page.leaf = true
		-- page = entry({"admin", "network", "wan6"}, cbi("admin_network/ifaces_wan6"), _"WAN6", 2)
		-- page.leaf = true
end


function iface_status(ifaces)
	local netm = require "luci.model.network".init()
	local uci = require("luci.model.uci").cursor()
	local util = require "luci.util"
	local portst_str = util.exec("ethstt")
	local portwanst = string.match(portst_str, "port 2 (.*)\nport 3")
	local rv   = { }

	local iface
	for iface in ifaces:gmatch("[%w%.%-_]+") do
		local net = netm:get_network(iface)
		local prot = netm.protocol(iface)
		local device = net and net:get_interface()
		if device then
			local data = {
				id         = iface,
				proto      = net:proto(),
				uptime     = net:uptime(),
				gwaddr     = net:gwaddr(),
				dnsaddrs   = net:dnsaddrs(),
				name       = device:shortname(),
				type       = device:type(),
				ifname     = device:name(),
				macaddr    = device:mac(),
				l3_status  = prot:_ubus("up"),
				portst 	   = portwanst == "up" and true or false,
				rx_bytes   = device:rx_bytes(),
				tx_bytes   = device:tx_bytes(),
				rx_packets = device:rx_packets(),
				tx_packets = device:tx_packets(),
				dfroute	   = uci:get("network", iface, "defaultroute") == "1" and "1" or "0",
				
				ipaddrs    = { },
				ip6addrs   = { },
				subdevices = { }
			}

			local _, a
			for _, a in ipairs(device:ipaddrs()) do
				data.ipaddrs[#data.ipaddrs+1] = {
					addr      = a:host():string(),
					netmask   = a:mask():string(),
					prefix    = a:prefix()
				}
			end
			for _, a in ipairs(device:ip6addrs()) do
				if not a:is6linklocal() then
					data.ip6addrs[#data.ip6addrs+1] = {
						addr      = a:host():string(),
						netmask   = a:mask():string(),
						prefix    = a:prefix()
					}
				end
			end

			for _, device in ipairs(net:get_interfaces() or {}) do
				data.subdevices[#data.subdevices+1] = {
					name       = device:shortname(),
					type       = device:type(),
					ifname     = device:name(),
					macaddr    = device:mac(),
					is_up      = device:is_up(),
					rx_bytes   = device:rx_bytes(),
					tx_bytes   = device:tx_bytes(),
					rx_packets = device:rx_packets(),
					tx_packets = device:tx_packets(),
				}
			end

			rv[#rv+1] = data
		else
			rv[#rv+1] = {
				id   = iface,
				name = iface,
				type = "ethernet"
			}
		end
	end

	if #rv > 0 then
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
		return
	end

	luci.http.status(404, "No such device")
end

function iface_reconnect(iface)
	local netmd = require "luci.model.network".init()
	local net = netmd:get_network(iface)
	if net then
		luci.sys.call("env -i /sbin/ifup %q >/dev/null 2>/dev/null" % iface)
		luci.http.status(200, "Reconnected")
		return
	end

	luci.http.status(404, "No such interface")
end

function iface_shutdown(iface)
	local netmd = require "luci.model.network".init()
	local net = netmd:get_network(iface)
	if net then
		luci.sys.call("env -i /sbin/ifdown %q >/dev/null 2>/dev/null" % iface)
		luci.http.status(200, "Shutdown")
		return
	end

	luci.http.status(404, "No such interface")
end

function iface_delete(iface)
	local uci
	uci = luci.model.uci.cursor()
	local need_network_reload = false
	local iface_type = uci:get("network", iface, "type") or "route"
	local netmd = require "luci.model.network".init()
	local net = netmd:get_network(iface)
	if not net then
		luci.http.status(404, "No such interface")
		return
	end
	
	if iface_type == "bridge" then
		local bind = uci:get("network", iface,"binding")
		if bind ~= nil then
			local lanports = uci:get("network", "lan", "ifname")
			if lanports ~= nil then
				lanports = lanports.." "..bind
			else
				lanports = bind
			end
			uci:set("network", "lan", "ifname", lanports)
			uci:commit("network")
			need_network_reload = true
		end
	end

	netmd:del_network(iface)
	if iface_type == "route" then
		netmd:del_network(iface.."_ip6")
	end
	luci.sys.call("env -i /sbin/ifdown %q >/dev/null 2>/dev/null" % iface)
	luci.http.redirect(luci.dispatcher.build_url("admin/network/wan"))
	netmd:commit("network")
	netmd:commit("wireless")
	if need_network_reload then
		luci.sys.call("env -i /etc/init.d/network reload >/dev/null 2>&1")
	end
	return
end

function iface_add(type)
	local ntm = require "luci.model.network".init()
	local uci = require("luci.model.uci").cursor()
	local netname_list = {}
	for _, net in ipairs(ntm:get_networks()) do
		netname_list[net:name()] = 1
	end
	for i = 1, 10 do
		if netname_list["wan"..i] == nil then
			uci:section("network", "interface", "wan"..i, {})
			if type == "route" then
				uci:section("network", "interface", "wan"..i.."_ip6", {})
			end
			uci:commit("network")
			return "wan"..i
		end
	end
end

function do_add_interface(iface)
	local uci = require("luci.model.uci").cursor()
	local default_ops = 
	{
		ifname = "eth1",
		proto = "dhcp",
		binding = "",
		-- type = "bridge",
		defaultroute = "0",
		_conn_name = "VIETTEL_",
		_vlanid = "0",
		_applied = "0"
	}
	local default_ops_v6 =
	{
		ifname = "eth1",
		proto = "dhcpv6",
		defaultroute = "0",
		reqaddress = "none",
		reqprefix = "no"
	}
	uci:section("network", "interface", iface, default_ops)
	uci:section("network", "interface", iface.."_ip6", default_ops_v6)
	uci:commit("network")
	luci.http.redirect(luci.dispatcher.build_url("admin/network/network", iface))
end

function wan_cfg(iface)
	local util = require "luci.util"
	util.perror("[fanwar] render for "..iface)
	luci.template.render(
		"admin_network/config_wan", 
		{
			iface = iface
		}
	)
end

function update_binding(iface, cfgs, uci)
	local group_binding = ""
	local cur_binding = uci:get("network", iface, "binding") or ""
	local lanports = {0, 0}
	local lan_ifname = uci:get("network", "lan", "ifname") or ""

	for port in lan_ifname:gmatch("%S+") do
		if port == "eth0.1" then
			lanports[1] = 1
		end
		if port == "eth0.2" then
			lanports[2] = 1
		end
	end
	if cfgs["conn_binding_1"] == "on" then
		group_binding = #group_binding > 0 and group_binding.." eth0.1" or group_binding.."eth0.1"
		lanports[1] = 0
	else
		if string.find(cur_binding, "eth0.1") ~= nil then
			lanports[1] = 1
		end
	end
	if cfgs["conn_binding_2"] == "on" then
		group_binding = #group_binding > 0 and group_binding.." eth0.2" or group_binding.."eth0.2"
		lanports[2] = 0
	else
		if string.find(cur_binding, "eth0.2") ~= nil then
			lanports[2] = 1
		end
	end
	lan_ifname = lanports[1] == 1 and "eth0.1" or ""
	if lanports[2] == 1 then
		if #lan_ifname > 0 then
			lan_ifname = lan_ifname.." eth0.2"
		else
			lan_ifname = "eth0.2"
		end
	end
	
	uci:set("network", "lan", "ifname", lan_ifname)

	return group_binding
end

function create_ifname(cfgs, bridge_members)
	local main_ifname = #cfgs["conn_vlan"] > 0 and "eth1."..cfgs["conn_vlan"] or "eth1"
	if bridge_members and #bridge_members > 0 then
		main_ifname = main_ifname.." "..bridge_members
	end
	return main_ifname
end

function create_macaddr(iface)
	local ret = ""
    
    local macaddr = luci.util.exec("cat /sys/class/net/eth1/address")
	macaddr=luci.util.trim(macaddr)
    local tailmac = tonumber(macaddr:sub(16,17),16) + tonumber(iface:sub(4))
    ret=string.format("%02x",tailmac > 255 and (tailmac - 255) or tailmac)
    ret=string.gsub(macaddr,macaddr:sub(16,17),ret)
    return ret 
end

function update_defroute(iface, cur_defroute, defroute, uci)
	if iface ~= cur_defroute then
		if defroute == "1" then
			uci:set("network", cur_defroute, "defaultroute", "0")
			uci:set("network", cur_defroute.."_ip6", "defaultroute", "0")
			uci:set("network", "globals", "wan_df_route", iface)
			uci:delete("firewall", "zone_wan_df_route", "network")
			uci:set_list("firewall", "zone_wan_df_route", "network", {iface, iface.."_ip6"})
			uci:commit("firewall")
		end
	end
end

function clear_nwcfgs(iface, uci)
	local util = require "luci.util"
	util.perror("[fanwar] clear_nwcfgs "..iface)
	util.perror("[fanwar] xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	local tbl = uci:get_all("network", iface)
	-- util.dumptable(tbl, nil, nil, nil)
	if tbl ~= nil then
		for k,v in pairs(tbl) do
			if k:sub(1, 1) ~= "." and k ~= "macaddr" then
				util.perror("[fanwar] clear "..k)
				uci:delete("network", iface, k)
			end
		end
		util.perror("[fanwar] xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	end
end

function wan_set_bridge_cfg(iface, cfgs)
	local uci = require("luci.model.uci").cursor()
	local group_binding = update_binding(iface, cfgs, uci)
	local bridge_params = 
	{
		ifname = create_ifname(cfgs, group_binding),
		binding = group_binding,
		type = "bridge",
		_conn_name = cfgs["conn_name"],
		_vlanid = #cfgs["conn_vlan"] > 0 and cfgs["conn_vlan"] or "0",
		_service = cfgs["conn_serv"]
	}
	if iface ~= "wan0" then
		bridge_params["macaddr"] = create_macaddr(iface)
	end
	clear_nwcfgs(iface, uci)
	uci:tset("network", iface, bridge_params)
	uci:delete("network", iface.."_ip6")
	uci:commit("network")
end

function wan_set_route_cfg(iface, cfgs)
	local uci = require("luci.model.uci").cursor()
	local defroute = cfgs["conn_defroute"] and "1" or "0"
	local cur_defroute_if = uci:get("network", "globals", "wan_df_route")
	local route4_params = 
	{
		ifname = create_ifname(cfgs),
		proto = cfgs["conn_proto"],
		defaultroute = defroute,
		_vlanid = #cfgs["conn_vlan"] > 0 and cfgs["conn_vlan"] or "0",
		ipv6 = cfgs["conn_ip6"] and "auto" or "0",
		_conn_name = cfgs["conn_name"],
		_service = cfgs["conn_serv"]
	}
	local route6_params = 
	{
		ifname = "@"..iface,
		proto = cfgs["conn_proto"] == "static" and "static" or "dhcpv6",
		defaultroute = route4_params["defaultroute"]
	}
	if cfgs["conn_proto"] == "static" then
		route4_params["ipaddr"] = cfgs["static_ipv4_addr"]
		route4_params["netmask"] = cfgs["static_ipv4_mask"]
		route4_params["dns"] = cfgs["static_ipv4_dns"]
		route4_params["gateway"] = cfgs["static_ipv4_gw"]

		route6_params["ip6addr"] = cfgs["static_ipv6_ip6addr"]
		route6_params["ip6prefix"] = cfgs["static_ipv6_ip6prefix"]
		route6_params["dns"] = cfgs["static_ipv6_dns6"]
		route6_params["ip6gw"] = cfgs["static_ipv6_ip6gw"]
	else
		route6_params["reqprefix"] = cfgs["auto_ipv6_reqprefix"] and "auto" or "no"
		route6_params["reqaddress"] = cfgs["auto_ipv6_reqaddress"]
		if cfgs["conn_proto"] == "pppoe" then
			route4_params["username"] = cfgs["pppoe_usrname"]
			route4_params["password"] = cfgs["pppoe_pwd"]
		end
	end
	if iface ~= "wan0" then
		route4_params["macaddr"] = create_macaddr(iface)
	end
	update_binding(iface, cfgs, uci)
	update_defroute(iface, cur_defroute_if, defroute, uci)
	clear_nwcfgs(iface, uci)
	clear_nwcfgs(iface.."_ip6", uci)
	uci:tset("network", iface, route4_params)
	-- AP-570: Work around for multi odhcp6c problem
	-- IPv6 setting of dhcp and pppoe wan will be hard-coded
	if cfgs["conn_proto"] == "pppoe" then
		local pppoe_ip6_params = 
		{
			ifname = "@"..iface,
			proto = "dhcpv6",
			defaultroute = route4_params["defaultroute"]
		}
		uci:tset("network", iface.."_ip6", pppoe_ip6_params)
	elseif cfgs["conn_proto"] == "dhcp" then
		local dhcp_ip6_params = 
		{
			ifname = route4_params["_vlanid"] == "0" and "eth1" or "eth1."..route4_params["_vlanid"],
			proto = "dhcpv6",
			reqprefix = "auto",
			reqaddress = "none", 
			defaultroute = route4_params["defaultroute"]
		}
		uci:tset("network", iface.."_ip6", dhcp_ip6_params)
	else
		uci:tset("network", iface.."_ip6", route6_params)
	end
	uci:commit("network")
end

function fork_exec(command)
	local pid = nixio.fork()
	if pid > 0 then
		return
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end

function wan_apply(iface)
	local http = require("luci.http")
	local util = require "luci.util"
	local cfgs = {}
	local configlist = {"network", "firewall"}
	local reload_cmd = "/sbin/luci-reload"

	util.perror("[fanwar] apply "..iface)
	util.perror("[fanwar]-----------------------------------------------")
	for k,v in pairs(http.formvalue()) do
        if type(v) ~= type("") and type(v) ~= type(0) then
            nixio.syslog("err", "dev_cfg, invalid value type for "..k..","..type(v))
        elseif string.byte(k) == string.byte("_") then
            nixio.syslog("err", "dev_cfg, special: "..k.."="..v)
        else
			util.perror("[fanwar] ["..k.."] ---> "..v)
            cfgs[k] = v or ""
        end
    end
	util.perror("[fanwar]-----------------------------------------------")

	if iface == "add" then
		iface = iface_add(cfgs["conn_type"])
	end

	if cfgs["conn_type"] == "bridge" then
		wan_set_bridge_cfg(iface, cfgs)
	elseif cfgs["conn_type"] == "route" then
		wan_set_route_cfg(iface, cfgs)
	end
	util.perror("[fanwar] reload "..table.concat(configlist, ","))
	fork_exec("/sbin/luci-reload".." "..table.concat(configlist, " "))
	luci.http.redirect(luci.dispatcher.build_url("admin/network/wan"))
end

function ifc_uci_cfg(iface)
	local uci = require("luci.model.uci").cursor()
	local tbl = {}
	if iface and #iface > 0 then
		tbl = uci:get_all("network", iface)
	else
		tbl = uci:get_all("network")
	end

	luci.http.write_json(tbl)
end

function get_wan_dns_option(uci)
	local util = require("luci.util")
	local wan_defroute = uci:get("network", "globals","wan_df_route")
	local ntm = require "luci.model.network".init()
	local wan = ntm:get_network(wan_defroute)
	local dnsv4 = wan:dnsaddrs()
	local dhcp_opt_str = nil
	if next(dnsv4) then
		dhcp_opt_str = "6"
		for _,v in pairs(dnsv4) do
			dhcp_opt_str = dhcp_opt_str..","..v
		end
	end
	return dhcp_opt_str
end

function handle_apply_lan()
	local uci = require("luci.model.uci").cursor()
	local util = require("luci.util")
	local current_dns_mode = uci:get("dhcp", "lan", "dns_mode")
	local ipaddr = luci.http.formvalue("addr4") 
	local netmask = luci.http.formvalue("mask4") 
	local ipv6
	if luci.http.formvalue("enable_ip6") then
		ipv6 = "1"
	else
		ipv6 = "0"
	end

	local ignore 
	if luci.http.formvalue("enable_dhcp4") then
		ignore = "0"
	else
		ignore = "1"
	end


	local start = luci.http.formvalue("dhcp_start") or "1"
	local tmp = luci.http.formvalue("dhcp_end") or "250"
	local limit
	if start and tmp then
		limit = tonumber(tmp) - tonumber(start) + 1
		limit = tostring(limit)
	end
	local leasetime = luci.http.formvalue("dhcp_leasetime") or "3h"

	local dns_mode = luci.http.formvalue("dnsv4_mode")

	local dhcp_option
	if dns_mode and dns_mode == "Static" then
		dhcp_option ="6"
		for k,v in pairs(luci.http.formvalue()) do
			if string.find(k, "dns_server_")  and v ~="" then
				dhcp_option = dhcp_option..","..v
			end
		end
		util.perror(dhcp_option)
	end


	util.perror("ipaddr: "..tostring(ipaddr).." netmask: "..tostring(netmask).." ipv6: "..tostring(ipv6))
	-- uci set
	uci:set("network", "lan", "ipaddr", ipaddr)
	uci:set("network", "lan", "netmask", netmask)
	uci:set("network", "lan", "ipv6", ipv6)

	uci:set("dhcp", "lan", "ignore", ignore)
	if ignore == "0" then
		uci:set("dhcp", "lan", "start", start)
		uci:set("dhcp", "lan", "limit", limit)

		uci:set("dhcp", "lan", "leasetime", leasetime)
		uci:set("dhcp", "lan", "dns_mode", dns_mode)	
		
		util.perror(tostring(current_dns_mode).."->"..tostring(dns_mode) )
		if current_dns_mode == "Forwarder" then 
			if dns_mode == "Proxy" then
				util.perror("Forwarder -> Proxy")
				uci:delete("dhcp", "lan", "dhcp_option")	
			elseif dns_mode == "Static" then
				util.perror("Forwarder -> Static")
				uci:set("dhcp", "lan", "dhcp_option", dhcp_option)	
			end

		end

		if current_dns_mode == "Proxy" then 
			if dns_mode == "Forwarder" then
				local wan_dns = get_wan_dns_option(uci)
				if wan_dns then
					uci:set("dhcp", "lan", "dhcp_option", wan_dns)
				end
			elseif dns_mode == "Static" then
				uci:set("dhcp", "lan", "dhcp_option", dhcp_option)
			end

		end

		if current_dns_mode == "Static" then 
			if dns_mode == "Forwarder" then
				local wan_dns = get_wan_dns_option(uci)
				if wan_dns then
					uci:set("dhcp", "lan", "dhcp_option", wan_dns)
				end
			elseif dns_mode == "Proxy" then
				uci:delete("dhcp", "lan", "dhcp_option")
			elseif dns_mode == "Static" then
				uci:set("dhcp", "lan", "dhcp_option", dhcp_option)
			end
		end
	else
		--uci:set("dhcp", "lan", "dns_mode", "Forwarder")
		--uci:delete("dhcp", "lan", "dhcp_option")
	end


	--static lease

	for k,v in pairs(luci.http.formvalue()) do
		local cfg_name = ""
		if string.find(k, "lease_name_")  and v ~="" then
			cfg_name = k:match("lease_name_(.+)")
			uci:set("dhcp", cfg_name, "name", v)
		elseif string.find(k, "lease_mac_")  and v ~="" then
			cfg_name  = k:match("lease_mac_(.+)")
			uci:set("dhcp", cfg_name, "mac", v)
		elseif string.find(k, "lease_ip_")  and v ~="" then
			cfg_name  = k:match("lease_ip_(.+)")
			uci:set("dhcp", cfg_name, "ip", v)
		end
	end

	uci:commit("network")
	uci:commit("dhcp")
	rv = {}
	rv["status"] = "ok"
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
	os.execute("/sbin/luci-reload network dhcp")
	--luci.http.redirect(luci.dispatcher.build_url("admin/network/lan"))
end

function cfg_static_lease()
	local uci = require("luci.model.uci").cursor()
	local util = require("luci.util")
	local operation = luci.http.formvalue("operation") 
	local cfg_name = luci.http.formvalue("cfg_name") 
	local rv = {}
	if operation then
		if operation == "add" then
			rv["cfg_name"] = uci:add("dhcp", "host");
			uci:commit("dhcp")
			--need to reload dhcp service
			luci.http.prepare_content("application/json")
			luci.http.write_json(rv)
		elseif operation == "del" then
			util.perror(cfg_name);
			uci:delete("dhcp", cfg_name)
			uci :commit("dhcp")	
			rv["status"] = "ok"
			luci.http.prepare_content("application/json")
			luci.http.write_json(rv)
		end
	end
end