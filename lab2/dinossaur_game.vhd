library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dinossaur_game is
  port (
    CLOCK_50      : in  std_logic;
    VGA_SYNC_N    : out std_logic;
    VGA_BLANK_N   : out std_logic;
    VGA_HS        : out std_logic;
    VGA_VS        : out std_logic;
    VGA_R         : out std_logic_vector(7 downto 0);
    VGA_G         : out std_logic_vector(7 downto 0);
    VGA_B         : out std_logic_vector(7 downto 0);
    VGA_CLK       : out std_logic
  );
end entity;

architecture rtl of dinossaur_game is
  signal clk25   : std_logic;
  signal lock    : std_logic;

  signal pixel_x      : std_logic_vector(9 downto 0);
  signal pixel_y      : std_logic_vector(9 downto 0);
  signal video_active : std_logic;
  signal r_in         : std_logic_vector(7 downto 0);
  signal g_in         : std_logic_vector(7 downto 0);
  signal b_in         : std_logic_vector(7 downto 0);
  
  component pll is
		port (
			refclk   : in  std_logic := 'X'; -- clk
			rst      : in  std_logic := 'X'; -- reset
			outclk_0 : out std_logic;        -- clk
			locked   : out std_logic         -- export
		);
	end component pll;

  component VGA is
    port (
      pixel_clk    : IN  STD_LOGIC;
      reset_n      : IN  STD_LOGIC;
      r_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      g_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      b_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      pixel_x      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
      pixel_y      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
      video_active : OUT STD_LOGIC;
      VGA_R        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      VGA_G        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      VGA_B        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      VGA_HS       : OUT STD_LOGIC;
      VGA_VS       : OUT STD_LOGIC;
      VGA_BLANK_N  : OUT STD_LOGIC;
      VGA_SYNC_N   : OUT STD_LOGIC;
      VGA_CLK      : OUT STD_LOGIC
    );
  end component VGA;
	
begin
	clk : pll
	port map(
		refclk => CLOCK_50,
		rst => '0',
		outclk_0 => clk25,
		locked => lock	
	);

  r_in <= (others => '0');
  g_in <= (others => '0');
  b_in <= (others => '1');

  vga_inst : VGA
    port map(
      pixel_clk    => clk25,
      reset_n      => '1',
      r_in         => r_in,
      g_in         => g_in,
      b_in         => b_in,
      pixel_x      => pixel_x,
      pixel_y      => pixel_y,
      video_active => video_active,
      VGA_R        => VGA_R,
      VGA_G        => VGA_G,
      VGA_B        => VGA_B,
      VGA_HS       => VGA_HS,
      VGA_VS       => VGA_VS,
      VGA_BLANK_N  => VGA_BLANK_N,
      VGA_SYNC_N   => VGA_SYNC_N,
      VGA_CLK      => VGA_CLK
    );

end architecture;