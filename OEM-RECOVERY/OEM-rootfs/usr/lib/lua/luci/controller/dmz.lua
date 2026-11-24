
module("luci.controller.dmz", package.seeall)

local http = require("luci.http")
local ds = require "luci.dispatcher"
local logDisable = 0

function debug_write(...)
    -- luci.http.write(...)
	local nixio = require("nixio")
    if logDisable == 1 then
        return
    end
    local syslog_msg = "";
    local ff = io.open("/tmp/dbgmsg", "a")
    local nargs = select('#',...)

    for n=1, nargs do
      local v = select(n,...)
      if (type(v) == "string" or type(v) == "number") then
        ff:write(v.." ")
        syslog_msg = syslog_msg..v.." ";
      elseif (type(v) == "boolean") then
        if v then
          ff:write("true ")
          syslog_msg = syslog_msg.."true ";
        else
          ff:write("false ")
          syslog_msg = syslog_msg.."false ";
        end
      elseif (type(v) == "nil") then
        ff:write("nil ")
        syslog_msg = syslog_msg.."nil ";
      else
        ff:write("<Non-printable data type = "..type(v).."> ")
        syslog_msg = syslog_msg.."<Non-printable data type = "..type(v).."> ";
      end
    end
    ff:write("\n")
    ff:close()
    nixio.syslog("debug", syslog_msg)
end

function index()
	local device_role = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local mesh_enable = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
	if mesh_enable == "1" and device_role == "2" then
		return
	end
	entry({"admin", "app", "dmz"},
		alias("admin", "app", "dmz", "cfgdmz"),
		_("DMZ"), 5)
	
  entry({"admin", "app", "dmz", "cfgdmz"},
    template("dmz/dmz"),
		nil).leaf = true --leaf:stops parsing the request at this node and goes no further in the dispatching tree

  entry({"admin", "app", "dmz", "apply"}, call("handle_apply")).leaf = true
	--entry({"admin", "app", "dmz", "nodmz"},
	--	template("dmz/firewall_disable"),
	--	nil).leaf = true --leaf:stops parsing the request at this node and goes no further in the dispatching tree

end

--[[
function check_firewall_enable()
	local nixio = require("nixio")
	local process = io.popen('iptables -nvL | grep zone_wandfroute_src_REJECT; echo $?') -- echo return code of last run command
	local lastline
	for line in process:lines() do
		lastline = line
	end
	if 0 == tonumber(lastline) then
		debug_write("firewall exist!=>disable firewall to use dmz")
    luci.http.redirect(ds.build_url("admin/app/dmz/nodmz"))
		-- nixio.syslog("warning", "firewall exist!")
		-- luci.http.redirect(ds.build_url("admin/app/dmz/hasdmz"))
	else
		debug_write("firewall does not exist!")
    luci.http.redirect(ds.build_url("admin/app/dmz/hasdmz"))
		-- nixio.syslog("warning", "firewall does not exist!")
	end
end
]]--

function ip_validate(ip)
	local R = {ERROR = 0, IPV4 = 1, STRING = 2}
	if type(ip) ~= "string" then return R.ERROR end

	local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
		if #chunks == 4 then
			for _,v in pairs(chunks) do
				if tonumber(v) > 255 then return R.STRING end
				end
		return R.IPV4
	end
	return R.STRING
end


function handle_apply()
	local uci = require("luci.model.uci").cursor()
	local util = require("luci.util")
	local enable = luci.http.formvalue("cb_enable_dmz") 
	local dest_ip = luci.http.formvalue("submit_ip") 

	if enable then
		if dest_ip then
			local ip_check = ip_validate(dest_ip)
			if ip_check == 1 then
				uci:set("firewall", "dmz", "enabled", "1")
				uci:set("firewall", "dmz", "dest_ip", dest_ip)
			else
				util.perror("DMZ invalid IP")
			end
		else			
			util.perror("DMZ error when getting IP")
		end
	else
		uci:set("firewall", "dmz", "enabled", "0")
		uci:delete("firewall", "dmz", "dest_ip")
	end
	uci:commit("firewall")
	os.execute("/etc/init.d/firewall reload")

	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "dmz"))
end
