local http = require "luci.http"
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
module("luci.controller.tailscaler", package.seeall)

local boolean_options = {
	"enabled",
	"acceptRoutes",
	"advertiseExitNode"
}

local string_options = {
	"loginServer",
	"authkey",
	"hostname",
	"advertiseRoutes"
}

function index()
	if not nixio.fs.access("/etc/config/tailscaler") then
        return
    end
	entry({"admin", "services", "tailscaler"},				call("tailscale_template"), _("Tailscale"), 21).dependent = true
	entry({"admin", "services", "tailscaler", "config"}, 	call("tailscale_config"))
	entry({"admin", "services", "tailscaler", "status"}, 	call("tailscale_status"))
	entry({"admin", "services", "tailscaler", "logout"}, 	call("tailscale_logout"))
end

function tailscale_template()
    luci.template.render("tailscaler/main")
end


function getTailscaleConfig()
    local uci  				= 	require "luci.model.uci".cursor()
    local enabled   		= 	uci:get_first("tailscaler", "settings", "enabled")
    local acceptRoutes  	= 	uci:get_first("tailscaler", "settings", "acceptRoutes")
    local advertiseExitNode = uci:get_first("tailscaler", "settings", "advertiseExitNode")
    local hostname   		= 	uci:get_first("tailscaler", "settings", "hostname")
    local advertiseRoutes   = 	uci:get_first("tailscaler", "settings", "advertiseRoutes")
    local loginServer  		= 	uci:get_first("tailscaler", "settings", "loginServer")
    local authkey   		= 	uci:get_first("tailscaler", "settings", "authkey")
    local result 			= 	{
        enabled    			= 	(enabled == "1"),
		acceptRoutes 		= 	(acceptRoutes == "1"),
		advertiseExitNode 	= 	(advertiseExitNode == "1"),
		advertiseRoutes		=	advertiseRoutes,
		hostname			=	hostname,
		loginServer			=	loginServer,
		authkey				=	authkey,
    }
    return result
end

function submitTailscaleConfig(req)
	local uci = require "luci.model.uci".cursor()

	for _, option in ipairs(boolean_options) do
		if req[option] ~= nil then
			uci:set("tailscaler", "@settings[0]", option, req[option] and "1" or "0")
		end
	end

	for _, option in ipairs(string_options) do
		if req[option] ~= nil then
			uci:set("tailscaler", "@settings[0]", option, req[option])
		end
	end

	return uci:commit("tailscaler")
end

local function validateTailscaleConfig(req)
	if type(req) ~= "table" or next(req) == nil then
		return false, "invalid request"
	end

	for _, option in ipairs(boolean_options) do
		if req[option] ~= nil and type(req[option]) ~= "boolean" then
			return false, option .. " must be a boolean"
		end
	end

	for _, option in ipairs(string_options) do
		if req[option] ~= nil and type(req[option]) ~= "string" then
			return false, option .. " must be a string"
		end
	end

	return true
end

local function writeError(status, message)
	http.status(status, message)
	http.write_json({
		success = false,
		error = message
	})
end

function tailscale_config()
	http.prepare_content("application/json")
	local method = http.getenv("REQUEST_METHOD")
	if method == "post" or method == "POST" then
		local req = jsonc.parse(http.content() or "")
		local valid, validation_error = validateTailscaleConfig(req)
		if not valid then
			writeError(400, validation_error)
			return
		end

		if not submitTailscaleConfig(req) then
			writeError(500, "failed to save configuration")
			return
		end

		local result = sys.call("/etc/init.d/tailscaler reload >/dev/null 2>&1")
		if result ~= 0 then
			writeError(500, "configuration was saved but could not be applied; check the tailscaler system log")
			return
		end

		http.write_json({
			success = true,
			config = getTailscaleConfig()
		})
		return
	end

	local response = getTailscaleConfig()
    http.write_json(response)
end

function tailscale_status()
	local sys  = require "luci.sys"
	local http = require "luci.http" 
    -- http.prepare_content("text/plain;charset=utf-8")
	http.prepare_content("application/json")
	local text = sys.exec("tailscale status --json")
    http.write(text)
end

function tailscale_logout()
	local sys  = require "luci.sys"
	local http = require "luci.http" 
	http.prepare_content("application/json")
	local text = sys.exec("tailscale logout")
    http.write(text)
end