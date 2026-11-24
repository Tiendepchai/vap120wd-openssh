
-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.


module("luci.controller.api.bootup_params", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")
local ip = require "luci.ip"

function index()
    entry({"api", "lock"}, call("handle_lock"))
    entry({"api", "bootup_params"}, call("handle_bootup_params"))
end

function get_lock()
	local lock = luci.util.exec("cof_cli read LockStatus")
	lock = luci.util.trim(lock)
	if (lock == "1") then
		return "true"
	else
		return "false"
	end
end

function set_lock(lock)
	if lock == "true" then
		luci.sys.call("/usr/bin/lock/lock_action.sh do_lock 5")
	else
		luci.sys.call("/usr/bin/lock/lock_action.sh do_unlock 3")
	end
	return true
end

function handle_lock()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			X_VT_Lock = get_lock()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = {Status = "Success"}
		local value = table["X_VT_Lock"]
		local current_lock = get_lock()
		if current_lock ~= value then
			if value ~= nil then
				if set_lock(value) then
					rv.Status = "Success"
				else
					rv.Status = "Fail"
				end
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

function get_macaddress(uci)
	local macaddr = uci:get("network", "lan", "macaddr")
	if macaddr == nil or string.len(macaddr) < 17 then
		luci.util.perror("[TMS] uci macaddress failed - get again") 
		macaddr = luci.util.exec_trim("cat /sys/class/net/eth0/address")
	end
	return string.upper(macaddr)
end

function get_meshinfo(macaddr, mesh_enable, devRole)
	local ret = {
		ControllerMac = "",
		BHLinkRate = "1000",
		AgentCount = 0
	}
	
    if mesh_enable == "1" then 
		if devRole == "1" then
			ret.ControllerMac = macaddr
		end
		-- When mesh done, mapd send event to obuspafm for dump topology into vt_topodump.txt
		-- local r = c_get_vt_runtime_topology()
		if file_exists("/tmp/vt_topodump.txt") then
			local r_str = util.exec_trim("cat /tmp/vt_topodump.txt");

			if r_str ~= nil or string.len(r_str) > 1 then
				local r_tbl = json.decode(r_str)
				for _, device in ipairs(r_tbl["topology information"]) do
					local role = device["Device role"]
					if role == "01" then
						ret.ControllerMac = string.upper(device["AL MAC"])
					elseif role == "02" then
						if devRole == "1" then
							ret.AgentCount = ret.AgentCount + 1
						end
						
						local bh_metric = device["backhaul link metrics"]
						local mac = string.upper(string.trim(device["AL MAC"]))
						if mac == macaddr then
							if device["BH Info"]["Backhaul Medium Type"] == "Ethernet" then
								ret.BHLinkRate = "1000"
							else
								if bh_metric ~= nil and bh_metric[1] ~= nil and bh_metric[1]["metrics"] ~= nil and bh_metric[1]["metrics"][1] ~= nil and bh_metric[1]["metrics"][1]["phyRate"] ~= nil then
									ret.BHLinkRate = bh_metric[1]["metrics"][1]["phyRate"]
								end
							end
						end
					end
				end
			end
		end
	end

	return ret
end

function get_uplink_neighbor(uci, name, proto, wan_if)

	if proto == "pppoe" then
		local mac = uci:get("network", name, "macaddr")
		if mac == nil or string.len(mac) < 17 then
			luci.util.perror("[TMS] can get pppoe wan mac")
		else
			return string.upper(mac)
		end
	end

    for _, v in ipairs(ip.neighbors({ family = 4 })) do
        if v.dev == wan_if and v.mac ~= nil then
            return string.upper(v.mac)
        end
    end
    
    return ""
end

function get_bootup_params()

	local rv = {
		X_VT_MacAddress = "",
		X_VT_ControllerMacAddress = "",
		X_VT_BHLink_Rate = "",
		X_VT_AgentQuatity = 0,
		X_VT_AccessMode = "",
		X_VT_UplinkNeighborMacAddress = ""
	}

	uci = require("luci.model.uci").cursor()
	local mesh_enable = util.exec_trim("cat /etc/mapd_cfg.txt | grep MapEnable | grep -Eo [0-9]+");
	local devRole = util.exec_trim("cat /etc/mapd_cfg.txt | grep DeviceRole | grep -oE '[0-9]+'")
	local macaddr = get_macaddress(uci)
	local mesh_info = get_meshinfo(macaddr, mesh_enable, devRole)
	local proto = ""
	local wan_name = "wan0"
	local wan_if = "eth1"

	uci:foreach("network","interface",
		function(x)
			local name = x['.name']
			local defaultroute = uci:get("network", name, "defaultroute")
			if defaultroute == "1" then
				local service = uci:get("network", name, "_service")
				if service == "_internet" or service == "internet" then
					proto = uci:get("network", name, "proto")
					wan_if = uci:get("network", name, "ifname")
					wan_name = name
				end
			end
		end
	)

	rv["X_VT_MacAddress"] = macaddr
	rv["X_VT_ControllerMacAddress"] = mesh_info.ControllerMac
	rv["X_VT_BHLink_Rate"] = mesh_info.BHLinkRate
	rv["X_VT_AgentQuatity"] = tostring(mesh_info.AgentCount)
	rv["X_VT_AccessMode"] = string.upper(proto)

	if mesh_enable == "1" and devRole == "2" then
		rv["X_VT_UplinkNeighborMacAddress"] = ""
	else
		rv["X_VT_UplinkNeighborMacAddress"] = get_uplink_neighbor(uci, wan_name, proto, wan_if)
	end

	return rv
end

function handle_bootup_params()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		rv = get_bootup_params()
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end