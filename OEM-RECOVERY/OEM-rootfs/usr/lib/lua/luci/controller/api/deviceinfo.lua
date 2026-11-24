
-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.


module("luci.controller.api.deviceinfo", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")

function index()
	entry({"api", "device_info"}, call("handle_deviceinfo"))
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
 

function get_firmware_version()
	local fileversion = io.open("/usr/etc/version","r")
  	local firmversion = fileversion:read("*line")
	return firmversion
end

function get_active_firmware_image()
	local str = io.popen("cat /proc/cmdline","r")
  	local cmdline = str:read("*line")
	local t = cmdline:split(" ")
	local pair
	local activefirmware = ""
	for _,param in pairs(t) do
		pair = param:split("=")
		if pair[1] == "bootflag" then
			activefirmware = pair[2]
			break
		end
	end
	activefirmware = "Device.DeviceInfo.ActiveFirmwareImage."..activefirmware.."."
	return activefirmware
end

function get_boot_firmware_image()
	local str = io.popen("fw_printenv bootflag","r")
  	local bootfirmware = str:read("*line")
	local t = bootfirmware:split("=")	
	bootfirmware = "Device.DeviceInfo.ActiveFirmwareImage." .. t[2] .. "."
	return bootfirmware
end

function set_boot_firmware_image(img)
	local t = img:split(".")
	local image_no = t[4]
	if image_no == "1" or image_no == "2" then
		util.exec("fw_setenv bootflag "..image_no)
		return true
	else
		return false
	end
end

function get_description(img)
	local map_cfgs = mtkwifi.load_profile(mtkwifi.__easymesh_profile_path())
	local devRole = map_cfgs.DeviceRole
	local mapenable = map_cfgs.MapEnable
	if tonumber(mapenable) == 1 then
		if tonumber(devRole) == 1 then
			device_role = "Controller";
		else
			device_role = "Agent";
		end
	else
		device_role = "StandAlone";
	end
	return device_role
end

function get_DeviceName()
	local result = luci.util.trim(luci.util.exec("/sbin/uci get device.deviceinfo.devicename"))
	return result
end

function set_DeviceName(name)
	luci.util.exec("/sbin/uci set device.deviceinfo.devicename='"..name.."'")
	luci.util.exec("/sbin/uci commit device")
	return true
end

function get_memorystatus()
	local memtbl = {}

	memtbl["Total"] =luci.util.trim(luci.util.exec("cat /proc/meminfo | grep MemTotal | grep -Eo '[0-9]+'")) 
	memtbl["Free"] = luci.util.trim(luci.util.exec("cat /proc/meminfo | grep MemFree | grep -Eo '[0-9]+'"))
	return memtbl
end

function get_cpustatus()
	local cputbl = {}

	local result = luci.util.exec("cat /proc/stat | grep 'cpu '")
	local result_tbl = result:split(" ")
	local cpu = tonumber(result_tbl[5])/(tonumber(result_tbl[2])+tonumber(result_tbl[3])+tonumber(result_tbl[4])+tonumber(result_tbl[5])+tonumber(result_tbl[6])+tonumber(result_tbl[7])
										+tonumber(result_tbl[8])+tonumber(result_tbl[9])+tonumber(result_tbl[10])+tonumber(result_tbl[11]))
	local cpuusage = 100 - 100*cpu + 0.5

	if cpuusage < 10 then
		cpuusage = cpuusage + 20
	elseif cpuusage >= 10 and cpuusage < 20 then
		cpuusage = cpuusage + 10
	end

	cputbl["CPUUsage"] = string.format("%d", math.floor(cpuusage))
	return cputbl
end

function get_temperaturestatus()
	local tbl = {
		TemperatureSensor = {
			["1"] = {
				Name = "CPU",
				Value = "50",
			}
		}
	}

	local strcur = luci.util.exec_trim("/usr/sbin/iwpriv ra0 stat | grep Temperature")
	local cur_tbl = strcur:split("=")
	if cur_tbl[2] ~= nil then
		tbl["TemperatureSensor"]["1"]["Value"] = string.trim(cur_tbl[2])
	end
	return tbl
end

function set_deviceinfo_params(table)
	local imgstatus = ""
	local devstatus = ""
	local status = "Success"
	local value = table["BootFirmwareImage"]
	if value ~= nil then
		if set_boot_firmware_image(value) then
			imgstatus = "Success"
		else
			imgstatus = "Failed"
		end
	end

	local name = table["X_DeviceName"]
	if name ~= nil then
		if set_DeviceName(name) then
			devstatus = "Success"
		else
			devstatus = "Failed"
		end
	end

	if imgstatus == "Failed" and devstatus == "Failed" then
		status = "Failed"
	elseif  imgstatus == "Failed" then
		status = "Failed - not set firmware image"
	elseif devstatus == "Failed" then
		status = "Failed - not set devicename"
	end

	return status
end

function handle_deviceinfo()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			HardwareVersion = "0.1",
			SoftwareVersion = get_firmware_version(),
			ActiveFirmwareImage = get_active_firmware_image(),
			BootFirmwareImage = get_boot_firmware_image(),
			X_DeviceName = get_DeviceName(),
			Description = get_description(),
			MemoryStatus = get_memorystatus(),
			ProcessStatus = get_cpustatus(),
			TemperatureStatus = get_temperaturestatus()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = {Status = "Fail"}
		if (table ~= nil) then
			rv.Status = set_deviceinfo_params(table)
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end