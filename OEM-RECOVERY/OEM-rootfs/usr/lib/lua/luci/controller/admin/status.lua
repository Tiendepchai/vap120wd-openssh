-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.status", package.seeall)
local mtkwifi = require("mtkwifi")
local http = require("luci.http")
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")

function index()
--[[	entry({"admin", "status"}, alias("admin", "status", "overview"), _("Status"), 20).index = true
	entry({"admin", "status", "overview"}, template("admin_status/index"), _("Overview"), 1)
	entry({"admin", "status", "iptables"}, call("action_iptables"), _("Firewall"), 2).leaf = true
	entry({"admin", "status", "routes"}, template("admin_status/routes"), _("Routes"), 3)
	entry({"admin", "status", "syslog"}, call("action_syslog"), _("System Log"), 4)
	entry({"admin", "status", "dmesg"}, call("action_dmesg"), _("Kernel Log"), 5)
	entry({"admin", "status", "processes"}, cbi("admin_status/processes"), _("Processes"), 6)

	entry({"admin", "status", "realtime"}, alias("admin", "status", "realtime", "load"), _("Realtime Graphs"), 7)

	entry({"admin", "status", "realtime", "load"}, template("admin_status/load"), _("Load"), 1).leaf = true
	entry({"admin", "status", "realtime", "load_status"}, call("action_load")).leaf = true

	entry({"admin", "status", "realtime", "bandwidth"}, template("admin_status/bandwidth"), _("Traffic"), 2).leaf = true
	entry({"admin", "status", "realtime", "bandwidth_status"}, call("action_bandwidth")).leaf = true

	entry({"admin", "status", "realtime", "wireless"}, template("admin_status/wireless"), _("Wireless"), 3).leaf = true
	entry({"admin", "status", "realtime", "wireless_status"}, call("action_wireless")).leaf = true

	entry({"admin", "status", "realtime", "connections"}, template("admin_status/connections"), _("Connections"), 4).leaf = true
	entry({"admin", "status", "realtime", "connections_status"}, call("action_connections")).leaf = true

	entry({"admin", "status", "nameinfo"}, call("action_nameinfo")).leaf = true
	]]
	entry({"admin", "easy_setup"}, template("admin_status/easy_setup"), _("Easy Setup"), 1).index = true
	entry({"admin", "easy_setup", "info"}, call("easy_setup_info")).leaf = true
	entry({"admin", "easy_setup", "apply_cfg"}, call("easy_setup_apply")).leaf = true
	entry({"admin", "easy_setup", "loading"}, template("admin_status/loading")).leaf = true
	entry({"admin", "easy_setup", "apply_status"}, call("handle_apply")).leaf = true

-- june
	entry({"admin", "status"}, alias("admin", "status", "overview"), _("Status"), 20)
	entry({"admin", "status", "overview"}, template("admin_status/index"), _("Overview"), 2)
--AP-77

--    entry({"admin", "status", "newtopology"}, template("admin_status/mtk_wifi_multi_ap"), _("EasyMesh Status"), 5);
	local device_role = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local mesh_enable = luci.util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
	if mesh_enable == "1" and device_role == "1" then
		entry({"admin","topology"}, template("admin_status/vt_topology"), _("Topology"), 6);
	end
--AP-76
	entry({"admin", "status", "devices"}, template("admin_status/connected_devices"), _("Connected devices"), 3)
-- june end
end

-- june
function action_show_topology()
end
-- june end

function action_iptables()
	if luci.http.formvalue("zero") then
		if luci.http.formvalue("zero") == "6" then
			luci.util.exec("ip6tables -Z")
		else
			luci.util.exec("iptables -Z")
		end
		luci.http.redirect(
			luci.dispatcher.build_url("admin", "status", "iptables")
		)
	elseif luci.http.formvalue("restart") == "1" then
		luci.util.exec("/etc/init.d/firewall reload")
		luci.http.redirect(
			luci.dispatcher.build_url("admin", "status", "iptables")
		)
	else
		luci.template.render("admin_status/iptables")
	end
end

function action_bandwidth(iface)
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -i %q 2>/dev/null" % iface)
	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_wireless(iface)
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -r %q 2>/dev/null" % iface)
	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_load()
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -l 2>/dev/null")
	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_connections()
	local sys = require "luci.sys"

	luci.http.prepare_content("application/json")

	luci.http.write("{ connections: ")
	luci.http.write_json(sys.net.conntrack())

	local bwc = io.popen("luci-bwc -c 2>/dev/null")
	if bwc then
		luci.http.write(", statistics: [")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end

	luci.http.write(" }")
end

function action_nameinfo(...)
	local i
	local rv = { }
	for i = 1, select('#', ...) do
		local addr = select(i, ...)
		local fqdn = nixio.getnameinfo(addr)
		rv[addr] = fqdn or (addr:match(":") and "[%s]" % addr or addr)
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end
function save_easymesh_driver_profile(easymesh_cfgs)
    local profiles = mtkwifi.search_dev_and_profile()
    -- Following EasyMesh settings must be written to all DAT files of Driver,
    --    1. MapEnable
    --    2. MAP_Turnkey
    for _,profile in pairs(profiles) do
        local driver_cfgs = mtkwifi.load_profile(profile)
        driver_cfgs['MapEnable'] = easymesh_cfgs['MapEnable']
        driver_cfgs['MAP_Turnkey'] = tonumber(easymesh_cfgs['MapEnable']) == 1 and "1" or "0"
        __mtkwifi_save_profile(driver_cfgs, profile, false)
    end
end
function __mtkwifi_save_profile(cfgs, path, isProfileSettingsAppliedToDriver)
    -- Create the applied settings backup file before saving the new profile settings only if it does not exist.
    if not mtkwifi.exists(mtkwifi.__profile_applied_settings_path(path)) then
        os.execute("cp -f "..path.." "..mtkwifi.__profile_applied_settings_path(path))
    end
    if isProfileSettingsAppliedToDriver then
        -- It means the some context based profile settings to be saved in DAT file is already applied to the driver.
        -- Find the profile settings which are not applied to the driver before saving the new profile settings
        local diff = mtkwifi.diff_profile(path)
        mtkwifi.save_profile(cfgs, path)
        -- If there are any settings which are not applied to the driver, then do NOT copy and WebUI will display the "need reload to apply changes" message
        -- Otherwise, copy the new profile settings and WebUI will NOT display the "need reload to apply changes" message
        if next(diff) == nil then
            os.execute("cp -f "..path.." "..mtkwifi.__profile_applied_settings_path(path))
        end
    else
        mtkwifi.save_profile(cfgs, path)
    end
end

function easy_setup_info()
	local util = require("luci.util")
	local uci = require("luci.model.uci").cursor("/etc/nw_ctrl_config")
	local rv = {}
	local mesh_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
	local device_role = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local ssid_24 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get SSID1")
	local pwd_24 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get WPAPSK1")
	local state_24 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get State")
	local state_ssid_24 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get EnableSSID")
	local wifi24_mode = mtkwifi.token_get(util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get AuthMode"), 1, "WPA2PSK")
	local wifi5_mode = mtkwifi.token_get(util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get AuthMode"), 1, "WPA2PSK")
	local ssid_5 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get SSID1")
	local pwd_5 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get WPAPSK1")
	local state_5 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get State")
	local state_ssid_5 = util.exec_trim("wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get EnableSSID")
	local band_steer_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get BSEnable")
	local wan_dfroute = uci:get("network", "globals", "wan_df_route")
	local wan_prot = uci:get("network", wan_dfroute, "proto")
	local usrname
	local pwd
	local vid
	local used_vid_list = {}
	if wan_prot == "pppoe" then
		usrname = uci:get("network", wan_dfroute, "username")
		pwd = uci:get("network", wan_dfroute, "password")
		vid = uci:get("network", wan_dfroute, "_vlanid")
	end
	local ipaddr
	local ip6addr
	local ntm = require("luci.model.network").init()
	local wan = ntm:get_network(wan_dfroute)
	local wan6 = ntm:get_network(wan_dfroute.."_ip6")
	if wan ~= nil then
		ipaddr = wan:ipaddr()
	end
	if wan6 ~= nil then
		ip6addr = wan6:ip6addr()
	end
	rv["mesh"] = {}
	rv["wifi"] = {}
	rv["wifi"]["wifi_24"] = {}
	rv["wifi"]["wifi_5"] = {}
	rv["wan"] = {}

	rv["mesh"]["mesh_enable"] = mesh_enable
	rv["mesh"]["device_role"] = device_role
	rv["wifi"]["wifi_24"]["ssid_24"] = ssid_24
	rv["wifi"]["wifi_24"]["pwd_24"] = pwd_24
	rv["wifi"]["wifi_24"]["auth_mode"] = wifi24_mode
	if state_24 == "up" and mtkwifi.token_get(state_ssid_24, 1, "1") == "1" then
		rv["wifi"]["wifi_24"]["state"] = "up"
	else
		rv["wifi"]["wifi_24"]["state"] = "down"
	end
	rv["wifi"]["wifi_5"]["ssid_5"] = ssid_5
	rv["wifi"]["wifi_5"]["pwd_5"] = pwd_5
	rv["wifi"]["wifi_5"]["auth_mode"] = wifi5_mode
	if state_5 == "up" and mtkwifi.token_get(state_ssid_5, 1, "1") == "1" then
		rv["wifi"]["wifi_5"]["state"] = "up"
	else
		rv["wifi"]["wifi_5"]["state"] = "down"
	end
	rv["wifi"]["bs_enable"] = band_steer_enable
	rv["wan"]["protocol"] = wan_prot
	if wan_prot == "pppoe" then
		rv["wan"]["username"] = usrname
		rv["wan"]["password"] = pwd
		rv["wan"]["vid"] = vid
	end
	rv["wan"]["ipaddr"] = ipaddr or "N/A"
	rv["wan"]["ip6addr"] = ip6addr or "N/A"

	uci:foreach("network", "interface", 
		function(s)
			if s["_vlanid"] ~= nil and s[".name"] ~= wan_dfroute then
				table.insert(used_vid_list, s["_vlanid"])
			end
		end
	)
	if next(used_vid_list) then
		rv["wan"]["used_vid"] = used_vid_list
	end
	rv["status"] = "DONE"
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
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

function dump_uci_data(dst_cfg, type, name, tbl, uci)
	local a = {}
	for k,v in pairs(tbl) do
		-- uci:section("network_controller", v[".type"], v[".name"], v)
		table.insert(a, v)
	end
	table.sort(a, function (k1, k2) return k1[".index"] < k2[".index"] end)
	for k,v in ipairs(a) do
		local stype = type or v[".type"]
		local sname = name or v[".name"]
		uci:section(dst_cfg, stype, sname, v)
	end
end

function backup_network_config(next_backup_role, uci)
	-- local backup_role = uci:get("network_backup", "backup_role", "role")
	util.perror("[fanwar] backup_network_config, next_backup_role "..next_backup_role)
	local backup_cfg = uci:get_all("network_backup")
	local cur_network_cfg = uci:get_all("network")
	local cur_dhcpd_cfg = uci:get("dhcp", "lan", "ignore") or "0"
	local backup_role = backup_cfg["backup_role"]["role"]

	uci:set("dhcp", "lan", "ignore", backup_cfg["lan_dhcp"]["ignore"])
	uci:commit("dhcp")
	uci:delete_all("network_backup", "interface")
	uci:delete_all("network_backup", "globals")
	uci:delete_all("network_backup", "dhcp")
	uci:delete_all("network", "interface")
	uci:delete_all("network", "globals")
	backup_cfg["lan_dhcp"] = nil
	backup_cfg["backup_role"] = nil
	dump_uci_data("network_backup", nil, nil, cur_network_cfg, uci)
	dump_uci_data("network", nil, nil, backup_cfg, uci)
	uci:set("network_backup", "lan_dhcp", "dhcp")
	uci:set("network_backup", "lan_dhcp", "ignore", cur_dhcpd_cfg)
	uci:set("network_backup", "backup_role", "role", next_backup_role)
	uci:commit("network_backup")
end

function switch_network_config(to)
	local target = "/etc/"..to.."/network"
	util.exec("ln -sf "..target.." /etc/config/network")
	util.perror("[fanwar] ".."ln -sf "..target.." /etc/config/network")
end

function config_mesh_profile(cur_role, request_role, bndstr_enable)
	util.perror("[fanwar] config_mesh_profile, cur_role "..cur_role.." request_role "..request_role)
	local uci = require"luci.model.uci".cursor("/etc/config")
	local map_cfgs = mtkwifi.load_profile(mtkwifi.__easymesh_profile_path())
	local bss_config_controller = "\""..mtkwifi.get_bss_config_priority().."\""
    local bss_config_agent = "\"rax0;rax1;rax2;rax3;ra0;ra1;ra2;ra3;apclix0;apcli0\""
	if request_role == "0" then
		-- mesh is disabled
		util.exec("wificonf -f /etc/mapd_cfg.txt set MapEnable 0")
		if cur_role == "2" then
			util.exec("cof_cli write MultiAPRole 1")
			switch_network_config("nw_ctrl_config")
			uci:set("dhcp", "lan", "dhcpv6", "server")
			uci:set("dhcp", "lan", "ra", "server")
			uci:set("dhcp", "lan", "ignore", uci:get("dhcp", "lan", "_ctrl_ignore") or "0") 
		end
	elseif request_role == "1" then
		-- controller
		-- should not down apcli0 here to prevent bugs when switch from agent to ctrl
		-- util.exec("ifconfig apcli0 down")
		-- util.exec("ifconfig apclix0 down")
		util.exec("wificonf -f /etc/mapd_cfg.txt set MapEnable 1")
		util.exec("wificonf -f /etc/mapd_cfg.txt set DeviceRole 1")
		util.exec("wificonf -f /etc/map_cfg.txt set map_root 1")
		util.exec("wificonf -f /etc/map_cfg.txt set map_agent 0")
		util.exec("wificonf -f /etc/map_cfg.txt set lan1 eth0.1")
		util.exec("wificonf -f /etc/map_cfg.txt set lan2 eth0.2")
		util.exec("wificonf -f /etc/map_cfg.txt set bss_config_priority "..bss_config_controller)
		util.exec("wificonf -f /etc/mapd_cfg.txt set bss_config_priority "..bss_config_controller)
		util.exec("wificonf -f /etc/mapd_cfg.txt set DhcpCtl 0")
		if cur_role == "2" then
			util.exec("cof_cli write MultiAPRole 1")
			switch_network_config("nw_ctrl_config")
			uci:set("dhcp", "lan", "dhcpv6", "server")
			uci:set("dhcp", "lan", "ra", "server")
			uci:set("dhcp", "lan", "ignore", uci:get("dhcp", "lan", "_ctrl_ignore") or "0") 
		end
	elseif request_role == "2" then
		-- agent
		util.exec("wificonf -f /etc/mapd_cfg.txt set MapEnable 1")
		util.exec("wificonf -f /etc/mapd_cfg.txt set DeviceRole 2")
		util.exec("wificonf -f /etc/map_cfg.txt set map_root 0")
		util.exec("wificonf -f /etc/map_cfg.txt set map_agent 1")
		util.exec("wificonf -f /etc/map_cfg.txt set lan1 eth0")
		util.exec("wificonf -f /etc/map_cfg.txt set lan2 eth0")
		util.exec("wificonf -f /etc/map_cfg.txt set bss_config_priority "..bss_config_agent)
		util.exec("wificonf -f /etc/mapd_cfg.txt set bss_config_priority "..bss_config_agent)
		util.exec("wificonf -f /etc/mapd_cfg.txt set DhcpCtl 1")
		if cur_role ~= "2" then
			util.exec("cof_cli write MultiAPRole 2")
			switch_network_config("nw_agent_config")
			uci:set("dhcp", "lan", "dhcpv6", "disabled")
			uci:set("dhcp", "lan", "ra", "disabled")
			uci:set("dhcp", "lan", "_ctrl_ignore", uci:get("dhcp", "lan", "ignore"))
			uci:set("dhcp", "lan", "ignore", "0")
		end
	end
	-- some extra map_cfg
	if bndstr_enable ~= nil then
		util.exec("wificonf -f /etc/mapd_cfg.txt set BSEnable "..bndstr_enable)
	end
	uci:commit("dhcp")
	uci:commit("network")
end

function config_mesh_agent(cfgs)
	local profile_24 = "/etc/wireless/mt7615/mt7615.1.2G.dat"
	local profile_5 = "/etc/wireless/mt7615/mt7615.1.5G.dat"
	local cfgs_24 = mtkwifi.load_profile(profile_24)
	local cfgs_5 = mtkwifi.load_profile(profile_5)
	-- local bndstr_enble = cfgs["bstr_enable"] and "1" or "0"
	config_mesh_profile(cfgs["cur_role"], "2", nil)
	cfgs_24["ApCliEnable"] = "1"
	cfgs_5["ApCliEnable"] = "1"
	cfgs_24["MapEnable"] = "1"
	cfgs_5["MapEnable"] = "1"
	cfgs_24["MAP_Turnkey"] = "1"
	cfgs_5["MAP_Turnkey"] = "1"
	__mtkwifi_save_profile(cfgs_24, profile_24, true)
	__mtkwifi_save_profile(cfgs_5, profile_5, true)
	mtkwifi.save_easymesh_bss_cfgs(mtkwifi.get_bss_cfgs_from_dat())
end

function config_gw(cfgs, request_ctrl)
	-- config Wifi
	util.perror("[fanwar] config_gw ")
	local ssid_24 = cfgs["ssid_wifi24"] or "N/A"
	local pwd_24 = cfgs["pwd_wifi24"] or "N/A"
	local ssid_5 = cfgs["ssid_wifi5"] or "N/A"
	local pwd_5 = cfgs["pwd_wifi5"] or "N/A"
	local bndstr_enble = cfgs["bstr_enable"] and "1" or "0"
	local profile_24 = "/etc/wireless/mt7615/mt7615.1.2G.dat"
	local profile_5 = "/etc/wireless/mt7615/mt7615.1.5G.dat"
	local cfgs_24 = mtkwifi.load_profile(profile_24)
	local cfgs_5 = mtkwifi.load_profile(profile_5)

	if bndstr_enble == "1" then
		ssid_5 = ssid_24
		pwd_5 = pwd_24	
		local authmode_str_24 = cfgs_24["AuthMode"]
		local authmode_str_5 = cfgs_5["AuthMode"]
		local enctype_str_24 = cfgs_24["EncrypType"]
		local enctype_str_5 = cfgs_5["EncrypType"]

		cfgs_5["AuthMode"] = mtkwifi.token_set(authmode_str_5, 1, mtkwifi.token_get(authmode_str_24, 1, "WPA2PSK"))
		cfgs_5["EncrypType"] = mtkwifi.token_set(enctype_str_5, 1, mtkwifi.token_get(enctype_str_24, 1, "AES"))
	end
	cfgs_24["SSID1"] = ssid_24
	cfgs_24["WPAPSK1"] = pwd_24
	cfgs_24["ApCliEnable"] = "0"
	cfgs_5["SSID1"] = ssid_5
	cfgs_5["WPAPSK1"] = pwd_5
	cfgs_5["ApCliEnable"] = "0"
	
	cfgs_24["MapEnable"] = request_ctrl == "1" and "1" or "0"
	cfgs_24["MAP_Turnkey"] = cfgs_24["MapEnable"]
	cfgs_5["MapEnable"] = cfgs_24["MapEnable"]
	cfgs_5["MAP_Turnkey"] = cfgs_24["MapEnable"]

	config_mesh_profile(cfgs["cur_role"], request_ctrl, bndstr_enble)
	__mtkwifi_save_profile(cfgs_24, profile_24, true)
	__mtkwifi_save_profile(cfgs_5, profile_5, true)

	mtkwifi.save_easymesh_bss_cfgs(mtkwifi.get_bss_cfgs_from_dat())
	-- config WAN
	local uci = require"luci.model.uci".cursor("/etc/config")
	local wan_dfroute = uci:get("network", "globals", "wan_df_route")
	if cfgs["protocol"] ~= nil then
		if cfgs["protocol"] ~= "static" then
			-- in case previous proto was Static, need some clean up
			local prev_proto = uci:get("network", wan_dfroute, "proto")
			if prev_proto == "static" then
				uci:delete("network", wan_dfroute, "ipaddr")
				uci:delete("network", wan_dfroute, "netmask")
				uci:delete("network", wan_dfroute, "dns")
				uci:delete("network", wan_dfroute, "gateway")
			end 
			-- 
			uci:set("network", wan_dfroute, "proto", cfgs["protocol"])
			uci:set("network", wan_dfroute, "_service", "internet")
			if cfgs["protocol"] == "pppoe" then
				uci:set("network", wan_dfroute, "username", cfgs["pppoe_usrname"])
				uci:set("network", wan_dfroute, "password", cfgs["pppoe_pwd"])
				uci:set("network", wan_dfroute, "_vlanid", cfgs["pppoe_vlanid"])
				if cfgs["pppoe_vlanid"] == "0" then
					uci:set("network", wan_dfroute, "ifname", "eth1")
				else				
					uci:set("network", wan_dfroute, "ifname", "eth1."..cfgs["pppoe_vlanid"])
				end
				uci:delete("network", wan_dfroute.."_ip6")
				uci:section("network", "interface", wan_dfroute.."_ip6", {ifname = "@"..wan_dfroute, proto = "dhcpv6"})
			elseif cfgs["protocol"] == "dhcp" then
				local dhcpv6_cfg = 
				{
					ifname = "eth1",
					defaultroute = "1",
					proto = "dhcpv6",
					reqprefix = "auto",
					reqaddress = "none"
				}
				uci:delete("network", wan_dfroute, "username")
				uci:delete("network", wan_dfroute, "password")
				uci:set("network", wan_dfroute, "_vlanid", "0")
				uci:set("network", wan_dfroute, "ifname", "eth1")
				-- uci:set("network", wan_dfroute.."_ip6", "ifname", "eth1")
				uci:section("network", "interface", wan_dfroute.."_ip6", dhcpv6_cfg)
			end
			uci:commit("network")
		end
	else
		util.perror("[fanwar] Missing protocol")
	end
end

function handle_parentald()
	local uci = require("luci.model.uci").cursor()
	local util = require("luci.util")
	local device_role = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local mesh_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")	
	local parentalctrl_enable = uci:get("parental", "global", "enabled")
	local parental_state
	if util.exec_trim("ubus list | grep parental") == "parental" then
		parentald_state = "1"
	else   
		parentald_state = "0"
	end
	
	-- if mesh_enable == "1" and device_role == "1" then
	-- 	if parentald_state == "0" then
	-- 		util.exec("/etc/init.d/parental start")	
	-- 	end
	if mesh_enable == "1" and device_role == "1" then
		if parentalctrl_enable == "1" and parentald_state == "0" then                   
			util.exec("/etc/init.d/parental start")	
			luci.util.perror("[easysetup]exec parental start")                                                            
		elseif parentalctrl_enable == "0" and parentald_state == "1" then                          
			util.exec("/etc/init.d/parental stop")	
			luci.util.perror("[easysetup]exec parental stop")  
		end
	elseif mesh_enable == "1" and device_role == "2" then
		if parentald_state == "1" then
			util.exec("/etc/init.d/parental stop")
			luci.util.perror("[easysetup]exec parental stop")  	
		end
	elseif parentalctrl_enable == "1" and mesh_enable == "0" then
		if parentald_state == "0" then
			util.exec("/etc/init.d/parental start")	
			luci.util.perror("[easysetup]exec parental start")  
		end
	end
end

function handle_apply()
	local cfgs = {}
	for k,v in pairs(http.formvalue()) do
        if type(v) ~= type("") and type(v) ~= type(0) then
            nixio.syslog("err", "dev_cfg, invalid value type for "..k..","..type(v))
        elseif string.byte(k) == string.byte("_") then
            nixio.syslog("err", "dev_cfg, special: "..k.."="..v)
        else
			util.perror("[fanwar] ["..k.."] ---> "..v)
            cfgs[k] = v or ""
        end
    end
	if cfgs["page_status"] == "READY" then
		-- local configlist = {"network", "wireless", "firewall"}
		local configlist = {"network", "firewall"}
		local rv = {}
		rv["status"] = "READY"
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
		util.perror("[fanwar] reload "..table.concat(configlist, ","))
		fork_exec("/etc/init.d/odhcpd restart")
		fork_exec("/sbin/luci-reload".." "..table.concat(configlist, " "))
		handle_parentald()
		-- fork_exec("wifi reload")
	end
end

function validate_data_at_server(cfgs)
	-- This function is a work-around solution for losing data put from client side
	-- We will check some must-have parameter to decide whether to apply
	-- required params: ssid, password, protocol
	if cfgs["ssid_wifi24"] == nil or cfgs["ssid_wifi5"] == nil or 
		cfgs["pwd_wifi24"] == nil or cfgs["pwd_wifi5"] == nil or 
	   cfgs["protocol"] == nil then
		return false
	end
	return true
end

function config_firewall_agent()
	local uci = require("luci.model.uci").cursor()
	uci:foreach("firewall", "redirect",
		function(x)
			local sid = x['.name']
			uci:set("firewall", sid, "enabled", "0")
		end
	)
	uci:commit("firewall")
	fork_exec("/etc/init.d/firewall reload")
end

function easy_setup_apply()
	local cfgs = {}
	local device_role = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
	local mesh_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
	local do_not_apply = false

	util.perror("[fanwar] apply ")
	util.perror("[fanwar]-----------------------------------------------")
	for k,v in pairs(http.formvalue()) do
        if type(v) ~= type("") and type(v) ~= type(0) then
            nixio.syslog("err", "dev_cfg, invalid value type for "..k..","..type(v))
        elseif string.byte(k) == string.byte("_") then
            nixio.syslog("err", "dev_cfg, special: "..k.."="..v)
        else
			-- AP-845: validation vulnerable key
			if k == k:match("^ssid_wifi%d-$") then
				if mtkwifi.validate_ssid(v) == false then
					util.perror("[fanwar] easy_setup_apply, invalid ssid "..v)
					return 
				end
			elseif k == k:match("^pwd_wifi%d-$") then
				if mtkwifi.validate_key(v) == false then
					util.perror("[fanwar] easy_setup_apply, invalid key "..v)
					return 
				end
			end
			----------
			util.perror("[fanwar] ["..k.."] ---> "..v)
            cfgs[k] = v or ""
        end
    end
	if validate_data_at_server(cfgs) == false then
        luci.http.redirect(luci.dispatcher.build_url("admin", "easy_setup"))
		return
	end
	if do_not_apply == false then
		if cfgs["pppoe_vlanid"] == nil or #cfgs["pppoe_vlanid"] == 0 then
			cfgs["pppoe_vlanid"] = "0"
		end
		util.perror("[fanwar]-----------------------------------------------")
		if mesh_enable == "0" then
			cfgs["cur_role"] = "0"
		else
			cfgs["cur_role"] = device_role
		end
		if (cfgs["mesh_enable"] ~= nil) then
			if (cfgs["role_sel"] == "1") then
				config_gw(cfgs, "1")	
				
			elseif (cfgs["role_sel"] == "2") then
				if cfgs["cur_role"] == "2" then
					do_not_apply = true
				else
					config_firewall_agent();		--AP-672 disable dmz, portforwarding when AP is Agent
					config_mesh_agent(cfgs)
				end
			else
				util.perror("[fanwar] Mesh role is missing")
				return
			end
		else
			config_gw(cfgs, "0")
		end
	end

	if do_not_apply == false then
		-- Here a quick workaround, backup the easymesh cfgs file to /tmp
		local easymesh_applied_path = mtkwifi.__profile_applied_settings_path(mtkwifi.__easymesh_profile_path())
		os.execute("cp -f "..mtkwifi.__easymesh_profile_path().." "..easymesh_applied_path)
		-- 
		-- luci.http.redirect(luci.dispatcher.build_url("admin", "easy_setup", "loading", "{admin/easy_setup}"))
		luci.template.render(
			"admin_status/loading", 
			{
				return_url = luci.dispatcher.build_url("admin", "easy_setup"),
				apply_url = luci.dispatcher.build_url("admin", "easy_setup", "apply_status"),
				status_url = luci.dispatcher.build_url("admin", "easy_setup", "info")
			}
		)
	else
		luci.http.redirect(luci.dispatcher.build_url("admin", "easy_setup"))
	end
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
	if tonumber(devRole) == 1 then
		device_role = "Controller";
	else
		device_role = "Agent";
	end
	return device_role
end

function handle_deviceinfo()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			HardwareVersion = "0.1",
			SoftwareVersion = get_firmware_version(),
			ActiveFirmwareImage = get_active_firmware_image(),
			BootFirmwareImage = get_boot_firmware_image(),
			Description = get_description()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = {Status = "Fail"}
		local value = table["BootFirmwareImage"]
		if value ~= nil then
			if set_boot_firmware_image(value) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
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
	local macaddr = luci.util.exec("cat /sys/class/net/"..ethernet_iface_list[idx].."/address")
	macaddr=luci.util.trim(macaddr)
	local enable = luci.util.exec("cat /sys/class/net/"..ethernet_iface_list[idx].."/operstate")
	enable=luci.util.trim(enable)

	if enable == "unknown" then
		enable=luci.util.exec("ubus call network.interface.wan0 status | grep '\"up\":' | grep -oE 'true'")
		enable=luci.util.trim(enable)
		if enable == "true" then
			enable = "up"
		else
			enable = "down"
		end
	end

	local status = luci.util.exec("ethstt | grep 'port "..(idx+1).."' | grep -oE 'up'")
	status=luci.util.trim(status)
	if status == "up" then
		status = "up"
	else
		status = "down"
	end 
	
	local this_entry_tbl =
	{
		Enable = enable == "up" and "true" or "false",
		MACAddress = macaddr,
		Status = status
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

	local status = luci.util.exec("cat /sys/class/net/"..bridging_list[idx].."/operstate")
	status=luci.util.trim(status)

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
	local macaddr = luci.util.exec("cat /sys/class/net/"..ethernetlink_list[idx].."/address")
	macaddr = luci.util.trim(macaddr)

	if idx == 1 then
		lowerlayer = bridging_layer[1]
	else
		lowerlayer = ethernet_layer_list[idx-1]
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

local vlantermination_layer = 
{
	[1] = "Device.Ethernet.VLANTermination.1",
	[2] = "Device.Ethernet.VLANTermination.2",
	[3] = "Device.Ethernet.VLANTermination.3"
}

function get_ethernet_vlantermination(idx)

	local status = luci.util.exec("cat /sys/class/net/"..vlan_interface_list[idx].."/operstate")
	status=luci.util.trim(status)
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

	for i = 1,3,1 do
		tmp_entry = get_ethernet_vlantermination(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

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

--- ethernetinfo ---
function get_vlan_quantity()
       local count = ""
       for idx = 1,3,1 do
               local status = luci.util.exec("cat /sys/class/net/"..vlan_interface_list[idx].."/operstate")
               status=luci.util.trim(status)
               if status == "up" or status == "down" then
                       count = count..idx
               end
       end
       return count
end

function get_ppp_quantity()
       local count = ""
       for idx = 1,4,1 do
               local proto = luci.util.exec("uci get network."..ppp_list[idx]..".proto")
               proto=luci.util.trim(proto)
               if proto == "pppoe" then
                       count = count..idx
               end
       end
       return count
end

function get_ipinterface_quantity()
	local count = ""
	for idx=1,5,1 do
		local proto = luci.util.exec("uci get network."..ipinterface_list[idx]..".proto")
		proto=luci.util.trim(proto)
		if proto == "dhcp" or proto == "static" or  proto == "pppoe" then
			count = count..idx
		end
	end
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
--------------------------------------------------------------
local ppp_list = 
{
	[1] = "wan0",
	[2] = "wan1",
	[3] = "wan2",
	[4] = "wan3"
}

local ppp_layer = 
{
	[1] = "Device.PPP.Interface.1",
	[2] = "Device.PPP.Interface.2",
	[3] = "Device.PPP.Interface.3",
	[4] = "Device.PPP.Interface.4"
}
------PPP/interface------
function get_PPP_Interface(idx)
	local proto = luci.util.exec("uci get network."..ppp_list[idx]..".proto")
	proto=luci.util.trim(proto)

	if proto == "pppoe" then
		local lowerlayer = ""
		local connstatus = ""
		local ifname = luci.util.exec("uci get network."..ppp_list[idx]..".ifname")
		ifname=luci.util.trim(ifname)
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
		local user = luci.util.exec("uci get network."..ppp_list[idx]..".username")
		user = luci.util.trim(user)
		local pwd = luci.util.exec("uci get network."..ppp_list[idx]..".password")
		pwd = luci.util.trim(pwd)

		local this_entry_tbl =
		{
			LowerLayers = lowerlayer,
			ConnectionStatus = connstatus,
			Username = user,
			Password = pwd
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

	for i = 1,4,1 do
		tmp_entry = get_PPP_Interface(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

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
	luci.util.exec("reload_config")
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
	[5] = "wan3"
}

function get_IP_Interface(idx)
	local proto = luci.util.exec("uci get network."..ipinterface_list[idx]..".proto")
	proto=luci.util.trim(proto)

	if proto == "dhcp" or proto == "static" or  proto == "pppoe" then
		local lowerlayer = ""
		local ipaddressv4 = ""
		local subnet = ""
		local protov4 = ""
		local ipaddressv6 = ""
		local protov6 = ""
		local statustbl = {}
		local ifname = luci.util.exec("uci get network."..ipinterface_list[idx]..".ifname")
		ifname=luci.util.trim(ifname)
		if ifname == "eth1" then
			lowerlayer = ethernetlink_layer[2]
		elseif ifname == "eth0.1" or ifname == "eth0.2" then
			lowerlayer = ethernetlink_layer[1]
		elseif ifname == "eth0.1 eth0.2" or ifname == "eth0.2 eth0.1" then
			lowerlayer = ethernetlink_layer[1]
		else
			lowerlayer = ppp_layer[idx-1]
		end
		
		local ipv4 = luci.util.exec("uci show network."..ipinterface_list[idx].." | grep 'interface' | grep -oE 'interface'")
		ipv4 = luci.util.trim(ipv4)
		if ipv4 == "interface" then
			ipv4 = "true"
		else
			ipv4 = "false"
		end

		local ipv6 = luci.util.exec("uci show network."..ipinterface_list[idx].."_ip6 | grep 'interface' | grep -oE 'interface'")
		ipv6 = luci.util.trim(ipv6)
		if ipv6 == "interface" then
			ipv6 = "true"
		else
			ipv6 = "false"
		end

		local service = luci.util.exec("uci get network."..ipinterface_list[idx].."._service")
		service = luci.util.trim(service)
		
		statustbl=json.decode(luci.util.exec("ifstatus "..ipinterface_list[idx]..""))
		protov4 = statustbl["proto"]
		if protov4 == "pppoe" then
			protov4 = "IPCP"
		end
		for name,cfg in pairs(statustbl) do
			if name == "ipv4-address" and cfg ~= nil then
				for k,v in pairs(cfg) do
					if k ~= nil and v ~= nil then
						ipaddressv4 = v["address"]
						subnet = string.format("%d",v["mask"])
					end
				end
			end
		end

		local checkipv6 = luci.util.exec("uci get network."..ipinterface_list[idx].."_ip6.proto")
		checkipv6=luci.util.trim(checkipv6)
		if checkipv6 == "dhcpv6" or checkipv6 == "static" or  checkipv6 == "pppoe" then
			statustbl=json.decode(luci.util.exec("ifstatus "..ipinterface_list[idx].."_ip6"))
			protov6 = statustbl["proto"]
			if protov6 == "pppoe" then
				protov6 = "IPCP"
			end
			for name,cfg in pairs(statustbl) do
				if name == "ipv6-address" and cfg ~= nil then
					for k,v in pairs(cfg) do
						if k ~= nil and v ~= nil then
							ipaddressv6 = v["address"]
						end
					end
				end
			end
		end
		
		local this_entry_tbl =
		{
			LowerLayers = lowerlayer,
			IPv4Enable = ipv4,
			IPv6Enable = ipv6,
			Name = service,
			IPv4Address = {
				Enable = ipv4,
				IPAddress = ipaddressv4,
				SubnetMask = subnet,
				AddressingType = protov4 
			},
			IPv6Address = {
				Enable = ipv6,
				IPAddress = ipaddressv6,
				Origin = protov6 
			}
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

function get_all_IP_Interface()
	local tbl = {}
	local tmp_entry = {}

	for i = 1,4,1 do
		tmp_entry = get_IP_Interface(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end
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
					local proto = luci.util.exec("uci get network."..ipinterface_list[tonumber(idx)]..".proto")
					proto = luci.util.trim(proto)
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
					local proto = luci.util.exec("uci get network."..ipinterface_list[tonumber(idx)].."_ip6.proto")
					proto = luci.util.trim(proto)
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
	luci.util.exec("reload_config")
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
local dhcp_client = 
{
	[1] = "wan0",
	[2] = "wan1",
	[3] = "wan2",
	[4] = "wan3"
}

function  get_DHCPv4_client(idx)
	local proto = luci.util.exec("uci get network."..dhcp_client[idx]..".proto")
	proto=luci.util.trim(proto)
	if proto == "dhcp" or proto == "static" or  proto == "pppoe" then
		local interface = ""
		local ipaddress = ""
		local subnet = ""
		local iproute = ""
		local dnsserver = ""
		local dhcpserver = ""
		local leasetime = ""
		local statustbl = {}
		statustbl=json.decode(luci.util.exec("ifstatus "..dhcp_client[idx]..""))
		if proto == "pppoe" then
			proto = "IPCP"
		end
		interface = statustbl["device"]
		for name,cfg in pairs(statustbl) do
			if name == "ipv4-address" and cfg ~= nil then
				for k,v in pairs(cfg) do
					if k ~= nil and v ~= nil then
						ipaddress = v["address"]
						subnet = string.format("%d",v["mask"])
					end
				end
			end
			if name == "route" and cfg ~= nil then
				for k,v in pairs(cfg) do
					if k ~= nil and v ~= nil then
						iproute = v["target"]
						dhcpserver = v["target"]
					end
				end
			end
			if name == "dns-server" and cfg ~= nil then
				dnsserver=cfg[1]
			end

			if name == "data" and cfg ~= nil then
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

	for i = 1,4,1 do
		tmp_entry = get_DHCPv4_client(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

	return tbl
end

function set_DHCPv4_client(tbl)
	for idx,cfg in pairs(tbl) do
		if idx ~= nil and cfg ~= nil then
			if cfg["Interface"] ~= nil then
				luci.util.exec("uci set network."..dhcp_client[tonumber(idx)]..".ifname='"..cfg["Interface"].."'")
				luci.util.exec("uci commit")
			end
		end
	end
	luci.util.exec("reload_config")
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

