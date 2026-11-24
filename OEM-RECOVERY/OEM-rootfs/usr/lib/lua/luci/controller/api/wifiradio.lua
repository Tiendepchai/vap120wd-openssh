module("luci.controller.api.wifiradio", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")
local nixio = require("nixio")
local os = require("os")

local ifname_list = 
{   
    [1] = "rax0", 
    [2] = "rax1", 
    [3] = "rax2", 
    [4] = "rax3", 
    [5] = "ra0", 
    [6] = "ra1", 
    [7] = "ra2", 
    [8] = "ra3"
}
local WirelessModeList = 
{
    [0] = "b,g",
    [1] = "b",
    [2] = "a",
    -- [3] = "A/B/G mixed",
    [4] = "g",
    -- [5] = "A/B/G/GN/AN mixed",
    -- [6] = "N in 2.4G only",
    [7] = "g,n", -- i.e., no CCK mode
    [8] = "a,n",
    [9] = "b,g,n",
    -- [10] = "A/AN/G/GN mode", --not support B mode
    -- [11] = "only N in 5G band",
    -- [12] = "B/G/GN/A/AN/AC mixed",
    -- [13] = "G/GN/A/AN/AC mixed", -- no B mode
    [14] = "a,n,ac",
    [15] = "n,ac", --but no A mode
}
local SupportedBW_WMode =
{
    [0] = "20MHz",
    [1] = "20MHz",
    [2] = "20MHz",
    [4] = "20MHz",
    [7] = "20MHz,40MHz", -- i.e., no CCK mode
    [8] = "20MHz,40MHz",
    [9] = "20MHz,40MHz",
    [14] = "20MHz,40MHz,80MHz",
    [15] = "20MHz,40MHz,80MHz", --but no A mode
}
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

function save_backup_cfg(path)   
    os.execute("cp -f "..path.." "..mtkwifi.__profile_applied_settings_path(path)) 
end

function index()
    entry({"api", "wifi", "radio"}, call("handle_wifi_radio")).leaf = true
end

function get_vifs_channel(vifname)
    local command = "iwlist "..vifname.." channel"
    local pipe = io.popen(command)
    local _ch
    for line in pipe:lines() do
        if line:find("Current Channel") then
            _ch = string.match(line, "%d+")
        end
    end
    pipe:close()
    return _ch
end

function get_radio(idx)
    local profilename
    local name
    local OperatingFrequencyBand
    local bw
    local ifname

    if idx == 1 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        name = "Wireless 2.4Ghz"
        OperatingFrequencyBand = "2.4GHz"
        ifname = "rax0"
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        name = "Wireless 5Ghz"
        OperatingFrequencyBand = "5GHz"
        ifname = "ra0"
    end
    -- get State of the band
    local radiostate_str = util.exec_trim("wificonf -f "..profilename.." get State")
    -- get config to determine BW
    local cfg_HT_BW = util.exec_trim("wificonf -f "..profilename.." get HT_BW")
    local cfg_VHT_BW = util.exec_trim("wificonf -f "..profilename.." get VHT_BW")
    local cfg_HT_BSSCoexistence = util.exec_trim("wificonf -f "..profilename.." get HT_BSSCoexistence")
    if cfg_HT_BW == "0" and cfg_VHT_BW == "0" then
        bw = "20MHz"
    elseif cfg_HT_BW == "1" and cfg_VHT_BW == "0" then
        bw = "40MHz"
    elseif cfg_HT_BW == "1" and cfg_VHT_BW == "1" then
        bw = "80MHz"
    end
    local wmode = tonumber(util.exec_trim("wificonf -f "..profilename.." get WirelessMode"))
    local channel_dat = tonumber(util.exec_trim("wificonf -f "..profilename.." get Channel"))
    local this_entry_tbl = 
    {
        Enable = radiostate_str == "up" and "true" or "False",
        Status = radiostate_str == "up" and "Up" or "Down",
        Name = name,
        OperatingFrequencyBand = OperatingFrequencyBand,
        OperatingStandards = WirelessModeList[wmode],
        Channel = get_vifs_channel(ifname),
        OperatingChannelBandwidth = bw,
        CurrentOperatingChannelBandwidth = bw,
        TransmitPower = util.exec_trim("wificonf -f "..profilename.." get TxPower"),
        MCS = "",
        BeaconPeriod = "",
        SupportedOperatingChannelBandwidths = SupportedBW_WMode[wmode],
        AutoChannelSupported = "true",
        AutoChannelEnable = channel_dat == 0 and "true" or "false"
    }
    return {[tostring(idx)] = this_entry_tbl}
end
function get_all_radio()
    local tbl = {}
    local tmp_entry = {}
    for i = 1,2,1 do
        tmp_entry = get_radio(i)
        tbl[tostring(i)] = tmp_entry[tostring(i)]
    end
    return tbl
end

function disable_dev(devname)
    local profilename
    local j
    if devname == "MT7615D.1.2" then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = 1
    elseif devname == "MT7615D.1.1" then
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = 5
    end
    local Devstate = util.exec_trim("wificonf -f "..profilename.." get State")
    if Devstate == "down" then
        return "Success"
    end
    util.exec("wificonf -f "..profilename.." set State ".."\"".."down".."\"")
    local enableSSID = util.exec_trim("wificonf -f "..profilename.." get EnableSSID")
    util.exec("wificonf -f "..profilename.." set StateSSID ".."\""..enableSSID.."\"")
    -- for i=j,j+3 do
    --     util.exec("ifconfig "..ifname_list[i].." down")
    -- end
    return "Success"
end

function enable_dev(devname)
    local profilename
    local j
    if devname == "MT7615D.1.2" then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = 1
    elseif devname == "MT7615D.1.1" then
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = 5
    end
    local Devstate = util.exec_trim("wificonf -f "..profilename.." get State")
    if Devstate == "up" then
        return "Success"
    end
    util.exec_trim("wificonf -f "..profilename.." set State ".."\"".."up".."\"")
    local SSIDstate = util.exec_trim("wificonf -f "..profilename.." get StateSSID")
    util.exec_trim("wificonf -f "..profilename.." set EnableSSID ".."\""..SSIDstate.."\"")
    -- for i=j,j+3 do
    --     if mtkwifi.token_get(SSIDstate, j == 1 and i or i - 4, "0") == "1" then
    --         util.exec("ifconfig "..ifname_list[i].." up")
    --     end
    -- end
    return "Success"
end

function set_operatingstadards(band, value, profilename)
    local supportedoperatingStd = 
    {
        ["2.4GHz"] =
        {
            ["b"] = 1,
            ["g"] = 4,
            ["b,g"] = 0, ["g,b"] = 0,
            ["g,n"] = 7, ["n,g"] = 7,
            ["b,g,n"] = 9, ["b,n,g"] = 9, 
            ["n,b,g"] = 9, ["n,g,b"] = 9, 
            ["g,b,n"] = 9, ["g,n,b"] = 9
        },
        ["5GHz"] = 
        {
            ["a"] = 2,
            ["n,ac"] = 15, ["ac,n"] = 15,
            ["a,n"] = 8, ["n,a"] = 8,
            ["a,n,ac"] = 14, ["a,ac,n"] = 14,
            ["n,a,ac"] = 14, ["n,ac,a"] = 14,
            ["ac,a,n"] = 14, ["ac,n,a"] = 14
        }
    }
    local j = band == "2.4GHz" and 1 or 5
    if supportedoperatingStd[band][value] ~= nil then
        util.exec("wificonf -f "..profilename.." set WirelessMode ".."\""..supportedoperatingStd[band][value].."\"")
        -- for i=j,j+3 do        
        --     util.exec("iwpriv "..ifname_list[i].." set WirelessMode="..supportedoperatingStd[band][value])
        -- end
        return "Success"
    else
        return "Failed", "Not supported Operating Standards"
    end
end

function remove_ch_by_region(ch_list, region)
    for i = #ch_list,2,-1 do
        if not ch_list[i].region[region] then
            table.remove(ch_list, i)
        end
    end
end

function get_channel_list(band, region)
    local ch_list

    if band == "5GHz" then
        ch_list = mtkwifi.ChannelList_5G_All
    else
        ch_list = mtkwifi.ChannelList_2G_All
    end

    remove_ch_by_region(ch_list, region)
    return ch_list
end

function set_channel(band, value, profilename)
    local j = band == "2.4GHz" and 1 or 5
    local region
    if (j == 1) then
        region = tonumber(util.exec_trim("wificonf -f "..profilename.." get CountryRegion"))
    else
        region = tonumber(util.exec_trim("wificonf -f "..profilename.." get CountryRegionABand"))
    end
    local ch_list = get_channel_list(band, region)
    for k,v in ipairs(ch_list) do
        if v["channel"] == tonumber(value) then
            util.exec("wificonf -f "..profilename.." set Channel ".."\""..value.."\"")
            -- for i=j,j+3 do        
            --     util.exec("iwpriv "..ifname_list[i].." set Channel="..value)
            -- end
            return "Success"
        end
    end
    return "Failed", "Not supported channel"
end

function set_bw(band, value, profilename)
    local j = band == "2.4GHz" and 1 or 5
    local wmode = tonumber(util.exec_trim("wificonf -f "..profilename.." get WirelessMode"))
    if string.find(SupportedBW_WMode[wmode], value) ~= nil then
        if value == "20MHz" then
            util.exec("wificonf -f "..profilename.." set VHT_BW ".."\"".."0".."\"")
            util.exec("wificonf -f "..profilename.." set HT_BW ".."\"".."0".."\"")
            -- for i=j,j+3 do        
            --     util.exec("iwpriv "..ifname_list[i].." set VhtBw=".."0")
            --     util.exec("iwpriv "..ifname_list[i].." set HtBw=".."0")
            -- end
        elseif value == "40MHz" then
            util.exec("wificonf -f "..profilename.." set VHT_BW ".."\"".."0".."\"")
            util.exec("wificonf -f "..profilename.." set HT_BW ".."\"".."1".."\"")
            -- for i=j,j+3 do        
            --     util.exec("iwpriv "..ifname_list[i].." set VhtBw=".."0")
            --     util.exec("iwpriv "..ifname_list[i].." set HtBw=".."1")
            -- end
        elseif value == "80MHz" then
            util.exec("wificonf -f "..profilename.." set VHT_BW ".."\"".."1".."\"")
            util.exec("wificonf -f "..profilename.." set HT_BW ".."\"".."1".."\"")
            -- for i=j,j+3 do        
            --     util.exec("iwpriv "..ifname_list[i].." set VhtBw=".."1")
            --     util.exec("iwpriv "..ifname_list[i].." set HtBw=".."1")
            -- end
        end
    else
        return "Failed", "Not supported bandwidth"
    end
    return "Success"
end

function set_radio(idx, cfg)
    local profilename
    local devname 
    local supportedband
    local ret = "Success"
    local errmsg = {}
    local ch_list
    local j

    if idx == 1 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        devname = "MT7615D.1.2"
        supportedband = "2.4GHz"
        j = 1
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        devname = "MT7615D.1.1"
        supportedband = "5GHz"
        j = 5
    end
    if cfg["Enable"] ~= nil then
        if cfg["Enable"] == "true" then
            enable_dev(devname)
        elseif cfg["Enable"] == "false" then
            disable_dev(devname)
        else
            ret = "Failed"
            errmsg["Enable"] = "Enable value is invalid"
        end
    end

    if cfg["OperatingFrequencyBand"] ~= nil then
        if cfg["OperatingFrequencyBand"] ~= supportedband then
            ret = "Failed"
            errmsg["OperatingFrequencyBand"] = "Not supported frequency band"
        end
    end

    if cfg["OperatingStandards"] ~= nil then
        ret, errmsg["OperatingStandards"] = set_operatingstadards(supportedband, cfg["OperatingStandards"], profilename)
    end

    if cfg["Channel"] ~= nil then
        ret, errmsg["Channel"] = set_channel(supportedband, cfg["Channel"], profilename)
    end

    if cfg["AutoChannelEnable"] ~= nil then
        if cfg["AutoChannelEnable"] == "true" then
            util.exec("wificonf -f "..profilename.." set Channel \"0\"")
        elseif cfg["AutoChannelEnable"] ~= "false" then
            ret = "Failed"
            errmsg["AutoChannelEnable"] = "AutoChannelEnable value is invalid"
        end
    end

    if cfg["OperatingChannelBandwidth"] ~= nil then
        ret, errmsg["OperatingChannelBandwidth"] = set_bw(supportedband, cfg["OperatingChannelBandwidth"], profilename)

    end

    if cfg["TransmitPower"] ~= nil then
        if cfg["TransmitPower"] == "25" or cfg["TransmitPower"] == "50" or cfg["TransmitPower"] == "75" or cfg["TransmitPower"] == "100" then
            util.exec_trim("wificonf -f "..profilename.." set TxPower ".."\""..cfg["TransmitPower"].."\"")
        else
            ret = "Failed"
            errmsg["TransmitPower"] = "TransmitPower value is invalid"
        end
    end

    return ret, errmsg
end

function set_all_radio(tbl)
    local ret
    local errmsg = {}
    for idx, cfg in pairs(tbl) do
        local err = {}
        if idx ~= nil and cfg ~= nil then
            ret, err = set_radio(tonumber(idx), cfg)
            if ret == "Failed" then
                errmsg[tostring(idx)] = err
            end
        end
    end
    return ret, errmsg
end

function handle_wifi_radio(idx)
    util.perror_hieupt35("handle_wifi_radio")
    local rv = {}
    local ret = "Success"
    local errmsg = {}
    if luci.http.getenv("REQUEST_METHOD") == "GET" then
        if idx and #idx > 0 then
            rv = get_radio(tonumber(idx))
        else
            rv = get_all_radio()
        end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)

        ret, errmsg = set_all_radio(table)

        if ret == "Success" then
            rv["Status"] = "Success"
            luci.http.prepare_content("application/json")
            luci.http.write_json(rv)
            save_backup_cfg("/etc/wireless/mt7615/mt7615.1.2G.dat")
            save_backup_cfg("/etc/wireless/mt7615/mt7615.1.5G.dat")

            mtkwifi.save_easymesh_bss_cfgs(mtkwifi.get_bss_cfgs_from_dat())
            local bss_config_controller = "\""..mtkwifi.get_bss_config_priority().."\""
            os.execute("wificonf -f /etc/map_cfg.txt set bss_config_priority "..bss_config_controller)
            os.execute("wificonf -f /etc/mapd_cfg.txt set bss_config_priority "..bss_config_controller)
            
            fork_exec("wifi reload")
        else
            util.print_table(errmsg)
            rv["Status"] = "Failed"
            rv["DetailStatus"] = {}
            rv["DetailStatus"]["Radio"] = errmsg
            luci.http.prepare_content("application/json")
            luci.http.write_json(rv)
        end
	end
end
