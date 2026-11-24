
module("luci.controller.portforward", package.seeall)

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

	entry({"admin", "app", "portforward"},
		alias("admin", "app", "portforward", "forwards"),
		_("Port Forwarding"), 4)
	
	entry({"admin", "app", "portforward", "oldfwd"},
		arcombine(cbi("portforward/forwards"), cbi("portforward/forward-details"),_("Old Port Forwarding"), 4),
		nil)
	
	entry({"admin", "app", "portforward", "noforwards"},
		template("portforward/firewall_disable"),
		nil).leaf = true --leaf:stops parsing the request at this node and goes no further in the dispatching tree

  --AP-  : refactor Port Forwarding page
	entry({"admin", "app", "portforward", "forwards"}, template("portforward/portforward"), nil).leaf = true 
  entry({"admin", "app", "portforward", "apply"}, call("handle_apply")).leaf = true
	
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
		debug_write("firewall exist!=> disable firewall to use this feature (PW)")
		luci.http.redirect(ds.build_url("admin/app/portforward/noforwards"))
		-- nixio.syslog("warning", "firewall exist!")
	else
		debug_write("firewall does not exist!")
		luci.http.redirect(ds.build_url("admin/app/portforward/forwards"))
		-- nixio.syslog("warning", "firewall does not exist!")
	end
end
]]--

function reorder_dmz()
	local uci =  require("luci.model.uci").cursor()
	local dmz_idx = -1
	local max_idx = -1
	local firewall_tbl = uci:get_all("firewall")
	for k, v in pairs(firewall_tbl) do
		if v[".name"] == "dmz" then
			dmz_idx = v[".index"]
		end
		if v[".index"] > max_idx then
			max_idx = v[".index"]
		end
	end
	uci:reorder("firewall", "dmz", max_idx)
	uci:commit("firewall")
end

function get_num_fwds()
	local util = require("luci.util")
	local uci =  require("luci.model.uci").cursor()
	local firewall_tbl = uci:get_all("firewall")
	local portforward_tbl = {}
	local num_portforward_entry = 0
	for k, v in pairs(firewall_tbl) do
		if v[".type"] == "redirect" and v["target"] == "DNAT" and v[".name"] ~= "dmz" then
			num_portforward_entry = num_portforward_entry + 1
		end
	end
	return num_portforward_entry
end

function is_dmz_section(id)
	local util = require("luci.util")
	ret = util.exec("uci show firewall.@redirect["..id.."].dest_port")
	if string.match(ret, "not found") ~= nil then
		return true
	else
		return false
	end

end

function handle_apply()

	local util = require("luci.util")
	local uci = require("luci.model.uci").cursor()
	local data = {}
	if luci.http.formvalue() ~= nil then
		--local formvalue = luci.http.formvalue()
		--util.dumptable(formvalue, nil, nil, nil)
		local operation = luci.http.formvalue("operation") 
		local index = luci.http.formvalue("index") 
		local name = luci.http.formvalue("name") 
		local proto = luci.http.formvalue("proto")
		local src_dport = luci.http.formvalue("src_dport") 
		local dest_ip = luci.http.formvalue("dest_ip") 
		local dest_port = luci.http.formvalue("dest_port")
		local enabled
		if(luci.http.formvalue("enable")) then	enabled = '1' else enabled = '0' end

		if operation == "edit" then
			util.exec("uci set firewall.@redirect["..index.."].name=\'"..name.."\'")
			util.exec("uci set firewall.@redirect["..index.."].proto=\'"..proto.."\'")
			util.exec("uci set firewall.@redirect["..index.."].src_dport=\'"..src_dport.."\'")
			util.exec("uci set firewall.@redirect["..index.."].dest_ip=\'"..dest_ip.."\'")
			util.exec("uci set firewall.@redirect["..index.."].dest_port=\'"..dest_port.."\'")
			util.exec("uci set firewall.@redirect["..index.."].enabled=\'"..enabled.."\'")
			uci:commit("firewall")
		elseif operation == "add" then
			local number_of_entry = get_num_fwds()
			local target = "DNAT"
			local src = "wandfroute"
			local dest = "lan"

			if tostring(index) == tostring(number_of_entry) then 
				uci:add("firewall", "redirect")
				uci:commit("firewall")
				reorder_dmz()	--to make sure DMZ section has lower priority than FWDs section

				util.perror(name)
				util.exec("uci set firewall.@redirect["..index.."].name=\'"..name.."\'")
				util.exec("uci set firewall.@redirect["..index.."].proto=\'"..proto.."\'")
				util.exec("uci set firewall.@redirect["..index.."].src_dport=\'"..src_dport.."\'")
				util.exec("uci set firewall.@redirect["..index.."].dest_ip=\'"..dest_ip.."\'")
				util.exec("uci set firewall.@redirect["..index.."].dest_port=\'"..dest_port.."\'")
				util.exec("uci set firewall.@redirect["..index.."].enabled=\'"..enabled.."\'")

				util.exec("uci set firewall.@redirect["..index.."].target=\'"..target.."\'")
				util.exec("uci set firewall.@redirect["..index.."].src=\'"..src.."\'")
				util.exec("uci set firewall.@redirect["..index.."].dest=\'"..dest.."\'")
				uci:commit("firewall")
			end

		elseif operation == "del" then
			local index = {}
			local ret 
			local tmp
			local number_of_entry = get_num_fwds()
			if number_of_entry > 0  then
				for k,v in pairs(luci.http.formvalue()) do
					tmp = string.match(k, "del_(%d+)")
					table.insert(index, tmp)
				end
				table.sort(index, function(x, y) return x > y end)
				util.dumptable(index, nil, nil, nil)

				for _, id in pairs(index) do
					if is_dmz_section(id) == false then
						util.exec("uci del firewall.@redirect["..id.."]")
						uci:commit("firewall")
					end
				end
			end
		end
		os.execute("/etc/init.d/firewall reload")
	end

    luci.http.redirect(luci.dispatcher.build_url("admin", "app", "portforward"))
end