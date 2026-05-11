library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library pll;

entity dram_top_level is
  port (
    CLOCK_50   : in    std_logic;
    SW         : in    std_logic_vector(9 downto 0);
    KEY        : in    std_logic_vector(3 downto 0);
    HEX0       : out   std_logic_vector(6 downto 0);
    HEX1       : out   std_logic_vector(6 downto 0);
    HEX2       : out   std_logic_vector(6 downto 0);
    HEX3       : out   std_logic_vector(6 downto 0);
    HEX4       : out   std_logic_vector(6 downto 0);
    HEX5       : out   std_logic_vector(6 downto 0);
    LEDR       : out   std_logic_vector(9 downto 0);
    DRAM_ADDR  : out   std_logic_vector(12 downto 0);
    DRAM_BA    : out   std_logic_vector(1 downto 0);
    DRAM_CAS_N : out   std_logic;
    DRAM_CKE   : out   std_logic;
    DRAM_CLK   : out   std_logic;
    DRAM_CS_N  : out   std_logic;
    DRAM_DQ    : inout std_logic_vector(15 downto 0);
    DRAM_LDQM  : out   std_logic;
    DRAM_RAS_N : out   std_logic;
    DRAM_UDQM  : out   std_logic;
    DRAM_WE_N  : out   std_logic
  );
end dram_top_level;

architecture rtl of dram_top_level is
  signal board_rst   : std_logic;
  signal rst         : std_logic;
  signal pll_clk     : std_logic;
  signal pll_locked  : std_logic;
  signal address     : std_logic_vector(25 downto 0);
  signal write_data  : std_logic_vector(7 downto 0);
  signal read_data   : std_logic_vector(7 downto 0);
  signal req         : std_logic;
  signal wEn         : std_logic;
  signal ready       : std_logic;
begin
  board_rst <= not KEY(0);
  rst       <= board_rst or not pll_locked;

  pll_i : entity pll.pll
    port map (
      refclk   => CLOCK_50,
      rst      => board_rst,
      outclk_0 => pll_clk,
      locked   => pll_locked
    );

  HEX2 <= (others => '1');
  HEX3 <= (others => '1');

  LEDR(0) <= req;
  LEDR(1) <= wEn;
  LEDR(2) <= ready;
  LEDR(9 downto 3) <= address(25 downto 19);

  iface_i : entity work.dram_iface
    port map (
      clk        => pll_clk,
      rst        => rst,
      SW         => SW,
      KEY        => KEY,
      HEX0       => HEX0,
      HEX1       => HEX1,
      HEX4       => HEX4,
      HEX5       => HEX5,
      address    => address,
      write_data => write_data,
      read_data  => read_data,
      req        => req,
      wEn        => wEn,
      ready      => ready
    );

  -- controller_i : entity work.dram_controller
  --   port map (
  --     clk         => pll_clk,
  --     rst         => rst,
  --     address     => address,
  --     write_data  => write_data,
  --     read_data   => read_data,
  --     req         => req,
  --     wEn         => wEn,
  --     ready       => ready,
  --     DRAM_ADDR   => DRAM_ADDR,
  --     DRAM_BA     => DRAM_BA,
  --     DRAM_CAS_N  => DRAM_CAS_N,
  --     DRAM_CKE    => DRAM_CKE,
  --     DRAM_CLK    => DRAM_CLK,
  --     DRAM_CS_N   => DRAM_CS_N,
  --     DRAM_DQ     => DRAM_DQ,
  --     DRAM_LDQM   => DRAM_LDQM,
  --     DRAM_RAS_N  => DRAM_RAS_N,
  --     DRAM_UDQM   => DRAM_UDQM,
  --     DRAM_WE_N   => DRAM_WE_N
  --   );
end rtl;
