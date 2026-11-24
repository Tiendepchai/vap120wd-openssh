-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.api.faultmgmt", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")

function index()
	entry({"api", "faultmgmtnum"}, call("handle_faultmgmtnum"))
	entry({"api", "faultmgmt"})
	entry({"api", "faultmgmt", "supalarm"}, call("handle_faultmgmt"))
	entry({"api", "faultmgmt", "curalarm"}, call("handle_faultmgmt_curalarm"))
	entry({"api", "faultmgmt", "hisevent"}, call("handle_faultmgmt_hisevent"))
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

function __trim(s)
	if s then return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

function __lines(str)
    local t = {}
    local function helper(line) table.insert(t, line) return "" end
    helper((str:gsub("(.-)\r?\n", helper)))
    return t
end

function read_pipe(pipe)
    local fp = io.popen(pipe)
    local txt =  fp:read("*a")
    fp:close()
    return txt
end
 -----------------------------------------
local alarmfile = "/tmp/fmdb_currentalarm.txt"
local eventfile = "/tmp/fmdb_historyevent.txt"
function get_num_of_currentalarm()
	local idx = "0"
	local num = luci.util.exec_trim("cat "..alarmfile.." | grep numofalarm")
	if num == nil then
		return idx
	end
	local t = num:split("=")
	idx = t[2]
	-- luci.util.perror_hieupt35("get_num_of_currentalarm")
	-- luci.util.perror_hieupt35(t[2])
	return idx
end 

function get_num_of_historyevent()
	local idx = "0"
	local num = luci.util.exec_trim("cat "..eventfile.." | grep numofevent")
	if num == nil then
		return idx
	end

	local t = num:split("=")
	idx = t[2]
	-- luci.util.perror_hieupt35("get_num_of_historyevent")
	-- luci.util.perror_hieupt35(t[2])
	return idx
end 

function handle_faultmgmtnum(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
            Numofcuralarm = get_num_of_currentalarm(),
			Numofhisevent = get_num_of_historyevent()
        }
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
-----------------------------------------
local eventtype_list =
{
	[1] = "cpu.01",
	[2] = "cpu.02",
	[3] = "cpu.03",
    [4] = "cpu.04",
	[5] = "mem.01",
	[6] = "mem.02",
    [7] = "mem.03",
	[8] = "mem.04",
	[9] = "mesh.01",
	[10] = "mesh.02",
	[11] = "mesh.03",
    [12] = "mesh.04",
	[13] = "sta.01",
	[14] = "sta.02",
    [15] = "sta.03",
	[16] = "sta.04",
	[17] = "sta.05",
	[18] = "sta.06",
	[19] = "sta.07",
    [20] = "sta.08",
	[21] = "sta.09",
	[22] = "sta.10",
    [23] = "sta.11",
	[24] = "sta.12",
	[25] = "sta.13",
	[26] = "sta.14",
	[27] = "eth.01",
	[28] = "eth.02",
    [29] = "cpu.05",
	[30] = "cpu.06",
	[31] = "cpu.07",
    [32] = "mesh.05",
	[33] = "mesh.06",
	[34] = "mesh.07",
	[35] = "mesh.08"
}

local cause_list =
{
	[1] = "CPU high load",
	[2] = "CPU very high load",
	[3] = "CPU overload",
    [4] = "CPU warning cleared",
	[5] = "Memory warning",
	[6] = "Memory busy",
    [7] = "Memory very busy",
	[8] = "Memory warning cleared",
	[9] = "Wi-fi backhaul warning",
	[10] = "Wi-fi backhaul error",
	[11] = "Wi-fi backhaul Unusage",
    [12] = "Wi-fi backhaul warning cleared",
	[13] = "STA operating standard is old",
	[14] = "STA authentication failure",
    [15] = "STA data downlink rate low",
	[16] = "STA data downlink rate cleared",
	[17] = "STA data uplink rate low ",
	[18] = "STA data uplink rate low cleared",
	[19] = "STA SignalStrength low",
    [20] = "STA SignalStrength very low",
	[21] = "STA SignalStrength clear",
	[22] = "STA noise high",
    [23] = "STA noise high clear",
	[24] = "STA roaming failure",
	[25] = "STA sterring failure",
	[26] = "STA deactivated",
	[27] = "Ethernet Connection abnormal",
	[28] = "Ethernet Connection normal",
    [29] = "Temperature high",
	[30] = "Temperature very high",
	[31] = "Temperature high clear",
    [32] = "AP disconnected",
	[33] = "AP connection",
	[34] = "Noise high",
	[35] = "Noise high clear"
}

local specific_list =
{
	[1] = "90 <= CPU Usage < 95%",
	[2] = "95 <= CPU Usage < 99%",
	[3] = "99% <= CPU Usage",
    [4] = "CPU Usage < 90%",
	[5] = "90 <= Memory Percent < 95%",
	[6] = "95 <= Memory Percent< 99%",
    [7] = "99% <= Memory Percent",
	[8] = "Memory Percent < 90%",
	[9] = "-70 < Backhaul Signal Strength <= -65",
	[10] = "-80 < Backhaul Signal Strength <= -70",
	[11] = "-90 < Backhaul Signal Strength <= -80",
    [12] = "-65 < Backhaul Signal Strength",
	[13] = "OperatingStandard = a|b|g",
	[14] = "AuthenticationState = false",
    [15] = "LastDataDownlinkRate <= 13000",
	[16] = "LastDataDownlinkRate <= 13000",
	[17] = "LastDataUplinkRate <= 13000",
	[18] = "LastDataUplinkRate > 13000",
	[19] = "-80 <= RSSI < -70 dBm",
    [20] = "-90 <= RSSI < -80 dBm",
	[21] = "-70  <= RSSI",
	[22] = "SNR = RSSI - Noise < 18 dBm",
    [23] = "SNR = RSSI - Noise >= 18 dBm",
	[24] = "STA roaming failure",
	[25] = "STA steering failure",
	[26] = "STA deactivated",
	[27] = "Ethernet connection <= [Max speed] Mbps/Gbps",
	[28] = "Ethernet connection = [Max speed] Mbps/Gbps",
    [29] = "70 oC <= Temperature < 85 oC",
	[30] = "85 oC <= Temperature",
	[31] = "Temperature < 70 oC",
    [32] = "AP disconnected",
	[33] = "AP connected",
	[34] = "Backhaul Signal noise <= -85",
	[35] = "Backhaul Signal noise > -85"
}

local addtext_list =
{
	[1] = "CPUU three times in any alarm range either 2, 3 or 4, at least one time in the alarm range 2, interval of each is ",
	[2] = "CPUU three times in any alarm range either 3 or 4, at least one time in the alarm range 3, interval of each is ",
	[3] = "CPUU three times in the alarm range 4, interval of each is ",
    [4] = "CPUU three times in the alarm range lower 2, interval of each is ",
	[5] = "MEMU three times in any alarm range either 2, 3 or 4, at least one time in the alarm range 2, interval of each is ",
	[6] = "MEMU three times in any alarm range either 3 or 4, at least one time in the alarm range 3, interval of each is ",
    [7] = "MEMU three times in the alarm range 4, interval of each is ",
	[8] = "MEMU three times in the alarm range lower 2, interval of each is ",
	[9] = "Backhaul signal strength three times in any alarm range either 2, 3 or 4, at least one time in the alarm range 2, interval of each is ",
	[10] = "Backhaul signal strength three times in any alarm range either 3 or 4, at least one time in the alarm range 3, interval of each is ",
	[11] = "Backhaul signal strength three times in the alarm range 4, interval of each is ",
    [12] = "Backhaul signal strength three times in the alarm range lower 2, interval of each is ",
	[13] = "Operating Standard of Wifi client is 802.11a/b/g",
	[14] = "STA authentication failure",
    [15] = "Last data downlink rate three times is lower or equal 13000, interval of each is ",
	[16] = "Last data downlink rate three times is greater 13000, interval of each is ",
	[17] = "Last data uplink rate three times is lower 13000, interval of each is ",
	[18] = "Last data downlink rate three times is greater 13000, interval of each is ",
	[19] = "STA SignalStrength three times in this range or lower, at least one times in this range, interval of each is ",
    [20] = "STA SignalStrength three times in this range or lower, at least one times in this range, interval of each is ",
	[21] = "STA SignalStrength three times in this range, interval of each is ",
	[22] = "SNR three times in this range, interval of each is ",
    [23] = "SNR three times in this range, interval of each is ",
	[24] = "STA roaming failure",
	[25] = "STA steering failure",
	[26] = "STA deactivated",
	[27] = "The negotiation speed of Ethernet Interface lower than the max speed",
	[28] = "The negotiation speed of Ethernet Interface equals the max speed",
    [29] = "Temperature three times in any alarm range either 2, 3 or 4, at least one time in the alarm range 2, interval of each is ",
	[30] = "Temperature three times in any alarm range either 3 or 4, at least one time in the alarm range 3, interval of each is ",
	[31] = "Temp three times in the alarm range lower 2, interval of each is ",
    [32] = "AP connection time out",
	[33] = "AP Connected",
	[34] = "Backhaul noise three times in any alarm range either 2, 3 or 4, at least one time in the alarm range 2, interval of each is ",
	[35] = "Backhaul noise three times in the alarm range lower 2, interval of each is "
}

local PerceivedSeverity_list = 
{
	[1] = "Warning",
	[2] = "Minor",
	[3] = "Major",
    [4] = "Clear",
	[5] = "Warning",
	[6] = "Minor",
    [7] = "Major",
	[8] = "Clear",
	[9] = "Warning",
	[10] = "Minor",
	[11] = "Major",
    [12] = "Clear",
	[13] = "Indeterminate",
	[14] = "Indeterminate",
    [15] = "Warning",
	[16] = "Clear",
	[17] = "Warning",
	[18] = "Clear",
	[19] = "Indeterminate",
    [20] = "Warning",
	[21] = "Clear",
	[22] = "Warning",
    [23] = "Clear",
	[24] = "Indeterminate",
	[25] = "Indeterminate",
	[26] = "Indeterminate",
	[27] = "Warning",
	[28] = "Clear",
    [29] = "Warning",
	[30] = "Error",
	[31] = "Clear",
    [32] = "Indeterminate",
	[33] = "Indeterminate",
	[34] = "Warning",
	[35] = "Clear"
}

local reportmechanism = "2 Logged"

function get_AdditionText(idx, time)
	local addtext = ""
	if time > 0 then
		addtext = addtext_list[idx]..time.." ms"
	else
		addtext = addtext_list[idx]
	end

	return addtext
end

function get_alarm(idx)

	local entry_tbl =
	{
		EventType = eventtype_list[idx],
        ProbableCause = cause_list[idx],
        SpecificProblem = specific_list[idx],
        PerceivedSeverity = PerceivedSeverity_list[idx],
        ReportingMechanism = reportmechanism
	}

	return {[tostring(idx)] = entry_tbl}
end

function get_supportedalarm()
    local tbl = {}
    local tmp_entry = {}

    for i = 1,35,1 do
		tmp_entry = get_alarm(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

    return tbl
end

function handle_faultmgmt(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = get_supportedalarm()

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
----------------------------------------------------
function get_faultmgmt_currentalarm()
	local ca_tbl = {}

	local result = read_pipe("cat "..alarmfile.."")
	local xx = {}
	local index = 1
	
    for i, line in ipairs(__lines(result)) do
        local string_present = string.find(line, "notifyType")

        if #line>20 and string_present then
            xx.Obj = {string.find(line, "Obj "),7}
            xx.ID = {string.find(line, "ID"),15}
            xx.notifyType = {string.find(line, "notifyType"),15}
            xx.STATE = {string.find(line, "STATE"),6}
			xx.RAISETIME = {string.find(line, "RAISETIME"),23}
			xx.CHANGEDTIME = {string.find(line, "CHANGEDTIME"),23}
			xx.ADDTEXT = {string.find(line, "ADDTEXT"),9}
			xx.ADDINFO = {string.find(line, "ADDINFO"),63}
			
        end

        if #line>20 and not string_present then
        	local ca_tbl_entry = {
				AlarmIdentifier = "",
				AlarmRaisedTime = "",
				AlarmChangedTime = "",
				ManagedObjectInstance = "",
				EventType = "",
				ProbableCause = "",
				SpecificProblem = "",
				PerceivedSeverity = "",
				AdditionalText = "",
				AdditionalInformation = ""
			}

			local state = __trim(string.sub(line, xx.STATE[1], xx.STATE[1]+xx.STATE[2]))
			local addtext = __trim(string.sub(line, xx.ADDTEXT[1], xx.ADDTEXT[1]+xx.ADDTEXT[2]))

			ca_tbl_entry["AlarmIdentifier"] = __trim(string.sub(line, xx.ID[1], xx.ID[1]+xx.ID[2]))
			ca_tbl_entry["AlarmRaisedTime"] = __trim(string.sub(line, xx.RAISETIME[1], xx.RAISETIME[1]+xx.RAISETIME[2]))
			ca_tbl_entry["AlarmChangedTime"] = __trim(string.sub(line, xx.CHANGEDTIME[1], xx.CHANGEDTIME[1]+xx.CHANGEDTIME[2]))
			ca_tbl_entry["AdditionalInformation"] = __trim(string.sub(line, xx.ADDINFO[1], xx.ADDINFO[1]+xx.ADDINFO[2]))
			ca_tbl_entry["EventType"] = eventtype_list[tonumber(state)]
			ca_tbl_entry["SpecificProblem"] = specific_list[tonumber(state)]
			ca_tbl_entry["ProbableCause"] = cause_list[tonumber(state)]
			ca_tbl_entry["PerceivedSeverity"] = PerceivedSeverity_list[tonumber(state)]
			ca_tbl_entry["AdditionalText"] = get_AdditionText(tonumber(state), tonumber(addtext))
			ca_tbl_entry["ManagedObjectInstance"] = "Device.FaultMgmt.CurrentAlarm."..index.."."

			ca_tbl[tostring(index)] = ca_tbl_entry
			index = index + 1
        end
    end

	return ca_tbl
end

function handle_faultmgmt_curalarm()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = get_faultmgmt_currentalarm()

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
---------------------------------------------------
function get_faultmgmt_historyevent()
	local he_tbl = {}
	
	local result = read_pipe("cat "..eventfile.."")
	local xx = {}
	local index = 1

    for i, line in ipairs(__lines(result)) do
        local string_present = string.find(line, "notifyType")
        luci.util.perror_hieupt35("string_present")

        if #line>20 and string_present then
            xx.Obj = {string.find(line, "Obj "),7}
            xx.ID = {string.find(line, "ID"),15}
            xx.notifyType = {string.find(line, "notifyType"),15}
            xx.STATE = {string.find(line, "STATE"),6}
			xx.RAISETIME = {string.find(line, "RAISETIME"),23}
			xx.CHANGEDTIME = {string.find(line, "CHANGEDTIME"),23}
			xx.ADDTEXT = {string.find(line, "ADDTEXT"),9}
			xx.ADDINFO = {string.find(line, "ADDINFO"),63}
        end

        if #line>20 and not string_present then
        	local he_tbl_entry = {
				EventTime = "",
				AlarmIdentifier = "",
				NotificationType = "",
				ManagedObjectInstance = "",
				EventType = "",
				ProbableCause = "",
				SpecificProblem = "",
				PerceivedSeverity = "",
				AdditionalText = "",
				AdditionalInformation = ""
			}

			local state = __trim(string.sub(line, xx.STATE[1], xx.STATE[1]+xx.STATE[2]))
			local addtext = __trim(string.sub(line, xx.ADDTEXT[1], xx.ADDTEXT[1]+xx.ADDTEXT[2]))

			he_tbl_entry["AlarmIdentifier"] = __trim(string.sub(line, xx.ID[1], xx.ID[1]+xx.ID[2]))
			he_tbl_entry["NotificationType"] = __trim(string.sub(line, xx.notifyType[1], xx.notifyType[1]+xx.notifyType[2]))
			he_tbl_entry["EventTime"] = __trim(string.sub(line, xx.CHANGEDTIME[1], xx.CHANGEDTIME[1]+xx.CHANGEDTIME[2]))
			he_tbl_entry["AdditionalInformation"] = __trim(string.sub(line, xx.ADDINFO[1], xx.ADDINFO[1]+xx.ADDINFO[2]))
			he_tbl_entry["EventType"] = eventtype_list[tonumber(state)]
			he_tbl_entry["SpecificProblem"] = specific_list[tonumber(state)]
			he_tbl_entry["ProbableCause"] = cause_list[tonumber(state)]
			he_tbl_entry["PerceivedSeverity"] = PerceivedSeverity_list[tonumber(state)]
			he_tbl_entry["AdditionalText"] = get_AdditionText(tonumber(state), tonumber(addtext))
			he_tbl_entry["ManagedObjectInstance"] = "Device.FaultMgmt.HistoryEvent."..index.."."

			he_tbl[tostring(index)] = he_tbl_entry
			index = index + 1
        end
    end

	return he_tbl
end

function handle_faultmgmt_hisevent()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = get_faultmgmt_historyevent()

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
