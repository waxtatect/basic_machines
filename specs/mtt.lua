local MP = minetest.get_modpath("basic_machines") .. "/"

-- Load a 20x20x20 area.
local pos = { x=0, y=0, z=0 }
local halfsize = { x=10, y=10, z=10 }
local pos1 = vector.subtract(pos, halfsize)
local pos2 = vector.add     (pos, halfsize)
mtt.emerge_area(pos1, pos2)

-- Create a fake player to be the machine owner.
local player
mtt.register("setup", function(callback)
	player = mtt.join_player("singleplayer")
	callback()
end)

local function place_schematic(schematic, schem_pos1, schem_pos2)
	-- Init vmanip
	local manip = minetest.get_voxel_manip()
	local minedge, maxedge = manip:read_from_map(schem_pos1, schem_pos2)
	local area = VoxelArea:new({MinEdge=minedge, MaxEdge=maxedge})

	-- Fill with air
	local data = {}
	for i = 1, area:getVolume() do
		data[i] = minetest.get_content_id("air")
	end
	manip:set_data(data)

	-- Place schematic onto a vmanip to ensure blocks stay within a predictable area.
	local center = (schem_pos1 + schem_pos2) / 2
	local schem_flags = { place_center_x = true, place_center_y = true, place_center_z = true }
	if not minetest.place_schematic_on_vmanip(manip, center, schematic, nil, nil, nil, schem_flags) then
		error("schematic is too big")
	end

	-- Write to map
	manip:write_to_map()
	manip:update_map()

	-- Ensure all metadata is cleared
	local meta_positions = minetest.find_nodes_with_meta(schem_pos1, schem_pos2)
	for _, meta_pos in ipairs(meta_positions) do
		minetest.get_meta(meta_pos):from_table(nil)
	end
end

-- Benchmark time it takes to move 9 pieces of dirt back and forth between a 3x3 area and a chest.
mtt.benchmark("move-9-dirt-with-mover-and-distributor", function(callback, iterations)
	local schematic = MP .. "specs/schematics/move-9-dirt-with-mover-and-distributor.mts"
	place_schematic(schematic, pos1, pos2)

	-- Node defs
	local chest_def = minetest.registered_nodes["default:chest"]
	local mover_def = minetest.registered_nodes["basic_machines:mover"]
	local batt_def = minetest.registered_nodes["basic_machines:battery_0"]
	local dist_def = minetest.registered_nodes["basic_machines:distributor"]
	local dirt_def = minetest.registered_nodes["default:dirt"]

	-- Look for nodes
	local chest_pos = minetest.find_node_near(pos, 10, chest_def.name, true)
	local mover_pos = minetest.find_node_near(pos, 10, mover_def.name, true)
	local batt_pos = minetest.find_node_near(pos, 10, batt_def.name, true)

	local halfx = { x=10, y=0, z=0 }
	local left_pos = vector.subtract(pos, halfx)
	local right_pos = vector.add(    pos, halfx)
	local dist1_pos = minetest.find_node_near(left_pos, 10, dist_def.name, true)
	local dist2_pos = minetest.find_node_near(right_pos, 10, dist_def.name, true)

	-- Area to move dirt from / to
	local src_pos1 = { x=0, y=5, z=0 }
	local src_pos2 = { x=3, y=5, z=3 }

	-- On place
	mover_def.after_place_node(mover_pos, player)
	batt_def.after_place_node(batt_pos, player)
	dist_def.after_place_node(dist1_pos, player)
	dist_def.after_place_node(dist2_pos, player)
	chest_def.on_construct(chest_pos)

	-- Configure mover
	local mover_meta = minetest.get_meta(mover_pos)
	mover_meta:set_string("prefer", dirt_def.name)

	-- Source
	mover_meta:set_int("x0", src_pos1.x - mover_pos.x)
	mover_meta:set_int("y0", src_pos1.y - mover_pos.y)
	mover_meta:set_int("z0", src_pos1.z - mover_pos.z)
	mover_meta:set_int("x1", src_pos2.x - mover_pos.x)
	mover_meta:set_int("y1", src_pos2.y - mover_pos.y)
	mover_meta:set_int("z1", src_pos2.z - mover_pos.z)
	mover_meta:set_int("dim", 4 * 4)

	-- Target
	mover_meta:set_int("x2", chest_pos.x - mover_pos.x)
	mover_meta:set_int("y2", chest_pos.y - mover_pos.y)
	mover_meta:set_int("z2", chest_pos.z - mover_pos.z)

	-- Configure dist1
	local dist1_meta = minetest.get_meta(dist1_pos)
	for i = 1, 9 do
		dist1_meta:set_int("x" .. i, mover_pos.x - dist1_pos.x)
		dist1_meta:set_int("y" .. i, mover_pos.y - dist1_pos.y)
		dist1_meta:set_int("z" .. i, mover_pos.z - dist1_pos.z)
	end
	dist1_meta:set_int("n", 9)

	-- Configure dist2
	local dist2_meta = minetest.get_meta(dist2_pos)
	dist2_meta:set_int("x1", dist1_pos.x - dist2_pos.x)
	dist2_meta:set_int("y1", dist1_pos.y - dist2_pos.y)
	dist2_meta:set_int("z1", dist1_pos.z - dist2_pos.z)
	dist2_meta:set_int("x2", mover_pos.x - dist2_pos.x)
	dist2_meta:set_int("y2", mover_pos.y - dist2_pos.y)
	dist2_meta:set_int("z2", mover_pos.z - dist2_pos.z)
	dist2_meta:set_int("active2", -1) -- flip mover direction

	-- Configure battery
	local batt_meta = minetest.get_meta(batt_pos)
	batt_meta:set_float("capacity", 100 * iterations)
	batt_meta:set_float("energy", 100 * iterations)

	-- Configure chest
	local chest_meta = minetest.get_meta(chest_pos)
	local chest_inv = chest_meta:get_inventory()
	local stack = ItemStack({ name = dirt_def.name, count = 9 })
	chest_inv:add_item("main", stack)

	-- Ignore machine limits
	basic_machines.properties.machines_minstep = 0
	basic_machines.properties.machines_timer = 0
	basic_machines.settings.mover_max_temp = iterations

	-- Critical path to benchmark
	for _ = 1, iterations do
		dist_def.effector.action_on(dist2_pos, basic_machines.properties.machines_TTL)
	end

	callback()
end)