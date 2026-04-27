library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_game_controller is
end entity;

architecture tb of tb_game_controller is
    -- Entradas de Controle
    signal clk          : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal KEY          : std_logic_vector(0 downto 0) := "1";

    -- Saídas do Controller
    signal dino_x       : unsigned(9 downto 0);
    signal dino_y       : unsigned(9 downto 0);
    signal cactus_x     : unsigned(9 downto 0);
    signal cactus_y     : unsigned(9 downto 0);
    signal collision    : std_logic;

    -- Controle de Simulação
    constant CLK_PERIOD : time := 39.72 ns; -- Clock de ~25.175 MHz baseado no tb_VGA
    constant FRAME_CYCLES : integer := 600000; -- Referente à constante FRAME_DIVISOR do controller
    signal sim_done     : boolean := false;

begin
    -- Instanciando o DUT (Device Under Test)
    dut: entity work.game_controller
    port map(
        clk          => clk,
        reset_n      => reset_n,
        KEY          => KEY,
        dino_x       => dino_x,
        dino_y       => dino_y,
        cactus_x     => cactus_x,
        cactus_y     => cactus_y,
        collision    => collision
    );

    -- Gerador de Clock (idêntico ao modelo do tb_VGA)
    clk_gen: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Processo de Estímulos
    stim: process
    begin
        -- 1. Aplicar Reset
        reset_n <= '0';
        KEY(0) <= '1';
        wait for CLK_PERIOD * 10;

        -- Liberar o Reset (Posições devem inicializar: dino=200x380, cacto=640x370)
        reset_n <= '1';
        wait for CLK_PERIOD * 10;

        -- 2. Simular pulo do dinossauro
        -- O controller detecta o pulo na borda de descida de KEY(0)
        KEY(0) <= '0';
        wait for CLK_PERIOD * 5; -- Mantém pressionado por alguns ciclos
        KEY(0) <= '1';

        wait for CLK_PERIOD * FRAME_CYCLES * 20;
        -- confere se ele não tem bugs se gerar 2 estimulos um atrás do outro
        KEY(0) <= '0';
        wait for CLK_PERIOD * 5; -- Mantém pressionado por alguns ciclos
        KEY(0) <= '1';

        -- 3. Observar a dinâmica ao longo do tempo
        -- Como FRAME_DIVISOR = 600000, aguardamos múltiplos de FRAME_CYCLES
        -- para observar os ciclos de atualização (gravidade, movimento e colisão).
        -- 80 frames garantem tempo suficiente para o pulo completo e colisão.
        wait for CLK_PERIOD * FRAME_CYCLES * 60;

        -- 4. Simular Reset/Restart após o Game Over
        -- Pressionar novamente deve fazer o game_state voltar a '0'
        KEY(0) <= '0';
        wait for CLK_PERIOD * 5;
        KEY(0) <= '1';
        
        -- Aguarda mais alguns frames para garantir que reiniciou
        wait for CLK_PERIOD * FRAME_CYCLES * 5;

        -- Fim da simulação
        sim_done <= true;
        wait;
    end process;

end architecture tb;