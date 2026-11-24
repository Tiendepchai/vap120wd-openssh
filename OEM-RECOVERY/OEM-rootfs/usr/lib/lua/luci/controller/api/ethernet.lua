
-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.api.ethernet", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")

function index()
	entry({"api", "ethernet_info"}, call("handle_ethernetinfo"))
	entry({"api", "ethernet"}, call("handle_ethernet_X_VT"))
	entry({"api", "ethernet", "interface"}, call("handle_ethernet_interface"))
	entry({"api", "ethernet", "link"}, call("handle_ethernet_link"))
	entry({"api", "ethernet", "vlantermination"}, call("handle_ethernet_vlantermination"))
	entry({"api", "bridging"})
	entry({"api", "bridging", "bridge"}, call("handle_bridging_bridge"))
	entry({"api", "ppp"})
	entry({"api", "ppp", "interface"}, call("handle_PPP_interface"))
	entry({"api", "ip"})
	entry({"api", "ip",  "interface"}, call("handle_IP_interface"))
	entry({"api", "dhcpv4"})
	entry({"api", "dhcpv4",  "client"}, call("handle_DHCPv4_client"))
end


function split(pString, pPattern)
	local Table = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pPattern
	local last_end = 1
	local s, e, cap = pString:find(fpat, 1)
	while s do
	   if s ~= 1 or cap ~= "" then
	  table.insert(Table,cap)
	   end
	   last_end = e+1
	   s, e, cap = pString:find(fpat, last_end)
	end
	if last_end <= #pString then
	   cap = pString:sub(last_end)
	   table.insert(Table, cap)
	end
	return Table
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

-------Ethernet/Interface--------
local ethernet_iface_list =
{
	[1] = "eth1",
	[2] = "eth0.1",
	[3] = "eth0.2"
}
local ethernet_layer_list = 
{
	[1] = "Device.Ethernet.Interface.1",
	[2] = "Device.Ethernet.Interface.2",
	[3] = "Device.Ethernet.Interface.3"
}

function get_Ethernet_Interface(idx)
	local bsent = ""
	local breceived = ""
	local psent = ""
	local preceived = ""
	local errsent = ""
	local errreceived = ""
	local stats_tbl = {} 
	local currate = ""
	local macaddr = luci.util.exec_trim("cat /sys/class/net/eth0/address")

	local check = luci.util.exec_trim("ifconfig | grep -oE '"..ethernet_iface_list[idx].."'")
	if string.len(check) > 3 then
		macaddr = luci.util.exec_trim("cat /sys/class/net/"..ethernet_iface_list[idx].."/address")
		
		stats_tbl = json.decode(luci.util.exec("ubus call network.device status '{\"name\":\""..ethernet_iface_list[idx].."\"}'"))
		if stats_tbl["statistics"] ~= nil then
			bsent = tostring(stats_tbl["statistics"]["tx_bytes"])
			breceived = tostring(stats_tbl["statistics"]["rx_bytes"])
			psent = tostring(stats_tbl["statistics"]["tx_packets"])
			preceived = tostring(stats_tbl["statistics"]["rx_packets"])
			errsent = tostring(stats_tbl["statistics"]["tx_errors"])
			errreceived = tostring(stats_tbl["statistics"]["rx_errors"])
		end
	end
	
	local status = luci.util.exec_trim("ethstt | grep 'port "..(idx+1).."' | grep -oE 'up'")
	if status == "up" then
		status = "up"
	else
		status = "down"
	end 

	if status == "down" then
		currate = "0"
	else
		local result = luci.util.exec_trim("/usr/bin/switch reg r 3"..(idx+1).."08")
		local result_tbl = result:split("=")

		if result_tbl[3] == "3b" or result_tbl[3] == "b" then
			currate = "1000"
		else
			currate = "100"
		end
	end
	
	local this_entry_tbl =
	{
		Enable = "true",
		MACAddress = macaddr,
		Status = status,
		MaxBitRate = "1000",
		CurrentBitRate = currate,
		DuplexMode = "Auto",
		Stats = {
			BytesSent = bsent,
			BytesReceived = breceived,
			PacketsSent = psent,
			PacketsReceived = preceived,
			ErrorsSent = errsent,
			ErrorsReceived = errreceived
		}
	}

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_Ethernet_Interface()
	local tbl = {}
	local tmp_entry = {}

	for i = 1,3,1 do
		tmp_entry = get_Ethernet_Interface(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

	return tbl
end

function set_Ethernet_Interface_Enable(tbl)
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if(cfg["Enable"] == "true") then
				luci.util.exec("ifconfig "..ethernet_iface_list[tonumber(idx)].." up")
			elseif(cfg["Enable"] == "false") then
				luci.util.exec("ifconfig "..ethernet_iface_list[tonumber(idx)].." down")
			else
				return false
			end
		end
	end

	return true
end

function handle_ethernet_interface(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_Ethernet_Interface(tonumber(idx))
		else
			rv=get_all_Ethernet_Interface()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_Ethernet_Interface_Enable(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
----- bridging/bride-----------
local bridging_list =
{
	[1] = "br-lan"
}

local bridging_layer = 
{
	[1] = "Device.Bridging.Bridge.1"
}

function get_bridging_bridge(idx)

	local status = luci.util.exec_trim("cat /sys/class/net/"..bridging_list[idx].."/operstate")

	local this_entry_tbl =
	{
		Enable = status == "up" and "true" or "false",
		Status = status,
		Port   = {
			["1"] = {
				LowerLayers = ethernet_layer_list[2]
			},
			["2"] = {
				LowerLayers = ethernet_layer_list[3]
			}
		}
	}

	return {[tostring(idx)] = this_entry_tbl}
end

function set_bridging_bridge_Enable(tbl)
	
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if(cfg["Enable"] == "true") then
				luci.util.exec("ifconfig "..bridging_list[tonumber(idx)].." up")
			elseif(cfg["Enable"] == "false") then
				luci.util.exec("ifconfig "..bridging_list[tonumber(idx)].." down")
			else
				return false
			end
		end
	end

	return true
end

function handle_bridging_bridge(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		rv=get_bridging_bridge(1)

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_Ethernet_Interface_Enable(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

--------------------------------------------------------------
local ethernetlink_list = 
{
	[1] = "br-lan",
	[2] = "eth1",
	[3] = "eth0.1",
	[4] = "eth0.2"
}

local ethernetlink_layer = 
{
	[1] = "Device.Ethernet.Link.1",
	[2] = "Device.Ethernet.Link.2"
}

function get_Ethernet_Link(idx)

	local lowerlayer = ""
	local macaddr = luci.util.exec_trim("cat /sys/class/net/eth0/address")

	local check = luci.util.exec_trim("ifconfig | grep -oE '"..ethernetlink_list[idx].."'")
	if string.len(check) > 3 then
		macaddr = luci.util.exec_trim("cat /sys/class/net/"..ethernetlink_list[idx].."/address")
		if idx == 1 then
			lowerlayer = bridging_layer[1]
		else
			lowerlayer = ethernet_layer_list[idx-1]
		end
	end

	local this_entry_tbl =
	{
		MACAddress = macaddr,
		LowerLayers = lowerlayer
	}

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_Ethernet_Link()
	local tbl = {}
	local tmp_entry = {}

	for i = 1,4,1 do
		tmp_entry = get_Ethernet_Link(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

	return tbl
end

function set_Ethernet_Link_Lowerlayer(tbl)

	return false
end

function handle_ethernet_link(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_Ethernet_Link(tonumber(idx))
		else
			rv=get_all_Ethernet_Link()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_Ethernet_Link_Lowerlayer(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
------------------------------------------------
local vlan_interface_list = 
{
	[1] = "eth1.35",
	[2] = "eth1.2502",
	[3] = "eth1.335"
}

local vlanid_list = 
{
	[1] = "35",
	[2] = "2502",
	[3] = "335"
}

local vlantermination_layer = 
{
	[1] = "Device.Ethernet.VLANTermination.1",
	[2] = "Device.Ethernet.VLANTermination.2",
	[3] = "Device.Ethernet.VLANTermination.3"
}

function get_ethernet_vlantermination(idx)

	local status = luci.util.exec_trim("cat /sys/class/net/"..vlan_interface_list[idx].."/operstate")
	if status == "up" or status == "down" then
		local name = vlan_interface_list[idx]
		local t = name:split(".")
		vlanid = t[2]

		local this_entry_tbl =
		{
			Enable = status == "up" and "true" or "false",
			Status = status,
			VLANID = vlanid,
			LowerLayers = ethernetlink_layer[2]
		}
		return {[tostring(idx)] = this_entry_tbl}
	else
		local this_entry_tbl =
		{
			Status = "NULL",
		}
	end

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_ethernet_vlantermination()
	local tbl = {}
	local tmp_entry = {}

	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			local vlanid = uci:get("network", name, "_vlanid")
			for idx = 1,3,1 do
				if vlanid == vlanid_list[idx] then
					tmp_entry = get_ethernet_vlantermination(idx)
					tbl[tostring(idx)] = tmp_entry[tostring(idx)]
				end
			end
		end
	)

	return tbl
end

function set_ethernet_vlantermination_Enable(tbl)
	
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if(cfg["Enable"] == "true") then
				luci.util.exec("ifconfig "..vlan_interface_list[tonumber(idx)].." up")
			elseif(cfg["Enable"] == "false") then
				luci.util.exec("ifconfig "..vlan_interface_list[tonumber(idx)].." down")
			else
				return false
			end
		end
	end

	return true
end

function handle_ethernet_vlantermination(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_ethernet_vlantermination(tonumber(idx))
		else
			rv=get_all_ethernet_vlantermination()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_ethernet_vlantermination_Enable(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

--------------------------------------------------------------
local ppp_list = 
{
	[1] = "wan0",
	[2] = "wan1",
	[3] = "wan2",
	[4] = "wan3",
	[5] = "wan4",
	[6] = "wan5",
	[7] = "wan6",
	[8] = "wan7",
	[9] = "wan8",
	[10] = "wan9"
}

local ppp_layer = 
{
	[1] = "Device.PPP.Interface.1",
	[2] = "Device.PPP.Interface.2",
	[3] = "Device.PPP.Interface.3",
	[4] = "Device.PPP.Interface.4",
	[5] = "Device.PPP.Interface.5",
	[6] = "Device.PPP.Interface.6",
	[7] = "Device.PPP.Interface.7",
	[8] = "Device.PPP.Interface.8",
	[9] = "Device.PPP.Interface.9",
	[10] = "Device.PPP.Interface.10"
}
------PPP/interface------
function get_PPP_Interface(idx)
	local proto = luci.util.exec_trim("uci get network."..ppp_list[idx]..".proto")

	if proto == "pppoe" then
		local lowerlayer = ""
		local connstatus = ""
		local ifname = luci.util.exec_trim("uci get network."..ppp_list[idx]..".ifname")
		for i=1,3,1 do
			if ifname == vlan_interface_list[i] then
				lowerlayer = vlantermination_layer[i]
				break
			else
				lowerlayer = ethernetlink_layer[2]
			end
		end	
		local statustbl = {}
		statustbl=json.decode(luci.util.exec("ifstatus "..ppp_list[idx]..""))
		connstatus = statustbl["pending"]
		if connstatus == false then
			connstatus = "Connected"
		else
			connstatus = "Disconnected"
		end
		local user = luci.util.exec_trim("uci get network."..ppp_list[idx]..".username")
		local pwd = luci.util.exec_trim("uci get network."..ppp_list[idx]..".password")

		local this_entry_tbl =
		{
			LowerLayers = lowerlayer,
			ConnectionStatus = connstatus,
			Username = user,
			Password = pwd,
			LastConnectionError = "",
			ConnectionTrigger = "",
			LCPEcho = "",
			LCPEchoRetry = ""
		}
		return {[tostring(idx)] = this_entry_tbl}
	else
		local this_entry_tbl =
		{
			Status = "NULL",
		}
	end

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_PPP_Interface()
	local tbl = {}
	local tmp_entry = {}
	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			for idx = 1,10,1 do
				if name == ppp_list[idx] then
					tmp_entry = get_PPP_Interface(idx)
					tbl[tostring(idx)] = tmp_entry[tostring(idx)]
				end
			end
		end
	)

	return tbl
end

function set_PPP_Interface(tbl)
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if cfg["Username"] ~= nil then
				luci.util.exec("uci set network."..ppp_list[tonumber(idx)]..".username='"..cfg["Username"].."'")
				luci.util.exec("uci commit")
			end
			if cfg["Password"] ~= nil then
				luci.util.exec("uci set network."..ppp_list[tonumber(idx)]..".password='"..cfg["Password"].."'")
				luci.util.exec("uci commit")
			end
		end
	end
	-- luci.util.exec("/sbin/luci-reload network")
	fork_exec("sleep 1; /sbin/luci-reload network")
	return true
end

function handle_PPP_interface(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_PPP_Interface(tonumber(idx))
		else
			rv=get_all_PPP_Interface()
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_PPP_Interface(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
		-- luci.util.exec("/etc/init.d/network reload")
	end
end
--------------------------------------------------
----IP/Interface------------
local ipinterface_list = 
{
	[1] = "lan",
	[2] = "wan0",
	[3] = "wan1",
	[4] = "wan2",
	[5] = "wan3",
	[6] = "wan4",
	[7] = "wan5",
	[8] = "wan6",
	[9] = "wan7",
	[10] = "wan8",
	[11] = "wan9"
}

function get_lowerlayers_internet_wan(str)
	local lowerlayer = ""
	local idx

	local proto = luci.util.exec_trim("uci get network."..str..".proto")
	local ifname = luci.util.exec_trim("uci get network."..str..".ifname")

	if proto == "dhcp" then
		local vlanid = luci.util.exec_trim("uci get network."..str.."._vlanid")
		if vlanid == "0" then
			lowerlayer =  ethernetlink_layer[2]..","..ethernet_layer_list[1]..","
		else
			for i=1,3,1 do
				if ifname == vlan_interface_list[i] then
					lowerlayer = vlantermination_layer[i]..","..ethernetlink_layer[2]..","..ethernet_layer_list[1]..","
					break
				else
					lowerlayer = ethernetlink_layer[2]..","..ethernet_layer_list[1]..","
				end
			end
		end
	end
	
	if proto == "pppoe" then
		idx = tonumber(string.sub(str,4))

		for i=1,3,1 do
			if ifname == vlan_interface_list[i] then
				lowerlayer = ppp_layer[idx+1]..","..vlantermination_layer[i]..","..ethernetlink_layer[2]..","..ethernet_layer_list[1]..","
				break
			else
				lowerlayer = ppp_layer[idx+1]..","..ethernetlink_layer[2]..","..ethernet_layer_list[1]..","
			end
		end	
		
	end

	return lowerlayer
end

function get_IP_Interface(idx)
	local tail = "_ip6"
	local ifname = " "
	local ipv6 = " "
	local ipv4 = "false"
	local service = " "
	local lowerlayer = " "
	local ipaddressv4 = " "
	local subnet = " "
	local protov4 = " "
	local ipaddressv6 = " "
	local protov6 = " "
	local statustbl = {}
	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			if name == ipinterface_list[idx] then
				ipv4 = "true"

				ifname = uci:get("network", name, "ifname")
				if ifname == "eth1" then
					lowerlayer = ethernetlink_layer[2]
				elseif ifname == "eth0.1" or ifname == "eth0.2" then
					lowerlayer = ethernetlink_layer[1]
				elseif ifname == "eth0.1 eth0.2" or ifname == "eth0.2 eth0.1" then
					lowerlayer = ethernetlink_layer[1]
				else
					lowerlayer = ppp_layer[idx-1]
				end

				ipv6 = uci:get("network", name, "ipv6")
				if ipv6 == "false" or ipv6 == "0" then
					ipv6 = "false"
				end

				if ipv6 == "true" or ipv6 == "1" or ipv6 == "auto" then
					ipv6 = "true"
				end

				local defaultroute = uci:get("network", name, "defaultroute")
				if defaultroute == "1" then
					lowerlayer = get_lowerlayers_internet_wan(ipinterface_list[idx]);
					service = uci:get("network", name, "_service")
					if service == "_internet" or service == "internet" then
						service = "internet"
					else 
						service = ""
					end
				end
				

				statustbl=json.decode(luci.util.exec("ifstatus "..ipinterface_list[idx]..""))
				protov4 = statustbl["proto"]
				if protov4 == "pppoe" then
					protov4 = "IPCP"
				end
				for name,cfg in pairs(statustbl) do
					if name == "ipv4-address" and cfg ~= nil then
						for k,v in pairs(cfg) do
							if k ~= nil and v ~= nil then
								if v["address"]~= nil then
									ipaddressv4 = v["address"]
								end

								if v["mask"] ~= nil then
									subnet = string.format("%d",v["mask"])
								end
							end
						end
					end
				end

				name = ipinterface_list[idx]..tail
				local checkipv6 = uci:get("network", name, "proto")
				if checkipv6 == "dhcpv6" or checkipv6 == "static" or  checkipv6 == "pppoe" then
					if ipv6 ~= "true" and ipv6 ~= "false" then
						ipv6 = "true"
					end
					
					if ipv6 == "true" then
						statustbl=json.decode(luci.util.exec("ifstatus "..ipinterface_list[idx].."_ip6"))
						protov6 = statustbl["proto"]
						if protov6 == "pppoe" then
							protov6 = "IPCP"
						end
						for name,cfg in pairs(statustbl) do
							if name == "ipv6-address" and cfg ~= nil then
								for k,v in pairs(cfg) do
									if k ~= nil and v["address"] ~= nil then
										ipaddressv6 = v["address"]
									end
								end
							end
						end
					end
				else
					ipv6 = "false"
				end
			
			end
		end
	)

		
	local this_entry_tbl =
	{
		LowerLayers = lowerlayer,
		IPv4Enable = ipv4,
		IPv6Enable = ipv6,
		Name = service,
		IPv4Address = {
			["1"] = {
				Enable = ipv4,
				IPAddress = ipaddressv4,
				SubnetMask = subnet,
				AddressingType = protov4 
			}
		},
		IPv6Address = {
			["1"] = {
				Enable = ipv6,
				IPAddress = ipaddressv6,
				Origin = protov6 
			}
		}
	}
	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_IP_Interface()
	local tbl = {}
	local tmp_entry = {}
	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			for idx = 1,11,1 do
				if name == ipinterface_list[idx] then
					tmp_entry = get_IP_Interface(idx)
					tbl[tostring(idx)] = tmp_entry[tostring(idx)]
				end
			end
		end
	)

	return tbl
end

function set_IP_Interface(tbl)
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if cfg["IPv6Enable"] ~= nil then
				luci.util.exec("uci set network."..ipinterface_list[tonumber(idx)]..".ipv6='"..cfg["IPv6Enable"].."'")
				luci.util.exec("uci commit")
			end

			for k,v in pairs(cfg) do
				if k == "IPv4Address" and v ~= nil then
					local proto = luci.util.exec_trim("uci get network."..ipinterface_list[tonumber(idx)]..".proto")
					if proto == "static" then
						if cfg["IPAddress"] ~= nil then
							luci.util.exec("uci set network."..ipinterface_list[tonumber(idx)]..".ipaddr='"..cfg["IPAddress"].."'")
							luci.util.exec("uci commit")
						end
						if cfg["SubnetMask"] ~= nil then
							luci.util.exec("uci set network."..ipinterface_list[tonumber(idx)]..".netmask='"..cfg["SubnetMask"].."'")
							luci.util.exec("uci commit")
						end
					else
						return false
					end
				end

				if k == "IPv6Address" and v ~= nil then
					local proto = luci.util.exec_trim("uci get network."..ipinterface_list[tonumber(idx)].."_ip6.proto")
					if proto == "static" then
						if cfg["IPAddress"] ~= nil then
							luci.util.exec("uci set network."..ipinterface_list[tonumber(idx)].."_ip6.ipaddr='"..cfg["IPAddress"].."'")
							luci.util.exec("uci commit")
						end
					else
						return false
					end
				end
			end
		end
	end
	-- luci.util.exec("/sbin/luci-reload network")
	fork_exec("sleep 1; /sbin/luci-reload network")
	return true
end

function handle_IP_interface(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_IP_Interface(tonumber(idx))
		else
			rv=get_all_IP_Interface()
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_IP_Interface(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
------------------------------------------
------ ip/interface/ipv4address ----------
function  get_DHCPv4_client(idx)
	local proto = luci.util.exec_trim("uci get network.wan"..(idx-1)..".proto")
	if proto == "dhcp" or proto == "static" or  proto == "pppoe" then
		local interface = ""
		local ipaddress = ""
		local subnet = ""
		local iproute = ""
		local dnsserver = ""
		local dhcpserver = ""
		local leasetime = ""
		local statustbl = {}
		statustbl=json.decode(luci.util.exec("ifstatus wan"..(idx-1)..""))
		if proto == "pppoe" then
			proto = "IPCP"
		end
		interface = statustbl["device"]
		for name,cfg in pairs(statustbl) do
			if name == "ipv4-address" and cfg ~= nil then
				for k,v in pairs(cfg) do
					if k ~= nil and v ~= nil then
						if v["address"] ~= nil then
							ipaddress = v["address"]
						end
						
						if v["mask"] ~= nil then
							subnet = string.format("%d",v["mask"])
						end
					end
				end
			end
			if name == "route" and cfg ~= nil then
				for k,v in pairs(cfg) do
					if k ~= nil and v ~= nil then
						if v["target"] ~= nil then
							iproute = v["target"]
						end

						if v["target"] ~= nil then
							dhcpserver = v["target"]
						end
					end
				end
			end
			if name == "dns-server" and cfg[1] ~= nil then
				dnsserver=cfg[1]
			end

			if name == "data" and cfg["leasetime"] ~= nil then
				leasetime = cfg["leasetime"]
			end
		end
		local this_entry_tbl =
		{
			Interface = interface,
			IPAddress = ipaddress,
			SubnetMask = subnet,
			IPRouters = iproute,
			DNSServers = dnsserver,
			DHCPServer = dhcpserver,
			LeaseTimeRemaining = leasetime
		}
		return {[tostring(idx)] = this_entry_tbl}
	else
		local this_entry_tbl =
		{
			Status = "NULL",
		}
	end
	return {[tostring(idx)] = this_entry_tbl}	
end

function get_all_DHCPv4_client()
	local tbl = {}
	local tmp_entry = {}

	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			for idx = 1,10,1 do
				if name == ppp_list[idx] then
					tmp_entry = get_DHCPv4_client(idx)
					tbl[tostring(idx)] = tmp_entry[tostring(idx)]
				end
			end
		end
	)

	return tbl
end

function set_DHCPv4_client(tbl)
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if cfg["Interface"] ~= nil then
				luci.util.exec("uci set network.wan"..tonumber(idx-1)..".ifname='"..cfg["Interface"].."'")
				luci.util.exec("uci commit")
			end
		end
	end
	-- luci.util.exec("/sbin/luci-reload network")
	fork_exec("sleep 1; /sbin/luci-reload network")
	return true
end

function handle_DHCPv4_client(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_DHCPv4_client(tonumber(idx))
		else
			rv=get_all_DHCPv4_client()
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		if (table ~= nil) then
			if(set_DHCPv4_client(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

--- ethernetinfo ---
function get_vlan_quantity()
   	local count = ""
   	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			local vlanid = uci:get("network", name, "_vlanid")
			for idx = 1,3,1 do
				if vlanid == vlanid_list[idx] then
					count = count..idx
				end
			end
		end
	)
   return count
end

function get_ppp_quantity()
	local count = ""
	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			for idx = 1,10,1 do
				if name == ppp_list[idx] then
					local proto = uci:get("network", name, "proto")
					if proto == "pppoe" then
						count = count..idx
						break
					end
				end
			end
		end
	)

    return count
end

function get_ipinterface_quantity()
	local count = ""
	local uci = require("luci.model.uci").cursor()

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			for idx = 1,10,1 do
				if name == ipinterface_list[idx] then
					local proto = uci:get("network", name, "proto")
					if proto == "dhcp" or proto == "static" or  proto == "pppoe" then
						count = count..idx
						break
					end
				end
			end
		end
	)

	return count
end

function handle_ethernetinfo()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			VlanQtt = get_vlan_quantity(),
			PPPInterfaceQtt = get_ppp_quantity(),
			IPInterfaceQtt = get_ipinterface_quantity()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

------ Device Ethernet X_VT --------
function get_lastdatarate()
	local tbl = {
		X_VT_UplinkLastDataUplinkRate = "0",
		X_VT_UplinkLastDataDownlinkRate = "0"
	}
	local ethernetiface = ""
	local uplinkrate = 0
	local downlinkrate = 0
	local stats_tbl = {}
	local devRole = util.exec_trim("cat /etc/mapd_cfg.txt | grep DeviceRole | grep -oE '[0-9]+'")
	if devRole == "1" then
		ethernetiface = "eth1"
	else
		ethernetiface = "br-lan"
	end

	statstbl_prev = json.decode(luci.util.exec("ubus call network.device status '{\"name\":\""..ethernetiface.."\"}'"))
	os.execute("sleep 2")
	statstbl = json.decode(luci.util.exec("ubus call network.device status '{\"name\":\""..ethernetiface.."\"}'"))

	if statstbl_prev["statistics"]["rx_bytes"] ~= nil and statstbl["statistics"]["rx_bytes"] ~= nil then
		downlinkrate = math.abs(statstbl["statistics"]["rx_bytes"] - statstbl_prev["statistics"]["rx_bytes"])
	end

	if statstbl_prev["statistics"]["tx_bytes"] ~= nil and statstbl["statistics"]["tx_bytes"] ~= nil then
		uplinkrate = math.abs(statstbl["statistics"]["tx_bytes"] - statstbl_prev["statistics"]["tx_bytes"])
	end

	tbl["X_VT_UplinkLastDataUplinkRate"] = string.format("%d", math.floor((uplinkrate*8)/1024 + 0,5))
	tbl["X_VT_UplinkLastDataDownlinkRate"] = string.format("%d", math.floor((downlinkrate*8)/1024 + 0.5))

	return tbl
end

function handle_ethernet_X_VT()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		rv = get_lastdatarate()
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end