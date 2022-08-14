Area = require "models.Area"
Surface = require "models.Surface"
Chunk = require "models.Chunk"
Patch = require "models.Patch"
Resource = require "models.Resource"
Format = require "core.Format"

local module = {}

module.on_init = function()
end

module.on_load = function()
end

module.on_configuration_changed = function()
end

module.add_commands= function()
    commands.add_command(defines.mod.command.name,defines.mod.command.header, module.command_run)
end

module.command_run = function(event)
    if event ~= nil and event.player_index ~= nil then
        Player.load(event)
        module.execute(event)
    end
end

---@param event CustomCommandData
---@return {action:string, resource_names:table, resource_limit:double}
module.parse_parameter = function(event)
    local action, resource_name, resource_limit = string.match(event.parameter, "([^%s]+)[ ]?([^%s]*)[ ]?([^%s]*)")
    local resource_names = nil
    if  resource_name ~= defines.mod.default.filter and resource_name ~= "" then
        local resources = Player.get_resource_entity_prototypes()
        for _, resource in pairs(resources) do
            local name = resource.name
            if string.find(name, resource_name, 1, true) then
                if resource_names == nil then resource_names = {} end
                table.insert(resource_names, name)
            end
        end
    end
    if resource_limit == "" then resource_limit = defines.mod.default.limit end
    return action, resource_names, resource_limit
end
-------------------------------------------------------------------------------
---@param event CustomCommandData
---@return ParametersData
module.get_parameter = function(event)
    local force = Player.get_force()
    local surface = Player.get_surface()
    local action, resource_names, resource_limit = module.parse_parameter(event)
    local limit = string.parse_number(resource_limit)
    local parameters = {}
    parameters.player_index = event.player_index
    parameters.action = action
    parameters.resource_names = resource_names
    parameters.resource_limit = limit
    parameters.event = event
    parameters.force_id = force.index
    parameters.surface_id = surface.index
    parameters.surface_name = surface.name
    return parameters
end

module.append_queue = function(parameters)
    if global.queue == nil then global.queue = {} end
    local queue = global.queue
    local force_id = parameters.force_id
    local surface_id = parameters.surface_id
    if queue[force_id] == nil then queue[force_id] = {} end
    if queue[force_id][surface_id] ~= nil then return false end
    queue[force_id][surface_id] = parameters
    return true
end
-------------------------------------------------------------------------------
---Callback function
---@param event CustomCommandData
function module.execute(event)
  local ok , err = pcall(function()
    if event.name == defines.mod.command.name then
        if event.parameter ~= nil then
            local parameters = module.get_parameter(event)
            local response = module.append_queue(parameters)
            if response then
                Player.printf("Added in queue! %s", parameters.surface_name)
            else
                Player.print("Already in queue!")
            end
        end
    end
  end)
  if not(ok) then
    Player.print(err)
    log(err)
  end
end


module.on_nth_tick={}
module.on_nth_tick[1] = function(event)
    local queue = global.queue
    if queue == nil then return end
    for force_id, surfaces in pairs(queue) do
        if surfaces ~= nil then
            if table.size(surfaces) > 0 then
                for surface_id, parameters in pairs(surfaces) do
                    module.run_on_tick(parameters)
                    if parameters.finished or parameters.error ~= nil then
                        surfaces[surface_id] = nil
                        break
                    end
                end
            else
                queue[force_id] = nil
                break
            end
        end
    end
    if #queue == 0 then
        global.queue = nil
    end
end

---@param parameters ParametersData
module.run_on_tick = function(parameters)
    local ok , err = pcall(function()
        if parameters == nil then return end
        Player.load(parameters)
        Surface.load(parameters.surface_id)

        local action = parameters.action
        if action == "remove" then
            module.action_remove(parameters)
        elseif action == "scan" then
            module.action_scan(parameters)
        elseif action == "show" then
            module.action_show(parameters)
        elseif action == "hide" then
            module.action_hide(parameters)
        elseif action == "reset" then
            module.action_reset(parameters)
        else
            parameters.finished = true
            Player.printf("Action %s not found!", action)
        end
    end)
    if not(ok) then
        parameters.error = err
        Player.print(err)
        log(err)
    end
end

---@param parameters ParametersData
module.action_remove = function(parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    Surface.remove_patch_tags(force, surface)
    parameters.finished = true
end

---@param parameters ParametersData
module.action_reset = function(parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    Surface.destroy(force, surface)
    parameters.finished = true
end

---Check match resources names
---@param resource_names {[uint]:string}
---@param resource_name string
---@return boolean
module.match_resource_names = function(resource_names, resource_name)
    if resource_names == nil then return true end
    for _, name in pairs(resource_names) do
        if resource_name == name then return true end
    end
    return false
end

---@param parameters ParametersData
module.action_show = function (parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    local resource_names = parameters.resource_names
    local resource_limit = parameters.resource_limit
    local patchs = Surface.get_patchs()
    for _, patch in pairs(patchs) do
        if module.match_resource_names(resource_names, patch.name)
            and (resource_limit == 0 or patch.amount >= resource_limit) then
                Surface.update_patch_tag(force, surface, patch)
        end
    end
    parameters.finished = true
end

---@param parameters ParametersData
module.action_hide = function (parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    local resource_names = parameters.resource_names
    local resource_limit = parameters.resource_limit
    local patchs = Surface.get_patchs()
    for _, patch in pairs(patchs) do
        if module.match_resource_names(resource_names, patch.name)
            and (resource_limit == 0 or patch.amount <= resource_limit) then
                Surface.remove_patch_tag(force, surface, patch)
        end
    end
    parameters.finished = true
end

---@param parameters ParametersData
module.action_scan = function(parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    if parameters.cleanup == nil then
        Surface.remove_patch_tags(force, surface)
        parameters.cleanup = true
        return
    end
    -- load chunks
    if parameters.chunks == nil then
        module.get_chunks(parameters)
        Player.print("Loaded chunks!")
        return
    end
    if parameters.index == nil then parameters.index = 1 end
    -- load resources
    if parameters.index <= #parameters.chunks then
        local step = 1
        module.get_chunks_patchs(parameters, step)
        if parameters.percent == nil then parameters.percent = 0 end
        local percent = 100 * parameters.index / #parameters.chunks
        if percent >= parameters.percent + 10 then
            parameters.percent = percent
            Player.printf("%s%s%%!", "Loaded resources:", percent)
        end
        -- incremente l'index
        parameters.index = parameters.index + step
        return
    else
        parameters.finished = true
        Player.print("Finished tags!")
    end
end

---@param parameters ParametersData
module.get_chunks = function(parameters)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    parameters.chunks = {}
    for chunk in surface.get_chunks() do
        -- chunk decouvert (non noir)
        local is_chunk_charted = force.is_chunk_charted(surface, chunk)
        if is_chunk_charted then
            table.insert(parameters.chunks, chunk)
        end
    end
end

---Scan few chunks
---@param parameters ParametersData
---@param step uint
module.get_chunks_patchs = function(parameters, step)
    local force_id = parameters.force_id
    local force = game.forces[force_id]
    local surface_id = parameters.surface_id
    local surface = game.get_surface(surface_id)
    local resource_names = parameters.resource_names
    local resource_limit = parameters.resource_limit

    local index_start = parameters.index
    local index_end = parameters.index + step
    for i = index_start, index_end, 1 do
        local chunk = parameters.chunks[i]
        if chunk == nil then break end -- loop finished
        local patchs = Chunk.get_chunk_patchs(chunk, surface)
        -- if patchs ~= nil then
        --     for _, patch in pairs(patchs) do
        --         if module.match_resource_names(resource_names, patch.name)
        --             and (resource_limit == 0 or patch.amount >= resource_limit) then
        --             Surface.update_patch_tag(force, surface, patch)
        --         else
        --             Surface.remove_patch_tag(force, surface, patch)
        --         end
        --     end 
        -- end
    end
end

---Chunk analyse
---@param chunk ChunkData
---@param surface LuaSurface
module.chunk_analyse = function(chunk, surface)
    local patchs = Chunk.get_chunk_patchs(chunk, surface)
    
end

---Called when a resource entity reaches 0 or its minimum yield for infinite resources.
---@param event EventData.on_resource_depleted
module.on_resource_depleted  = function(event)
    local ok, err = pcall(function()
    end)
    if not (ok) then
        Player.print(err)
        log(err)
    end
end

---Called when a chunk is generated.
---@param event EventData.on_chunk_generated
module.on_chunk_generated  = function(event)
    local ok, err = pcall(function()
        local chunk = Chunk.get_chunk_data(event.position)
        --module.chunk_analyse(chunk, event.surface)
    end)
    if not (ok) then
        Player.print(err)
        log(err)
    end
end

---Called when an entity of type radar finishes scanning a sector. Can be filtered for the radar using LuaSectorScannedEventFilter.
---@param event EventData.on_sector_scanned
module.on_sector_scanned  = function(event)
    local radar = event.radar
    local surface = radar.surface
    local force = radar.force
    local player = radar.last_user
    
    local chunk = {
        x=event.chunk_position.x,
        y=event.chunk_position.y,
        area = event.area
    }

    local parameters = {}
    parameters.player_index = player.index
    parameters.action = "scan"
    parameters.resource_name = defines.mod.default.filter
    parameters.resource_limit = defines.mod.default.limit
    parameters.event = event
    parameters.force_id = force.index
    parameters.surface_id = surface.index
    parameters.surface_name = surface.name
    parameters.chunks = {chunk}
    module.append_queue(parameters)
end

module.events =
{
    --[defines.events.on_resource_depleted] = module.on_resource_depleted,
    --[defines.events.on_sector_scanned] = module.on_sector_scanned
    [defines.events.on_chunk_generated] = module.on_chunk_generated
}

return module