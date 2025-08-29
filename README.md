# Node Updates
Nodes will signal when they have been changed, such as when a neighboring node was placed or dug. This means you can avoid timers and globalsteps in some cases, and generally makes your game more "reactive" than passive.

## Common Usage
For most purposes, add this callback to your node definition:
```lua
core.register_node("my_mod:node_name", {
	_on_node_update = function(pos, cause, user, counts, payload, last_pos)
		return true or {} or false or nil
	end,
})
```
Or for example to dig all leaves when punched:
```lua
core.register_node("my_mod:leaves", {
	_on_node_update = function(pos, cause, user, counts, payload, last_pos)
        -- `dig_node` and similar functions will cause another update which
        -- could lead to infinite updates, so we have to be careful when using it
        if cause == "punch" then -- and not `cause == "dig"`
            core.node_dig(pos, core.get_node(pos), user)
            return true
        end
	end,
})
```

## What it Detects
- dig_node
- place_node
- set_node if flag set (`core.set_node(pos, node, true)`)
- liquid transforms (engine limitations might cause this to not be 100% accurate)
- custom node update types

## Advanced Usage
You may also wish to hook into all node updates. This is not completely airtight however; it's not intended to catch all causes. For example it will not pick up `set_node` by default.
```lua
node_update.register_on_node_update(
	function(pos, cause, user, counts, payload, last_pos)
		-- function body here
	end
)
```

You can also cause updates to happen. You can do so manually or using a shortcut:
```lua
-- triggers a [cause] node update at this position, mimicking the normal updates
-- especially useful when using `swap_node` or LVM
node_updates.trigger_update(pos, user, cause)

-- updates this node and also always propagate it to adjacent ones
-- if `last_pos` included, it will not update the last_pos node
node_updates.update_node_propagate(pos, cause, user, count, delay, payload, last_pos)

-- updates a single node, and depending on its return value, propagates it to adjacent nodes
-- if included, does not update `last_pos`
node_updates.update_node(pos, cause, user, count, delay, payload, last_pos)
```