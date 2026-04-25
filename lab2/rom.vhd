LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY rom IS
  PORT (
    addr     : IN STD_LOGIC_VECTOR (12 DOWNTO 0);
    data_out : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
  );
END rom;

ARCHITECTURE behavioral OF rom IS
  CONSTANT TILE_W      : INTEGER := 8;
  CONSTANT TILE_H      : INTEGER := 8;
  CONSTANT TILE_BYTES  : INTEGER := TILE_H;
  CONSTANT TILE_COUNT  : INTEGER := 5;
  CONSTANT TILE_BASE   : INTEGER := 0;
  CONSTANT MAP_W       : INTEGER := 80;
  CONSTANT MAP_H       : INTEGER := 60;
  CONSTANT MAP_BASE    : INTEGER := TILE_BASE + (TILE_COUNT * TILE_BYTES);
  CONSTANT MAP_SIZE    : INTEGER := MAP_W * MAP_H;
  CONSTANT ROM_SIZE    : INTEGER := MAP_BASE + MAP_SIZE;

  TYPE rom_array IS ARRAY (0 TO ROM_SIZE - 1) OF STD_LOGIC_VECTOR (7 DOWNTO 0);

  FUNCTION init_rom RETURN rom_array IS
    VARIABLE mem : rom_array := (OTHERS => (OTHERS => '0'));
    VARIABLE row : INTEGER;
    VARIABLE idx : INTEGER;
    VARIABLE map_index : INTEGER;
    CONSTANT TILE_BG     : INTEGER := 0;
    CONSTANT TILE_CACTUS : INTEGER := 1;
    CONSTANT TILE_DINO   : INTEGER := 2;
    CONSTANT TILE_CLOUD  : INTEGER := 3;
    CONSTANT TILE_GRASS  : INTEGER := 4;
  BEGIN
    FOR row IN 1 TO 6 LOOP
      idx := TILE_BASE + (TILE_CACTUS * TILE_BYTES) + row;
      mem(idx) := "00111100";
    END LOOP;

    FOR row IN 1 TO 6 LOOP
      idx := TILE_BASE + (TILE_DINO * TILE_BYTES) + row;
      mem(idx) := "01111110";
    END LOOP;

    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 0;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 1;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 2;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 3;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 4;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 5;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 6;
    mem(idx) := "11111111";
    idx := TILE_BASE + (TILE_CLOUD * TILE_BYTES) + 7;
    mem(idx) := "11111111";

    FOR row IN 0 TO 7 LOOP
      idx := TILE_BASE + (TILE_GRASS * TILE_BYTES) + row;
      mem(idx) := "11111111";  
    END LOOP;

    FOR y IN 50 TO 59 LOOP
      FOR x IN 0 TO MAP_W - 1 LOOP
        map_index := MAP_BASE + (y * MAP_W) + x;
        mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_GRASS, 8));
      END LOOP;
    END LOOP;

    map_index := MAP_BASE + (10 * MAP_W) + 5;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (10 * MAP_W) + 6;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (9 * MAP_W) + 5;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (9 * MAP_W) + 6;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));

    map_index := MAP_BASE + (12 * MAP_W) + 35;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (12 * MAP_W) + 36;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (11 * MAP_W) + 35;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (11 * MAP_W) + 36;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));

    map_index := MAP_BASE + (8 * MAP_W) + 60;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (8 * MAP_W) + 61;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (7 * MAP_W) + 60;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));
    map_index := MAP_BASE + (7 * MAP_W) + 61;
    mem(map_index) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_CLOUD, 8));

    RETURN mem;
  END FUNCTION;

  SIGNAL storage : rom_array := init_rom;
  SIGNAL addr_i  : INTEGER RANGE 0 TO 8191;
BEGIN
  addr_i <= TO_INTEGER(UNSIGNED(addr));
  data_out <= storage(addr_i) WHEN addr_i < ROM_SIZE ELSE (OTHERS => '0');
END behavioral;