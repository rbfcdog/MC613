transcript on
if ![file isdirectory dinossaur_game_iputf_libs] {
	file mkdir dinossaur_game_iputf_libs
}

if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

###### Libraries for IPUTF cores 
###### End libraries for IPUTF cores 
###### MIF file copy and HDL compilation commands for IPUTF cores 


vcom "/home/estrela/Documents/MC613/lab2/pll_sim/pll.vho"

vcom -93 -work work {/home/estrela/Documents/MC613/lab2/sprite_renderer.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/ram.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/game_controller.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/PPU.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/VGA.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/dinossaur_game.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/rom.vhd}

vcom -93 -work work {/home/estrela/Documents/MC613/lab2/PPU.vhd}
vcom -93 -work work {/home/estrela/Documents/MC613/lab2/tb_PPU.vhd}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L cyclonev -L rtl_work -L work -voptargs="+acc"  tb_PPU

add wave *
view structure
view signals
run -all
