module("luci.controller.api.vendorlogfile", package.seeall)

local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local nixio = require("nixio")
local os = require("os")
local mtkwifi = require("mtkwifi")


function index()
    entry({"api","vendorlogfile"}, call("handle_vendorlogfile"))
end

local logfile_name_list =
{
	[1] = "logmesh",
	[2] = "messages",
	[3] = "wifilog",
	[4] = "signal.log",
	[5] = "vt_rebootreason"
}

function get_vendorlogfile(idx)
	local this_entry_tbl =
	{
		Alias = "N/A",
		Name = "",
		MaximumSize = "",
		Persistent = "",
	}
    this_entry_tbl["Name"] = logfile_name_list[idx]
    if idx > 3 then
        this_entry_tbl["Persistent"] = "true"
    else
        this_entry_tbl["Persistent"] = "false"
    end

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_vendorlogfile()
	local tbl = {}
	local tmp_entry = {}

	for i = 1,5,1 do
		tmp_entry = get_vendorlogfile(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

	return tbl
end

function handle_vendorlogfile(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_vendorlogfile(tonumber(idx))
		else
			rv=get_all_vendorlogfile()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
