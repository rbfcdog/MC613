LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY PPU IS
  PORT (
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
END PPU;

ARCHITECTURE rtl OF PPU IS
  CONSTANT TILE_W     : INTEGER := 8;
  CONSTANT TILE_H     : INTEGER := 8;
  CONSTANT TILE_BYTES : INTEGER := TILE_H;
  CONSTANT TILE_BASE  : INTEGER := 0;
  CONSTANT MAP_W      : INTEGER := 80;
  CONSTANT MAP_H      : INTEGER := 60;
  CONSTANT MAP_BASE   : INTEGER := 24;

  COMPONENT rom IS
    PORT (
      addr     : IN STD_LOGIC_VECTOR (12 DOWNTO 0);
      data_out : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
    );
  END COMPONENT;

  SIGNAL map_addr  : STD_LOGIC_VECTOR(12 DOWNTO 0);
  SIGNAL tile_addr : STD_LOGIC_VECTOR(12 DOWNTO 0);
  SIGNAL map_data  : STD_LOGIC_VECTOR(7 DOWNTO 0);
  SIGNAL tile_data : STD_LOGIC_VECTOR(7 DOWNTO 0);

  SIGNAL pixel_x_u : UNSIGNED(9 DOWNTO 0);
  SIGNAL pixel_y_u : UNSIGNED(9 DOWNTO 0);
BEGIN
  map_rom : rom
    PORT MAP(
      addr     => map_addr,
      data_out => map_data
    );

  tile_rom : rom
    PORT MAP(
      addr     => tile_addr,
      data_out => tile_data
    );

  pixel_x_u <= UNSIGNED(pixel_x);
  pixel_y_u <= UNSIGNED(pixel_y);

  PROCESS(pixel_x_u, pixel_y_u, video_active, map_data, tile_data)
    VARIABLE tile_x     : INTEGER;
    VARIABLE tile_y     : INTEGER;
    VARIABLE row        : INTEGER;
    VARIABLE col        : INTEGER;
    VARIABLE map_index  : INTEGER;
    VARIABLE tile_id    : INTEGER;
    VARIABLE tile_index : INTEGER;
    VARIABLE pixel_on   : STD_LOGIC;
  BEGIN
    tile_x := TO_INTEGER(pixel_x_u(9 DOWNTO 3));
    tile_y := TO_INTEGER(pixel_y_u(9 DOWNTO 3));
    row := TO_INTEGER(pixel_y_u(2 DOWNTO 0));
    col := TO_INTEGER(pixel_x_u(2 DOWNTO 0));

    map_index := MAP_BASE + (tile_y * MAP_W) + tile_x;
    map_addr <= STD_LOGIC_VECTOR(TO_UNSIGNED(map_index, 13));

    tile_id := TO_INTEGER(UNSIGNED(map_data));
    tile_index := TILE_BASE + (tile_id * TILE_BYTES) + row;
    tile_addr <= STD_LOGIC_VECTOR(TO_UNSIGNED(tile_index, 13));

    pixel_on := tile_data(7 - col);

    IF video_active = '0' THEN
      r <= (OTHERS => '0');
      g <= (OTHERS => '0');
      b <= (OTHERS => '0');
    ELSE
      IF pixel_on = '1' THEN
        IF tile_id = 1 THEN
          r <= x"00";
          g <= x"FF";
          b <= x"00";
        ELSIF tile_id = 2 THEN
          r <= x"00";
          g <= x"00";
          b <= x"00";
        ELSE
          r <= x"70";
          g <= x"C0";
          b <= x"FF";
        END IF;
      ELSE
        r <= x"70";
        g <= x"C0";
        b <= x"FF";
      END IF;
    END IF;
  END PROCESS;
END rtl;