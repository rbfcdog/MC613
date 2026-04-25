LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Testbench para o game_controller
ENTITY tb_game_controller IS
END tb_game_controller;

ARCHITECTURE test OF tb_game_controller IS
  SIGNAL clk          : STD_LOGIC := '0';
  SIGNAL reset_n      : STD_LOGIC := '0';
  SIGNAL KEY          : STD_LOGIC_VECTOR(0 DOWNTO 0) := (OTHERS => '1');
  SIGNAL dino_x       : UNSIGNED(9 DOWNTO 0);
  SIGNAL dino_y       : UNSIGNED(9 DOWNTO 0);
  SIGNAL cactus_x     : UNSIGNED(9 DOWNTO 0);
  SIGNAL cactus_y     : UNSIGNED(9 DOWNTO 0);
  SIGNAL collision    : STD_LOGIC;

  COMPONENT game_controller IS
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
  END COMPONENT;

  -- Clock de 50 MHz (20ns period)
  CONSTANT CLK_PERIOD : TIME := 20 ns;

BEGIN
  -- Instanciar o módulo a testar
  uut : game_controller
    PORT MAP(
      clk       => clk,
      reset_n   => reset_n,
      KEY       => KEY,
      dino_x    => dino_x,
      dino_y    => dino_y,
      cactus_x  => cactus_x,
      cactus_y  => cactus_y,
      collision => collision
    );

  -- Gerador de clock
  PROCESS
  BEGIN
    clk <= '0';
    WAIT FOR CLK_PERIOD / 2;
    clk <= '1';
    WAIT FOR CLK_PERIOD / 2;
  END PROCESS;

  -- Estímulos de teste
  PROCESS
  BEGIN
    -- Inicialização
    reset_n <= '0';
    KEY <= (OTHERS => '1');
    WAIT FOR 100 ns;

    -- Liberar reset
    reset_n <= '1';
    WAIT FOR 100 ns;

    REPORT "=== Teste 1: Posição Inicial ===" SEVERITY NOTE;
    REPORT "Dinossauro X: " & INTEGER'IMAGE(TO_INTEGER(dino_x)) SEVERITY NOTE;
    REPORT "Dinossauro Y: " & INTEGER'IMAGE(TO_INTEGER(dino_y)) SEVERITY NOTE;
    REPORT "Cacto X: " & INTEGER'IMAGE(TO_INTEGER(cactus_x)) SEVERITY NOTE;
    REPORT "Cacto Y: " & INTEGER'IMAGE(TO_INTEGER(cactus_y)) SEVERITY NOTE;

    WAIT FOR 1 us;

    -- Teste 2: Simular pulo (borda de descida em KEY[0])
    REPORT "=== Teste 2: Acionando Pulo (Debounce) ===" SEVERITY NOTE;
    KEY(0) <= '0';  -- Pressionar botão (borda de descida)
    WAIT FOR CLK_PERIOD;
    KEY(0) <= '1';  -- Soltar botão
    WAIT FOR 5 us;

    REPORT "Após pulo - Dinossauro Y: " & INTEGER'IMAGE(TO_INTEGER(dino_y)) SEVERITY NOTE;

    -- Aguardar o dinossauro cair e voltar ao chão
    WAIT FOR 50 us;

    REPORT "Após queda - Dinossauro Y: " & INTEGER'IMAGE(TO_INTEGER(dino_y)) SEVERITY NOTE;

    -- Teste 3: Simular colisão (posicionar cacto próximo)
    REPORT "=== Teste 3: Observando Movimento do Cacto ===" SEVERITY NOTE;
    WAIT FOR 100 us;

    REPORT "Cacto X após tempo: " & INTEGER'IMAGE(TO_INTEGER(cactus_x)) SEVERITY NOTE;
    REPORT "Colisão Detectada: " & STD_LOGIC'IMAGE(collision) SEVERITY NOTE;

    WAIT FOR 100 us;

    REPORT "=== Teste Finalizado ===" SEVERITY NOTE;
    WAIT;
  END PROCESS;

END test;
