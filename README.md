# Node Updates
Nodes will signal when they have been changed, such as when a neighboring node was placed or dug. This means you can avoid timers and globalsteps in some cases, and generally makes your game more "reactive" than passive.

## Common Usage
For most purposes, add this callback to your node definition. The first return value is whether to keep updating adjacent nodes. The second value should be true if you change the node.
```lua
core.register_node("my_mod:node_name", {
	_on_node_update = function(pos, cause, user, data)
		return
			true or false or nil, --> change payload, or bool for whether to propagate
			true or false or nil --> true if this node has changed and should not have more callbacks run
	end,
})
```

Or for example to dig all leaves when punched:
```lua
core.register_node("my_mod:leaves", {
	_on_node_update = function(pos, cause, user, data)
		-- `dig_node` and similar functions will cause another update which
		-- could lead to infinite updates, so we have to be careful when using it
		if cause == "punch" then -- and not `cause == "dig"`
			core.node_dig(pos, core.get_node(pos), user)
			return true, true
		end
	end,
})
```

## What it Detects
- dig_node --> `"dig"`
- place_node --> `"place"`
- any `falling_node`s --> `"dig"`
- set_node if flag set (`core.set_node(pos, node, true)`) --> `"set"`
- liquid transforms (engine limitations might cause this to not be 100% accurate) --> `"liquid"`
- custom node update types

## Advanced Usage
You may also wish to hook into all node updates. This is not completely airtight however; it's not intended to catch all causes. For example it will not pick up `set_node` by default.
```lua
node_update.register_on_node_update(
	function(pos, cause, user, count, payload, data)
		return
			true or false or nil, --> change payload, or bool for whether to propagate
			true or false or nil --> true if this node has changed and should not have more callbacks run
	end
)
```

You can also cause updates to happen.
```lua
-- update all adjacent nodes
node_updates.cause_adjacent_update(pos, "place", user)
-- update all adjacent nodes, including the `pos` node
node_updates.cause_adjacent_update(pos, "dig", user, {}, true)
-- update only this node and propagate the update if it returns true
node_updates.cause_single_update(pos, "punch", user, {})
-- update adjacent nodes and give them some arbitrary data
node_updates.cause_adjacent_update(pos, "my_special_update_type", user, {
	my_arbitrary_data = "hello world",
	_count = 2, -- distance to update (manhatten dist)
	_visited_list = {[tostring(pos)]=true}, -- no updates for positions in this map
	_delay = 0.0, -- delay between updating this one and its adjacent (0 for instant), NOT saved between server starts
})
```
