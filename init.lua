
-- Example use:
--[[

	core.register_node("my_mod:node_name", {
		_on_node_update = function(pos, cause, user, count, payload, data)
			return
				true or {} or false or nil, --> change payload, or bool for whether to propagate
				true or false --> true if this node has changed and should not have more callbacks run
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
		function(pos, cause, user, count, payload, data)
			return
				true or {} or false or nil, --> change payload, or bool for whether to propagate
				true or false --> true if this node has changed and should not have more callbacks run
		end
	)
--]]
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

local function propagate(pos, cause, user, count, delay, payload, data)
	local offset = 2 -- math.random(0, 5)
	for i=1, #adjacent do
		local p = adjacent[(i + offset) % 6 + 1]
		local v = vector.add(pos, p)
		if not data.node_index[tostring(v)] then
			node_updates.update_node(v, cause, user, count-1, delay, payload, data)
		end
	end
end

local function check_data(data)
	-- convert vectors to a table that includes the vector
	if data and type(data) == "table" and getmetatable(data) == vector then
		data = {node_index = {tostring(data)}}
	end
	if not data then data = {node_index = {}} end
	if not data.node_index then data.node_index = {} end
	return data
end

-- updates this node and also propagate it to adjacent ones
---@param pos table
---@param cause string
---@param user table | nil (or userdata)
---@param count number
---@param delay number | nil
---@param payload table | nil
---@param data table | nil
---@return nil
function node_updates.update_node_propagate(pos, cause, user, count, delay, payload, data)
	data = check_data(data)
	if not delay then delay = 0.1 end
	-- only allow a certain limit on total updates per server step
	if calls > call_limit then return false end
	if count <= 0 then return end
	-- update this node only if it's not already processed
	if not data.node_index[tostring(pos)] then
		local ret = node_updates.update_node(pos, cause, user, count-1, delay, payload, pos)
		if (not payload) and type(ret) == "table" then payload = ret end
	end
	-- propagate will do count - 1 anyway, so don't even bother doing adjacent if count==1
	if count <= 1 then return end
	if delay == 0 then
		-- #RECURSION
		propagate(pos, cause, user, count, delay, payload, data)
	else
		core.after(delay, propagate, pos, cause, user, count, delay, payload, data)
	end
end

-- Updates a single node, and depending on its return value, propagates it to adjacent nodes.
---@param pos table
---@param cause string
---@param user table | nil (or userdata)
---@param count number
---@param delay number | nil
---@param payload table | nil
---@param data table | nil
---@param node table | nil
---@return table | boolean
function node_updates.update_node(pos, cause, user, count, delay, payload, data, node)
	data = check_data(data)
	data.node_index[tostring(pos)] = true
	if count <= 0 then return false end
	if not node then node = core.get_node_or_nil(pos) end
	-- don't trigger on `ignore` or un-generated nodes
	if not node then return false end
	-- don't trigger on unknown nodes either
	local ndef = core.registered_nodes[node.name]
	if ndef then
		local updated = false
		if ndef._on_node_update then
			calls = calls + (cause == "liquid" and 0.1 or 1)
			-- allow the payload to propogate
			local ret, halt = ndef._on_node_update(pos, cause, user, count, payload, data)
			if ret then
				if type(ret) == "table" then payload = ret end
				updated = true
			end
		end
		-- go through the registered update funcs and if any of them return true, propogate the update
		for _, node_func in ipairs(node_updates.registered_on_node_updates) do
			local ret, halt = node_func(pos, cause, user, count, delay, payload, data)
			if ret then
				if type(ret) == "table" then payload = ret end
				updated = true
			end
			if halt then break end
		end
		-- if the node updated and signalled so, it will continue propagating the update
		if updated then
			node_updates.update_node_propagate(pos, cause, user, count, delay, payload, data)
			return payload or false
		end
	end
	return false
end

-- triggers a node update, such as "place" or "dig"
---@param pos table
---@param user table
---@param cause string
function node_updates.trigger_update(pos, user, cause, self_update)
	node_updates.update_node_propagate(pos, cause, user, 15, nil, nil, (self_update==true) and pos or nil)
end

core.register_on_dignode(function(pos, oldnode, user)
	node_updates.update_node_propagate(pos, "dig", user, 15, nil, nil, pos) end)
core.register_on_placenode(function(pos, oldnode, user)
	node_updates.update_node_propagate(pos, "place", user, 15, nil, nil, pos) end)
core.register_on_punchnode(function(pos, oldnode, user, pointed_thing)
	node_updates.update_node(pos, "punch", user, 15, nil, nil, nil, oldnode) end)

core.register_on_liquid_transformed(function(pos_list, node_list)
	-- local time = os.clock()
	for i, pos in ipairs(pos_list) do repeat
		local node = core.get_node(pos)
		if node.name ~= node_list[i].name then
			node_updates.update_node_propagate(pos, "liquid", nil, 2, 0, {old_node = node_list[1]}, nil)
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
	node_updates.update_node_propagate(pos, "place", nil, 15, nil, nil, pos)
end

-- falling_node

local core_spawn_falling_node = core.spawn_falling_node
function core.spawn_falling_node(pos, ...)
	local a, b, c = core_spawn_falling_node(pos, ...)
	if a then
		node_updates.update_node_propagate(pos, "dig", nil, 15, nil, nil, pos)
	end
	return a, b, c
end

local core_check_single_for_falling = core.check_single_for_falling
function core.check_single_for_falling(pos, ...)
	local a, b, c = core_check_single_for_falling(pos, ...)
	if a then
		node_updates.update_node_propagate(pos, "dig", nil, 15, nil, nil, pos)
		return a, b, c
	end
end

local core_falling_node = core.registered_entities["__builtin:falling_node"]
local falling_node = table.copy(core_falling_node)

local old_add_node = core.add_node
local add_node_calls = {}
local function add_node(pos, ...)
	table.insert(add_node_calls, pos)
	return old_add_node(pos, ...)
end
-- bad builtin means stupid workarounds
local function hook_add_node()
	if add_node ~= core.add_node then old_add_node = core.add_node end
	rawset(core, "add_node", add_node)
end
local function unhook_add_node()
	rawset(core, "add_node", old_add_node)
	local sets = add_node_calls
	add_node_calls = {}
	return sets
end

falling_node.try_place = function(self, bcp, bcn)
	hook_add_node()
	local a, b, c = core_falling_node.try_place(self, bcp, bcn)
	local sets = unhook_add_node()
	for i, pos in ipairs(sets) do
		node_updates.update_node_propagate(pos, "place", nil, 15, nil, nil, pos)
	end
	return a, b, c
end
core.register_entity(":__builtin:falling_node", falling_node)
