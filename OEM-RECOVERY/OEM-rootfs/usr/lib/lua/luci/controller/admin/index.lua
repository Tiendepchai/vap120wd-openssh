-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.index", package.seeall)

function index()
	local root = node()
	if not root.target then
		root.target = alias("admin")
		root.index = true
	end

	local page   = node("admin")
	page.target  = firstchild()
	page.title   = _("Administration")
	page.order   = 10
	page.sysauth = {"root","admin"}
	page.sysauth_authenticator = "htmlauth"
	page.ucidata = true
	page.index = true

	-- Empty services menu to be populated by addons
	page   = node("api")
	page.target  = firstchild()
	page.title   = _("API")
	page.order   = 11
	page.sysauth = {"api"}
	page.sysauth_authenticator = "htmlauth"
	page.ucidata = true
	page.index = true

	page   = node("smartalert")
	page.target  = firstchild()
	page.title   = _("Smartalert")
	page.order   = 11
	page.sysauth = {"smartalert"}
	page.sysauth_authenticator = "smartalertauth"
	page.ucidata = true
	page.index = true

	page   = node("forgetpassword")
	page.target  = firstchild()
	page.title   = _("Forgetpassword")
	page.order   = 12
	page.sysauth = {"forgetpassword"}
	page.sysauth_authenticator = "forgetpasswordauth"
	page.ucidata = true
	page.index = true

	entry({"admin", "services"}, firstchild(), _("Services"), 40).index = true

	entry({"admin", "logout"}, call("action_logout"), nil, nil)
	entry({"api", "logout"}, call("action_logout"), nil, nil)
end

function action_logout()
	local dsp = require "luci.dispatcher"
	local utl = require "luci.util"
	local sid = dsp.context.authsession

	if sid then
		utl.ubus("session", "destroy", { ubus_rpc_session = sid })

		dsp.context.urltoken.stok = nil

		luci.http.header("Set-Cookie", "sysauth=%s; expires=%s; path=%s/" %{
			sid, 'Thu, 01 Jan 1970 01:00:00 GMT', dsp.build_url()
		})
	end

	luci.http.redirect(luci.dispatcher.build_url())
end
