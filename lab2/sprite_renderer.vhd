LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY sprite_renderer IS
  PORT (
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
END sprite_renderer;

ARCHITECTURE behavioral OF sprite_renderer IS
  CONSTANT DINO_WIDTH   : INTEGER := 16;
  CONSTANT DINO_HEIGHT  : INTEGER := 20;
  CONSTANT CACTUS_WIDTH : INTEGER := 8;
  CONSTANT CACTUS_HEIGHT: INTEGER := 30;
  
BEGIN
  PROCESS(pixel_x, pixel_y, dino_x, dino_y, cactus_x, cactus_y, r_in, g_in, b_in)
    VARIABLE in_dino   : BOOLEAN;
    VARIABLE in_cactus : BOOLEAN;
  BEGIN
    r_out <= r_in;
    g_out <= g_in;
    b_out <= b_in;
    
    IF (pixel_x >= dino_x) AND (pixel_x < dino_x + DINO_WIDTH) AND
       (pixel_y >= dino_y) AND (pixel_y < dino_y + DINO_HEIGHT) THEN
      r_out <= x"FF";
      g_out <= x"DD";
      b_out <= x"00";
    ELSIF (pixel_x >= cactus_x) AND (pixel_x < cactus_x + CACTUS_WIDTH) AND
          (pixel_y >= cactus_y) AND (pixel_y < cactus_y + CACTUS_HEIGHT) THEN
      r_out <= x"BB";
      g_out <= x"66";
      b_out <= x"00";
    END IF;
    
  END PROCESS;
  
END behavioral;
