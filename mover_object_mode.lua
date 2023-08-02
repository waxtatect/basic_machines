-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_chests = basic_machines.get_mover("chests")
local vector_add = vector.add
local max_range = basic_machines.properties.max_range
local mover_no_teleport_table = basic_machines.get_mover("no_teleport_table")

local function object(pos, meta, owner, prefer, pos1, _, _, _, pos2, mreverse)
	local x1, y1, z1

	if mreverse == 1 then
		x1, y1, z1 = meta:get_int("x0"), meta:get_int("y0"), meta:get_int("z0") -- source1
	else
		x1, y1, z1 = meta:get_int("x1"), meta:get_int("y1"), meta:get_int("z1") -- source2
	end

	local radius = math.min(vector.distance(pos1, vector_add(pos, {x = x1, y = y1, z = z1})), max_range) -- distance source1-source2
	local elevator = meta:get_int("elevator"); if elevator == 1 and radius == 0 then radius = 1 end -- for compatibility
	local teleport_any, no_sound

	local node2 = minetest.get_node_or_nil(pos2)
	local node2_name
	if node2 then
		node2_name = node2.name
	else
		minetest.load_area(pos2)
		node2_name = minetest.get_node(pos2).name
	end

	-- object move
	if mover_chests[node2_name] and elevator == 0 then -- put objects in target chest
		prefer = prefer or meta:get_string("prefer")
		local inv

		for _, obj in ipairs(minetest.get_objects_inside_radius(pos1, radius)) do
			if not obj:is_player() then
				local lua_entity = obj:get_luaentity()
				local detected_obj = lua_entity and (lua_entity.itemstring or lua_entity.name) or ""
				local stack = ItemStack(detected_obj); local detected_obj_name = stack:get_name()
				if not mover_no_teleport_table[detected_obj_name] then -- forbid to take an object on no teleport list
					if prefer == "" or prefer == detected_obj_name or prefer == detected_obj then
						if not stack:is_empty() and minetest.registered_items[detected_obj_name] then -- put item in chest
							if lua_entity and not lua_entity.tamed then -- check if mob (mobs_redo) tamed
								inv = inv or minetest.get_meta(pos2):get_inventory()
								if inv:room_for_item("main", stack) then
									obj:remove(); inv:add_item("main", stack); teleport_any = true
								end
							end
						end
					elseif prefer == "bucket:bucket_empty" and detected_obj_name == "mobs_animal:cow" then -- milk cows, bucket and mobs_animals mods needed
						if lua_entity and not lua_entity.child and not lua_entity.gotten then -- already milked ?
							inv = inv or minetest.get_meta(pos2):get_inventory()
							if inv:contains_item("main", "bucket:bucket_empty") then
								inv:remove_item("main", "bucket:bucket_empty")
								if inv:room_for_item("main", "mobs:bucket_milk") then
									inv:add_item("main", "mobs:bucket_milk")
								else
									minetest.add_item(obj:get_pos(), {name = "mobs:bucket_milk"})
								end
								lua_entity.gotten = true; teleport_any = true
							end
						end
					end
				end
			end
		end
	elseif node2_name ~= "ignore" then -- move objects to another location
		prefer = prefer or meta:get_string("prefer")
		local times, velocityv = tonumber(prefer) or 0
		if times ~= 0 then
			if times == 99 then
				velocityv = {x = 0, y = 0, z = 0}
			else
				if times > 20 then times = 20 elseif times < 0.2 then times = 0.2 end
				velocityv = vector.subtract(pos2, pos1)
				local vv = math.sqrt(velocityv.x * velocityv.x + velocityv.y * velocityv.y + velocityv.z * velocityv.z)
				if vv ~= 0 then vv = vv / vv * times else vv = 0 end
				velocityv = vector.multiply(velocityv, vv)
			end
		end

		for _, obj in ipairs(minetest.get_objects_inside_radius(pos1, radius)) do
			if obj:is_player() then
				if not minetest.is_protected(obj:get_pos(), owner) and
					(prefer == "" or prefer == obj:get_player_name())
				then -- move player only from owners land
					obj:set_pos(pos2); teleport_any = true
				end
			else
				local lua_entity = obj:get_luaentity()
				local detected_obj = lua_entity and (lua_entity.itemstring or lua_entity.name) or ""
				if not mover_no_teleport_table[detected_obj] then -- forbid to take an object on no teleport list
					if times > 0 then -- interaction with objects like carts
						if times == 99 then
							obj:set_acceleration(velocityv)
							obj:set_velocity(velocityv)
							obj:set_properties({automatic_rotate = vector.distance(pos1, obj:get_pos()) / (radius + 5)})
						else
							if lua_entity then
								local name = lua_entity.name
								if name == "basic_machines:ball" then -- move balls for free
									obj:set_velocity(velocityv) -- move balls with set velocity in target direction
								elseif name == "carts:cart" then -- just accelerate cart
									obj:set_velocity(velocityv) -- move cart with set velocity in target direction
									no_sound = true; break
								end
							else -- don't move objects like balls to destination after delay
								minetest.after(times, function()
									obj:move_to(pos2, false); teleport_any = true
								end)
							end
						end
					else
						obj:move_to(pos2, false); teleport_any = true
					end
				end
			end
		end
	end

	-- fuel cost applied only if any teleport
	if teleport_any then
		local activation_count = meta:get_int("activation_count")
		if no_sound then
			return activation_count
		else
			-- if activation_count < 16 then -- play sound
				-- minetest.sound_play("basic_machines_object_move", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
			-- end
			return activation_count
		end
	end
end

basic_machines.add_mover_mode("object",
	F(S("Make TELEPORTER/ELEVATOR:\n This will move any object inside a sphere (with center source1 and radius defined by distance between source1/source2) to target position\n" ..
		" For ELEVATOR, teleport origin/destination need to be placed exactly in same coordinate line with mover, and you need to upgrade with 1 diamond block for every 100 height difference")),
	F(S("object")), object
)