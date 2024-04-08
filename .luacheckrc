globals = {
	"basic_machines"
}

read_globals = {
	"ItemStack",
	"default",
	"farming",
	"machines",
	"minetest",
	"player_monoids",
	"unified_inventory",
	"vector",
	table = {fields = {"copy"}}
}

files["ball.lua"] = {globals = {"boneworld.killxp"}}
files["grinder.lua"] = {read_globals = {"cg", "i3"}}
files["keypad.lua"] = {read_globals = {"signs_lib"}}
files["machines_configuration.lua"] = {max_line_length = 190}
files["mark.lua"] = {globals = {"machines"}}
files["mesecon_adapter.lua"] = {read_globals = {"mesecon"}}
files["mover.lua"] = {max_line_length = 290, read_globals = {"x_farming"}}
files["mover_dig_mode.lua"] = {max_line_length = 140, read_globals = {"bucket", "nodeupdate", "x_farming"}}
files["mover_inventory_mode.lua"] = {max_line_length = 130}
files["mover_normal_mode.lua"] = {max_line_length = 140}
files["mover_object_mode.lua"] = {max_line_length = 200, read_globals = {"bucket"}}
files["mover_transport_mode.lua"] = {max_line_length = 160}
files["protect.lua"] = {globals = {"minetest.is_protected"}, read_globals = {"beerchat"}}
files["technic_power.lua"] = {max_line_length = 140}