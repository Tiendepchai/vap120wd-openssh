#!/usr/bin/lua

local uci = require("luci.model.uci").cursor()
local req_http = uci:get("lighttpd", "main", "listen_http")
local req_https = uci:get("lighttpd", "main", "listen_https")
local http_port_pattern = "server%.port = (%d+)"
local https_port_pattern = "%$SERVER%[\"socket\"%] == \":(%d+)\""
local redirect_pattern = "0:(%d+)%$0"
local http_port_str = "server.port = %d"
local https_port_str = "$SERVER[\"socket\"] == \":%d\""
local redirect_str = "0:%d$0"
local config_file = "/etc/lighttpd/lighttpd.conf"
local file = io.open(config_file, "r")
local content = file:read("*a")
file:close()

content = string.gsub(content, http_port_pattern, string.format(http_port_str, req_http))
content = string.gsub(content, https_port_pattern, string.format(https_port_str, req_https))
content = string.gsub(content, redirect_pattern, string.format(redirect_str, req_https))

file = io.open(config_file, "w")
file:write(content)
file:close()
