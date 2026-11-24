-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.
local map, section, net = ...
local ifc = net:get_interface()
-- IPv6 Auto Configuration Block --
ds_ip6 = section:option(DummyValue, "_dummy_IPv6", translate("IPv6 Config"))
ds_ip6:depends("ipv6", conn_ip6_enable.enabled)

ip6_acquire = section:option(ListValue, "reqaddress", translate("IPv6 acquire mode"))
ip6_acquire:value("try", "DHCPv6")
ip6_acquire:value("none", "SLAAC")
ip6_acquire:depends("ipv6", conn_ip6_enable.enabled)
function ip6_acquire.cfgvalue(self, section)
    local value = m:get(net:name().."_ip6", "reqaddress")
    if value == nil or value == "try" then
        return "try"
    elseif value == "none" then
        return "none"
    end
end
function ip6_acquire.write(self, section, value)
    if value and #value > 0 then
        return m:set(net:name().."_ip6", "reqaddress", value)
    end
end

ip6_req_pd = section:option(Flag, "reqprefix", translate("Request PD"))
ip6_req_pd:depends("ipv6", conn_ip6_enable.enabled)
ip6_req_pd.rmempty = false
ip6_req_pd.forcewrite = true
function ip6_req_pd.cfgvalue(self, section)
    local value = m:get(net:name().."_ip6", "reqprefix")
    if value and #value > 0 then
        if value == "auto" then
            return "1"
        else
            return "0"
        end
    end
end
function ip6_req_pd.write(self, section, value)
    if value == "1" then
        m:set(net:name().."_ip6", "reqprefix", "auto")
    elseif value == "0" then
        nixio.syslog("debug", "[fanwar] write reqprefix = no")
        m:set(net:name().."_ip6", "reqprefix", "no")
    else
        nixio.syslog("debug", "[fanwar][error] ip6_req_pd write invalid value")
    end
end