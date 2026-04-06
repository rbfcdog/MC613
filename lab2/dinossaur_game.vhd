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
    VGA_B         : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of dinossaur_game is
  signal clk25   : std_logic := '0';

  signal h_count : integer range 0 to 799 := 0;
  signal v_count : integer range 0 to 524 := 0;

  signal visible : std_logic;

begin
  process(CLOCK_50)
  begin
    if rising_edge(CLOCK_50) then
      clk25 <= not clk25;
    end if;
  end process;

  process(clk25)
  begin
    if rising_edge(clk25) then
      if h_count = 799 then
        h_count <= 0;
        if v_count = 524 then
          v_count <= 0;
        else
          v_count <= v_count + 1;
        end if;
      else
        h_count <= h_count + 1;
      end if;
    end if;
  end process;

  visible <= '1' when (h_count < 640 and v_count < 480) else '0';

  VGA_HS <= '0' when (h_count >= 656 and h_count < 752) else '1';
  VGA_VS <= '0' when (v_count >= 490 and v_count < 492) else '1';

  VGA_SYNC_N  <= '1';
  VGA_BLANK_N <= '0'; 

  VGA_R <= (others => '0');
  VGA_G <= (others => '0');
  VGA_B <= (others => '1') when visible = '1' else (others => '0');

end architecture;