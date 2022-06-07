-- rnd: code borrowed from machines, mark.lua

-- Needed for marking
machines = {
	marker1 = {}, marker11 = {}, marker2 = {}
}

-- mark position 1
machines.mark_pos1 = function(name, pos)
	minetest.get_voxel_manip():read_from_map(pos, pos) -- make area stay loaded

	if machines.marker1[name] then -- marker already exists
		machines.marker1[name]:remove() -- remove marker
	end

	-- add marker
	machines.marker1[name] = minetest.add_entity(pos, "machines:pos1")

	if machines.marker1[name] then
		machines.marker1[name]:get_luaentity()._name = name
	end
end

-- mark position 11
machines.mark_pos11 = function(name, pos)
	minetest.get_voxel_manip():read_from_map(pos, pos) -- make area stay loaded

	if machines.marker11[name] then -- marker already exists
		machines.marker11[name]:remove() -- remove marker
	end

	-- add marker
	machines.marker11[name] = minetest.add_entity(pos, "machines:pos11")

	if machines.marker11[name] then
		machines.marker11[name]:get_luaentity()._name = name
	end
end

-- mark position 2
machines.mark_pos2 = function(name, pos)
	minetest.get_voxel_manip():read_from_map(pos, pos) -- make area stay loaded

	if machines.marker2[name] then -- marker already exists
		machines.marker2[name]:remove() -- remove marker
	end

	-- add marker
	machines.marker2[name] = minetest.add_entity(pos, "machines:pos2")

	if machines.marker2[name] then
		machines.marker2[name]:get_luaentity()._name = name
	end
end

minetest.register_entity(":machines:pos1", {
	initial_properties = {
		physical = false,
		collisionbox = {-0.55, -0.55, -0.55, 0.55, 0.55, 0.55},
		visual = "cube",
		visual_size = {x = 1.1, y = 1.1},
		textures = {"machines_pos1.png", "machines_pos1.png",
			"machines_pos1.png", "machines_pos1.png",
			"machines_pos1.png", "machines_pos1.png"},
		glow = 11,
		static_save = false,
		shaded = false
	},
	on_deactivate = function(self)
		machines.marker1[self._name] = nil
	end,
	on_step = function(self, dtime)
		self._timer = self._timer + dtime
		if self._timer > 9 then
			self.object:remove()
		end
	end,
	on_punch = function(self)
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end,
	_name = "",
	_timer = 0
})

minetest.register_entity(":machines:pos11", {
	initial_properties = {
		physical = false,
		collisionbox = {-0.55, -0.55, -0.55, 0.55, 0.55, 0.55},
		visual = "cube",
		visual_size = {x = 1.1, y = 1.1},
		textures = {"machines_pos11.png", "machines_pos11.png",
			"machines_pos11.png", "machines_pos11.png",
			"machines_pos11.png", "machines_pos11.png"},
		glow = 11,
		static_save = false,
		shaded = false
	},
	on_deactivate = function(self)
		machines.marker11[self._name] = nil
	end,
	on_step = function(self, dtime)
		self._timer = self._timer + dtime
		if self._timer > 9 then
			self.object:remove()
		end
	end,
	on_punch = function(self)
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end,
	_name = "",
	_timer = 0
})

minetest.register_entity(":machines:pos2", {
	initial_properties = {
		physical = false,
		collisionbox = {-0.55, -0.55, -0.55, 0.55, 0.55, 0.55},
		visual = "cube",
		visual_size = {x = 1.1, y = 1.1},
		textures = {"machines_pos2.png", "machines_pos2.png",
			"machines_pos2.png", "machines_pos2.png",
			"machines_pos2.png", "machines_pos2.png"},
		glow = 11,
		static_save = false,
		shaded = false
	},
	on_deactivate = function(self)
		machines.marker2[self._name] = nil
	end,
	on_step = function(self, dtime)
		self._timer = self._timer + dtime
		if self._timer > 9 then
			self.object:remove()
		end
	end,
	on_punch = function(self)
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end,
	_name = "",
	_timer = 0
})