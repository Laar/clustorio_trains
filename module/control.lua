local clusterio_api = require("modules/clusterio/api")
local ipc = require("modules/clusterio_trains/types/ipc")
local instance_api = require("modules/clusterio_trains/instances")
local zones_api = require("modules/clusterio_trains/zones")
local stations_api = require("modules/clusterio_trains/stations")
local trains_api = require("modules/clusterio_trains/trains")
local gui = require("modules/clusterio_trains/gui")

local clusterio_trains = {
	events = {},
	on_nth_tick = {},
	rcon = ipc.rcon_handlers,
}


local merge_events = function (apis)
	local event_keys = {}
	for _, api in ipairs(apis) do
		if (api.events) then
			for key, handler in pairs(api.events) do
				if (event_keys[key] == nil) then event_keys[key] = {} end
				table.insert(event_keys[key], handler)
			end
		end
	end

	local events = {}
	for key, handlers in pairs(event_keys) do
		if (#handlers == 1) then
			events[key] = handlers[1]
		else
			error('Not implemented')
		end
	end
	return events
end
clusterio_trains.events = merge_events({stations_api, trains_api, gui})
clusterio_trains.on_nth_tick = trains_api.on_nth_tick


clusterio_trains.zones = {
	add = zones_api.add,
	delete = zones_api.delete,
	link = zones_api.link,
	debug = zones_api.debug
}

local function setupGlobalData()
	if global.clusterio_trains == nil then
		global.clusterio_trains = {}
	end
	instance_api.init()
	zones_api.init()
	stations_api.init()
	trains_api.init()
	gui.init()
end

clusterio_trains.events[clusterio_api.events.on_server_startup] = function(event)
	setupGlobalData()
end

clusterio_trains.on_load = function ()
	if global.clusterio_trains ~= nil then
		-- Not safe on the first load due to lacking init
		instance_api.on_load()
		zones_api.on_load()
		stations_api.on_load()
		trains_api.on_load()
		gui.on_load()
	end
end

--- Top level module table that gets registered
return clusterio_trains
