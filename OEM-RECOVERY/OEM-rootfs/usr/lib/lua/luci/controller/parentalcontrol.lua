
module("luci.controller.parentalcontrol", package.seeall)

function index()
	local device_role = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local mesh_enable = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
	if mesh_enable == "1" and device_role == "2" then
		return
	end
	
	entry({"admin", "app", "parental"},
    alias("admin", "app", "parental", "prtcontrol"),
		_("Parental Control"), 5)
    
    entry({"admin", "app", "parental", "prtcontrol"},
    template("parentalcontrol/prtcontrol"),
    nil).leaf = true --leaf:stops parsing the request at this node and goes no further in the dispatching tree

    entry({"admin", "app", "parental", "info"}, call("get_parental_info")).leaf = true
    entry({"admin", "app", "parental", "apply_rule"}, call("handle_apply_rule")).leaf = true
	entry({"admin", "app", "parental", "remove_template"}, call("handle_remove_template")).leaf = true
	entry({"admin", "app", "parental", "prttemplate"},call("template_cfg")).leaf = true 
	entry({"admin", "app", "parental", "apply_template"}, call("handle_apply_template")).leaf = true
end

function handle_apply_template(idx)
	if idx == nil then return end
	--.syslog("alert", "new update to template"..idx)
	local util = require("luci.util")
	local uci = require("luci.model.uci").cursor()
	uci:delete("parental", "template"..idx)

	local data = {}
	data["index"] = tostring(idx)

	for k,v in pairs(luci.http.formvalue()) do		
		if string.find(k, "url") then
			if data["url"] then
				table.insert(data["url"], v)
			else
				data["url"] = {}
				table.insert(data["url"], v)
			end
		else
			data[k] = v
		end

	end
	--util.dumptable(data, nil, nil, nil)
	uci:section("parental", "template", "template"..idx, data)
	uci:commit("parental")
	os.execute("ubus call parental reload")
	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "parental", "prttemplate", tostring(idx)))
end

function template_cfg(idx)
	luci.template.render(
		"parentalcontrol/prttemplate", 
		{
			target_idx = tostring(idx)
		}
	)
end

function get_template_tbl()
	local uci =  require("luci.model.uci").cursor()
	local parental_tbl = uci:get_all("parental")
	local template_tbl = {}
	local rule_tbl = {}
	local template_tbl_len = 0
	local rule_tbl_len = 0
	for k, v in pairs(parental_tbl) do
		if v[".type"] == "template" then
			table.insert(template_tbl, v)
			template_tbl_len = template_tbl_len + 1
		elseif v[".type"] == "rule" then
			table.insert(rule_tbl, v)
			rule_tbl_len = rule_tbl_len + 1
		end
	end
	table.sort(template_tbl, function(k1, k2) return k1["index"] < k2["index"] end)
	return rule_tbl, template_tbl, rule_tbl_len, template_tbl_len
end

function get_parental_info()
    local util = require("luci.util")
    local uci = require("luci.model.uci").cursor()
    local rv = uci:get_all("parental")
    util.dumptable(rv, nil, nil, nil)
    luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

function handle_apply_rule()
	local uci = require("luci.model.uci").cursor()
	local data = {}
	local util = require("luci.util")
	local is_parentald_enable = "1"
	local is_parentald_need_reload = "1"
	local parental_state
	if util.exec_trim("ubus list | grep parental") == "parental" then
		parentald_state = "1"
	else   
		parentald_state = "0"
	end
	if(luci.http.formvalue()) then
		uci:delete_all("parental", "rule")
		for k,v in pairs(luci.http.formvalue()) do
			if k == "enabled" then
				uci:set("parental", "global", k, v)
				-- if parentald_state == "1" and tostring(v) == "0" then
				-- 	util.exec("/etc/init.d/parental stop")
				-- 	luci.util.perror("[parentalctrl]exec parental stop")
				-- 	is_parentald_enable = "0";
				-- elseif parentald_state == "0" and tostring(v) == "1" then
				-- 	util.exec("/etc/init.d/parental start")
				-- 	luci.util.perror("[parentalctrl]exec parental start")
				is_parentald_enable = tostring(v)
				--  end
			elseif k == "rule_idx_max" then
				uci:set("parental", "global", k, v)
			else
				idx,opt = k:match("(.+)-(.+)")
				if data[tostring(idx)] then
					data[tostring(idx)][tostring(opt)] = v
				else
					data[tostring(idx)] = {}
					data[tostring(idx)][tostring(opt)] = v
				end
			end
			
		end
	end
    table.sort(data, function(k1, k2) return k1.index < k2.index end)

	for k,v in pairs(data) do
		uci:section("parental", "rule", "rule"..k, v)
	end
		util.perror("[parentald]Apply rule to /etc/config/parental")
		uci:commit("parental")

	if parentald_state == "1" and is_parentald_enable == "0" then
		util.exec("/etc/init.d/parental stop")
		luci.util.perror("[parentalctrl]exec parental stop")
		is_parentald_enable = "0";
	elseif parentald_state == "0" and is_parentald_enable == "1" then
		util.exec("/etc/init.d/parental start")
		is_parentald_need_reload = "0"
		luci.util.perror("[parentalctrl]exec parental start")
	end

	if is_parentald_enable == "1" and is_parentald_need_reload == "1" then
		os.execute("ubus call parental reload")
	end
	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "parental"))
end

function handle_remove_template()
	if(luci.http.formvalue()) then
		local uci =  require("luci.model.uci").cursor()
		local formvalue = luci.http.formvalue()
		local target = formvalue["target"]
		local rule_tbl, template_tbl, rule_tbl_len, template_tbl_len = get_template_tbl()
		uci:delete_all("parental", "template")
		--nixio.syslog("alert", "len: "..template_tbl_len.."  target  "..target)
		if tonumber(target) == tonumber(template_tbl_len) then
			table.remove(template_tbl, template_tbl_len)		
		else
			for id = target, template_tbl_len-1, 1 do
				template_tbl[id].name = template_tbl[id+1].name
				template_tbl[id].FilterMode = template_tbl[id+1].FilterMode
				template_tbl[id].FilterType = template_tbl[id+1].FilterType
				template_tbl[id].start_time = template_tbl[id+1].start_time
				template_tbl[id].stop_time = template_tbl[id+1].stop_time
				template_tbl[id].weekdays = template_tbl[id+1].weekdays
				template_tbl[id].url = template_tbl[id+1].url
			end		
			table.remove(template_tbl, template_tbl_len)
		end
		
		for k,v in pairs(template_tbl) do
			uci:section("parental", "template", "template"..k, v)
		end

		--update index of rules
		uci:delete_all("parental", "rule")
		for k,v in pairs(rule_tbl) do
			if v["template"] > target then
				v["template"] = v["template"] - 1
			end
			uci:section("parental", "rule", "rule"..k, v)
		end

		--commit all changes
		uci:commit("parental")
		
	end
	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "parental"))	
end