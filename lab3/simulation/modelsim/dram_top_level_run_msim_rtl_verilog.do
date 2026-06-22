transcript on
if ![file isdirectory dram_top_level_iputf_libs] {
	file mkdir dram_top_level_iputf_libs
}

if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

###### Libraries for IPUTF cores 
###### End libraries for IPUTF cores 
###### MIF file copy and HDL compilation commands for IPUTF cores 


vcom "/home/rodrigodog/MC613/lab3/pll_sim/pll.vho"

vcom -93 -work work {/home/rodrigodog/MC613/lab3/dram_iface.vhd}
vcom -93 -work work {/home/rodrigodog/MC613/lab3/reader.vhd}
vcom -93 -work work {/home/rodrigodog/MC613/lab3/dram_top_level.vhd}
vcom -93 -work work {/home/rodrigodog/MC613/lab3/dram_controller.vhd}

vcom -93 -work work {/home/rodrigodog/MC613/lab3/dram_iface.vhd}
vcom -93 -work work {/home/rodrigodog/MC613/lab3/tb_dram_iface.vhd}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work -L work -voptargs="+acc"  tb_dram_iface

add wave *
view structure
view signals
run -all
