module("luci.controller.firewall", package.seeall)
local util = require("luci.util")

function index()
	entry({"admin", "app", "firewall"},
		alias("admin", "app", "firewall", "overview"),
		_("Firewall"), 1)

	entry({"admin", "app", "firewall", "overview"},
		template("firewall/firewall_overview"),
		nil).leaf = true

	entry({"admin", "app", "firewall", "enable"},
		call("enable_firewall"),
		nil).leaf = true

	entry({"admin", "app", "firewall", "disable"},
		call("disable_firewall"),
		nil).leaf = true
	
	-- entry({"admin", "app", "firewall", "config"},
	-- 	alias("admin", "app", "firewall","config", "zones"),
	-- 	_("Configuration"), 2)

	-- entry({"admin", "app", "firewall", "config", "zones"},
	-- 	arcombine(cbi("firewall/zones"), cbi("firewall/zone-details")),
	-- 	_("General Settings"), 10).leaf = true

	-- entry({"admin", "app", "firewall", "config", "rules"},
	-- 	arcombine(cbi("firewall/rules"), cbi("firewall/rule-details")),
	-- 	_("Traffic Rules"), 20).leaf = true


	-- entry({"admin", "app", "firewall", "config", "custom"},
	-- 	cbi("firewall/custom"),
	-- 	_("Custom Rules"), 30).leaf = true

	
	-- entry({"admin", "app", "firewall", "forwards"},
	-- 	arcombine(cbi("firewall/forwards"), cbi("firewall/forward-details")),
	-- 	_("Port Forwards"), 40).leaf = true
end

function check_firewall_enable(uci)
	local wan_input_cfg = uci:get("firewall", "zone_wan_df_route", "input")
	if wan_input_cfg == "REJECT" then
		return true
	elseif wan_input_cfg == "ACCEPT" then
		return false
	end
end

function enable_firewall()
	local uci = require("luci.model.uci").cursor()

	if false == check_firewall_enable(uci) then -- stop
		-- Block access from wan, block tcp sync( state NEW and INVALID), block all icmp
		uci:set("firewall", "zone_wan_df_route", "input", "REJECT")

		--[[
		--Disable all PW section
		uci:foreach("firewall", "redirect",
			function(x)
				local sid = x['.name']
				uci:set("firewall", sid, "enabled", "0")
			end
		)
		]]--
		uci:commit("firewall")
		os.execute("/etc/init.d/firewall restart")
		-- Kill all conntrack sessionss
		os.execute("echo 0 > /proc/net/nf_conntrack")
		debug_write("[duyhh2] enable firewall")
	end
	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "firewall"))
end

function disable_firewall()
	local uci = require("luci.model.uci").cursor()
	if true == check_firewall_enable(uci) then -- stop
		-- Accept from WAN
		uci:set("firewall", "zone_wan_df_route", "input", "ACCEPT")

		--[[
		--Enable all PW section
		uci:foreach("firewall", "redirect",
			function(x)
				local sid = x['.name']
				uci:set("firewall", sid, "enabled", "1")
			end
		)
		]]--
		uci:commit("firewall")
		os.execute("/etc/init.d/firewall restart")
		debug_write("[duyhh2] Disable firewall")
	end
	luci.http.redirect(luci.dispatcher.build_url("admin", "app", "firewall"))
end