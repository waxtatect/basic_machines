-- rnd: code borrowed from machines, mark.lua
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

-- Needed for marking
machines = {}

for _, n in ipairs({"1", "11", "2", "N", "A"}) do
	local markern = "marker" .. n
	local posn = "machines:pos" .. n
	local texturen, delay

	if n == "N" then
		texturen = "machines_pos.png^[colorize:#ffd700"
		delay = 27
	elseif n == "A" then
		texturen = "machines_pos.png^[colorize:#008080"
		delay = 21
	else
		texturen = "machines_pos" .. n .. ".png"
		delay = 9
	end

	machines[markern] = {}

	machines["mark_pos" .. n] = function(name, pos)
		if machines[markern][name] then -- marker already exists
			machines[markern][name]:remove() -- remove marker
		end

		-- add marker
		machines[markern][name] = minetest.add_entity(pos, posn)
		if machines[markern][name] then
			machines[markern][name]:get_luaentity()._name = name
		end

		return machines[markern][name]
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
			physical = false,
			pointable = false,
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
				self.object:remove()
			end)
		end,
		_name = "",
		_timer = 0
	})
end