--Owner selects an item to insert
--Any other player can click this node with an item and it will send
--a mesecon signal, though taking an item.
--It will do nothing if item is incorrect or count is not enough

--==============================================================================================
-------------------------- MAGIC WORDS ---------------------------------------------------------
--==============================================================================================

local S = minetest.get_translator(minetest.get_current_modname())

local use_texture_alpha = minetest.features.use_texture_alpha_string_modes and "opaque" or nil

local nodebox = { -6/16, -6/16, 2/16, 6/16, 6/16, 8/16 }

local ia_name = S("Item acceptor")

--==============================================================================================
---------------------------- SHORTCUTS ---------------------------------------------------------
--==============================================================================================
-- owner's UI
local get_ia_formspec = function(pos)
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z
	return "size[8,10.5]"..
	"list[nodemeta:" .. spos .. ";key;3.5,0.5;1,1;]"..
	"list[nodemeta:" .. spos .. ";main;0,1.75;8,4]"..
	"list[current_player;main;0,6.25;8,1;]"..
	"list[current_player;main;0,7.5;8,3;8]"..
	"listring[current_player;main]"..
	"listring[nodemeta:" .. spos .. ";key]"..
	"listring[current_player;main]"..
	"listring[nodemeta:" .. spos .. ";main]"..
	"listring[current_player;main]"..
	default.get_hotbar_bg(0, 6.25)
end

------------------------------------------------------------------------------------------------

local item_acceptor_swap = function(pos)
	local node = minetest.get_node(pos)
	if node.name:sub(1, 14) ~= "item_acceptor:" then -- something went wrong
		return
	end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack("key", 1)
	
	local nodename = node.name
	
	if inv:is_empty("key") then
		nodename = "item_acceptor:unconfigured"
	elseif inv:room_for_item("main", stack) then
		nodename = "item_acceptor:off"
	else
		nodename = "item_acceptor:full"
	end
	
	if node.name ~= nodename then
		minetest.swap_node(pos, {name = nodename, param2 = node.param2})
	end
end

------------------------------------------------------------------------------------------------

-- called by a node timer
mesecon.item_acceptor_turnoff = function(pos)
	local node = minetest.get_node(pos)
	if node.name ~= "item_acceptor:on" then -- has been dug
		return
	end
	
	item_acceptor_swap(pos)
	
	local rules = mesecon.rules.buttonlike_get(node)
	mesecon.receptor_off(pos, rules)
end

------------------------------------------------------------------------------------------------

local update_infotext = function(pos)
	local meta = minetest.get_meta(pos)
	local player_name = meta:get_string("owner")
	local inv = meta:get_inventory()
	
	local owned = S("Owned by @1", player_name)
	
	-- empty key - unconfigured
	if inv:is_empty("key") then
		meta:set_string("infotext", ia_name .. " " .. S("not configured") .. "\n" .. owned)
		return
	end
	
	local stack = inv:get_stack("key", 1)
	
	-- full
	if not inv:room_for_item("main", stack) then
		meta:set_string("infotext", ia_name .. " " .. S("full") .. "\n" .. owned)
		return
	end
	
	--configured
	
	local desc = stack:get_short_description()
	local count = tostring(stack:get_count())
	
	local player_name = meta:get_string("owner")
	
	meta:set_string("infotext", ia_name .. ": " .. desc .. " " .. count .. "\n" .. owned)
	
end

--==============================================================================================
-------------------------- NODE DEFINITION CALLBACKS -------------------------------------------
--==============================================================================================

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	--meta:set_string("infotext", ia_name)
	meta:set_string("owner", "")
	local inv = meta:get_inventory()
	inv:set_size("main", 8*4)
	inv:set_size("key", 1)
	
end

------------------------------------------------------------------------------------------------

-- create an inventory and owner name
local after_place_node = function(pos, placer, itemstack, pointed_thing)
	local meta = minetest.get_meta(pos)
	local player_name = placer:get_player_name()
	
	meta:set_string("owner", player_name)
	
	item_acceptor_swap(pos)
	update_infotext(pos)
	
	return minetest.is_creative_enabled(player_name)
	
end

------------------------------------------------------------------------------------------------

-- protection - only owner can dig it (if empty)
local can_dig = function(pos, player)
	local meta = minetest.get_meta(pos);
	local inv = meta:get_inventory()
	return inv:is_empty("key") and default.can_interact_with_node(player, pos)
end

------------------------------------------------------------------------------------------------

-- owner: configure
-- anyone else: insert an item
local on_rightclick = function(pos, node, clicker, wielded_stack, pointed_thing)
	
	if not minetest.is_player(clicker) then return end
	
	local meta = minetest.get_meta(pos)
	local player_name = clicker:get_player_name()
	if player_name == meta:get_string("owner") then
		
		minetest.show_formspec(player_name, "item_acceptor:off", get_ia_formspec(pos))
		
	else
		-- do nothing if already on
		if node.name == "item_acceptor:on" then return end
		
		-- bare hands, no item can be inserted
		if wielded_stack:is_empty() then return end
		
		local inv = meta:get_inventory()
		
		-- unconfigured
		if inv:is_empty("key") then return end
		
		local stack = inv:get_stack("key", 1)
		if not inv:room_for_item("main", stack) then return end
		
		if wielded_stack:get_name() == stack:get_name() and wielded_stack:get_count() >= stack:get_count() then
			
			local item = wielded_stack:take_item(stack:get_count())
			inv:add_item("main", item)
			
			-- swapping node
			minetest.swap_node(pos, {name = "item_acceptor:on", param2 = node.param2})
			mesecon.receptor_on(pos, mesecon.rules.buttonlike_get(node))
			minetest.sound_play("item_acceptor_coin", { pos = pos }, true) -- TODO: change sound
			minetest.get_node_timer(pos):start(1)
			
			update_infotext(pos)
		end
	end
end

------------------------------------------------------------------------------------------------

local on_blast = function(pos)
	local drops = {}
	default.get_inventory_drops(pos, "main", drops)
	default.get_inventory_drops(pos, "key", drops)
	drops[#drops+1] = "item_acceptor:off"
	minetest.remove_node(pos)
	return drops
end

--==============================================================================================
-------------------------- INVENTORY INTERACTION -----------------------------------------------
--==============================================================================================

------------------------------------------------------------------------------------------------
----- ALLOW

-- only owner can put an item in
local allow_metadata_inventory_put = function(pos, listname, index, stack, player)
	if not default.can_interact_with_node(player, pos) then
		return 0
	end
	-- cannot use this node as a storage
	if listname == "main" then
		return 0
	end
	
	-- really dumb workaround, but otherwise buckets will be duped
	local stackname = stack:get_name()
	if stackname:sub(1, 7) == "bucket:" and stackname ~= "bucket:bucket_empty" then
		return 0
	end
	
	return stack:get_count()
end

-- only owner can take items
local allow_metadata_inventory_take = function(pos, listname, index, stack, player)
	if not default.can_interact_with_node(player, pos) then
		return 0
	end
	return stack:get_count()
end

local allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

------------------------------------------------------------------------------------------------
----- ON

local on_metadata_inventory_put = function(pos, listname, index, stack, player)
	if listname ~= "key" then return end
	update_infotext(pos)
	item_acceptor_swap(pos)
end

local on_metadata_inventory_take = function(pos, listname, index, stack, player)
	if listname ~= "key" then return end
	update_infotext(pos)
	item_acceptor_swap(pos)
end

local on_metadata_inventory_move = function(pos)
	if listname ~= "key" then return end
	update_infotext(pos)
	item_acceptor_swap(pos)
end

--==============================================================================================
---------------------------------- THE DEFINITION ITSELF ---------------------------------------
--==============================================================================================

minetest.register_node("item_acceptor:off", {
	drawtype = "nodebox",
	tiles = {
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_off.png",
	},
	use_texture_alpha = use_texture_alpha,
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	legacy_wallmounted = true,
	walkable = true,
	on_rotate = mesecon.buttonlike_onrotate,
	sunlight_propagates = true,
	selection_box = {
	type = "fixed",
		fixed = nodebox,
	},
	node_box = {
		type = "fixed",
		fixed = {
			nodebox,
		},
	},
	groups = {dig_immediate = 2, mesecon_needs_receiver = 1},
	description = ia_name,
	sounds = default.node_sound_metal_defaults(),
	mesecons = {
		receptor = {
			state = mesecon.state.off,
			rules = mesecon.rules.buttonlike_get,
		}
	},
	on_blast = mesecon.on_blastnode,
	--- these functions are defined above
	on_rightclick = on_rightclick,
	on_construct = on_construct,
	after_place_node = after_place_node,
	can_dig = can_dig,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
})

------------------------------------------------------------------------------------------------

minetest.register_node("item_acceptor:on", {
	drawtype = "nodebox",
	tiles = {
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_on.png",
	},
	use_texture_alpha = use_texture_alpha,
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	legacy_wallmounted = true,
	walkable = true,
	on_rotate = false,
	light_source = minetest.LIGHT_MAX-7,
	sunlight_propagates = true,
	selection_box = {
		type = "fixed",
		fixed = nodebox,
	},
	node_box = {
		type = "fixed",
		fixed = {
			nodebox,
		},
    },
	groups = {dig_immediate=2, not_in_creative_inventory=1, mesecon_needs_receiver = 1},
	drop = "item_acceptor:off",
	description = S("Item acceptor"),
	sounds = default.node_sound_metal_defaults(),
	mesecons = {
		receptor = {
			state = mesecon.state.on,
			rules = mesecon.rules.buttonlike_get,
		},
	},
	on_blast = mesecon.on_blastnode,
	--- these functions are defined above
	on_timer = mesecon.item_acceptor_turnoff,
	can_dig = can_dig,
	on_rightclick = on_rightclick,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
})

------------------------------------------------------------------------------------------------

minetest.register_node("item_acceptor:full", {
	drawtype = "nodebox",
	tiles = {
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_full.png",
	},
	use_texture_alpha = use_texture_alpha,
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	legacy_wallmounted = true,
	walkable = true,
	on_rotate = false,
	light_source = minetest.LIGHT_MAX-7,
	sunlight_propagates = true,
	selection_box = {
		type = "fixed",
		fixed = nodebox,
	},
	node_box = {
		type = "fixed",
		fixed = {
			nodebox,
		},
    },
	groups = {dig_immediate=2, not_in_creative_inventory=1, mesecon_needs_receiver = 1},
	drop = "item_acceptor:off",
	description = S("Item acceptor"),
	sounds = default.node_sound_metal_defaults(),
	mesecons = {
		receptor = {
			state = mesecon.state.off,
			rules = mesecon.rules.buttonlike_get
		}
	},
	on_blast = mesecon.on_blastnode,
	--- these functions are defined above
	can_dig = can_dig,
	on_rightclick = on_rightclick,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
})

------------------------------------------------------------------------------------------------

minetest.register_node("item_acceptor:unconfigured", {
	drawtype = "nodebox",
	tiles = {
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_sides.png",
		"item_acceptor_unconfigured.png",
	},
	use_texture_alpha = use_texture_alpha,
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	legacy_wallmounted = true,
	walkable = true,
	on_rotate = false,
	light_source = minetest.LIGHT_MAX-7,
	sunlight_propagates = true,
	selection_box = {
		type = "fixed",
		fixed = nodebox,
	},
	node_box = {
		type = "fixed",
		fixed = {
			nodebox,
		},
    },
	groups = {dig_immediate=2, not_in_creative_inventory=1, mesecon_needs_receiver = 1},
	drop = "item_acceptor:off",
	description = S("Item acceptor"),
	sounds = default.node_sound_metal_defaults(),
	mesecons = {
		receptor = {
			state = mesecon.state.off,
			rules = mesecon.rules.buttonlike_get
		}
	},
	on_blast = mesecon.on_blastnode,
	--- these functions are defined above
	can_dig = can_dig,
	on_rightclick = on_rightclick,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
})

--==============================================================================================
---------------------------------- CRAFTING ----------------------------------------------------
--==============================================================================================

minetest.register_craft({
	output = 'item_acceptor:off',
	recipe = {
		{"mesecons_gamecompat:steel_ingot", "mesecons_gamecompat:steel_ingot", "mesecons_gamecompat:steel_ingot"},
		{"",								"default:chest",                   "group:mesecon_conductor_craftable"},
		{"mesecons_gamecompat:steel_ingot", "mesecons_gamecompat:steel_ingot", "mesecons_gamecompat:steel_ingot"},
	}
})
