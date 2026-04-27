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
  CONSTANT TILE_H         : INTEGER := 8;
  CONSTANT TILE_BYTES     : INTEGER := TILE_H;
  CONSTANT TILE_BASE      : INTEGER := 0;
  CONSTANT GROUND_PIXEL_Y : INTEGER := 400;

  COMPONENT rom IS
    PORT (
      addr     : IN STD_LOGIC_VECTOR (12 DOWNTO 0);
      data_out : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
    );
  END COMPONENT;

  SIGNAL tile_addr : STD_LOGIC_VECTOR(12 DOWNTO 0);
  SIGNAL tile_data : STD_LOGIC_VECTOR(7 DOWNTO 0);
  SIGNAL pixel_x_u : UNSIGNED(9 DOWNTO 0);
  SIGNAL pixel_y_u : UNSIGNED(9 DOWNTO 0);

BEGIN
  -- ROM contains the 8x8 bitmap patterns for tiles
  tile_rom : rom
    PORT MAP(
      addr     => tile_addr,
      data_out => tile_data
    );

  pixel_x_u <= UNSIGNED(pixel_x);
  pixel_y_u <= UNSIGNED(pixel_y);

  PROCESS(pixel_x_u, pixel_y_u, video_active, tile_data)
    VARIABLE tile_x_raw : INTEGER;
    VARIABLE tile_y_raw : INTEGER;
    VARIABLE row        : INTEGER;
    VARIABLE col        : INTEGER;
    VARIABLE tile_id    : INTEGER;
    VARIABLE tile_index : INTEGER;
    VARIABLE pixel_on   : STD_LOGIC;
  BEGIN
    -- 1. Calculate Grid Positions (Each tile is 8x8 pixels)
    -- Using bits 9 downto 3 effectively divides coordinate by 8
    tile_x_raw := TO_INTEGER(pixel_x_u(9 DOWNTO 3)); 
    tile_y_raw := TO_INTEGER(pixel_y_u(9 DOWNTO 3)); 
    row := TO_INTEGER(pixel_y_u(2 DOWNTO 0));        -- Scanline within the 8x8 tile
    col := TO_INTEGER(pixel_x_u(2 DOWNTO 0));        -- Pixel within the 8x8 tile row

    -- 2. BACKGROUND TILE SELECTION LOGIC
    -- Hardcoded map logic (replaces the old RAM-based tilemap)
    IF ((tile_y_raw = 9 OR tile_y_raw = 10) AND (tile_x_raw = 5 OR tile_x_raw = 6)) OR     -- Cloud 1
       ((tile_y_raw = 11 OR tile_y_raw = 12) AND (tile_x_raw = 35 OR tile_x_raw = 36)) OR  -- Cloud 2
       ((tile_y_raw = 7 OR tile_y_raw = 8) AND (tile_x_raw = 60 OR tile_x_raw = 61)) THEN  -- Cloud 3
        tile_id := 3; -- Cloud
    ELSIF tile_y_raw >= 50 AND tile_y_raw <= 59 THEN
        tile_id := 4; -- Grass
    ELSE
        tile_id := 0; -- Empty Sky
    END IF;

    -- 3. ROM Addressing logic
    tile_index := TILE_BASE + (tile_id * TILE_BYTES) + row;
    tile_addr <= STD_LOGIC_VECTOR(TO_UNSIGNED(tile_index, 13));

    -- Determine if the specific pixel in the current tile row is active
    pixel_on := tile_data(7 - col);

    -- 4. Color Generation (Output to Sprite Renderer)
    IF video_active = '0' THEN
      r <= (OTHERS => '0');
      g <= (OTHERS => '0');
      b <= (OTHERS => '0');
    ELSE
      -- Draw solid Ground at the bottom
      IF pixel_y_u >= TO_UNSIGNED(GROUND_PIXEL_Y, 10) THEN
        r <= x"20"; g <= x"A0"; b <= x"20";
      
      -- If pixel within a tile is 'on', use specific tile colors
      ELSIF pixel_on = '1' THEN
        CASE tile_id IS
          WHEN 3 =>      -- Cloud (White)
            r <= x"FF"; g <= x"FF"; b <= x"FF";
          WHEN 4 =>      -- Grass (Greenish)
            r <= x"20"; g <= x"A0"; b <= x"20";
          WHEN OTHERS => -- Default Sky
            r <= x"70"; g <= x"C0"; b <= x"FF";
        END CASE;
      ELSE
        -- Default Sky Background
        r <= x"70"; g <= x"C0"; b <= x"FF";
      END IF;
    END IF;
  END PROCESS;
END rtl;