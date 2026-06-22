# ============================================================================
#  Timing constraints for the DRAM controller (DE1-SoC, IS42S16320D-7)
#
#  The SDRAM is clocked by DRAM_CLK = (not pll_clk), so DRAM_CLK is an INVERTED
#  copy of the 143 MHz PLL system clock, forwarded to the pin. Without these
#  constraints Quartus leaves the bidirectional DRAM_DQ read-capture path
#  unconstrained, places the capture register in random fabric, and the
#  controller samples DQ while it is in high-impedance -> every read is 0xFF.
# ============================================================================

# --- Board reference clock ---
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# --- PLL output (143 MHz system clock) ---
derive_pll_clocks
derive_clock_uncertainty

# Node that drives the system clock (Cyclone V "Altera PLL" output counter 0).
# Hierarchy: top "pll_i" -> "pll_inst" (pll_0002) -> "altera_pll_i".
# If Quartus reports this source pin as not found, open Tools > Timing Analyzer,
# run "report_clocks", copy the real PLL output node name, and paste it here.
set PLL_OUT {pll_i|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

# --- Forwarded SDRAM clock: inverted copy of the system clock on the pin ---
create_generated_clock -name DRAM_CLK \
    -source [get_pins $PLL_OUT] -invert [get_ports {DRAM_CLK}]

# ----------------------------------------------------------------------------
#  SDRAM read path (SDRAM -> FPGA): data on DRAM_DQ is launched by the SDRAM
#  relative to DRAM_CLK. tAC(max) ~ 5.4 ns, tOH(min) ~ 2.5 ns for the -7 part,
#  plus a little board flight time. These let Quartus pull the DQ capture
#  register into the I/O cell and time it against the system clock.
# ----------------------------------------------------------------------------
set_input_delay -clock DRAM_CLK -max 5.9 [get_ports {DRAM_DQ[*]}]
set_input_delay -clock DRAM_CLK -min 3.0 [get_ports {DRAM_DQ[*]}]

# ----------------------------------------------------------------------------
#  SDRAM write/command path (FPGA -> SDRAM): must meet the SDRAM's setup/hold
#  with respect to DRAM_CLK.
# ----------------------------------------------------------------------------
set SDRAM_OUTS [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CKE DRAM_CS_N \
                           DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_DQ[*] \
                           DRAM_LDQM DRAM_UDQM}]
set_output_delay -clock DRAM_CLK -max 1.6  $SDRAM_OUTS
set_output_delay -clock DRAM_CLK -min -0.9 $SDRAM_OUTS

# ----------------------------------------------------------------------------
#  Non-timing-critical I/O: switches/keys are asynchronous, displays are human
#  speed. Cutting them keeps the timing report focused on the SDRAM.
# ----------------------------------------------------------------------------
set_false_path -from [get_ports {SW[*] KEY[*]}] -to [all_registers]
set_false_path -from * -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
