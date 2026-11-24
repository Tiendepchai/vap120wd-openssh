module("luci.controller.api.updatefirmware", package.seeall)

require("firmware_helper")

local util = require "luci.util"
local io = require "io"
local json = require "vt_json"
local mtkwifi = require("mtkwifi")

function index()
    entry({"api","activefirmware"}, call("handle_activefirmware"))
    entry({"api","updatefirmware"}, call("handle_updatefirmware"))
    entry({"api","deviceinfo"})
    entry({"api","deviceinfo","firmwareimage"}, call("handle_firmwareimage"))
end


----------- firmware image ---------------
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
	return activefirmware
end

function get_firmwareimage(idx)
    local version, name, available, status
	local active_firmware = tonumber(get_active_firmware_image())
	local error = false

	name = luci.util.exec("check_fw_info | grep 'firmware "..idx.."'")
	local t = name:split(":")
	if t[2] ~= nil then
    	name = luci.util.trim(t[2])
    else
    	error = true
    	name = "error-error-error"
    end
    local k = name:split("-")

    if k[1] ~= nil and k[2] ~= nil then
    	version = ""..k[1].."-"..k[2]..""
    else
    	error = true
    	name = "error"
    	version = "error"
    end

    available = error == false and "true" or "false"
    if idx == active_firmware then
    	status = "Active"
    else
    	status = error == false and "Available" or "NoImage"
    end
    
	local this_entry_tbl =
	{
		Name = name,
		Version = version,
		Available = available,
        Status = status
	}

	return {[tostring(idx)] = this_entry_tbl}
end

function get_all_firmwareimage()
	local tbl = {}
	local tmp_entry = {}

	for i = 1,2,1 do
		tmp_entry = get_firmwareimage(i)
		tbl[tostring(i)] = tmp_entry[tostring(i)]
	end

	return tbl
end

function handle_firmwareimage(idx)
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {}
		if idx and #idx > 0 then
			rv=get_firmwareimage(tonumber(idx))
		else
			rv=get_all_firmwareimage()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	elseif luci.http.getenv("REQUEST_METHOD") == "PUT" then
		local content = luci.http.content()
		local table = json.decode(content)
		local rv = { Status = "Fail"}
		-- insert code

		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
----------- Update Firmware ---------------
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

function action_updatefirmware()
	local sys = require "luci.sys"
	local fs  = require "nixio.fs"

	local upgrade_avail = fs.access("/lib/upgrade/platform.sh")
	local reset_avail   = os.execute([[grep -E '"rootfs_data"|"ubi"' /proc/mtd >/dev/null 2>&1]]) == 0

	local restore_cmd = "tar -xzC/ >/dev/null 2>&1"
	local backup_cmd  = "sysupgrade --create-backup - 2>/dev/null"

	local image_downloaded = "/tmp/firmware_downloaded.img"
	local image_original = "/tmp/firmware_original.img"
	local signature = "/tmp/signature.img"

	local function image_supported()
		return (os.execute("sysupgrade -T %q >/dev/null" % image_original) == 0)
	end

	local function image_checksum()
		return (luci.sys.exec("md5sum %q" % image_original):match("^([^%s]+)"))
	end

	local function storage_size()
		local size = 0
		if fs.access("/proc/mtd") then
			for l in io.lines("/proc/mtd") do
				local d, s, e, n = l:match('^([^%s]+)%s+([^%s]+)%s+([^%s]+)%s+"([^%s]+)"')
				if n == "linux" or n == "firmware" then
					size = tonumber(s, 16)
					break
				end
			end
		elseif fs.access("/proc/partitions") then
			for l in io.lines("/proc/partitions") do
				local x, y, b, n = l:match('^%s*(%d+)%s+(%d+)%s+([^%s]+)%s+([^%s]+)')
				if b and n and not n:match('[0-9]') then
					size = tonumber(b) * 1024
					break
				end
			end
		end
		return size
	end

    local function check_version(filename)
        return (c_checkVersion(filename) == 1)
    end

    local function check_signature()
        return (c_checkSignature(image_downloaded, image_original, signature) == 1)
    end

    if check_signature() then
        if check_version(image_original) then 
            if image_supported() then
            else
                fs.unlink(image_downloaded)
                fs.unlink(image_original)
                fs.unlink(signature)
				status = "Error - image not supported"
                return status;
            end
        else
            fs.unlink(image_downloaded)
            fs.unlink(image_original)
            fs.unlink(signature)
            status = "Error - check_version failed"
                return status;
        end
    else
        fs.unlink(image_downloaded)
        fs.unlink(image_original)
        fs.unlink(signature)
        status = "Error - signature failed"
        return status;
    end
	os.execute("reboot_reason w rb_reason RebootByTMSUpgradeFirmware")
    fork_exec("sleep 1; killall dropbear uhttpd; sleep 10; /sbin/sysupgrade "..image_original.."")

    status = "Complete"
    return status;
end

function handle_updatefirmware()
	if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			Status = action_updatefirmware()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end

----------- get activefirmware --------
function handle_activefirmware()
    if luci.http.getenv("REQUEST_METHOD") == "GET" then
		local rv = {
			ActiveFirmware = get_active_firmware_image()
		}
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
	end
end
