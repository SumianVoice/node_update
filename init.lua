
-- Example use:
--[[

    core.register_node("my_mod:node_name", {
        _on_node_update = function(pos, cause, user, counts, payload, last_pos)
            return true or {} or false or nil
        end,
    })
]]
-- This is intended to form a node update system, where if a node is updated,
-- it notifies its neighbors in case they need to do something in response.
node_updates = {}

node_updates.registered_on_node_updates = {}

local calls = 0
local call_limit = 500 -- per step

local function reset_calls(dtime)
    if calls > call_limit then
        core.log("warning", "[node_update] too many node updates are ocurring!")
    end
    calls = 0
end

core.register_globalstep(reset_calls)

--[[
    Same signature of nodedef._on_node_update

    node_updates.register_on_node_update(
        function(pos, cause, user, counts, payload, last_pos)
            return true or {} or false or nil
        end
    )
]]
---@param func function
function node_updates.register_on_node_update(func)
    table.insert(node_updates.registered_on_node_updates, func)
end

local adjacent = {
    [1] = vector.new(0, 1, 0),
    [2] = vector.new(0, -1, 0),
    [3] = vector.new(1, 0, 0),
    [4] = vector.new(-1, 0, 0),
    [5] = vector.new(0, 0, 1),
    [6] = vector.new(0, 0, -1),
}

local function propagate(pos, cause, user, count, delay, payload, last_pos)
    local offset = 2 -- math.random(0, 5)
    for i=1, #adjacent do
        local p = adjacent[(i + offset) % 6 + 1]
        local v = vector.add(pos, p)
        if (not last_pos) or not vector.equals(v, last_pos) then
            node_updates.update_node(v, cause, user, count-1, delay, payload, pos)
        end
    end
end

-- updates this node and also propagate it to adjacent ones
-- if `last_pos` included, it will not update the last_pos node
---@param pos table
---@param cause string
---@param user table | nil (or userdata)
---@param count number
---@param delay number | nil
---@param payload table | nil
---@param last_pos table | nil
---@return nil
function node_updates.update_node_propagate(pos, cause, user, count, delay, payload, last_pos)
    if not delay then delay = 0.1 end
    -- only allow a certain limit on total updates per server step
    if calls > call_limit then
        return false end
    -- only allow some number of recursions per update
    if count <= 0 then return end
    -- update this node only if it's not already processed
    if (not last_pos) or not pos:equals(last_pos) then
        local ret = node_updates.update_node(pos, cause, user, count-1, delay, payload, pos)
        if (not payload) and type(ret) == "table" then payload = ret end
    end
    if delay == 0 then
        -- #RECURSION
        propagate(pos, cause, user, count, delay, payload, last_pos)
    else
        core.after(delay, propagate, pos, cause, user, count, delay, payload, last_pos)
    end
end

-- Updates a single node, and depending on its return value, propagates it to adjacent nodes.
-- If included, does not update `last_pos`.
---@param pos table
---@param cause string
---@param user table | nil (or userdata)
---@param count number
---@param delay number | nil
---@param payload table | nil
---@param last_pos table | nil
---@return table | boolean
function node_updates.update_node(pos, cause, user, count, delay, payload, last_pos)
    if count <= 0 then return false end
    local node = core.get_node(pos)
    -- don't trigger on `ignore` or un-generated nodes
    if not node then return false end
    local ndef = core.registered_nodes[node.name]
    -- don't trigger on unknown nodes either
    if ndef then
        local updated = false
        if ndef._on_node_update then
            calls = calls + (cause == "liquid" and 0.01 or 1)
            -- allow the payload to propogate
            local ret = ndef._on_node_update(pos, cause, user, count-1, payload, last_pos)
            if ret then
                if type(ret) == "table" then payload = ret end
                updated = true
            end
        end
        -- go through the registered update funcs and if any of them return true, propogate the update
        for _, node_func in ipairs(node_updates.registered_on_node_updates) do
            if node_func(pos, cause, user, count, delay, payload, last_pos) then
                updated = true
            end
        end
        -- if the node updated and signalled so, it will continue propagating the update
        if updated then
            node_updates.update_node_propagate(pos, cause, user, count, delay, payload, last_pos)
            return payload or false
        end
    end
    return false
end

-- triggers a node update, such as "place" or "dig"
---@param pos table
---@param user table
---@param cause string
function node_updates.trigger_update(pos, user, cause)
    node_updates.update_node_propagate(pos, cause, user, 15)
end

core.register_on_dignode(function(pos, oldnode, digger)
    node_updates.trigger_update(pos, digger, "dig") end)
core.register_on_placenode(function(pos, oldnode, placer)
    node_updates.trigger_update(pos, placer, "place") end)
core.register_on_punchnode(function(pos, node, puncher, pointed_thing)
    node_updates.trigger_update(pos, puncher, "place") end)

core.register_on_liquid_transformed(function(pos_list, node_list)
    -- local time = os.clock()
    for i, pos in ipairs(pos_list) do repeat
        local prev_ndef = core.registered_nodes[node_list[i].name]
        if prev_ndef and prev_ndef._liquid_type then
            break end
        local node = core.get_node(pos)
        local def = core.registered_nodes[node.name]
        if not def then break end

        if def._liquid_type ~= nil then
            node_updates.update_node_propagate(pos, "liquid", nil, 2, 0, nil, nil)
        end
    until true end
    -- core.log(dump((os.clock() - time) * 100))
end)

local core_set_node = core.set_node
---@param pos table
---@param node table
---@param update boolean | nil
core.set_node = function(pos, node, update)
    core_set_node(pos, node)
    if not update then return end
    node_updates.update_node_propagate(pos, "place", nil, 15)
end

