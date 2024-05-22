local clusterio_api = require("modules/clusterio/api")

local zones_api = {}

-- TODO: Surface rename event?


function zones_api.init()
    if not global.clusterio_trains.zones
    then
        global.clusterio_trains.zones = {}
    end
    if not global.clusterio_trains.zone_debug == nil
    then
        global.clusterio_trains.zone_debug = false
    end
    if not global.clusterio_trains.zone_debug_shapes
    then
        global.clusterio_trains.zone_debug_shapes = {}
    end
	if not global.clusterio_trains.instances
	then
		global.clusterio_trains.instances = {}
	end
end

local function debug_draw()
    local debug_shapes = global.clusterio_trains.zone_debug_shapes;

	if debug_shapes
	then
		for idx, id in ipairs(debug_shapes) do
			rendering.destroy(id)
			debug_shapes[idx] = nil
		end
	end

	if not global.clusterio_trains.zone_debug
	then
		return
	end
	-- Actual drawing
	local zones = global.clusterio_trains.zones;
	for zone_name, zone in pairs(zones) do
		local region = zone.region
        debug_shapes[#debug_shapes + 1] = rendering.draw_rectangle {
            color = {r = 1, g = 0, b = 0},
            width = 2,
            filled = false,
            left_top = {x = region.x1, y = region.y1},
            right_bottom = {x = region.x2, y = region.y2},
            surface = region.surface,
        }
		local label = {}
		if zone.link then
			local link = zone.link
			local target_instance = global.clusterio_trains.instances[link.instanceId]
			local target = target_instance and target_instance.name or zone.link.instanceId
			label = {'', zone.name, ' -> ', target, ':', link.zoneName}
		else
			label = {'', zone.name, ' unlinked'}
		end
		debug_shapes[#debug_shapes + 1] = rendering.draw_text {
			text = label,
			surface = region.surface,
			target = {x = region.x1, y = region.y1},
			color = {r=1, g=0, b=0},
		}
    end
end

function zones_api.sync_all(zone_data)
    local zone_table = game.json_to_table(zone_data)
	local zone_count = 0
	for zone_name, zone in pairs(zone_table) do
		zone_count = zone_count + 1
	end
	global.clusterio_trains.zones = zone_table
	game.print({'', 'Synced ', zone_count, ' zones'})
	debug_draw();
end

function zones_api.set_instances(instance_data)
	local instance_table = game.json_to_table(instance_data)
	local instances = {}
	for _, instance in ipairs(instance_table) do
		local inst = {
			id = instance.id,
			name = instance.name
		}
		instances[instance.id] = inst
		instances[instance.name] = inst
	end
	global.clusterio_trains.instances = instances
	debug_draw()
end

function zones_api.sync(name, zone)
    if (zone)
	then
		-- Update
		game.print({'', 'Zone ', name, ' update ', zone})
		local zone = game.json_to_table(zone);
		global.clusterio_trains.zones[name] = zone
	else
		global.clusterio_trains.zones[name] = nil
	end
	debug_draw();
end

function zones_api.add(name, x1, y1, x2, y2, surface)
    -- local surface = surface or game.player.surface.name or ''
	local surface = surface or (game.player and game.player.surface.name) or 'nauvis';
	clusterio_api.send_json("clusterio_trains_zone", {
		t = "Add",
		z = {
			name = name,
			region = {
				surface = surface,
				x1 = x1,
				y1 = y1,
				x2 = x2,
				y2 = y2
			}
		}
	});
end

function zones_api.delete(name)
    clusterio_api.send_json("clusterio_trains_zone", {
		t = "Delete",
		z = {
			name = name
		}
	});
end

function zones_api.link (name, instance_name, target_name)
	if instance_name then
		local instance = global.clusterio_trains.instances[instance_name]
		if instance == nil then
			game.print({'', 'Unknown instance with name ', instance_name})
			return
		end
		clusterio_api.send_json("clusterio_trains_zone", {
			t = "Update",
			z = {
				name = name,
				link = {
					instanceId = instance.id,
					zoneName = target_name
				}
			}
		})
	else
		clusterio_api.send_json("clusterio_trains_zone",
			'{"t":"Update","z":{"name":"' + name + '","link":null}}')
	end
end

function zones_api.debug()
    global.clusterio_trains.zone_debug = not global.clusterio_trains.zone_debug
    local value = global.clusterio_trains.zone_debug and "enabled" or "disabled"
    game.print({'', 'Debug draw ', value})
    debug_draw()
end


-- Internal interface --
------------------------
function zones_api.find_zone(surface, position)
	local x = position.x
	local y = position.y
	for zone_name, zone in pairs(global.clusterio_trains.zones) do
		local region = zone.region
		if (region.surface == surface.name
				and x > region.x1 and x <= region.x2 
				and y > region.y1 and y <= region.y2)
		then
			return zone_name
		end
	end
	return nil
end

function zones_api.lookup_zone(name)
	return global.clusterio_trains.zones[name]
end

return zones_api;