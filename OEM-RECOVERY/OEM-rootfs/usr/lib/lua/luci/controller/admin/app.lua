module("luci.controller.admin.app", package.seeall)

function index()
	entry({"admin", "app"}, alias("admin", "app", "app"), _("Applications"), 70).index = true
	-- entry({"admin", "app", "routes"}, cbi("admin_app/routes"), _("Static Routes"), 2)
	entry({"admin", "app", "diagnostics"}, template("admin_app/diagnostics"), _("Diagnostics"), 3)
	entry({"admin", "app", "diag_ping"}, call("diag_ping"), nil).leaf = true
	entry({"admin", "app", "diag_nslookup"}, call("diag_nslookup"), nil).leaf = true
	entry({"admin", "app", "diag_traceroute"}, call("diag_traceroute"), nil).leaf = true
	entry({"admin", "app", "diag_ping6"}, call("diag_ping6"), nil).leaf = true
	entry({"admin", "app", "diag_traceroute6"}, call("diag_traceroute6"), nil).leaf = true
end

function diag_command(cmd, addr)
	if addr and addr:match("^[a-zA-Z0-9%-%.:_]+$") then
		luci.http.prepare_content("text/plain")

		local util = io.popen(cmd % addr)
		if util then
			while true do
				local ln = util:read("*l")
				if not ln then break end
				luci.http.write(ln)
				luci.http.write("\n")
			end

			util:close()
		end

		return
	end

	luci.http.status(500, "Bad address")
end

function diag_ping(addr)
	diag_command("ping -c 5 -W 1 %q 2>&1", addr)
end

function diag_traceroute(addr)
	diag_command("traceroute -q 1 -w 1 -n %q 2>&1", addr)
end

function diag_nslookup(addr)
	diag_command("nslookup %q 2>&1", addr)
end

function diag_ping6(addr)
	diag_command("ping6 -c 5 %q 2>&1", addr)
end

function diag_traceroute6(addr)
	diag_command("traceroute6 -q 1 -w 2 -n %q 2>&1", addr)
end
