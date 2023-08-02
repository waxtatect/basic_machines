-- basic_machines: lightweight automation mod for minetest
-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
--[[
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
--]]

-- load files
local MP = minetest.get_modpath("basic_machines") .. "/"

dofile(MP .. "common.lua")					-- basic_machines global table, settings and functions

dofile(MP .. "autocrafter.lua")				-- borrowed and adapted from pipeworks mod
dofile(MP .. "ball.lua")					-- interactive flying ball, can activate blocks or be used as a weapon
dofile(MP .. "clockgen.lua")				-- periodically activates machine on top of it
dofile(MP .. "constructor.lua")				-- enable machines constructor
dofile(MP .. "detector.lua")				-- detect block/player/object and activate machine
dofile(MP .. "distributor.lua")				-- forward signal to targets
dofile(MP .. "enviro.lua")					-- change surrounding environment physics
dofile(MP .. "grinder.lua")					-- grind materials into dusts
dofile(MP .. "keypad.lua")					-- activate machine by sending signal
dofile(MP .. "light.lua")					-- light on/off
dofile(MP .. "machines_configuration.lua")	-- depends on mover, distributor, keypad and detector
dofile(MP .. "mark.lua")					-- used for markings
dofile(MP .. "mover.lua")					-- universal digging/harvesting/teleporting/transporting machine
dofile(MP .. "protect.lua")					-- enable interaction with players, adds local on protect/chat event handling
dofile(MP .. "recycler.lua")				-- recycle old used tools
dofile(MP .. "technic_power.lua")			-- technic power: battery, generator

-- MESECON functionality
if minetest.global_exists("mesecon") then
	dofile(MP .. "mesecon_adapter.lua")
end

-- GRAVELSIEVE compatibility
if minetest.global_exists("gravelsieve") then
	dofile(MP .. "control_gravelsieve.lua")
end

-- SPACE
if basic_machines.settings.space_start then
	dofile(MP .. "space.lua")				-- change global physics (skybox, gravity, damage mechanism...)
end

-- OPTIONAL content
dofile(MP .. "crafts.lua")					-- additional craft recipes
dofile(MP .. "control_doors.lua")			-- if you want open/close doors/trapdoors with signal,
											-- also walk through trapdoors, steel doors/trapdoors are made impervious to dig through,
											-- removal by repeated punches
dofile(MP .. "control_lights.lua")			-- ability to toggle light for other light blocks

print("[MOD] basic_machines " .. basic_machines.version .. " loaded.")