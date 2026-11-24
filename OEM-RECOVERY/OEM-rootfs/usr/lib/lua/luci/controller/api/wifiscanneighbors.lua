module("luci.controller.api.wifiscanneighbors", package.seeall)

local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local nixio = require("nixio")
local os = require("os")
local mtkwifi = require("mtkwifi")


function index()
    entry({"api","wifiscanneighbors"}, call("handle_wifiscanneighbors"))
end

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
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
function scan_neighbors()
    os.execute("iwpriv rax0 set SiteSurvey=0")
    os.execute("sleep 1") -- depends on your env
    os.execute("iwpriv ra0 set SiteSurvey=0")
    os.execute("sleep 1") -- depends on your env
    local scan_result = read_pipe("iwpriv ra0 get_site_survey 2>/dev/null")
    local next_line_index = 0
    local rax_index = 0
    local ra0_index = 0
    local tbl_index = 1
    local cur_index
    local ap_list = {}
    local xx = {}
    local tmp

    while (tbl_index < 30) do
        for i, line in ipairs(__lines(scan_result)) do
            local is_mac_addr_present = string.match(line, "%s+%x%x:%x%x:%x%x:%x%x:%x%x:%x%x%s+")
            -- If the line does not contain any MAC address and length is greater than 40 bytes,
            -- then, the line is the header of the get_site_survey page.
            if #line>40 and not is_mac_addr_present then
                xx.Ch = {string.find(line, "Ch "),3}
                xx.SSID = {string.find(line, "SSID "),32}
                local fidx = string.find(line, "SSID_Len")
                if fidx then
                    xx.SSID_len = {fidx,2}
                end
                xx.BSSID = {string.find(line, "BSSID "),17}
                xx.Security = {string.find(line, "Security "),22}
                xx.Signal = {string.find(line, "Sig%a%al"),4}
                xx.Mode = {string.find(line, "W-Mode"),5}
                -- xx.ExtCh = {string.find(line, "ExtCH"),6}
                -- xx.WPS = {string.find(line, "WPS"),3}
                xx.NT = {string.find(line, "NT"),2}
                -- fidx = string.find(line, "OWETranIe")
                -- if fidx then
                --     xx.OWETranIe = {fidx,9}
                -- end
            end

            if #line>40 and is_mac_addr_present then
                ---
                tmp = {}
                local ssid
                if xx.SSID_len then
                    -- Maximum xx.SSID[2] characters are supported in SSID
                    local ssid_len = tonumber(__trim(string.sub(line, xx.SSID_len[1], xx.SSID_len[1]+xx.SSID_len[2]))) or xx.SSID[2]
                    if ssid_len > xx.SSID[2] or ssid_len < 0 then
                        ssid_len = xx.SSID[2]
                    end
                    ssid = string.sub(line, xx.SSID[1], xx.SSID[1]+ssid_len-1)
                else
                    ssid = __trim(string.sub(line, xx.SSID[1], xx.SSID[1]+xx.SSID[2]))
                    local ssid_len = tmp.ssid:len()
                end
                
                if ssid == "" then
                else 
                    tmp.SSID = ssid
                    tmp.Channel = __trim(string.sub(line, xx.Ch[1], xx.Ch[1]+xx.Ch[2]))
                    tmp.BSSID = string.upper(__trim(string.sub(line, xx.BSSID[1], xx.BSSID[1]+xx.BSSID[2])))
                    local security = __trim(string.sub(line, xx.Security[1], xx.Security[1]+xx.Security[2]))
                    tmp.SecurityModeEnabled = __trim(string.split(security, "/")[1])
                    tmp.EncryptionMode = __trim(string.split(security, "/")[2] or "NONE")
                    tmp.SignalStrength  = mtkwifi.__trim(string.sub(line, xx.Signal[1], xx.Signal[1]+xx.Signal[2]))
                    tmp.SupportedStandards = __trim(string.sub(line, xx.Mode[1], xx.Mode[1]+xx.Mode[2]))
                    local nt = __trim(string.sub(line, xx.NT[1], xx.NT[1]+xx.NT[2]))
                    if nt == "In" then
                        tmp.Mode = "Infrastructure"
                    else
                        tmp.Mode = "AdHoc"
                    end

                    if tonumber(tmp.Channel) > 35 then
                        tmp.Radio = "Device.Wifi.Radio.2"
                        tmp.OperatingFrequencyBand = "5GHz"
                        ra0_index = ra0_index + 1
                        if ra0_index < 16 then
                            ap_list[tostring(tbl_index)] = tmp
                            tbl_index = tbl_index + 1
                        end
                    else
                        tmp.Radio = "Device.Wifi.Radio.1"
                        tmp.OperatingFrequencyBand = "2.4GHz"
                        rax_index = rax_index + 1
                        if rax_index < 16 then
                            ap_list[tostring(tbl_index)] = tmp
                            tbl_index = tbl_index + 1
                        end
                    end
                    -- table.insert(ap_list, tmp)
                end

                cur_index = tonumber(line:match("^%d+"))
                next_line_index = cur_index and cur_index + 1 or next_line_index
            end
        end
        if cur_index and cur_index == next_line_index - 1 then
            scan_result = read_pipe("iwpriv ra0 get_site_survey "..next_line_index)
        else
            scan_result = nil
        end

        if not scan_result or not string.match(scan_result, "%s+%x%x:%x%x:%x%x:%x%x:%x%x:%x%x%s+") then
            break
        end
    end
    return ap_list
end

function handle_wifiscanneighbors()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
        rv = scan_neighbors()
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
