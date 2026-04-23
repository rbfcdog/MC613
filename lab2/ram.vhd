LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ram IS
  PORT (
    clock    : IN STD_LOGIC;
    addr     : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
    data_in  : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
    wr_en    : IN STD_LOGIC;
    data_out : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
  );
END ram;

ARCHITECTURE behavioral OF ram IS
  CONSTANT MAP_W     : INTEGER := 16;
  CONSTANT MAP_H     : INTEGER := 16;
  CONSTANT MAP_SIZE  : INTEGER := MAP_W * MAP_H;
  CONSTANT TILE_BG   : INTEGER := 0;
  CONSTANT TILE_GRASS: INTEGER := 4;

  TYPE ram_array IS ARRAY (0 TO MAP_SIZE - 1) OF STD_LOGIC_VECTOR (7 DOWNTO 0);

  FUNCTION init_ram RETURN ram_array IS
    VARIABLE mem : ram_array := (OTHERS => (OTHERS => '0'));
    VARIABLE x   : INTEGER;
    VARIABLE y   : INTEGER;
    VARIABLE i   : INTEGER;
  BEGIN
    FOR y IN 0 TO MAP_H - 1 LOOP
      FOR x IN 0 TO MAP_W - 1 LOOP
        i := (y * MAP_W) + x;
        IF y >= 14 THEN
          mem(i) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_GRASS, 8));
        ELSE
          mem(i) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_BG, 8));
        END IF;
      END LOOP;
    END LOOP;
    RETURN mem;
  END FUNCTION;

  SIGNAL storage : ram_array := init_ram;
BEGIN
  PROCESS(clock)
  BEGIN
    IF (RISING_EDGE(clock)) THEN
      IF (wr_en = '1') THEN
        storage(TO_INTEGER(UNSIGNED(addr))) <= data_in;
      END IF;
    END IF;
  END PROCESS;

  data_out <= storage(TO_INTEGER(UNSIGNED(addr)));
END behavioral;
