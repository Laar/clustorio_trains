local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")

local stations_api = {
}

---@class StationRegistration
---@field zone zone_name Name of the zone
---@field entity LuaEntity_TrainStop The train stop entity
---@field length number Size of the track associated with the train stop
---@field egress boolean Whether to use it as an egress from this server
---@field ingress boolean Whether to use it as an ingress to this server

-- Override of LuaEntity when it is a TrainStop
--- @class LuaEntity_TrainStop: LuaEntity
--- @field unit_number integer
--- @field backer_name string


local connection_directions = {
    defines.rail_connection_direction.left,
    defines.rail_connection_direction.straight,
    defines.rail_connection_direction.right
}

local invalidation_types = {
    ["rail-signal"] = true,
    ["rail-chain-signal"] = true,
    ["straight-rail"] = true,
    ["curved-rail"] = true
}

---Create a staiton registration
---@param station LuaEntity_TrainStop
---@param zone_name zone_name
---@return StationRegistration
local function create_registration(station, zone_name)
    local crail = station.connected_rail
    local rail_dir = station.connected_rail_direction
    local length = 0
    local ingress = false
    local egress = false
    if crail ~= nil
    then
        length = crail.get_rail_segment_length()

        -- Backside of the station is connected to a longer rail
        local segment_end, segment_out_dir = crail.get_rail_segment_end(1 - rail_dir)
        egress = false
        for _, connection_dir in ipairs(connection_directions) do
                local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
                if next_rail ~= nil then
                    egress = true
                end
        end
        -- front side of the station is connected to a longer rail
        segment_end, segment_out_dir = crail.get_rail_segment_end(rail_dir)
        ingress = false
        for _, connection_dir in ipairs(connection_directions) do
            local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
            if next_rail ~= nil then
                ingress = true
            end
        end
    end
    -- game.print({'', 'Registration ', station.backer_name, ' in zone ', zone_name, ' length ', length, ' ingress ', ingress, ' egress ', egress})
    return {
        zone = zone_name,
        entity = station,
        length = length,
        egress = egress,
        ingress = ingress
    }
end

-- Globals --
-------------
--- @class StationsGlobal
--- @field stations {[integer]: StationRegistration}
--- @field stations_invalid boolean

--- @type StationsGlobal
local stations_global

-- Reload --
------------

local function rebuild_station_mapping()
    stations_global.stations = {}
    local stations = stations_global.stations
    local found_stations = 0
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type='train-stop'}) do
            ---@cast entity LuaEntity_TrainStop
            local zone_name = zones_api.find_zone(entity.surface, entity.position)
            if zone_name then
                found_stations = found_stations + 1
                stations[entity.unit_number] = create_registration(entity, zone_name)
            end
        end
    end
    stations_global.stations_invalid = false
    game.print({'', 'Found ', found_stations, ' stations'})
end

local function ensure_valid_stations()
    if not stations_global.stations_invalid then return end
    local stations = stations_global.stations
    for key, registration in pairs(stations) do
        stations[key] = create_registration(registration.entity, registration.zone)
    end
    stations_global.stations_invalid = false
end

-- Init --
----------

function stations_api.init()
    -- Uses save-specific numbers -> needs updating on reload
    global.clusterio_trains.stations = {
        stations = {},
        stations_invalid = false,
    }
    stations_api.on_load()
    rebuild_station_mapping()
end

function stations_api.on_load()
    stations_global = global.clusterio_trains.stations
end

-- Interface --
---------------

---Lookup a stations registration
---@param entity LuaEntity_TrainStop
---@return StationRegistration?
function stations_api.lookup_station(entity)
    ensure_valid_stations()
    return stations_global.stations[entity.unit_number]
end

--- Lookup a station in a specific zone
--- @param zone_name zone_name
--- @return LuaEntity_TrainStop?
function stations_api.find_station_in_zone(zone_name)
    ensure_valid_stations()
    for _, registration in pairs(stations_global.stations) do
        if (registration.zone == zone_name) then
            return registration.entity
        end
    end
    return nil
end

---Lookup stations in teleporting zones
---@param query {zone?:zone_name, length?: number, ingress?: boolean, egress?: boolean, name?: string}
---@return [StationRegistration]
function stations_api.find_stations(query)
    ensure_valid_stations()
    local result = {}
    for _, station in pairs(stations_global.stations) do
        local ent = station.entity
        if not ent.valid then goto continue end
        if query.name ~= nil and ent.backer_name ~= query.name then goto continue end
        if query.zone ~= nil and station.zone ~= query.zone then goto continue end
        if query.length ~= nil and station.length < query.length then goto continue end
        if query.ingress ~= nil and station.ingress ~= query.ingress then goto continue end
        if query.egress ~= nil and station.egress ~= query.egress then goto continue end
        table.insert(result, station)
        ::continue::
    end
    return result
end

--- Reverse ipairs
---@generic T: table, V
---@param t T
---@return fun(table: V[], i?: integer):integer, V
---@return T
---@return integer i
local function ripairs(t)
    local iter = function (a, i)
        i = i - 1
        if i == 0 then return nil end
        local val = a[i]
        return i, val
    end
    return iter, t, #t + 1
end

--- @alias StationQuery {zone?:zone_name, length?: number, ingress?: boolean, egress?: boolean, name?: string}
---@param queries [StationQuery] Multiple station queries
---@return [ [StationRegistration] ] result List of stations matching a query and all subsequent queries
function stations_api.find_best_stations(queries)
    local result = {}
    for _, _ in ipairs(queries) do
        table.insert(result, {})
    end

    for _, registration in pairs(stations_global.stations) do
        local station = registration.entity
        local best_match = #queries + 1
        if not station.valid then goto continue end

        for idx, query in ripairs(queries) do
            if query.name ~= nil and station.backer_name ~= query.name then break end
            if query.zone ~= nil and registration.zone ~= query.zone then break end
            if query.length ~= nil and registration.length < query.length then break end
            if query.ingress ~= nil and registration.ingress ~= query.ingress then break end
            if query.egress ~= nil and registration.egress ~= query.egress then break end
            best_match = idx
        end
        if best_match <= #queries then
            table.insert(result[best_match], registration)
        end
        ::continue::
    end
    return result
end

-- Handlers --
--------------
---@param entity LuaEntity_TrainStop
local function on_built(entity)
    local zone_name = zones_api.find_zone(entity.surface, entity.position)
    if zone_name
    then
        stations_global.stations[entity.unit_number] = create_registration(entity, zone_name)
        game.print({'', 'Trainstop built inside zone ', zone_name})
    else
        game.print({'', 'Trainstop built outside zone'})
    end
end

---@param entity LuaEntity_TrainStop
local function on_remove(entity)
    stations_global.stations[entity.unit_number] = nil
    game.print({'', 'Trainstop removed'})
end

local function on_rename(entity)
    game.print({'', 'Trainstop renamed'})
end

-- Events --
------------

-- Helpers
--- @param entity LuaEntity
--- @return boolean
local function check_entity(entity)
    return entity and entity.valid and entity.type == 'train-stop'
    -- TODO: Check for ghosts?
end


-- Script teleport?
stations_api.events = {}

-- Player

---@param event EventData.on_built_entity
stations_api.events[defines.events.on_built_entity] = function (event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

---@param event EventData.on_player_mined_entity
stations_api.events[defines.events.on_player_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

-- Robot
---@param event EventData.on_robot_built_entity
stations_api.events[defines.events.on_robot_built_entity] = function(event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end
---@param event EventData.on_robot_mined_entity
stations_api.events[defines.events.on_robot_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

-- Script
---@param event EventData.script_raised_built
stations_api.events[defines.events.script_raised_built] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

---@param event EventData.script_raised_destroy
stations_api.events[defines.events.script_raised_destroy] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

-- General
---@param event EventData.on_entity_renamed
stations_api.events[defines.events.on_entity_renamed] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_rename(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

---@param event EventData.on_entity_died
stations_api.events[defines.events.on_entity_died] = function (event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        stations_global.stations_invalid = true
    end
end

return stations_api
