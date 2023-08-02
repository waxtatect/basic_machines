-- Make gravelsieve work with signals - can toggle on/off
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local STEP_DELAY = tonumber(minetest.settings:get("gravelsieve_step_delay")) or 1.0

local function enable_toggle_gravelsieve(name)
	local def = minetest.registered_nodes[name]
	if not def or def.effector or def.mesecons then return end -- we don't want to overwrite existing stuff!

	-- redefine item
	minetest.override_item(name, {
		effector = { -- action to toggle gravelsieve on/off
			action_on = function(pos, _)
				local timer = minetest.get_node_timer(pos)
				if not timer:is_started() then
					timer:start(STEP_DELAY)
				end
			end,

			action_off = function(pos, _)
				local timer = minetest.get_node_timer(pos)
				if timer:is_started() then
					timer:stop()
				end
			end
		}
	})
end

-- gravelsieves
local gravelsieves = { -- only automatic gravelsieve
	"gravelsieve:auto_sieve0",
	"gravelsieve:auto_sieve1",
	"gravelsieve:auto_sieve2",
	"gravelsieve:auto_sieve3",
	"gravelsieve:auto_sieve4"
}

for _, gravelsieve in ipairs(gravelsieves) do
	enable_toggle_gravelsieve(gravelsieve)
end