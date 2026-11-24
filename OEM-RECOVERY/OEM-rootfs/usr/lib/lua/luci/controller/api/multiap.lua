module("luci.controller.api.multiap", package.seeall)
local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")
local nixio = require("nixio")
local os = require("os")

local default_time = "1970-01-01T00:00:00+00:00"
local back_haul_link_type_list = 
{   
    [1] = "None", 
    [2] = "Wi-Fi", 
    [3] = "MoCA", 
    [4] = "Ethernet", 
    [5] = "G.hn", 
    [6] = "HPNA", 
    [7] = "HomePlug", 
    [8] = "UPA"
}

local ifname_list = 
{   
    [1] = "ra0", 
    [2] = "ra1", 
    [3] = "ra2", 
    [4] = "ra3", 
    [5] = "rax0", 
    [6] = "rax1", 
    [7] = "rax2", 
    [8] = "rax3"
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
local rj
local r
local assoc_dev_num_arr={} -- maximum 64 entries
local bssid_dev_num_arr={}
local radio_dev_num_arr={}
local maximum_ap_dev_num=8
function index()
--    entry({"api", "multiap_numurl"}, call("handle_multiap_numurl"))
    entry({"api", "wifi", "multiap"}, call("handle_wifi_multiap")).leaf = true
end

function get_multi_ap_associated_devices(i_dev,macaddr,i_ra,channel,i_bss,bssid,entry_num,operate_stand)
    local default_res = {
        MACAddress = "FF:FF:FF:FF:FF:FF",
        OperatingStandard = "",
        Active = "true",
        AssociationTime = default_time,
        LastDataDownlinkRate = "0",
        LastDataUplinkRate = "0",
        SignalStrength = "0",
        Noise = "0"
    }
    local fallback_ret = {
        ["1"] = default_res
    }
    local assoc_device_list = {}

    if rj == nil or rj["luaTopologyInfo"] == nil then
        return fallback_ret
    end

    for _, device in ipairs(r) do
        if device == nil then
            return fallback_ret
        end
        if device["AL MAC"] == macaddr then
            for _, radio in ipairs(device["Radio Info"]) do
                if radio == nil then
                    return fallback_ret
                end
                if tonumber(radio["channel"]) == channel then
                    for _, bss in ipairs(radio["BSSINFO"]) do
                        if bss == nil then
                            return fallback_ret
                        end

                        if bss["BSSID"] == bssid then
                            local i_sta = ((i_dev-1)*8+1) + ((i_ra-1)*4)+(i_bss-1)
                            assoc_dev_num_arr[i_sta]=tostring(entry_num)
                            for i = 1, entry_num,1 do
                                local assoc_device_tail = {
                                    MACAddress = "FF:FF:FF:FF:FF:FF",
                                    OperatingStandard = operate_stand,
                                    Active = "true",
                                    AssociationTime = default_time,
                                    LastDataDownlinkRate = "0",
                                    LastDataUplinkRate = "0",
                                    SignalStrength = "0",
                                    Noise = "-90" -- Hardcode
                                }
                        
                                for k,v in pairs(bss["connected sta info"]) do 
                                    if k == i and v ~= nil then
                                        assoc_device_tail["MACAddress"] = v["STA MAC address"]
                                        if v["uplink speed"] ~= nil then
                                            assoc_device_tail["LastDataDownlinkRate"] = tostring(v["uplink speed"])
                                            assoc_device_tail["LastDataUplinkRate"] = tostring(v["uplink speed"])
                                        end
                                        if v["uplink rssi"] ~= nil then
                                            assoc_device_tail["SignalStrength"] = tostring(2*(tonumber(v["uplink rssi"]) + 110))
                                        end
                                        if v["last assoc time"] ~= nil then
                                            assoc_device_tail["AssociationTime"] = os.date("%Y-%m-%dT%H:%M:%SZ", os.time() - tonumber(v["last assoc time"]))
                                        end
                                    end
                                end

                                assoc_device_list[tostring(i)] = assoc_device_tail
                            end
                            break
                        end
                    end
                    break
                end
            end
            break
        end
    end
    return assoc_device_list
end

function get_multi_ap(i_dev,macaddr,i_ra,channel,entry_num,operate_stand)
    local default_res = {
        BSSID = "",
        SSID = "",
        AssociatedDeviceNumberOfEntries = "0",
        AssociatedDevice = {}
    }
    local fallback_ret = {
        ["1"] = default_res
    }
    local ap_list = {}
    local assoc_device_count = 0

    if rj == nil or rj["luaTopologyInfo"] == nil then
        return fallback_ret
    end

    for _, device in ipairs(r) do
        if device["AL MAC"] == macaddr then
            for _, radio in ipairs(device["Radio Info"]) do
                if tonumber(radio["channel"]) == channel then
                    for i = 1, entry_num, 1 do
                        local ap_tail = {
                            BSSID = "",
                            SSID = "",
                            AssociatedDeviceNumberOfEntries = "0",
                            AssociatedDevice = {}
                        }
                        
                        for k,v in pairs(radio["BSSINFO"]) do 
                            if k == i and v ~= nil then
                                if v["BSSID"] ~= nil then
                                    ap_tail["BSSID"] = v["BSSID"]
                                end
                                if v["SSID"] ~= nil then
                                    ap_tail["SSID"] = v["SSID"]
                                end
                                assoc_device_count = 0 --init
                                if v["connected sta info"] ~= nil then
                                    for m,n in pairs(v["connected sta info"]) do 
                                        assoc_device_count = assoc_device_count + 1
                                    end
                                    ap_tail["AssociatedDeviceNumberOfEntries"] = tostring(assoc_device_count)
                                    ap_tail["AssociatedDevice"] = get_multi_ap_associated_devices(i_dev,macaddr,i_ra,channel,i,v["BSSID"],assoc_device_count,operate_stand)
                                else
                                    ap_tail["AssociatedDeviceNumberOfEntries"] = tostring(assoc_device_count)
                                end
                            end
                        end
                        ap_list[tostring(i)] = ap_tail
                    end
                    break
                end
            end
            break
        end
    end
    -- util.perror_hieupt35("get_multi_ap:"..debug.getinfo(1).currentline)
    return ap_list
end

function get_multi_ap_radio(i_dev,macaddr)
    local default_res = {
        MACAddress = "",
        OperatingFrequencyBand = "",
        OperatingStandards = "",
        Channel = "",
        CurrentOperatingChannelBandwidth = "",
        TransmitPower = "",
        APNumberOfEntries = "",
        ExtensionChannel = "",
        MCS = "",
        AP = {}
    }
    local fallback_ret = {
        ["1"] = default_res
    }
    local radio_list = {}
    local i = 0
    local idx = ""
    local profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
    local bssid_count = 0
    
    if rj == nil or rj["luaTopologyInfo"] == nil then
        default_res["MACAddress"] = "FF:FF:FF:FF:FF:FF"
        default_res["OperatingFrequencyBand"] = ""
        default_res["OperatingStandards"] = ""
        default_res["Channel"] = "0"
        default_res["CurrentOperatingChannelBandwidth"] = "0"
        default_res["TransmitPower"] = "0"
        default_res["APNumberOfEntries"] = "0"
        default_res["ExtensionChannel"] = ""
        default_res["MCS"] = ""
        default_res["AP"] = {}
        return fallback_ret
    end
    
    for _, device in ipairs(r) do
        if device["AL MAC"] == macaddr then
            for i_ra, radio in ipairs(device["Radio Info"]) do
                i = i + 1
                local radio_tail = {
                    MACAddress = "",
                    OperatingFrequencyBand = "",
                    OperatingStandards = "",
                    Channel = "",
                    CurrentOperatingChannelBandwidth = "",
                    TransmitPower = "100",
                    APNumberOfEntries = "",
                    ExtensionChannel = "",
                    MCS = "",
                    AP = {}
                }
                if radio["identifier"] ~= nil then
                    radio_tail["MACAddress"] = string.upper(radio["identifier"])
                end
                if radio["channel"] ~= nil then
                    radio_tail["Channel"] = radio["channel"]
                    if tonumber(radio["channel"]) >= 14 then
                        -- 5GHz
                        profilename = "/etc/wireless/mt7615/mt7615.1.5G.dat"
                        radio_tail["OperatingFrequencyBand"] = "5GHz"
                    else
                        -- 2GHz
                        profilename = "/etc/wireless/mt7615/mt7615.1.2G.dat"
                        radio_tail["OperatingFrequencyBand"] = "2.4GHz"
                    end
                end
                radio_tail["OperatingStandards"] = WirelessModeList[tonumber(util.exec_trim("wificonf -f "..profilename.." get WirelessMode"))] --Get from current device
                if radio["BW"] ~= nil then
                    radio_tail["CurrentOperatingChannelBandwidth"] = radio["BW"]
                end

                bssid_count = 0 --init
                for _,bssid in ipairs(radio["BSSINFO"]) do
                    bssid_count = bssid_count + 1
                end
                radio_tail["APNumberOfEntries"]=tostring(bssid_count)
                bssid_dev_num_arr[((i_dev-1)*2 + 1) + (i_ra -1)] = tostring(bssid_count)
                if bssid_count ~= 0 then
                    radio_tail["AP"] = get_multi_ap(i_dev,macaddr,i_ra,tonumber(radio["channel"]),bssid_count,radio_tail["OperatingStandards"])
                end
                radio_list[tostring(i)] = radio_tail
            end
            break
        end
    end
    return radio_list
end
function get_multi_ap_ap_device()
    local count = 0
    local default_res = {
        MACAddress = "",
        Manufacturer = "",
        ManufacturerOUI = "",
        ProductClass = "",
        SerialNumber = "",
        SoftwareVersion = "",
        LastContactTime = "",
        BackhaulLinkType = "",
        BackhaulMACAddress = "",
        BackhaulBytesSent = "",
        BackhaulBytesReceived = "",
        BackhaulLinkUtilization = "",
        BackhaulSignalStrength = "",
        X_VT_BackhaulDataRate = "",
        X_VT_BackhaulNoise = "",
        X_DeviceName = "",
        RadioNumberOfEntries = "",
        DFSEnable = "",
        Radio = {}
    }
    local fallback_ret = {
        ["1"] = default_res
    }
    local multiap_list={}
    local count = 0
    local Backhaul_mac_addr = ""
    local i = 1
    local idx = ""
    local controller_existed = false

    if rj == nil or rj["luaTopologyInfo"] == nil then
        default_res["MACAddress"] = "FF:FF:FF:FF:FF:FF"
        default_res["Manufacturer"] = "Viettel Group"  -- Hard code
        default_res["ManufacturerOUI"] = "240B2A"      -- Hard code   
        default_res["ProductClass"] = "vAP-120WD"      -- Hard code
        default_res["SerialNumber"] = ""
        default_res["SoftwareVersion"] = ""
        default_res["LastContactTime"] = default_time
        default_res["BackhaulMACAddress"] = ""
        default_res["BackhaulLinkType"] = ""
        default_res["BackhaulLinkUtilization"] = "0"
        default_res["BackhaulSignalStrength"] = "0"
        default_res["X_VT_BackhaulDataRate"] = "0"
        default_res["X_VT_BackhaulNoise"] = "0"
        default_res["X_DeviceName"] = ""
        default_res["RadioNumberOfEntries"] = "0"
        default_res["Radio"] = {}
        return tostring(count), fallback_ret
    end

    for _,device in pairs(r) do
        if device["AL MAC"] ~= nil and (tostring(device["Device role"]) == "01" or tostring(device["Device role"]) == "02") then 
            count = count + 1
        end
        if device["Device role"] == "01" and device["AL MAC"] ~= nil and device["Serial number"] ~= nil then
            local string_present = string.find(device["Serial number"], "VTGR")
            if string_present then
                controller_existed = true
                Backhaul_mac_addr = string.upper(device["AL MAC"])
            end
        end
    end

    if controller_existed == true then
        for _, device in ipairs(r) do
            local role = device["Device role"]
            local string_present = string.find(device["Serial number"], "VTGR")
            if role == "01" and string_present then -- Controller idx is always 1
                local multiap_pre = {
                    MACAddress = "",
                    Manufacturer = "Viettel Group", -- Hard code // do SysHwInfo vendorname r
                    ManufacturerOUI = "240B2A", -- Hard code
                    ProductClass = "",
                    SerialNumber = "",
                    SoftwareVersion = "",
                    LastContactTime = default_time,
                    BackhaulLinkType = "None",
                    BackhaulMACAddress = "",
                    BackhaulBytesSent = "",
                    BackhaulBytesReceived = "",
                    BackhaulLinkUtilization = "0",
                    BackhaulSignalStrength = "0",
                    X_VT_BackhaulDataRate = "0",
                    X_VT_BackhaulNoise = "0",
                    X_DeviceName = "AP",
                    DFSEnable = "true",
                    RadioNumberOfEntries = "",
                    Radio = {}
                }

                if device["AL MAC"] ~= nil then
                    multiap_pre["MACAddress"] = string.upper(device["AL MAC"])
                end

                if device["Product class"] ~= nil then
                    multiap_pre["ProductClass"] = device["Product class"]
                end
               
                if device["Serial number"] ~= nil then
                    multiap_pre["SerialNumber"] = string.upper(device["Serial number"])
                end
                
                if device["Firmware version"] ~= nil then
                    multiap_pre["SoftwareVersion"] = string.upper(device["Firmware version"])
                end

                if device["Device name"] ~= nil then
                    multiap_pre["X_DeviceName"] = device["Device name"]
                end

                if device["Number of radios"] ~= nil then
                    multiap_pre["RadioNumberOfEntries"] = device["Number of radios"]
                    radio_dev_num_arr[1] = device["Number of radios"]
                    if tonumber(device["Number of radios"]) ~= 0 then
                        multiap_pre["Radio"] = get_multi_ap_radio(1,device["AL MAC"])
                    end
                end
                multiap_list["1"] = multiap_pre
            elseif role == "02" then
                i=i+1
                local multiap_tail = {
                    MACAddress = "",
                    Manufacturer = "Viettel Group", -- Hard code // do SysHwInfo vendorname r
                    ManufacturerOUI = "240B2A", -- Hard code
                    ProductClass = "",
                    SerialNumber = "",
                    SoftwareVersion = "",
                    LastContactTime = default_time,
                    BackhaulLinkType = back_haul_link_type_list[2],    -- Wi-Fi
                    BackhaulMACAddress = Backhaul_mac_addr,
                    BackhaulBytesSent = "",
                    BackhaulBytesReceived = "",
                    BackhaulLinkUtilization = "0",
                    BackhaulSignalStrength = "0",
                    X_VT_BackhaulDataRate = "0",
                    X_VT_BackhaulNoise = "0",
                    X_DeviceName = "AP",
                    DFSEnable = "true",
                    RadioNumberOfEntries = "",
                    Radio = {}
                }

                if device["AL MAC"] ~= nil then
                    multiap_tail["MACAddress"] = string.upper(device["AL MAC"])
                end

                if device["Product class"] ~= nil then
                    multiap_tail["ProductClass"] = device["Product class"]
                end 

                if device["Serial number"] ~= nil then
                    multiap_tail["SerialNumber"] = string.upper(device["Serial number"])
                end 

                if device["Firmware version"] ~= nil then
                    multiap_tail["SoftwareVersion"] = string.upper(device["Firmware version"])
                end

                if device["Device name"] ~= nil then
                    multiap_tail["X_DeviceName"] = device["Device name"]
                end

                for k,v in pairs(device["BH Info"]) do
                    if k == 1 and v ~= nil then
                        if v["Backhaul Medium Type"] == "Ethernet" then
                            multiap_tail["BackhaulLinkType"] =  back_haul_link_type_list[4]    -- Ethernet
                        elseif v["Backhaul Medium Type"] == "5G" then
                            multiap_tail["BackhaulLinkType"] =  back_haul_link_type_list[2]    -- Wi-Fi
                        end
                    end
                end

                if device["Upstream 1905 device"] ~= nil then
                    multiap_tail["BackhaulMACAddress"] = string.upper(device["Upstream 1905 device"])
                end

                if multiap_list["1"] == nil then
                    multiap_list["1"] = multiap_pre
                end

                if multiap_tail["BackhaulLinkType"] == "Ethernet" then
                    if device["backhaul link metrics"] ~= nil then
                        for k,v in pairs(device["backhaul link metrics"]) do
                            if device["Upstream 1905 device"] == v["neighbor_al"] then 
                                for m,n in pairs(v["metrics"]) do 
                                    if m == 1 and n~=nil then
                                        if n["phyRate"] ~= nil then
                                            multiap_tail["X_VT_BackhaulDataRate"] = "1000"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if multiap_tail["BackhaulLinkType"] == "Wi-Fi" then
                    multiap_tail["X_VT_BackhaulNoise"] = "-90"
                    if device["backhaul link metrics"] ~= nil then
                        for k,v in pairs(device["backhaul link metrics"]) do
                            if device["Upstream 1905 device"] == v["neighbor_al"] then 
                                for m,n in pairs(v["metrics"]) do 
                                    if m == 1 and n~=nil then
                                        if n["RSSI"] ~= nil then
                                            multiap_tail["BackhaulSignalStrength"] = tostring(2*(tonumber(n["RSSI"]) + 110))
                                        end
                                        if n["phyRate"] ~= nil then
                                            multiap_tail["X_VT_BackhaulDataRate"] = tostring(n["phyRate"])
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if device["Number of radios"] ~= nil then
                    multiap_tail["RadioNumberOfEntries"] = device["Number of radios"]
                    radio_dev_num_arr[i] = device["Number of radios"]
                    if tonumber(device["Number of radios"]) ~= 0 then
                        multiap_tail["Radio"] = get_multi_ap_radio(i,device["AL MAC"])
                    end
                end
                multiap_list[tostring(i)] = multiap_tail
            end
        end
    else
        i=0 --start from 1
        for _, device in ipairs(r) do
            local role = device["Device role"]
            if role == "02" then
                i=i+1
                local multiap_tail= {
                    MACAddress = "",
                    Manufacturer = "Viettel Group", -- Hard code // do SysHwInfo vendorname r
                    ManufacturerOUI = "240B2A", -- Hard code
                    ProductClass = "",
                    SerialNumber = "",
                    SoftwareVersion = "",
                    LastContactTime = default_time,
                    BackhaulLinkType = back_haul_link_type_list[2],    -- Wi-Fi
                    BackhaulMACAddress = Backhaul_mac_addr,
                    BackhaulBytesSent = "",
                    BackhaulBytesReceived = "",
                    BackhaulLinkUtilization = "0",
                    BackhaulSignalStrength = "0",
                    X_VT_BackhaulDataRate = "0",
                    X_VT_BackhaulNoise = "0",
                    X_DeviceName = "AP",
                    DFSEnable = "true",
                    RadioNumberOfEntries = "",
                    Radio = {}
                }

                if device["AL MAC"] ~= nil then
                    multiap_tail["MACAddress"] = string.upper(device["AL MAC"])
                end
                
                if device["Product class"] ~= nil then
                    multiap_tail["ProductClass"] = device["Product class"]
                end 

                if device["Serial number"] ~= nil then
                    multiap_tail["SerialNumber"] = string.upper(device["Serial number"])
                end 

                if device["Firmware version"] ~= nil then
                    multiap_tail["SoftwareVersion"] = string.upper(device["Firmware version"])
                end

                if device["Device name"] ~= nil then
                    multiap_tail["X_DeviceName"] = device["Device name"]
                end

                for k,v in pairs(device["BH Info"]) do
                    if k == 1 and v ~= nil then
                        if v["Backhaul Medium Type"]== "Ethernet" then
                            multiap_tail["BackhaulLinkType"] =  back_haul_link_type_list[4]    -- Ethernet
                        elseif v["Backhaul Medium Type"] == "5G" then
                            multiap_tail["BackhaulLinkType"] =  back_haul_link_type_list[2]    -- Wi-Fi
                        end
                    end
                end
                
                if device["Upstream 1905 device"] ~= nil then
                    multiap_tail["BackhaulMACAddress"] = string.upper(device["Upstream 1905 device"])
                end

                if multiap_tail["BackhaulLinkType"] == "Ethernet" then
                    if device["backhaul link metrics"] ~= nil then
                        for k,v in pairs(device["backhaul link metrics"]) do
                            if device["Upstream 1905 device"] == v["neighbor_al"] then 
                                for m,n in pairs(v["metrics"]) do 
                                    if m == 1 and n~=nil then
                                        if n["phyRate"] ~= nil then
                                            multiap_tail["X_VT_BackhaulDataRate"] = "1000"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                if multiap_tail["BackhaulLinkType"] == "Wi-Fi" then
                    multiap_tail["X_VT_BackhaulNoise"] = "-90"
                    if device["backhaul link metrics"] ~= nil then
                        for k,v in pairs(device["backhaul link metrics"]) do
                            if device["Upstream 1905 device"] == v["neighbor_al"] then 
                                for m,n in pairs(v["metrics"]) do 
                                    if m == 1 and n~=nil then
                                        if n["RSSI"] ~= nil then
                                            multiap_tail["BackhaulSignalStrength"] = tostring(2*(tonumber(n["RSSI"]) + 110))
                                        end
                                        if n["phyRate"] ~= nil then
                                            multiap_tail["X_VT_BackhaulDataRate"] = tostring(n["phyRate"])
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if device["Number of radios"] ~= nil then
                    multiap_tail["RadioNumberOfEntries"] = device["Number of radios"]
                    radio_dev_num_arr[i] = device["Number of radios"]
                    if tonumber(device["Number of radios"]) ~= 0 then
                        multiap_tail["Radio"] = get_multi_ap_radio(i,device["AL MAC"])
                    end
                end
                multiap_list[tostring(i)] = multiap_tail
            end
        end
    end
    return tostring(count), multiap_list
end

-- sonnh68: handle case mesh is disabled

function get_AssociationTime(hr, min, sec)
    return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() - hr * 3600 - min * 60 - sec)
end

function get_assocdev_num()
    local ioctl_help = require "ioctl_helper"
    local tbl = {}
    for i = 1,8,1 do
        local count = 0;
        local stalist = c_StaInfo(ifname_list[i])
        for _ in pairs(stalist) do count = count + 1 end
        table.insert(tbl, count)
    end
    return table.concat(tbl, ",")
end


function get_assocdev_if(ifname, operatestand)
    local ioctl_help = require "ioctl_helper"
    local count = 0;
    local r_stalist = {}
    local stalist = c_StaInfo(ifname)
    for _,v in pairs(stalist) do 
        count = count + 1
        local idx = tostring(count)
        r_stalist[idx] = {
            MACAddress = "",
            OperatingStandard = operatestand,
            Active = "true",
            AssociationTime = "",
            LastDataDownlinkRate = "",
            LastDataUplinkRate = "",
            SignalStrength = "",
            Noise = "-90"
        }
        if v["MacAddr"] ~= nil then
            r_stalist[idx]["MACAddress"] = string.lower(v["MacAddr"])
        end
        if v["Hr"] ~= nil and v["Min"] ~= nil and v["Sec"] ~= nil then
            r_stalist[idx]["AssociationTime"] = get_AssociationTime(tonumber(v["Hr"]), tonumber(v["Min"]), tonumber(v["Sec"]))
        end
        if v["DataRate"] ~= nil then
            r_stalist[idx]["LastDataDownlinkRate"] = tostring(tonumber(v["DataRate"]) * 1000)
        end
        if v["LastRxRate"] ~= nil then
            r_stalist[idx]["LastDataUplinkRate"] = tostring(tonumber(v["LastRxRate"]) * 1000)
        end
        if v["AvgRssi0"] ~= nill and v["AvgRssi1"] ~= nil then
            r_stalist[idx]["SignalStrength"] = tostring(math.floor((tonumber(v["AvgRssi0"]) + tonumber(v["AvgRssi1"])) / 2))
        end
    end

    return count, r_stalist
end

function get_multi_ap_radio_when_mesh_disabled()
    local rv = {}
    local band_5G = {
        ExtensionChannel = "",
        TransmitPower = "100",
        OperatingStandards = "",
        MACAddress = "4D:41:50:35:47:4C", --MAP5GL
        Channel = "",
        MCS = "",
        OperatingFrequencyBand = "5GHz",
        CurrentOperatingChannelBandwidth = "NA",
        APNumberOfEntries = "0",
        AP = {}
    }
    local band_2G = {
        ExtensionChannel = "",
        TransmitPower = "100",
        OperatingStandards = "",
        MACAddress = "4D:41:50:32:34:47", --MAP2G
        Channel = "",
        MCS = "",
        OperatingFrequencyBand = "2.4GHz",
        CurrentOperatingChannelBandwidth = "NA",
        APNumberOfEntries = "0",
        AP = {}
    }
    local ap_5G = {}
    local ap_2G = {}
    local profile_5G = "/etc/wireless/mt7615/mt7615.1.5G.dat"
    local profile_2G = "/etc/wireless/mt7615/mt7615.1.2G.dat"

    --5G
    local operate_stand_5 = WirelessModeList[tonumber(util.exec_trim("wificonf -f "..profile_5G.." get WirelessMode"))]
    if operate_stand_5 ~= nil then
        band_5G["OperatingStandards"] =  operate_stand_5
    end
    local ap_num_5 = util.exec_trim("wificonf -f "..profile_5G.." get BssidNum")
    if ap_num_5 ~= nil then 
        band_5G["APNumberOfEntries"] = ap_num_5
    end
    local channel_5 = util.exec_trim("iwconfig ra0 | grep Channel | awk '{print $2}' | awk -F= '{print $2}'")
    if channel_5 ~= nil then
        band_5G["Channel"] = channel_5
    end

    local ifname_5G = util.exec_trim("wificonf -f "..profile_5G.." get ifname")
    local iflist_5G = str2arr(ifname_5G, ";")
    local idx_5G = 0

    for k,v in pairs(iflist_5G) do
        idx_5G = idx_5G + 1
        local entry = {
            BSSID = "",
            SSID = "",
            AssociatedDeviceNumberOfEntries = "0",
            AssociatedDevice = {}
        }
        local ssid = util.exec_trim("iwconfig "..v.." | grep ESSID | awk '{print $4}' | awk -F: '{print $2}'")
        ssid = ssid:gsub('"', '')
        local bssid = util.exec_trim("iwconfig "..v.." | grep 'Access Point' | awk '{print $5}'")
        if ssid ~= nil then
            entry["SSID"] = ssid
        end
        if bssid ~= nil then
            entry["BSSID"] = bssid
        end

        local num_assoc_dev, assocdev_list = get_assocdev_if(v, band_5G["OperatingStandards"])
        entry["AssociatedDeviceNumberOfEntries"] = tostring(num_assoc_dev)
        if(num_assoc_dev > 0) then
            entry["AssociatedDevice"] = assocdev_list
        end
        ap_5G[tostring(idx_5G)] = entry
    end
    band_5G["AP"] = ap_5G


    --2G
    local operate_stand_2 = WirelessModeList[tonumber(util.exec_trim("wificonf -f "..profile_2G.." get WirelessMode"))]
    if operate_stand_2 ~= nil then
        band_2G["OperatingStandards"] = operate_stand_2
    end

    local ap_num_2 = util.exec_trim("wificonf -f "..profile_2G.." get BssidNum")
    if ap_num_2 ~= nil then
        band_2G["APNumberOfEntries"] = ap_num_2
    end

    local channel_2 = util.exec_trim("iwconfig rax0 | grep Channel | awk '{print $2}' | awk -F= '{print $2}'")
    if channel_2 ~= nil then
        band_2G["Channel"] = channel_2
    end

    local ifname_2G = util.exec_trim("wificonf -f "..profile_2G.." get ifname")
    local iflist_2G = str2arr(ifname_2G, ";")

    local idx_2G = 0
    for k,v in pairs(iflist_2G) do
        idx_2G = idx_2G + 1
        local entry = {
            BSSID = "",
            SSID = "",
            AssociatedDeviceNumberOfEntries = "0",
            AssociatedDevice = {}
        }
        local ssid = util.exec_trim("iwconfig "..v.." | grep ESSID | awk '{print $4}' | awk -F: '{print $2}'")
        ssid = ssid:gsub('"', '')
        if ssid ~= nil then
            entry["SSID"] = ssid
        end

        local bssid = util.exec_trim("iwconfig "..v.." | grep 'Access Point' | awk '{print $5}'")
        if bssid ~= nil then
            entry["BSSID"] = ssid
        end
        
        local num_assoc_dev, assocdev_list = get_assocdev_if(v,band_2G["OperatingStandards"])
        entry["AssociatedDeviceNumberOfEntries"] = tostring(num_assoc_dev)
        if(num_assoc_dev > 0) then
            entry["AssociatedDevice"] = assocdev_list
        end
        ap_2G[tostring(idx_2G)] = entry
    end
    band_2G["AP"] = ap_2G

    rv["1"] = band_5G
    rv["2"] = band_2G

    return rv
end

function get_roaming_rssi_threshold()
    local rssi = util.exec_trim("cat /etc/mapd_cfg.txt | grep APSteerRssiTh")
    local rssi_tbl = rssi:split("=")
    if rssi_tbl[2] ~= nill then
        return rssi_tbl[2]
    else
        return "0"
    end
end

function str2arr (inputstr, sep)
    if sep == nil then
            sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end

function get_multi_ap_when_mesh_disabled()
    local rv = {
        APDeviceNumberOfEntries = "1",
        APRadioNumberOfEntries = "2",
        APBssidNumberOfEntries = "4,4",
        APAssociatedDeviceNum  = "",
        APDevice = {}
    }
    local mutil_ap = {}
    local ap = {
        MACAddress = "",
        Manufacturer = "Viettel Group",  -- Hard code
        ManufacturerOUI = "240B2A",      -- Hard code 
        ProductClass = "vAP-120WD",      -- Hard code
        SerialNumber = "",
        SoftwareVersion = "",
        LastContactTime = "",
        BackhaulMACAddress = "",
        BackhaulLinkType = "", -- self define: mesh is disable
        BackhaulLinkUtilization = "0",
        BackhaulBytesSent = "0",
        BackhaulBytesReceived = "0",
        DFSEnable = "true",
        BackhaulSignalStrength = "0",
        X_VT_BackhaulDataRate = "0",
        X_VT_BackhaulNoise = "0",
        X_DeviceName = "",
        RadioNumberOfEntries = "2",
        Radio = {}
    }

    local macaddr = util.exec_trim("/sbin/uci get network.lan.macaddr")
    local fileversion = io.open("/usr/etc/version","r")
    local firmversion = fileversion:read("*line")
    local releasetime = fileversion:read("*line")
    local modelname = fileversion:read("*line")
    local imageversion = fileversion:read("*line")
    local serialnumber = util.exec_trim("sysHwInfo serialnumber r")
    local devicename = util.exec_trim("/sbin/uci get device.deviceinfo.devicename")

    local uptime = util.exec_trim("cat /proc/uptime")
    local uptime_tbl = uptime:split(".")
    if uptime_tbl[1] ~= nil then
        ap["LastContactTime"] = os.date("%Y-%m-%dT%H:%M:%SZ", os.time() - tonumber(uptime_tbl[1]))
    end

    if macaddr ~= nil then
        ap["MACAddress"] = macaddr
    end
    if serialnumber ~= nil then
        ap["SerialNumber"] = serialnumber
    end
    if imageversion ~= nil then
        ap["SoftwareVersion"] = imageversion
    end
    if devicename ~= nil then
        ap["X_DeviceName"] = devicename
    end
    ap["Radio"] = get_multi_ap_radio_when_mesh_disabled()

    mutil_ap["1"] = ap

    rv["APAssociatedDeviceNum"] = get_assocdev_num()
    rv["APDevice"] = mutil_ap
    return rv
end

function get_multi_ap_info_all()
    local ret = {}
    local assoc_dev_num_str=""
    local bssid_dev_num_str=""
    local radio_dev_num_str=""
    for i=1, maximum_ap_dev_num*2*4 do
        assoc_dev_num_arr[i]="0"
    end

    for i=1,maximum_ap_dev_num,1 do
        radio_dev_num_arr[i] = "0"
    end

    for i=1,maximum_ap_dev_num*2,1 do 
        bssid_dev_num_arr[i] = "0"
    end

    local ap_radio_num = ""

    local mesh_enable = util.exec_trim("cat /etc/mapd_cfg.txt | grep MapEnable | grep -Eo [0-9]+");
    if mesh_enable == "1" then 
        rj = c_get_vt_runtime_topology()
        if rj ~= nil  and rj["luaTopologyInfo"] ~= nil then
            r = json.decode(rj["luaTopologyInfo"])
            r = r["topology information"]

            ret["APDeviceNumberOfEntries"], ret["APDevice"] = get_multi_ap_ap_device()

            for k,v in ipairs(assoc_dev_num_arr) do
                if k == maximum_ap_dev_num*2*4 then
                    assoc_dev_num_str=assoc_dev_num_str..v
                else
                    assoc_dev_num_str=assoc_dev_num_str..v..","
                end
            end
            ret["APAssociatedDeviceNum"] = assoc_dev_num_str

            for k,v in ipairs(radio_dev_num_arr) do
                if k == maximum_ap_dev_num then
                    radio_dev_num_str=radio_dev_num_str..v
                else
                    radio_dev_num_str=radio_dev_num_str..v..","
                end
            end
            ret["APRadioNumberOfEntries"] = radio_dev_num_str

            for k,v in ipairs(bssid_dev_num_arr) do
                if k == maximum_ap_dev_num*2 then
                    bssid_dev_num_str=bssid_dev_num_str..v
                else
                    bssid_dev_num_str=bssid_dev_num_str..v..","
                end
            end
            ret["APBssidNumberOfEntries"] = bssid_dev_num_str
        end
    else
        --if Mesh is disabled
        ret = get_multi_ap_when_mesh_disabled()
    end
    ret["X_VT_RoamingRSSIThreshold"] = get_roaming_rssi_threshold()
    return ret
end

function set_multi_ap_info(tbl)
    local status = false
    local mesh_enable = util.exec_trim("cat /etc/mapd_cfg.txt | grep MapEnable | grep -Eo [0-9]+")
    local devrole = util.exec_trim("cat /etc/mapd_cfg.txt | grep DeviceRole | grep -Eo [0-9]+")

    if mesh_enable == "1" and devrole == "1" then
        if tbl["X_VT_RoamingRSSIThreshold"] ~= nil then
            local rssi = tbl["X_VT_RoamingRSSIThreshold"]
            local rssi_num = tonumber(rssi)
            if rssi_num >= 0 or rssi_num <= -90 then
                return false
            end

            local rth = c_apply_ap_steer_rssi_th(rssi)
            if rth.status == "SUCCESS" then
                local easymesh_cfgs = mtkwifi.load_profile(mtkwifi.__easymesh_profile_path())
                if easymesh_cfgs['APSteerRssiTh'] ~= rssi then
                    easymesh_cfgs['APSteerRssiTh'] = rssi
                    mtkwifi.save_easymesh_profile(easymesh_cfgs)
                    status = true
                end
                local easymesh_mapd_cfgs = mtkwifi.load_profile(mtkwifi.__easymesh_mapd_profile_path())
                local mapd_rssi = rssi_num + 94
                if easymesh_mapd_cfgs['LowRSSIAPSteerEdge_RE'] ~= mapd_rssi then
                    easymesh_mapd_cfgs['LowRSSIAPSteerEdge_RE'] = mapd_rssi
                    mtkwifi.save_easymesh_mapd_profile(easymesh_mapd_cfgs)
                    status = true
                end
            end
        end
    end
    return status
end

function handle_wifi_multiap(idx)
    -- util.perror_hieupt35("handle_wifi_multiap")
    if luci.http.getenv("REQUEST_METHOD") == "GET" then
        local rv = {}
        rv = get_multi_ap_info_all()
        luci.http.prepare_content("application/json")
        luci.http.write_json(rv)
    elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code
		if (table ~= nil) then
			if(set_multi_ap_info(table)) then
				rv.Status = "Success"
			end
		end
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

