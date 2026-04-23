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
    VGA_CLK       : out std_logic;
    KEY           : in  std_logic_vector(0 downto 0);
    SW            : in  std_logic_vector(9 downto 0);
    LEDR          : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of dinossaur_game is
  signal clk25   : std_logic;
  signal lock    : std_logic;

  signal pixel_x      : std_logic_vector(9 downto 0);
  signal pixel_y      : std_logic_vector(9 downto 0);
  signal video_active : std_logic;
  signal r_ppu        : std_logic_vector(7 downto 0);
  signal g_ppu        : std_logic_vector(7 downto 0);
  signal b_ppu        : std_logic_vector(7 downto 0);
  
  signal r_final      : std_logic_vector(7 downto 0);
  signal g_final      : std_logic_vector(7 downto 0);
  signal b_final      : std_logic_vector(7 downto 0);
  
  signal dino_x       : unsigned(9 downto 0);
  signal dino_y       : unsigned(9 downto 0);
  signal cactus_x     : unsigned(9 downto 0);
  signal cactus_y     : unsigned(9 downto 0);
  signal collision    : std_logic;
  signal game_over    : std_logic;
  
  signal reset_n      : std_logic;
  signal buttons      : std_logic_vector(3 downto 0);
  
  component pll is
		port (
			refclk   : in  std_logic := 'X';
			rst      : in  std_logic := 'X';
			outclk_0 : out std_logic;
			locked   : out std_logic
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

  component PPU is
    port (
      clk          : IN  STD_LOGIC;
      reset_n      : IN  STD_LOGIC;
      switches     : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
      buttons      : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
      pixel_x      : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
      pixel_y      : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
      video_active : IN  STD_LOGIC;
      r            : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      g            : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      b            : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
  end component PPU;

  component game_controller is
    port (
      clk          : IN  STD_LOGIC;
      reset_n      : IN  STD_LOGIC;
      KEY          : IN  STD_LOGIC_VECTOR(0 DOWNTO 0);
      dino_x       : OUT UNSIGNED(9 DOWNTO 0);
      dino_y       : OUT UNSIGNED(9 DOWNTO 0);
      cactus_x     : OUT UNSIGNED(9 DOWNTO 0);
      cactus_y     : OUT UNSIGNED(9 DOWNTO 0);
      collision    : OUT STD_LOGIC
    );
  end component game_controller;

  component sprite_renderer is
    port (
      clk          : IN  STD_LOGIC;
      pixel_x      : IN  UNSIGNED(9 DOWNTO 0);
      pixel_y      : IN  UNSIGNED(9 DOWNTO 0);
      dino_x       : IN  UNSIGNED(9 DOWNTO 0);
      dino_y       : IN  UNSIGNED(9 DOWNTO 0);
      cactus_x     : IN  UNSIGNED(9 DOWNTO 0);
      cactus_y     : IN  UNSIGNED(9 DOWNTO 0);
      r_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      g_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      b_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      r_out        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      g_out        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      b_out        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
  end component sprite_renderer;

begin
	clk : pll
	port map(
		refclk => CLOCK_50,
		rst => '0',
		outclk_0 => clk25,
		locked => lock	
	);

  reset_n <= lock;
  buttons <= (OTHERS => '0'); 

  ppu_inst : PPU
    port map(
      clk          => clk25,
      reset_n      => reset_n,
      switches     => SW,
      buttons      => buttons,
      pixel_x      => pixel_x,
      pixel_y      => pixel_y,
      video_active => video_active,
      r            => r_ppu,
      g            => g_ppu,
      b            => b_ppu
    );

  game_ctrl : game_controller
    port map(
      clk       => clk25,
      reset_n   => reset_n,
      KEY       => KEY,
      dino_x    => dino_x,
      dino_y    => dino_y,
      cactus_x  => cactus_x,
      cactus_y  => cactus_y,
      collision => collision
    );

  sprite_rend : sprite_renderer
    port map(
      clk     => clk25,
      pixel_x => UNSIGNED(pixel_x),
      pixel_y => UNSIGNED(pixel_y),
      dino_x  => dino_x,
      dino_y  => dino_y,
      cactus_x => cactus_x,
      cactus_y => cactus_y,
      r_in    => r_ppu,
      g_in    => g_ppu,
      b_in    => b_ppu,
      r_out   => r_final,
      g_out   => g_final,
      b_out   => b_final
    );

  vga_inst : VGA
    port map(
      pixel_clk    => clk25,
      reset_n      => reset_n,
      r_in         => r_final,
      g_in         => g_final,
      b_in         => b_final,
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

  PROCESS(clk25, reset_n)
    VARIABLE counter : INTEGER;
  BEGIN
    IF reset_n = '0' THEN
      game_over <= '0';
      counter := 0;
    ELSIF RISING_EDGE(clk25) THEN
      IF collision = '1' THEN
        game_over <= '1';
      END IF;
      
      counter := counter + 1;
      IF counter > 25000000 THEN
        counter := 0;
      END IF;
      
      IF game_over = '1' THEN
        IF counter > 12500000 THEN
          LEDR(9) <= '1';
        ELSE
          LEDR(9) <= '0';
        END IF;
      ELSE
        LEDR(9) <= '0';
      END IF;
    END IF;
  END PROCESS;

  LEDR(8 downto 0) <= (others => '0');

end architecture;