module("luci.controller.api.wifi_ap_ssid", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local nixio = require("nixio")
local os = require("os")
local mtkwifi = require("mtkwifi")
local ioctl_help = require "ioctl_helper"

local mesh_cfgs = {}
local is_controller = false
local is_mesh_enable = false
local req_bandstr = 0
local tmp_mesh = {}
local g_staTable = nil
local g_macTable = nil

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
    [0] = "b/g",
    [1] = "b",
    [2] = "a",
    -- [3] = "A/B/G mixed",
    [4] = "g",
    -- [5] = "A/B/G/GN/AN mixed",
    -- [6] = "N in 2.4G only",
    [7] = "g/n", -- i.e., no CCK mode
    [8] = "a/n",
    [9] = "b/g/n",
    -- [10] = "A/AN/G/GN mode", --not support B mode
    -- [11] = "only N in 5G band",
    -- [12] = "B/G/GN/A/AN/AC mixed",
    -- [13] = "G/GN/A/AN/AC mixed", -- no B mode
    [14] = "a/n/ac",
    [15] = "n/ac", --but no A mode
}

local mode_supported = "None,WPA-Personal,WPA2-Personal"

function get_staTable()
    local ifname
    if g_staTable == nil then
        g_staTable = {}
        for i = 1,8,1 do
            ifname = ifname_list[i]
            g_staTable[ifname] = c_StaInfo(ifname)
        end
    end
    return g_staTable
end

function get_macTable()
    if g_macTable == nil then
        g_macTable = read_pipe("iwpriv ra0 get_mac_table")
    end
    return g_macTable
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

function save_backup_cfg(path)   
    os.execute("cp -f "..path.." "..mtkwifi.__profile_applied_settings_path(path)) 
end

function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
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

function validate_pwd(pwd)
    local specical_char_pwd = 
        {
            ["\\"] = 1,
            ["'"] = 1,
            ["`"] = 1,
            ["/"] = 1,
            ["\""] = 1,
            [" "] = 1
        }
    if #pwd < 8 or #pwd > 64 then
        return "Failed", "Password length must be in [8;64]"
    end

    for i = 1, #pwd do
        local c = pwd:sub(i,i)
        if specical_char_pwd[c] ~= nil then
            return "Failed", "Special character '"..c.."' is not allowed in password"
        end
    end
    return "Success"
end

function validate_ssid(ssid)
    local i
    local specical_char_ssid = 
        {
            ["\\"] = 1,
            ["'"] = 1,
            ["`"] = 1,
            ["/"] = 1,
            ["\""] = 1
        }
    if #ssid == 0 or #ssid > 32 then
        return "Failed", "SSID length must smaller than 32"
    end

    for i = 1, #ssid do
        local c = ssid:sub(i,i)
        if specical_char_ssid[c] ~= nil then
            return "Failed", "Special character '"..c.."' is not allowed in SSID"
        end
    end

    return "Success"
end

function index()
    entry({"api", "wifi"})
    entry({"api", "wifi", "ap_ssid"}, call("handle_wifi_ap_ssid")).leaf = true

    -- entry({"api", "wifi", "accesspoint"}, call("handle_wifi_accesspoint")).leaf = true
    -- entry({"api", "wifi", "accesspoint_security"}, call("handle_wifi_accesspoint_security")).leaf = true
    -- entry({"api", "wifi", "accesspoint_associateddevice"}, call("handle_wifi_accesspoint_associateddevice")).leaf = true
    -- entry({"api", "wifi", "accesspoint_assocdevnum"}, call("handle_wifi_accesspoint_assocdevnum")).leaf = true

    -- entry({"api", "wifi", "SSID"}, call("handle_wifi_SSID")).leaf = true
end

function get_accesspoint(idx)
    local profilename
    local j
    local bs_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get BSEnable")

    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = idx
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = idx - 4
    end
    -- get enableSSID
    local enableSSID_str = util.exec_trim("wificonf -f "..profilename.." get EnableSSID")
    local enable = mtkwifi.token_get(enableSSID_str, j, "0")
    -- get MaxStaNum
    local MaxStaNum_str = util.exec_trim("wificonf -f "..profilename.." get MbssMaxStaNum")
    local maxstanum = mtkwifi.token_get(MaxStaNum_str, j, "0")
    -- get HideSSID
    local hideSSID_str = util.exec_trim("wificonf -f "..profilename.." get HideSSID")
    local hideSSID = mtkwifi.token_get(hideSSID_str, j, "0")

    local this_entry_tbl = 
        {
            Enable = enable == "1" and "true" or "false",
            Status = enable == "1" and "Enabled" or "Disabled",
            MaxAllowedAssociations = maxstanum,
            SSIDReference = "Device.WiFi.SSID."..idx..".",
            SSIDAdvertisementEnabled = hideSSID == "1" and "false" or "true",
            Security = get_accesspoint_security(idx)[tostring(idx)]["Security"]
        }
    if idx == 1 or idx == 5 then
        this_entry_tbl["X_VT_BandsteeringEnable"] = bs_enable == "1" and "true" or "false"
    end
    local this_ap_associateddevs = get_accesspoint_associateddevice(idx)[tostring(idx)]
    if this_ap_associateddevs ~= nil then
        this_entry_tbl["AssociatedDevice"] = this_ap_associateddevs["AssociatedDevice"]
    end
    return {[tostring(idx)] = this_entry_tbl}
end

function get_all_accesspoint()
    local tbl = {}
    local tmp_entry = {}
    for i = 1,8,1 do
        tmp_entry = get_accesspoint(i)
        tbl[tostring(i)] = tmp_entry[tostring(i)]
    end
    return tbl
end

function set_accesspoint(idx, cfg)
    local profilename
    local j
    local ifname = ifname_list[idx]
    local errmsg = {}
    local ret = "Success"

    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = idx
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["8x"]
        end
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = idx - 4
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["11x"]
        end
    end

    if cfg["Enable"] ~= nil then
        -- set enableSSID in .dat file
        if cfg["Enable"] == "true" or cfg["Enable"] == "false" then
            local enableSSID_str = util.exec_trim("wificonf -f "..profilename.." get EnableSSID")
            enableSSID_str = mtkwifi.token_set(enableSSID_str, j, cfg["Enable"] == "true" and "1" or "0")
            util.exec("wificonf -f "..profilename.." set EnableSSID ".."\""..enableSSID_str.."\"")
        else
            errmsg["Enable"] = "Enable value is invalid"
            ret = "Failed"
        end
        -- execute it
        -- util.exec("ifconfig "..ifname.." "..(cfg["Enable"] == "true" and "up" or "down"))
    end

    if cfg["MaxAllowedAssociations"] ~= nil then
        -- set MaxStaNum
        if (tonumber(cfg["MaxAllowedAssociations"]) < 1 or tonumber(cfg["MaxAllowedAssociations"]) > 32) then
            errmsg["MaxAllowedAssociations"] = "MaxAllowedAssociations is out of range. Should in [1;32]"
            ret = "Failed"
        else
            local MaxStaNum_str = util.exec_trim("wificonf -f "..profilename.." get MbssMaxStaNum")
            MaxStaNum_str = mtkwifi.token_set(MaxStaNum_str, j, cfg["MaxAllowedAssociations"])
            util.exec("wificonf -f "..profilename.." set MbssMaxStaNum ".."\""..MaxStaNum_str.."\"")
        end
        -- execute it
        -- util.exec("iwpriv "..ifname.." set MbssMaxStaNum="..cfg["MaxAllowedAssociations"])
    end

    if cfg["Security"] ~= nil then
        errmsg["Security"] = {}
        ret, errmsg["Security"] = set_accesspoint_security(idx, cfg["Security"])
    end

    if cfg["SSIDAdvertisementEnabled"] ~= nil then
        if cfg["SSIDAdvertisementEnabled"] == "true" or cfg["SSIDAdvertisementEnabled"] == "false" then
            local hideSSID = cfg["SSIDAdvertisementEnabled"] == "true" and "0" or "1"
            local hideSSID_str = util.exec_trim("wificonf -f "..profilename.." get HideSSID")
            hideSSID_str = mtkwifi.token_set(hideSSID_str, j, hideSSID)
            util.exec("wificonf -f "..profilename.." set HideSSID ".."\""..hideSSID_str.."\"")
            -- util.exec("iwpriv "..ifname.." set HideSSID="..hideSSID)
            if (is_controller) then
                tmp_mesh[j]["isHidden"] = cfg["SSIDAdvertisementEnabled"] == "true" and "hidden-N" or "hidden-Y"
            end
        else
            errmsg["SSIDAdvertisementEnabled"] = "SSIDAdvertisementEnabled is not supported"
            ret = "Failed"
        end
    end

    if idx == 1 then
        local map_cfg = mtkwifi.load_profile(mtkwifi.__easymesh_profile_path())
        if cfg["X_VT_BandsteeringEnable"] and cfg["X_VT_BandsteeringEnable"] == "true" then
            req_bandstr = 1
            set_accesspoint(5, cfg)
            map_cfg["BSEnable"] = "1"
        else
            req_bandstr = 0
            map_cfg["BSEnable"] = "0"

        end
        save_easymesh_driver_profile(map_cfg)
        mtkwifi.save_easymesh_profile(map_cfg)
    end

    return ret, errmsg
end

function set_all_accesspoint(tbl)
    local ret
    local errmsg = {}

    for idx, cfg in pairs(tbl) do
        local err = {}
        if idx ~= nil and cfg ~= nil then
            ret, err = set_accesspoint(tonumber(idx), cfg)
            if ret == "Failed" then
                errmsg[tostring(idx)] = err
            end
        end
    end
    return ret, errmsg
end

function get_accesspoint_security(idx)
    local profilename
    local j
    local ifname = ifname_list[idx]

    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = idx
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = idx - 4
    end
    -- get AuthMode
    local authmode_str = util.exec_trim("wificonf -f "..profilename.." get AuthMode")
    local authmode = mtkwifi.token_get(authmode_str, j, "WPA2PSK")
    if authmode == "OPEN" then
        authmode = "None"
    elseif authmode == "WPAPSK" then
        authmode = "WPA-Personal"
    elseif authmode == "WPA2PSK" then
        authmode = "WPA2-Personal"
    end
    -- get EncType
    local encryptype_str = util.exec_trim("wificonf -f "..profilename.." get EncrypType")
    local encryptype = mtkwifi.token_get(encryptype_str, j, "AES")

    local this_entry_tbl = 
        {
            ModesSupported = mode_supported,
            ModeEnabled = authmode,
            EncryptionMode = encryptype,
            PreSharedKey = "",
        }
    return {[tostring(idx)] = {["Security"] = this_entry_tbl}}
end

function get_all_accesspoint_security()
    local tbl = {}
    local tmp_entry = {}
    for i = 1,8,1 do
        tmp_entry = get_accesspoint_security(i)
        tbl[tostring(i)] = tmp_entry[tostring(i)]
    end
    return tbl
end

function set_accesspoint_security(idx, cfg)
    local profilename
    local j
    local ifname = ifname_list[idx]
    local errmsg = {}
    local ret = "Success"

    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = idx
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["8x"]
        end
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = idx - 4
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["11x"]
        end
    end
    if cfg["ModeEnabled"] ~= nil then
        local authmode
        if cfg["ModeEnabled"] == "WPA2-Personal" then
            authmode = "WPA2PSK"
            if (is_controller) then
                tmp_mesh[j]["authMode"] = "0x0020"
                tmp_mesh[j]["encType"] = "0x0008"
            end
        elseif cfg["ModeEnabled"] == "WPA-Personal" then
            authmode = "WPAPSK"
            if (is_controller) then
                tmp_mesh[j]["authMode"] = "0x0002"
                tmp_mesh[j]["encType"] = "0x0008"
            end
        elseif cfg["ModeEnabled"] == "None" then
            authmode = "OPEN"
            if (is_controller) then
                tmp_mesh[j]["authMode"] = "0x0001"
                tmp_mesh[j]["encType"] = "0x0001"
                cfg["EncryptionMode"] = "NONE"
            end
        else
            errmsg["ModeEnabled"] = "ModeEnabled value is not supported"
            ret = "Failed"
        end
        -- set AuthMode in .dat file
        if errmsg["ModeEnabled"] == nil then
            local authmode_str = util.exec_trim("wificonf -f "..profilename.." get AuthMode")
            authmode_str = mtkwifi.token_set(authmode_str, j, authmode)
            util.exec("wificonf -f "..profilename.." set AuthMode ".."\""..authmode_str.."\"")
        end
        -- execute it
        -- util.exec("iwpriv "..ifname.." set AuthMode="..authmode)
    end

    if cfg["EncryptionMode"] ~= nil then
        -- set EncrypType in .dat
        if cfg["EncryptionMode"] == "TKIP" or cfg["EncryptionMode"] == "AES" or cfg["EncryptionMode"] == "TKIP/AES" or cfg["EncryptionMode"] == "NONE" then
            local encryptype_str = util.exec_trim("wificonf -f "..profilename.." get EncrypType")
            encryptype_str = mtkwifi.token_set(encryptype_str, j, cfg["EncryptionMode"])
            util.exec("wificonf -f "..profilename.." set EncrypType ".."\""..encryptype_str.."\"")
        else
            errmsg["EncryptionMode"] = "EncryptionMode value is not supported"
            ret = "Failed"
        end
        -- execute it
        -- util.exec("iwpriv "..ifname.." set EncrypType="..cfg["EncryptionMode"])
    end

    if cfg["PreSharedKey"] ~= nil then
        -- set WPAPSK{j} in .dat file
        if #cfg["PreSharedKey"] > 0 then
            ret, errmsg["PreSharedKey"] = validate_pwd(cfg["PreSharedKey"])
            if ret == "Success" then
                util.exec("wificonf -f "..profilename.." set WPAPSK"..j.." ".."\""..cfg["PreSharedKey"].."\"")
                if (is_controller) then
                    tmp_mesh[j]["passPhrase"] = cfg["PreSharedKey"]
                end
            end
        else
            cfg["PreSharedKey"] = util.exec_trim("wificonf -f "..profilename.." get WPAPSK"..j)
        end
        -- execute it
        -- util.exec("iwpriv "..ifname.." set WPAPSK="..cfg["PreSharedKey"])
    end
    return ret, errmsg
end

function set_all_accesspoint_security(tbl)
    local ret
    local errmsg

    for idx, cfg in pairs(tbl) do
        if idx ~= nil and cfg ~= nil then
            if cfg["Security"] ~= nil then
                ret, errmsg = set_accesspoint_security(tonumber(idx), cfg["Security"])
                if ret == "Failed" then
                    return "Failed", errmsg
                end
            else
                return "Failed", "No Security config to set for instance "..idx
            end
        end
    end

    return "Success"
end

function get_AssociationTime(hr, min, sec)
    return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() - hr * 3600 - min * 60 - sec)
end

function __trim(s)
  if s then return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

function __spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    --[[
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
        -- table.sort(keys, order)
    else
        table.sort(keys)
    end
    ]]
    table.sort(keys, order)
    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
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

function get_associateddevice_stat(mac)
    local ret = {
        LastDataDownlinkRate = "",
        LastDataUplinkRate = "",
        X_VT_DataRate = "",
        BytesSent = "",
        BytesReceived = "",
        PacketsSent = "",
        PacketsReceived = ""
    }
    
    local scan_result = get_macTable()
    local xx = {}
    for i, line in ipairs(__lines(scan_result)) do
        local is_mac_addr_present = string.match(line, "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x")
        -- If the line does not contain any MAC address and length is greater than 40 bytes,
        -- then, the line is the header of the get_mac_table page.
        if #line>40 and not is_mac_addr_present then
            xx.MAC = {string.find(line, "MAC "),17}
            xx.LastDataDownlinkRate = {string.find(line, "TxRealKbos"),12}
            xx.LastDataUplinkRate = {string.find(line, "RxRealKbos"),12}
            xx.X_VT_DataRate = {string.find(line, "RxPhyMbps"),12}
            xx.TxDataByte = {string.find(line, "TxDataBytes"),24}
            xx.RxDataByte = {string.find(line, "RxDataBytes"),24}
            xx.TxDataFr = {string.find(line, "TxDataFrames"),24}
            xx.RxDataFr = {string.find(line, "RxDataFrames"),24}
        end

        if #line>40 and is_mac_addr_present then
            local macchk = string.upper(__trim(string.sub(line, xx.MAC[1], xx.MAC[1]+xx.MAC[2])))
            if macchk == mac then
                ret["LastDataDownlinkRate"] = __trim(string.sub(line, xx.LastDataDownlinkRate[1], xx.LastDataDownlinkRate[1]+xx.LastDataDownlinkRate[2]))
                ret["LastDataUplinkRate"] = __trim(string.sub(line, xx.LastDataUplinkRate[1], xx.LastDataUplinkRate[1]+xx.LastDataUplinkRate[2]))
                ret["X_VT_DataRate"] = __trim(string.sub(line, xx.X_VT_DataRate[1], xx.X_VT_DataRate[1]+xx.X_VT_DataRate[2]))
                ret["BytesSent"] = __trim(string.sub(line, xx.TxDataByte[1], xx.TxDataByte[1]+xx.TxDataByte[2]))
                ret["BytesReceived"] = __trim(string.sub(line, xx.RxDataByte[1], xx.RxDataByte[1]+xx.RxDataByte[2]))
                ret["PacketsSent"] = __trim(string.sub(line, xx.TxDataFr[1], xx.TxDataFr[1]+xx.TxDataFr[2]))
                ret["PacketsReceived"] = __trim(string.sub(line, xx.RxDataFr[1], xx.RxDataFr[1]+xx.RxDataFr[2]))
                break
            end 
        end
    end

    return ret
end

function get_accesspoint_associateddevice(idx)
    local ifname = ifname_list[idx]
    local count = 0
    local staTable = get_staTable() 
    local stalist = staTable[ifname]
    local r_stalist = {}

    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
    end
    for _ in pairs(stalist) do count = count + 1 end
    if count == 0 then
        return {}
    end
    for i=0, count-1 do
        local idx = tostring(i+1)
        r_stalist[idx] = {}
        r_stalist[idx]["MACAddress"] = stalist[i]["MacAddr"]
        r_stalist[idx]["OperatingStandard"] = WirelessModeList[tonumber(util.exec_trim("wificonf -f "..profilename.." get WirelessMode"))]
        r_stalist[idx]["Active"] = "true"
        r_stalist[idx]["AssociationTime"] = get_AssociationTime(tonumber(stalist[i]["Hr"]), tonumber(stalist[i]["Min"]), tonumber(stalist[i]["Sec"]))
        r_stalist[idx]["SignalStrength"] = tostring(math.floor((tonumber(stalist[i]["AvgRssi0"]) + tonumber(stalist[i]["AvgRssi1"])) / 2))
        r_stalist[idx]["Noise"] = "-90"
        r_stalist[idx]["AuthenticationState"] = "true"
        -- r_stalist[idx]["Stats"] = get_associateddevice_stat(stalist[i]["MacAddr"])
        r_stalist[idx]["Stats"] = {}
        r_stalist[idx]["Stats"]["ErrorsSent"] = "0"
        r_stalist[idx]["Stats"]["ErrorsReceived"] = "0"

        -- luci.util.exec("iwpriv ra0 set enable_txrx_stat=1")
        -- luci.util.exec("sleep 1")
        local assoc_device_stats = get_associateddevice_stat(stalist[i]["MacAddr"])
        r_stalist[idx]["LastDataDownlinkRate"] = assoc_device_stats["LastDataDownlinkRate"]
        r_stalist[idx]["LastDataUplinkRate"] = assoc_device_stats["LastDataUplinkRate"]
        r_stalist[idx]["X_VT_DataRate"] = assoc_device_stats["X_VT_DataRate"]
        r_stalist[idx]["Stats"]["BytesSent"] = assoc_device_stats["BytesSent"]
        r_stalist[idx]["Stats"]["BytesReceived"] = assoc_device_stats["BytesReceived"]
        r_stalist[idx]["Stats"]["PacketsSent"] = assoc_device_stats["PacketsSent"]
        r_stalist[idx]["Stats"]["PacketsReceived"] = assoc_device_stats["PacketsReceived"]

        -- luci.util.exec("iwpriv ra0 set enable_txrx_stat=0")
    end
    return {[tostring(idx)] = {["AssociatedDevice"] = r_stalist}}
end

function get_all_accesspoint_associateddevice()
    local tbl = {}
    local tmp_entry = {}
    for i = 1,8,1 do
        tmp_entry = get_accesspoint_associateddevice(i)
        tbl[tostring(i)] = tmp_entry[tostring(i)]
    end
    return tbl
end

function get_assocdev_num()
    local string = ""
    local staTable = get_staTable()
    local count
    for i = 1,8,1 do
        stalist = staTable[ifname_list[i]]
        count = 0;
        for _ in pairs(stalist) do count = count + 1 end
        if i > 1 then
            string = string .. ","
        end
        string = string .. count
    end
    return string
end

--------------------------------------------------------------------------------------
--------------------------------This block handles ssid-------------------------------
--------------------------------------------------------------------------------------
function get_ssid(idx)
    local profilename
    local tmpdatname
    local j
    local statstbl = {
        BytesSent = "0",
        BytesReceived = "0",
        PacketsSent = "0",
        PacketsReceived = "0",
        ErrorsSent = "0",
        ErrorsReceived = "0"
    }
    local devrole = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
    local map_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        tmpdatname = "/etc/map/mt7615.1.2G.tmpdat"
        j = idx
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        tmpdatname = "/etc/map/mt7615.1.5G.tmpdat"
        j = idx - 4
    end
    -- get enableSSID
    local enableSSID_str = util.exec_trim("wificonf -f "..profilename.." get EnableSSID")
    local enable = mtkwifi.token_get(enableSSID_str, j, "0")
    -- get Name
    local name = util.exec_trim("wificonf -f "..profilename.." get SSID"..j)
    if map_enable == "1" and devrole == "2" then
        local tmpname = util.exec_trim("wificonf -f "..tmpdatname.." get SSID"..j)
        if tmpname and #tmpname > 0 then
            name = tmpname
        end
    end
    -- get MAC
    local macaddr = util.exec_trim("cat /sys/class/net/"..ifname_list[idx].."/address 2>/dev/null")

    local scan_result = read_pipe("iwpriv ra0 get_driverinfo")
    local xx = {}

    for i, line in ipairs(__lines(scan_result)) do
        local is_mac_addr_present = string.match(line, "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x")
        -- If the line does not contain any MAC address and length is greater than 40 bytes,
        -- then, the line is the header of the get_mac_table page.
        if #line>40 and not is_mac_addr_present then
            xx.SSID = {string.find(line, "SSID "),32}
            xx.BytesSent = {string.find(line, "TxDataPktByte"),24}
            xx.BytesReceived = {string.find(line, "RxDataPktByte"),24}
            xx.PacketsSent = {string.find(line, "TxDataPkt"),24}
            xx.PacketsReceived = {string.find(line, "RxDataPkt"),24}
            xx.ErrorsSent = {string.find(line, "TxDroppedPkt"),24}
            xx.ErrorsReceived = {string.find(line, "RxDroppedPkt"),24}
        end

        if #line>40 and is_mac_addr_present then
            local ssid_name = __trim(string.sub(line, xx.SSID[1], xx.SSID[1]+xx.SSID[2]))
            if ssid_name == name then
                statstbl["BytesSent"] = __trim(string.sub(line, xx.BytesSent[1], xx.BytesSent[1]+xx.BytesSent[2]))
                statstbl["BytesReceived"] = __trim(string.sub(line, xx.BytesReceived[1], xx.BytesReceived[1]+xx.BytesReceived[2]))
                statstbl["PacketsSent"] = __trim(string.sub(line, xx.PacketsSent[1], xx.PacketsSent[1]+xx.PacketsSent[2]))
                statstbl["PacketsReceived"] = __trim(string.sub(line, xx.PacketsReceived[1], xx.PacketsReceived[1]+xx.PacketsReceived[2]))
                statstbl["ErrorsSent"] = __trim(string.sub(line, xx.ErrorsSent[1], xx.ErrorsSent[1]+xx.ErrorsSent[2]))
                statstbl["ErrorsReceived"] = __trim(string.sub(line, xx.ErrorsReceived[1], xx.ErrorsReceived[1]+xx.ErrorsReceived[2]))
                break
            end 
        end
    end

    local this_entry_tbl = 
    {
        Enable = enable == "1" and "true" or "false",
        Status = enable == "1" and "Enabled" or "Disabled",
        Name = name,
        BSSID = macaddr,
        MACAddress = macaddr,
        SSID = name,
        Stats = statstbl
    }
    return {[tostring(idx)] = this_entry_tbl}
end

function get_all_ssid()
    local tbl = {}
    local tmp_entry = {}
    for i = 1,8,1 do
        tmp_entry = get_ssid(i)
        tbl[tostring(i)] = tmp_entry[tostring(i)]
    end
    return tbl
end

function set_ssid(idx, cfg)
    local profilename
    local j
    local ifname = ifname_list[idx]
    local ret = "Success"
    local errmsg = {}
    if idx < 5 then
        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
        j = idx
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["8x"]
        end
    else
        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
        j = idx - 4
        if (is_mesh_enable) then
            tmp_mesh = mesh_cfgs["wildCardAlMacCfgs"]["FF:FF:FF:FF:FF:FF"]["11x"]
        end
    end
    if cfg["Enable"] ~= nil then
        -- set enableSSID in .dat file
        if cfg["Enable"] == "true" or cfg["Enable"] == "false" then
            local enableSSID_str = util.exec_trim("wificonf -f "..profilename.." get EnableSSID")
            enableSSID_str = mtkwifi.token_set(enableSSID_str, j, cfg["Enable"] == "true" and "1" or "0")
            util.exec("wificonf -f "..profilename.." set EnableSSID ".."\""..enableSSID_str.."\"")
        else
            ret = "Failed"
            errmsg["Enable"] = "Enable value is not supported"
        end
        -- util.exec("ifconfig "..ifname.." "..(cfg["Enable"] == "true" and "up" or "down"))
    end
    if cfg["SSID"] ~= nil then
        ret, errmsg["SSID"] = validate_ssid(cfg["SSID"])
        if ret == "Success" then
            util.exec("wificonf -f "..profilename.." set SSID"..j.." ".."\""..cfg["SSID"].."\"")
            -- util.exec("iwpriv "..ifname.." set SSID=".."\""..cfg["SSID"].."\"")
            if (is_controller) then
                tmp_mesh[j]["ssid"] = cfg["SSID"]
            end
        end
    end
    if idx == 1 then
        if req_bandstr == 1 then
            set_ssid(5, cfg)
        end
    end
    return ret, errmsg
end

function set_all_ssid(tbl)
    local ret
    local errmsg = {}

    for idx, cfg in pairs(tbl) do
        local err
        if idx ~= nil and cfg ~= nil then
            ret, err = set_ssid(tonumber(idx), cfg)
            if ret == "Failed" then
                errmsg[tostring(idx)] = err
            end
        end
    end
    return ret, errmsg
end
--------------------------------------------------------------------------------------
--------------------------------End of ssid block-------------------------------------
--------------------------------------------------------------------------------------

function handle_wifi_ap_ssid()
    -- util.perror_hieupt35("handle_wifi_ap_ssid")
    local rv = {}
    local status1 = "Success"
    local status2 = "Success"
    local errmsg1 = {}
    local errmsg2 = {}
    if luci.http.getenv("REQUEST_METHOD") == "GET" then
            rv["AccessPoint_AssocDevNum"] = get_assocdev_num()
            rv["AccessPoint"] = get_all_accesspoint()
            rv["SSID"] = get_all_ssid()
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
        local devrole = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get DeviceRole")
        local map_enable = util.exec_trim("wificonf -f /etc/mapd_cfg.txt get MapEnable")
        local content = luci.http.content()
        local table = json.decode(content)
        if map_enable == "1" then
            is_mesh_enable = true
            if devrole == "1" then
                is_controller = true
                mesh_cfgs = mtkwifi.load_easymesh_bss_cfgs()
            end
        end

        if table["AccessPoint"] ~= nil then
            status1, errmsg1 = set_all_accesspoint(table["AccessPoint"])
        end

        if table["SSID"] ~= nil then
            status2, errmsg2 = set_all_ssid(table["SSID"])
        end

        if status1 == "Success" and status2 == "Success" then
            rv.Status = "Success"
            luci.http.prepare_content("application/json")
            luci.http.write_json(rv)
            save_backup_cfg("/etc/wireless/mt7615/mt7615.1.2G.dat")
            save_backup_cfg("/etc/wireless/mt7615/mt7615.1.5G.dat")
            if (is_controller) then
                mtkwifi.save_easymesh_bss_cfgs(mtkwifi.get_bss_cfgs_from_dat())
                local bss_config_controller = "\""..mtkwifi.get_bss_config_priority().."\""
                os.execute("wificonf -f /etc/map_cfg.txt set bss_config_priority "..bss_config_controller)
                os.execute("wificonf -f /etc/mapd_cfg.txt set bss_config_priority "..bss_config_controller)
            end
            fork_exec("wifi reload")
        else
            rv.Status = "Failed"
            rv["DetailStatus"] = {}
            
            if next(errmsg1) ~= nil then
                rv["DetailStatus"]["AccessPoint"] = errmsg1
            end
            if next(errmsg2) ~= nil then
                rv["DetailStatus"]["SSID"] = errmsg2
            end
            luci.http.prepare_content("application/json")
            luci.http.write_json(rv)
        end
	end
end

-- function handle_wifi_accesspoint(idx)
--     -- util.perror_hieupt35("handle_wifi_accesspoint")
--     local rv = {}
--     if luci.http.getenv("REQUEST_METHOD") == "GET" then
--         if idx and #idx > 0 then
--             rv = get_accesspoint(tonumber(idx))
--         else
--             rv = get_all_accesspoint()
--         end
-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
-- 		local content = luci.http.content()
-- 		local table = json.decode(content)

--         rv.Status = set_all_accesspoint(table)

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	end
-- end

-- function handle_wifi_accesspoint_security(idx)
--     -- util.perror_hieupt35("handle_wifi_accesspoint_security")
--     local rv = {}
--     if luci.http.getenv("REQUEST_METHOD") == "GET" then
--         if idx and #idx > 0 then
--             rv = get_accesspoint_security(tonumber(idx))
--         else
--             rv = get_all_accesspoint_security()
--         end
-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
-- 		local content = luci.http.content()
-- 		local table = json.decode(content)

--         rv.Status = set_all_accesspoint_security(table)

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	end
-- end

-- function handle_wifi_accesspoint_associateddevice(idx)
--     -- util.perror_hieupt35("handle_wifi_accesspoint_associateddevice")
--     local rv = {}
--     if luci.http.getenv("REQUEST_METHOD") == "GET" then
--         if idx and #idx > 0 then
--             rv = get_accesspoint_associateddevice(tonumber(idx))
--         else
--             rv = get_all_accesspoint_associateddevice()
--         end
-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then

--         rv.Status = "Failed"

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	end
-- end

-- function handle_wifi_accesspoint_assocdevnum()
--     -- util.perror_hieupt35("handle_wifi_accesspoint_assocdevnum")
--     local rv = {}
--     if luci.http.getenv("REQUEST_METHOD") == "GET" then        
--         rv["AccessPoint_AssocDevNum"] = get_assocdev_num()

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then

--         rv.Status = "Failed"

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	end
-- end
-- function handle_wifi_SSID(idx)
--     util.perror_hieupt35("handle_wifi_radio")
--     local rv = {}
--     if luci.http.getenv("REQUEST_METHOD") == "GET" then
--         if idx and #idx > 0 then
--             rv = get_ssid(tonumber(idx))
--         else
--             rv = get_all_ssid()
--         end
-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
-- 		local content = luci.http.content()
-- 		local table = json.decode(content)

--         rv.Status = set_all_ssid(table)

-- 		luci.http.prepare_content("application/json")
-- 		luci.http.write_json(rv)
-- 	end
-- end
