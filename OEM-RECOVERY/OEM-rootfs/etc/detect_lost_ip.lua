#!/usr/bin/env lua

local util = require("luci.util")
local nixio = require("nixio")
local clock = os.clock

function sleep(n)
    local t0 = clock()
    while clock() - t0 <= n do end
end

local uci = require "luci.model.uci".cursor()
local wan = uci:get("network", "globals", "wan_df_route")
local prot = uci:get("network", wan, "proto")
local vlanid = tonumber(uci:get("network", wan, "_vlanid"))
local ifname
local txt
local ip
local wan_up_status
local wan_status_cmd = "ifstatus %s | jsonfilter -e '@[\"up\"]'"
if prot == "dhcp" then
    if vlanid == 0 then
        ifname = "eth1"
    elseif vlanid > 0 then
        ifname = "eth1."..vlanid
    end
elseif prot == "pppoe" then
    ifname = "pppoe-"..wan
end
wan_up_status = util.exec_trim(string.format(wan_status_cmd, wan))
if wan_up_status == "true" then
    txt = util.exec_trim("ifconfig "..ifname)
    if txt and #txt > 0 then
        ip = txt:match("inet addr:(%d+.%d+.%d+.%d+)%s")
        if ip == nil then
            nixio.syslog("err", "[detect_lost_ip]: "..ifname.." is up but has no IPv4 address, reload "..wan)
            util.exec("ubus call network.interface."..wan.." down")
            sleep(2)
            util.exec("ubus call network.interface."..wan.." up")
        end
    end    
end