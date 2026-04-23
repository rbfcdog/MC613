LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY game_controller IS
  PORT (
    clk          : IN  STD_LOGIC;
    reset_n      : IN  STD_LOGIC;
    KEY          : IN  STD_LOGIC_VECTOR(0 DOWNTO 0);
    dino_x       : OUT UNSIGNED(9 DOWNTO 0);
    dino_y       : OUT UNSIGNED(9 DOWNTO 0);
    cactus_x     : OUT UNSIGNED(9 DOWNTO 0);
    cactus_y     : OUT UNSIGNED(9 DOWNTO 0);
    collision    : OUT STD_LOGIC
  );
END game_controller;

ARCHITECTURE behavioral OF game_controller IS
  CONSTANT DINO_START_X  : INTEGER := 200;
  CONSTANT DINO_START_Y  : INTEGER := 380;
  CONSTANT DINO_WIDTH    : INTEGER := 16;
  CONSTANT DINO_HEIGHT   : INTEGER := 20;
  CONSTANT CACTUS_WIDTH  : INTEGER := 8;
  CONSTANT CACTUS_HEIGHT : INTEGER := 30;
  CONSTANT GROUND_Y      : INTEGER := 380;
  CONSTANT JUMP_SPEED    : INTEGER := 15;
  CONSTANT GRAVITY       : INTEGER := 1;
  CONSTANT MAX_FALL_SPEED: INTEGER := 20;
  
  SIGNAL dino_x_reg      : UNSIGNED(9 DOWNTO 0);
  SIGNAL dino_y_reg      : UNSIGNED(9 DOWNTO 0);
  SIGNAL dino_vy         : SIGNED(10 DOWNTO 0);
  SIGNAL is_jumping      : STD_LOGIC;
  
  SIGNAL cactus_x_reg    : UNSIGNED(9 DOWNTO 0);
  SIGNAL cactus_y_reg    : UNSIGNED(9 DOWNTO 0);
  SIGNAL cactus_speed    : INTEGER;
  
  SIGNAL frame_counter   : INTEGER;
  CONSTANT FRAME_DIVISOR : INTEGER := 600000;
  
  SIGNAL key_0_prev      : STD_LOGIC;
  SIGNAL pulse_jump      : STD_LOGIC;
  SIGNAL game_state      : STD_LOGIC;
  SIGNAL is_colliding    : STD_LOGIC;
  
BEGIN
  PROCESS(clk, reset_n)
  BEGIN
    IF reset_n = '0' THEN
      dino_x_reg <= TO_UNSIGNED(DINO_START_X, 10);
      dino_y_reg <= TO_UNSIGNED(DINO_START_Y, 10);
      dino_vy <= (OTHERS => '0');
      is_jumping <= '0';
      cactus_x_reg <= TO_UNSIGNED(640, 10);
      cactus_y_reg <= TO_UNSIGNED(370, 10);
      key_0_prev <= '1';
      frame_counter <= 0;
      game_state <= '0';
      
    ELSIF RISING_EDGE(clk) THEN
      IF key_0_prev = '1' AND KEY(0) = '0' THEN
        pulse_jump <= '1';
      ELSE
        pulse_jump <= '0';
      END IF;
      key_0_prev <= KEY(0);
      
      IF game_state = '1' THEN
        IF pulse_jump = '1' THEN
          game_state <= '0';
          dino_y_reg <= TO_UNSIGNED(DINO_START_Y, 10);
          dino_vy <= (OTHERS => '0');
          is_jumping <= '0';
          cactus_x_reg <= TO_UNSIGNED(640, 10);
        END IF;
        
      ELSE
        IF is_colliding = '1' THEN
          game_state <= '1';
        END IF;

      IF frame_counter < FRAME_DIVISOR THEN
        frame_counter <= frame_counter + 1;
        
        IF pulse_jump = '1' AND is_jumping = '0' THEN
          is_jumping <= '1';
          dino_vy <= TO_SIGNED(-JUMP_SPEED, 11);
          dino_y_reg <= TO_UNSIGNED(GROUND_Y - 1, 10);
        END IF;
        
      ELSE
        frame_counter <= 0;
        
        IF pulse_jump = '1' AND is_jumping = '0' THEN
          is_jumping <= '1';
          dino_vy <= TO_SIGNED(-JUMP_SPEED, 11);
          dino_y_reg <= TO_UNSIGNED(GROUND_Y - 1, 10);
          
        ELSIF is_jumping = '1' OR dino_y_reg < GROUND_Y THEN
          IF dino_vy + TO_SIGNED(GRAVITY, 11) > TO_SIGNED(MAX_FALL_SPEED, 11) THEN
            dino_vy <= TO_SIGNED(MAX_FALL_SPEED, 11);
          ELSE
            dino_vy <= dino_vy + TO_SIGNED(GRAVITY, 11);
          END IF;
          
          IF SIGNED(dino_y_reg(9 DOWNTO 0)) + dino_vy >= TO_SIGNED(GROUND_Y, 11) THEN
            dino_y_reg <= TO_UNSIGNED(GROUND_Y, 10);
            dino_vy <= (OTHERS => '0');
            is_jumping <= '0';
          ELSE
            dino_y_reg <= UNSIGNED(SIGNED(dino_y_reg(9 DOWNTO 0)) + dino_vy(9 DOWNTO 0));
          END IF;
        ELSE
           dino_y_reg <= TO_UNSIGNED(GROUND_Y, 10);
           dino_vy <= (OTHERS => '0');
           is_jumping <= '0';
        END IF;

        IF cactus_x_reg > TO_UNSIGNED(6, 10) THEN
          cactus_x_reg <= cactus_x_reg - 6;
        ELSE
          cactus_x_reg <= TO_UNSIGNED(640, 10);
        END IF;
        
      END IF;
      END IF;
    END IF;
  END PROCESS;
  
  is_colliding <= '1' WHEN (
    (dino_x_reg + DINO_WIDTH > cactus_x_reg) AND
    (dino_x_reg < cactus_x_reg + CACTUS_WIDTH) AND
    (dino_y_reg + DINO_HEIGHT > cactus_y_reg) AND
    (dino_y_reg < cactus_y_reg + CACTUS_HEIGHT)
  ) ELSE '0';
  
  collision <= game_state;
  
  dino_x <= dino_x_reg;
  dino_y <= dino_y_reg;
  cactus_x <= cactus_x_reg;
  cactus_y <= cactus_y_reg;
  
END behavioral;
