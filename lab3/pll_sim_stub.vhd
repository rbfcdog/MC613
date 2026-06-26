library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- =============================================================================
--  Simulation-only stub for the Altera PLL.
--
--  The real pll.vhd is a Verilog/Altera megafunction that ghdl cannot
--  elaborate, so for ghdl simulation this entity is bound as work.pll.
--
--  IMPORTANT: the real PLL multiplies CLOCK_50 (50 MHz) up to ~143 MHz, which
--  is the clock the SDRAM controller and its CAS-latency / tAC read-capture
--  timing were tuned for. Simply forwarding the 50 MHz reference would HIDE
--  those tight timing relationships and let the test pass for the wrong reason.
--  This stub therefore synthesises its own ~143 MHz output clock and asserts
--  `locked` only after a short, realistic acquisition delay so the top level's
--  locked / reset-release path is actually exercised.
--
--  Synthesis always uses the real pll.vhd; this file is never synthesised.
-- =============================================================================
entity pll is
  port (
    refclk   : in  std_logic;
    rst      : in  std_logic;
    outclk_0 : out std_logic;
    locked   : out std_logic
  );
end pll;

architecture sim of pll is
  constant OUT_PERIOD : time := 7 ns;   -- ~142.857 MHz, the controller's design clock
  signal clk_int  : std_logic := '0';
  signal lock_int : std_logic := '0';
begin
  -- Free-running generated clock (a real PLL keeps clocking through lock
  -- acquisition). refclk is intentionally unused: the multiplied clock is not
  -- derivable from the reference by plain logic, so we model it directly.
  clk_gen : process
  begin
    wait for OUT_PERIOD / 2;
    clk_int <= not clk_int;
  end process;

  -- Lock asserts a few output cycles after power-up.
  lock_gen : process
  begin
    lock_int <= '0';
    wait for 20 * OUT_PERIOD;
    lock_int <= '1';
    wait;
  end process;

  outclk_0 <= clk_int;
  locked   <= lock_int;
end sim;
