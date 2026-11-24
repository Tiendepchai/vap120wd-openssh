-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.


module("luci.controller.api.host", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local ip = require "luci.ip"
local stat = require "luci.tools.status"
local wifi = require "luci.controller.api.wifi_ap_ssid"
local multiap = require "luci.controller.api.multiap"
local mtkwifi = require "mtkwifi"
local uci

function index()
	entry({"api","hosts"})
	entry({"api","hosts","hosts"}, call("handle_hosts")).leaf = true
	entry({"api","hosts","accesscontrol"}, call("handle_hosts_accesscontrol")).leaf = true
end

function str2arr (inputstr, sep)
    if sep == nil then
            sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end

function get_assocdev_if(ifname)
    local ioctl_help = require "ioctl_helper"
    local count = 0;
    local r_stalist = {}
    local stalist = c_StaInfo(ifname)
    for _,v in pairs(stalist) do 
        count = count + 1
        local idx = tostring(count)
        r_stalist[idx] = {}
        r_stalist[idx]["MACAddress"] = v["MacAddr"]
    end

    return count, r_stalist
end

function get_multi_ap_radio_when_mesh_disabled()
    local rv = {}
    local band_5G = {}
    local band_2G = {}
    local ap_5G = {}
    local ap_2G = {}
    local profile_5G = "/etc/wireless/mt7615/mt7615.1.5G.dat"
    local profile_2G = "/etc/wireless/mt7615/mt7615.1.2G.dat"

    --5G
    band_5G["MACAddress"] = "4D:41:50:35:47:4C" --MAP5GL
    local ifname_5G = util.exec_trim("wificonf -f "..profile_5G.." get ifname")
    local iflist_5G = str2arr(ifname_5G, ";")

    local idx_5G = 0
    for k,v in pairs(iflist_5G) do
        idx_5G = idx_5G + 1
        local entry = {}
        local num_assoc_dev, assocdev_list = get_assocdev_if(v)
        entry["AssociatedDeviceNumberOfEntries"] = tostring(num_assoc_dev)
        if(num_assoc_dev > 0) then
            entry["AssociatedDevice"] = assocdev_list
        end
        
        ap_5G[tostring(idx_5G)] = entry
    end
    band_5G["AP"] = ap_5G


    --2G
    band_2G["MACAddress"] = "4D:41:50:32:34:47" --MAP2G
    local ifname_2G = util.exec_trim("wificonf -f "..profile_2G.." get ifname")
    local iflist_2G = str2arr(ifname_2G, ";")

    local idx_2G = 0
    for k,v in pairs(iflist_2G) do
        idx_2G = idx_2G + 1
        local entry = {}
        local num_assoc_dev, assocdev_list = get_assocdev_if(v)
        entry["AssociatedDeviceNumberOfEntries"] = tostring(num_assoc_dev)
        if(num_assoc_dev > 0) then
            entry["AssociatedDevice"] = assocdev_list
        end
        
        ap_2G[tostring(idx_2G)] = entry
    end
    band_2G["AP"] = ap_2G

    rv["1"] = band_5G
    rv["2"] = band_2G

    return rv
end

function get_raw_topo_info()
	local rj = c_get_vt_runtime_topology()
	-- local rj
	-- local tb_encode = luci.util.exec("cat /tmp/vt_topodump.txt")
    -- if  string.len(tb_encode) > 1 then
    --    rj = {}
    --    rj["luaTopologyInfo"] = tb_encode
    -- end
	return rj
end

function  get_ap_list(rj)
	local ap_list = {}
	local idx = 0
	if rj ~= nil and rj["luaTopologyInfo"] ~= nil then
		local r = json.decode(rj["luaTopologyInfo"])
		local r = r["topology information"]
		for _, ap in ipairs(r) do
			idx = idx + 1
			ap_list[tostring(idx)] = ap["AL MAC"]
		end
	end
	return ap_list
end

 
function is_ap(mac, ap_mac_list)
	for _, entry in pairs(ap_mac_list) do
		if string.lower(mac) ==  string.lower(entry) then
			return true	
		end
	end
	return false
end
 
function get_multi_ap_associated_devices(r)
	local multiap_sta_list={}
	local idx=0
	local assoc_device_count=0

	if r == nil or r["luaTopologyInfo"] == nil then
		local radio_tb = get_multi_ap_radio_when_mesh_disabled()
		for i_ra, tb_ra in pairs(radio_tb) do
			if tb_ra["AP"] ~= nil then
				-- luci.util.print_table(tb_ra["AP"])
				for i_ap, tb_ap in pairs(tb_ra["AP"]) do
					if tb_ap["AssociatedDevice"] ~= nil then
						for i_asso, tb_asso in pairs(tb_ap["AssociatedDevice"]) do 
							idx = idx + 1
							multiap_sta_list[idx]={}
							multiap_sta_list[idx]["MACAddress"]=tb_asso["MACAddress"]
							multiap_sta_list[idx]["APDevice_index"]="1"
							multiap_sta_list[idx]["Radio_index"]=i_ra
							multiap_sta_list[idx]["BSS_index"]=i_ap
						end
					end
				end
			end
		end
		return multiap_sta_list
    end

    r = json.decode(r["luaTopologyInfo"])
	r = r["topology information"]

	for i_dev, device in ipairs(r) do
		if device["Radio Info"] ~= nil then
			for i_ra, radio in ipairs(device["Radio Info"]) do
				if radio["BSSINFO"] ~= nil then
					for i_bss, bss in ipairs(radio["BSSINFO"]) do
						assoc_device_count = 0 --init
						if bss["connected sta info"] ~= nil then
							-- util.print_table(radio["BSSINFO"][i]["connected sta info"])
							for i_assocdev, assoc_device in ipairs(bss["connected sta info"]) do
								idx = idx + 1
								multiap_sta_list[idx]={}
								multiap_sta_list[idx]["MACAddress"]=assoc_device["STA MAC address"]
								multiap_sta_list[idx]["APDevice_index"]=i_dev
								multiap_sta_list[idx]["Radio_index"]=i_ra
								multiap_sta_list[idx]["BSS_index"]=i_bss
							end
						end
					end
				end
			end
		end
	end
	return multiap_sta_list
end

function init_assoc_dev()
	local dev = {
		PhysAddress = "",
		IPAddress = "",
		AddressSource = "",
		LeaseTimeRemaining = "",
		AssociatedDevice = "",
		InterfaceType = "Ethernet",
		HostName = "",
		Active = "true",
		Layer1Interface = "",
		IPv6Address = {
			IPAddress = ""
		},
		WANStats = {
			BytesSent = "",
			BytesReceived ="",
			PacketsSent = "",
			PacketsReceived = "",
			ErrorsSent = "",
			ErrorsReceived = ""
		}
	}
	return dev
end

function get_dhcp_info(mac, dhcp_list)
	local info = {
		AddressSource = "Static",
		LeaseTimeRemaining = "0",
		HostName = "Unknown"
	}
	for _, dhcp_entry in pairs(dhcp_list) do
		if type(dhcp_entry) == "table" and dhcp_entry.macaddr == mac then
			info["AddressSource"] = "DHCP"
			info["LeaseTimeRemaining"] = tostring(dhcp_entry.expires)

			if(dhcp_entry.hostname) then
				info["HostName"] = dhcp_entry.hostname				
			end
			break
		end
	end

	return info
end

function get_assoc_info(mac, ap_assoc_table, multiap_assoc_table)
	local found_sta_in_current_ap=false
	
	--util.perror_hieupt35("ap_assoc_table")
	--util.print_table(ap_assoc_table)
	local info = {
		InterfaceType = "Ethernet",
		AssociatedDevice = ""
	}

	for iface_idx = 1,8 do
		local list = ap_assoc_table[tostring(iface_idx)]
		if list ~= nil then
			local stalist = list.AssociatedDevice
			for sta_idx, sta in pairs(stalist) do
				if string.lower(sta.MACAddress) == mac then
					info.InterfaceType = "Wi-Fi"
					info.AssociatedDevice = "Device.WiFi.AccessPoint."..iface_idx..".AssociatedDevice."..sta_idx
					found_sta_in_current_ap = true
					break
				end
			end
		end
	end
	
	if found_sta_in_current_ap == false then
		--search in mesh table
		for sta_idx, sta in pairs(multiap_assoc_table) do
			if string.lower(sta.MACAddress) == mac then
				info.InterfaceType = "Wi-Fi"
				info.AssociatedDevice = "Device.WiFi.MultiAP.APDevice."..sta.APDevice_index..".Radio."..sta.Radio_index..".AP."..sta.BSS_index
				break
			end
		end
	end

	return info
end

function handle_hosts(id)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		local host_count = 0
		local dhcp_list = stat.dhcp_leases()
		local i = 0
		local idx
		local raw_topology_info = get_raw_topo_info()

		local multiap_assoc_table = get_multi_ap_associated_devices(raw_topology_info)
		local ap_mac_list = get_ap_list(raw_topology_info)

		local ap_assoc_table = wifi.get_all_accesspoint_associateddevice()

		for _, v in ipairs(ip.neighbors({ family = 4 })) do
			if v.mac and v.dev ~= "eth1" and is_ap(v.mac, ap_mac_list) == false then
				host_count = host_count + 1
				i = i + 1
				idx = tostring(i)
				local dev = init_assoc_dev()

				--init
				dev["PhysAddress"] = v.mac
				dev["IPAddress"] = v.dest

				--dhcp
				local dhcp_info = get_dhcp_info(v.mac, dhcp_list)
				dev["AddressSource"] = dhcp_info["AddressSource"]
				dev["LeaseTimeRemaining"] = dhcp_info["LeaseTimeRemaining"]
				dev["HostName"] = dhcp_info["HostName"]

				--interface type
				local assoc_info = get_assoc_info(v.mac, ap_assoc_table, multiap_assoc_table)
				dev["InterfaceType"] = assoc_info["InterfaceType"]
				dev["AssociatedDevice"] = assoc_info["AssociatedDevice"]

				rv[idx] = dev
			end
		end

		rv["HostNumberOfEntries"] = tostring(host_count)
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
		
	end
end

-- Hosts.AccessControl

local rule_list = {
	[1] = "rule1",
	[2] = "rule2",
	[3] = "rule3",
	[4] = "rule4",
	[5] = "rule5",
	[6] = "rule6",
	[7] = "rule7",
	[8] = "rule8",
	[9] = "rule9",
	[10] = "rule10",
}

function removespace(str)
	local nospacestring = string.gsub(str, "%s+", "") 
	return nospacestring
end

function convert_weekday_short_to_full( weekdays)

	local result = ""

	if string.find(weekdays, "Sun") then
		result = result..",".."Sunday"
	end

	if string.find(weekdays, "Mon") then
		result = result..",".."Monday"
	end

	if string.find(weekdays, "Tue") then
		result = result..",".."TuesDay"
	end

	if string.find(weekdays, "Wed") then
		result = result..",".."Wednesday"
	end

	if string.find(weekdays, "Thu") then
		result = result..",".."Thursday"
	end

	if string.find(weekdays, "Fri") then
		result = result..",".."Friday"
	end

	if string.find(weekdays, "Sat") then
		result = result..",".."Saturday"
	end

	result = result:sub(2)

	return result
end

function convert_url_table_to_string(url_tbl)
	local result = ""

	if url_tbl ~= nil then
		for k,v in pairs(url_tbl) do
			result = result..","..v
		end
	end

	result = result:sub(2)
	return result

end
function convert_endtime_to_duration(starttime, endtime)
	local result = "0"
	local st_tbl = starttime:split(":")
	local et_tbl = endtime:split(":")

	if et_tbl[1] ~= nil and et_tbl[2] ~= nil and st_tbl[1] ~= nil and st_tbl[2] ~= nil then
		result = tostring(tonumber(et_tbl[1])*3600 + tonumber(et_tbl[2])*60 - tonumber(st_tbl[1])*3600 - tonumber(st_tbl[2])*60)
	end

	return result
end

function get_access_control()
	uci = require("luci.model.uci").cursor()
    local acces_tbl = uci:get_all("parental")
    local tbl = {}

    for i = 1, 10, 1 do
    	tbl_entry = {
    		PhysAddress = "",
    		HostName = "",
    		Enable = "",
			AccessPolicy = "Deny",
			X_COM_VT_URLs = "",
			FilterType = "",
			ScheduleNumberOfEntries = "1",
			Schedule = {
				["1"] = {
					Enable = "",
					Day = "",
					StartTime = "",
					Duration = ""
				}
			}
    	}
    	tbl[tostring(i)] = tbl_entry
    end

    if acces_tbl["global"]["enabled"] ~= "0" then
    	for k,v in pairs(acces_tbl) do
    		for i = 1, 10, 1 do
    			if k == rule_list[i] then

    				local templateidx = v["template"]

    				if v["mac"] ~= nil then
    					tbl[tostring(i)]["PhysAddress"] = v["mac"]
    				end

    				if v["name"] ~= nil then
	    				tbl[tostring(i)]["HostName"] = v["name"]
	    			end


    				if acces_tbl["template"..templateidx]["FilterMode"] == "Black" then
    					tbl[tostring(i)]["AccessPolicy"] = "Deny" 
    				elseif acces_tbl["template"..templateidx]["FilterMode"] == "White" then
    					tbl[tostring(i)]["AccessPolicy"] = "Allow" 
    				end

    				if acces_tbl["template"..templateidx]["FilterType"] ~= nil then
    					tbl[tostring(i)]["FilterType"] = acces_tbl["template"..templateidx]["FilterType"]
    				end

    				if acces_tbl["template"..templateidx]["url"] ~= nil then
    					tbl[tostring(i)]["X_COM_VT_URLs"] = convert_url_table_to_string(acces_tbl["template"..templateidx]["url"])
    				end

    				if acces_tbl["template"..templateidx]["Enable"] == "No" then
    					tbl[tostring(i)]["Schedule"]["1"]["Enable"] = "false"
					else
						tbl[tostring(i)]["Schedule"]["1"]["Enable"] = "true"
    				end

    				if acces_tbl["template"..templateidx]["start_time"] ~= nil then
    					tbl[tostring(i)]["Schedule"]["1"]["StartTime"] = acces_tbl["template"..templateidx]["start_time"]
    				end

    				if acces_tbl["template"..templateidx]["stop_time"] ~= nil then
    					tbl[tostring(i)]["Schedule"]["1"]["Duration"] = convert_endtime_to_duration(tbl[tostring(i)]["Schedule"]["1"]["StartTime"], acces_tbl["template"..templateidx]["stop_time"])
    				end

    				if acces_tbl["template"..templateidx]["weekdays"] ~= nil then
    					tbl[tostring(i)]["Schedule"]["1"]["Day"] = convert_weekday_short_to_full(acces_tbl["template"..templateidx]["weekdays"])
    				end
    			end
    		end
    	end
    end 

	return tbl
end

function convert_weekday_full_to_short(days)

	local result = ""

	if string.find(days, "Sun") then
		result = result..",".."Sun"
	end

	if string.find(days, "Mon") then
		result = result..",".."Mon"
	end

	if string.find(days, "Tue") then
		result = result..",".."Tue"
	end

	if string.find(days, "Wed") then
		result = result..",".."Wed"
	end

	if string.find(days, "Thu") then
		result = result..",".."Thu"
	end

	if string.find(days, "Fri") then
		result = result..",".."Fri"
	end

	if string.find(days, "Sat") then
		result = result..",".."Sat"
	end

	result = result:sub(2)

	return result	
end

function convert_url_string_to_table(url_str)
	local result = {}
	
	local url_tbl = url_str:split(",")

	if #url_tbl < 1 then
		return ""
	else
		for i=1,#url_tbl,1 do
			result[i] = removespace(url_tbl[i])
		end
	end

	return result
end

function convert_duration_to_endtime(starttime , duration)
	local seconds = 0
	local st_tbl = starttime:split(":")
	if st_tbl[1] ~= nil and st_tbl[2] ~= nil then
		seconds = tonumber(st_tbl[1]) * 3600 + tonumber(st_tbl[2]) * 60 + tonumber(duration)
	end

	if seconds <= 0 then
	    return "23:59"
	else
		local hours = string.format("%02.f", math.floor(seconds/3600))
		local mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)))
		return hours..":"..mins
	end

end

function write_accesscontrol(tbl)
	local enable = "0"
	local rule_idx_max = "0"

	local template1 = {
		index = "1",
		weekdays = "Sun,Mon,Tue,Wed,Thu,Fri,Sat",
		name = "Template1",
		stop_time = "00:00",
		start_time = "23:59",
		Enable = "",
		FilterMode = "",
		FilterType = "",
	}
	uci:section("parental", "template", "template1", template1)

	for k,v in pairs(tbl) do
		if string.len(v["PhysAddress"]) > 3 then

			enable = "1"
			local rule_data = {
				template = "",
				index = "",
				name = "",
				mac = ""
			}

			local template_data = {
				index = "",
				weekdays = "Sun,Mon,Tue,Wed,Thu,Fri,Sat",
				name = "",
				stop_time = "23:59",
				start_time = "00:00",
				Enable = "",
				FilterMode = "",
				FilterType = ""
			}

			if tonumber(k) > tonumber(rule_idx_max) then
				rule_idx_max = k
			end

			rule_data["index"] = k
			rule_data["template"] = k
			rule_data["name"] = removespace(v["HostName"])
			rule_data["mac"] = string.lower(v["PhysAddress"])

			template_data["name"] = "Template"..k
			template_data["index"] = k
			-- if v["AccessPolicy"] == "Allow" then
			-- 	template_data["FilterMode"] = "White"
			-- elseif v["AccessPolicy"] == "Deny" then
			-- 	template_data["FilterMode"] = "Black"
			-- end
			-- AP just support Backlist
			template_data["FilterMode"] = "Black"
			
			template_data["FilterType"] = v["FilterType"]

			if v["Schedule"]["1"]["Enable"] == "true" then
				template_data["Enable"] = "Yes"
			elseif v["Schedule"]["1"]["Enable"] == "false" then
				template_data["Enable"] = "No"
			end

			if string.len(v["Schedule"]["1"]["Day"]) > 3 then
				template_data["weekdays"] = convert_weekday_full_to_short(v["Schedule"]["1"]["Day"])
			end
			
			if string.len(v["Schedule"]["1"]["StartTime"]) > 3 then
				template_data["start_time"] = v["Schedule"]["1"]["StartTime"]
			end

			template_data["stop_time"] = convert_duration_to_endtime(v["Schedule"]["1"]["StartTime"], v["Schedule"]["1"]["Duration"])
			if string.len(v["X_COM_VT_URLs"]) > 3 then
				template_data["url"] = convert_url_string_to_table(v["X_COM_VT_URLs"])
			end

			uci:section("parental", "rule", "rule"..k, rule_data)
			uci:section("parental", "template", "template"..k, template_data)
		end
	end

	uci:set("parental", "global", "enabled", enable)
	uci:set("parental", "global", "rule_idx_max", rule_idx_max)
end

function set_access_control(tbl)
 	uci = require("luci.model.uci").cursor()
	local tbl_save = get_access_control()

	for idx,cfg in pairs(tbl) do
		local is_present = 0
		for idx_s,cfg_s in pairs(tbl_save) do
			if idx_s == idx then
				is_present = 1
				if cfg["PhysAddress"] ~= nil then
					cfg_s["PhysAddress"] = cfg["PhysAddress"]
				end
	
				if cfg["HostName"] ~= nil then
					cfg_s["HostName"] = cfg["HostName"]
				end
	
				if cfg["Enable"] ~= nil then
					cfg_s["Enable"] = cfg["Enable"]
				end
	
				if cfg["AccessPolicy"] ~= nil then
					cfg_s["AccessPolicy"] = cfg["AccessPolicy"]
				end
	
				if cfg["X_COM_VT_URLs"] ~= nil then
					cfg_s["X_COM_VT_URLs"] = cfg["X_COM_VT_URLs"]
				end

				if cfg["FilterType"] ~= nil then
					cfg_s["FilterType"] = cfg["FilterType"]
				end

				if cfg["Schedule"] ~= nil then
					for k,v in pairs(cfg["Schedule"]) do
						local is_schedule = 0
						for k_s,v_s in pairs(cfg_s["Schedule"]) do
							if k_s == k then
								is_schedule = 1
								if v["Enable"] ~= nil then
									v_s["Enable"] = v["Enable"]
								end
					
								if v["Day"] ~= nil then
									v_s["Day"] = v["Day"]
								end
					
								if v["StartTime"] ~= nil then
									v_s["StartTime"] = v["StartTime"]
								end
					
								if v["Duration"] ~= nil then
									v_s["Duration"] = v["Duration"]
								end
							end
						end
						
						if is_schedule == 0 then
							cfg_s["Schedule"][k] = v
						end
					end
				end
				local index = 0
				for m,n in pairs(cfg_s["Schedule"]) do
					index = index + 1
				end
				cfg_s["ScheduleNumberOfEntries"] = tostring(index)
				tbl_save[idx_s] = cfg_s
			end
		end

		if is_present == 0 then
			local index = 0
			if cfg["Schedule"] ~= nil then
				for m,n in pairs(cfg["Schedule"]) do
					index = index + 1
				end
			end
			cfg["ScheduleNumberOfEntries"] = tostring(index)
			tbl_save[idx] = cfg
		end
	end

	uci:delete_all("parental", "template")
	uci:delete_all("parental", "rule")
	write_accesscontrol(tbl_save)
	uci:commit("parental")
	local parentalctrl_enable = uci:get("parental", "global", "enabled")
	local mesh_enable = util.exec_trim("cat /etc/mapd_cfg.txt | grep MapEnable | grep -Eo [0-9]+")
    local devrole = util.exec_trim("cat /etc/mapd_cfg.txt | grep DeviceRole | grep -Eo [0-9]+")
	local parental_state
	if util.exec_trim("ubus list | grep parental") == "parental" then
		parentald_state = "1"
	else   
		parentald_state = "0"
	end
	
	if mesh_enable == "1" then
		if devrole == "1" then
			if parentalctrl_enable == "1" then
				if parentald_state == "0" then
					luci.util.perror("[TMS]exec parental start")  
					util.exec("/etc/init.d/parental start")	
				else
					luci.util.perror("[TMS]exec parental reload")
					os.execute("/bin/ubus call parental reload")
				end
			else
				if parentald_state == "1" then
					luci.util.perror("[TMS]exec parental stop") 
					util.exec("/etc/init.d/parental stop")
				end
			end
		else
			if parentald_state == "1" then
				luci.util.perror("[TMS]exec parental stop - not run on agent")  
				util.exec("/etc/init.d/parental stop")	
			end
		end
	else
		if parentalctrl_enable == "1" then
			if parentald_state == "0" then
				luci.util.perror("[TMS]exec parental start")
				util.exec("/etc/init.d/parental start")	  
			else
				luci.util.perror("[TMS]exec parental reload")
				os.execute("/bin/ubus call parental reload")
			end
		else
			if parentald_state == "1" then
				luci.util.perror("[TMS]exec parental stop") 
				util.exec("/etc/init.d/parental stop")
			end
		end
	end

	return true
end


function handle_hosts_accesscontrol(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		rv = get_access_control()
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		if table ~= nil then
			if(set_access_control(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
