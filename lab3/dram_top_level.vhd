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
    
    -- Physical SDRAM Pins
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
  
  -- Internal routing signals
  signal iface_address       : std_logic_vector(25 downto 0);
  signal iface_write_data    : std_logic_vector(7 downto 0);
  signal controller_data_out : std_logic_vector(7 downto 0);
  signal req_sig             : std_logic;
  signal wen_sig             : std_logic;
  signal ready_sig           : std_logic;
  
  -- The 26-bit vector from the controller containing CMD + Address
  signal dram_cmd            : std_logic_vector(25 downto 0);

  -- We declare the component specifically to fix the port directions
  -- so that the compiler doesn't throw errors when wiring them up.
  component dram_controller is
    port(
        clk      : in  std_logic;
        rst      : in  std_logic;
        SW       : in  std_logic_vector(9 downto 0);
        KEY      : in  std_logic_vector(3 downto 0);
        data_in  : in  std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0);
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX4     : out std_logic_vector(6 downto 0);
        HEX5     : out std_logic_vector(6 downto 0);
        adress   : out std_logic_vector(25 downto 0);
        
        -- These MUST be inputs from the user interface
        req      : in  std_logic;
        wEn      : in  std_logic;
        
        -- Missing in original entity but required to pass user's address
        -- into the controller so it can combine it with the command
        addr_in  : in  std_logic_vector(25 downto 0);
        ready    : out std_logic
    );
  end component;

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

  LEDR(0) <= req_sig;
  LEDR(1) <= wen_sig;
  LEDR(2) <= ready_sig;
  LEDR(9 downto 3) <= iface_address(25 downto 19);

  DRAM_ADDR   <= dram_cmd(12 downto 0);
  DRAM_BA     <= dram_cmd(14 downto 13);
  DRAM_WE_N   <= dram_cmd(15);
  DRAM_CAS_N  <= dram_cmd(16);
  DRAM_RAS_N  <= dram_cmd(17);
  DRAM_CS_N   <= dram_cmd(18);
  
  -- Static SDRAM controls
  DRAM_CKE    <= '1';         -- Clock Enable always high
  DRAM_CLK    <= pll_clk;     -- Sync to PLL
  DRAM_UDQM   <= '0';         -- Unmask upper byte
  DRAM_LDQM   <= '0';         -- Unmask lower byte

  -- Tri-state logic for Bidirectional DQ bus: 
  -- We ONLY drive data onto DRAM_DQ during a WRITE command (CS=0, RAS=1, CAS=0, WE=0)
  DRAM_DQ <= (x"00" & iface_write_data) when (dram_cmd(18) = '0' and dram_cmd(17) = '1' and dram_cmd(16) = '0' and dram_cmd(15) = '0') else (others => 'Z');


  iface_i : entity work.dram_iface
    port map (
      clk        => pll_clk,
      rst        => rst,
      SW         => SW,
      KEY        => KEY,
      HEX0       => HEX0,     -- Interface directly drives displays
      HEX1       => HEX1,
      HEX4       => HEX4,
      HEX5       => HEX5,
      address    => iface_address,
      write_data => iface_write_data,
      read_data  => controller_data_out,
      req        => req_sig,
      wEn        => wen_sig,
      ready      => ready_sig
    );

  controller_i : dram_controller
    port map (
      clk         => pll_clk,
      rst         => rst,
      SW          => SW,
      KEY         => KEY,
      data_in     => DRAM_DQ(7 downto 0),  -- Read data straight from physical pins
      data_out    => controller_data_out,  -- Latched data goes to iface
      
      -- Leave HEX ports open to prevent multiple-driver compilation errors
      HEX0        => open,
      HEX1        => open,
      HEX4        => open,
      HEX5        => open,
      
      adress      => dram_cmd,             -- Outputs the merged command + address
      addr_in     => iface_address,        -- Receives the target address from interface
      req         => req_sig,
      wEn         => wen_sig,
      ready       => ready_sig
    );

end rtl;