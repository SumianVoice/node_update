
-- Example use:
--[[

	core.register_node("my_mod:node_name", {
		_on_node_update = function(pos, cause, user, data)
			return
				true or false or nil, --> bool | nil for whether to propagate to adjacent
				true or false or nil --> true if this node has changed and should not have more callbacks run
		end,
	})
]]
-- This is intended to form a node update system, where if a node is updated,
-- it notifies its neighbors in case they need to do something in response.
node_updates = {}

-- internal functions, do not use
node_updates.p = {}

node_updates.p.registered_on_node_updates = {}
node_updates.p.registered_on_update_causes = {}

local calls = 0
-- max number of updates per server step
node_updates.call_limit = 1000 -- per step

node_updates.p.nodes_with_updates = {}
local nodes_with_updates = node_updates.p.nodes_with_updates

core.register_on_mods_loaded(function()
	for name, ndef in pairs(core.registered_nodes) do
		if ndef._on_node_update then
			nodes_with_updates[name] = true
		end
	end
end)
-- it's possible a node was overridden after the above
core.after(0.0, function()
	for name, ndef in pairs(core.registered_nodes) do
		if ndef._on_node_update then
			nodes_with_updates[name] = true
		end
	end
end)

local function reset_calls(dtime)
	if calls > node_updates.call_limit then
		core.log("warning", "[node_updates] too many node updates are ocurring!")
	end
	calls = 0
end

core.register_globalstep(reset_calls)

--[[
	Same callback signature of nodedef._on_node_update

	node_updates.register_on_node_update(
		function(pos, cause, user, data)
			return
				true or false or nil, --> bool | nil for whether to propagate to adjacent
				true or false or nil --> true if this node has changed and should not have more callbacks run
		end
	)
--]]
---@param func function
function node_updates.register_on_node_update(func)
	table.insert(node_updates.p.registered_on_node_updates, func)
end

-- Same callback signature of `nodedef._on_node_update` and `node_updates.register_on_node_update`
---@param func function
function node_updates.register_on_update_cause(cause, func)
	local set = node_updates.p.registered_on_update_causes[cause]
	if not set then
		set = {}
		node_updates.p.registered_on_update_causes[cause] = set
	end
	table.insert(set, func)
end

local adjacent = {
	[1] = vector.new(0, 1, 0),
	[2] = vector.new(0, -1, 0),
	[3] = vector.new(1, 0, 0),
	[4] = vector.new(-1, 0, 0),
	[5] = vector.new(0, 0, 1),
	[6] = vector.new(0, 0, -1),
}

local function check_data(data)
	-- convert vectors to a table that includes the vector
	if data and (type(data) == "table") and (getmetatable(data) == vector) then
		data = {_visited_list = {[tostring(data)] = pos}}
	end
	if not data then data = {_visited_list = {}} end
	if not data._visited_list then data._visited_list = {} end
	if not data._delay then data._delay = 0.1 end
	if not data._count then data._count = 8 end
	return data
end

local function mdist(p1, p2)
	return math.abs(p1.x - p2.x) + math.abs(p1.y - p2.y) + math.abs(p1.z - p2.z)
end

function node_updates.p.update_pos(pos, cause, user, data)
	calls = calls + (data._cost or 1)
	local node = core.get_node_or_nil(pos)
	if not node then return end
	local is_updated, halt
	if nodes_with_updates[node.name] then
		local ndef = node and core.registered_nodes[node.name]
		is_updated, halt = ndef._on_node_update(pos, cause, user, data)
	end
	if not data._visited_list[tostring(pos)] then
		data._visited_list[tostring(pos)] = pos
	end
	local cause_callbacks = node_updates.p.registered_on_update_causes[cause]
	if cause_callbacks and not halt then for _, node_func in ipairs(cause_callbacks) do
		local is_callback_updated
		is_callback_updated, halt = node_func(pos, cause, user, data)
		is_updated = is_updated or is_callback_updated
		if halt then break end
	end end
	if not halt then for _, node_func in ipairs(node_updates.p.registered_on_node_updates) do
		local is_callback_updated
		is_callback_updated, halt = node_func(pos, cause, user, data)
		is_updated = is_updated or is_callback_updated
		if halt then break end
	end end
	return is_updated, halt
end

function node_updates.p.queue_adjacent(pos, stack, cause, user, data, no_iterate)
	for i, d in ipairs(adjacent) do
		local p = pos + d
		-- only add unseen nodes
		if not data._visited_list[tostring(p)] then
			data._visited_list[tostring(p)] = pos
			table.insert(stack, p)
			if (not no_iterate) and data._delay > 0 then
				core.after(data._delay, node_updates.p.iterate_stack, stack, cause, user, data)
			end
		end
	end
end

function node_updates.p.iterate_stack(stack, cause, user, data)
	if #stack < 1 then return false end
	if calls > node_updates.call_limit then
		for i = #stack, 1, -1 do
			table.remove(stack, i)
		end
		return false
	end
	local pos = table.remove(stack, 1)
	local is_updated, halt = node_updates.p.update_pos(pos, cause, user, data)
	data._old_node = nil
	if is_updated then
		if data._start_pos and (mdist(pos, data._start_pos) < data._count) then
			node_updates.p.queue_adjacent(pos, stack, cause, user, data)
		end
	end
	return true
end

function node_updates.p.cause_update(pos, stack, cause, user, data)
	data = check_data(data)
	data._start_pos = pos
	if data._delay > 0 then
		-- first set of positions happens immediately, the rest get `core.after`
		for i = 1, #stack do
			node_updates.p.iterate_stack(stack, cause, user, data)
		end
	else
		for i = 1, 1e6 do
			if node_updates.p.iterate_stack(stack, cause, user, data) == false then
				break
			end
		end
	end
end

-- updates adjacent nodes but not the `pos` node and if it returns true propagates further
---@param pos table 'vector'
---@param cause string
---@param user table | nil 'userdata'
---@param data table | nil
---@param update_start boolean | nil 'whether to update `pos`'
function node_updates.cause_adjacent_update(pos, cause, user, data, update_start)
	data = check_data(data)
	local stack = {}
	if not update_start then
		data._visited_list[tostring(pos)] = pos
	end
	node_updates.p.queue_adjacent(pos, stack, cause, user, data, true)
	node_updates.p.cause_update(pos, stack, cause, user, data)
end

-- updates just a single node at `pos` and propagates further only if it returns true
---@param pos table 'vector'
---@param cause string
---@param user table | nil 'userdata'
---@param data table | nil
function node_updates.cause_single_update(pos, cause, user, data)
	data = check_data(data)
	local stack = {pos}
	data._visited_list[tostring(pos)] = pos
	node_updates.p.cause_update(pos, stack, cause, user, data)
end

core.register_on_dignode(function(pos, old_node, user)
	node_updates.cause_adjacent_update(pos, "dig", user)
end)
core.register_on_placenode(function(pos, newnode, user, old_node, itemstack, pointed_thing)
	node_updates.cause_adjacent_update(pos, "place", user)
end)
core.register_on_punchnode(function(pos, old_node, user, pointed_thing)
	node_updates.cause_single_update(pos, "punch", user, {
		_old_node = old_node
	})
end)

core.register_on_liquid_transformed(function(pos_list, node_list)
	for i, pos in ipairs(pos_list) do repeat
		local node = core.get_node(pos)
		if node.name ~= node_list[i].name then
			node_updates.cause_adjacent_update(pos, "liquid", nil, {
				_count = 2,
				_visited_list = {[tostring(pos)] = pos},
				_cost = 0.01,
			})
		end
	until true end
end)

local core_set_node = core.set_node
---@param pos table 'vector'
---@param node table
---@param trigger_updates boolean | nil
core.set_node = function(pos, node, trigger_updates)
	core_set_node(pos, node)
	if not trigger_updates then return end
	node_updates.cause_adjacent_update(pos, "set", nil)
end

-- falling_node

function node_updates.p.on_falling_node_landed(pos)
	node_updates.cause_adjacent_update(pos, "place", nil)
end

function node_updates.p.on_falling_node_fall(pos)
	node_updates.cause_adjacent_update(pos, "dig", nil)
end

local core_spawn_falling_node = core.spawn_falling_node
function core.spawn_falling_node(pos, ...)
	local a, b, c = core_spawn_falling_node(pos, ...)
	if a then
		node_updates.p.on_falling_node_fall(pos)
	end
	return a, b, c
end

local core_check_single_for_falling = core.check_single_for_falling
function core.check_single_for_falling(pos, ...)
	local a, b, c = core_check_single_for_falling(pos, ...)
	if a then
		node_updates.p.on_falling_node_fall(pos)
		return a, b, c
	end
end

node_updates.register_on_update_cause("falling_node_check",
    function(pos, cause, user, data)
		local ret = core.check_single_for_falling(pos)
		return ret, ret
    end
)

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
		node_updates.p.on_falling_node_landed(pos)
	end
	return a, b, c
end
core.register_entity(":__builtin:falling_node", falling_node)
