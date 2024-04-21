-- rnd: code borrowed from machines, mark.lua
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

-- Needed for marking
local machines_marks = {"1", "11", "2", "N", "S"}

machines = {
	remove_markers = function(name, marks)
		marks = marks or machines_marks
		for _, n in ipairs(marks) do
			local markern = "marker" .. n
			if machines[markern][name] then
				machines[markern][name]:remove() -- remove marker
			end
		end
	end
}

for _, n in ipairs(machines_marks) do
	local markern = "marker" .. n
	local posn = "machines:pos" .. n
	local texturen, delay

	if n == "N" then -- mover "Now" button marker
		texturen = "machines_pos.png^[colorize:#ffd700"
		delay = 27
	elseif n == "S" then -- mover "Show" button marker
		texturen = "machines_pos.png^[colorize:#008080"
		delay = 21
	else -- source1, source2 and target markers
		texturen = "machines_pos" .. n .. ".png"
		delay = 9
	end

	machines[markern] = {}

	machines["mark_pos" .. n] = function(name, pos, node_is_punchable)
		if machines[markern][name] then -- marker already exists
			machines[markern][name]:remove() -- remove marker
		end

		-- add marker
		local obj = minetest.add_entity(pos, posn)
		if obj then
			obj:get_luaentity()._name = name
			if node_is_punchable then
				obj:set_properties({pointable = false})
			else
				local node_name = minetest.get_node(obj:get_pos()).name
				if (node_name):sub(1, 15) == "basic_machines:" then
					obj:set_properties({pointable = false})
				end
			end
			machines[markern][name] = obj
		end

		return obj
	end

	minetest.register_entity(":" .. posn, {
		initial_properties = {
			collisionbox = {-0.55, -0.55, -0.55, 0.55, 0.55, 0.55},
			visual = "cube",
			visual_size = {x = 1.1, y = 1.1},
			textures = {texturen, texturen, texturen,
				texturen, texturen, texturen},
			glow = 11,
			static_save = false,
			shaded = false
		},
		on_deactivate = function(self)
			machines[markern][self._name] = nil
		end,
		on_step = function(self, dtime)
			self._timer = self._timer + dtime
			if self._timer > delay then
				self.object:remove()
			end
		end,
		on_punch = function(self)
			minetest.after(0.1, function()
				if self and self.object then
					self.object:remove()
				end
			end)
		end,
		_name = "",
		_timer = 0
	})
end