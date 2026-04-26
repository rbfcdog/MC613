library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sprite_renderer is
end entity;

architecture tb of tb_sprite_renderer is
    -- Sinais de Entrada
    signal clk          : std_logic := '0';
    signal pixel_x      : unsigned(9 downto 0) := (others => '0');
    signal pixel_y      : unsigned(9 downto 0) := (others => '0');
    signal dino_x       : unsigned(9 downto 0) := (others => '0');
    signal dino_y       : unsigned(9 downto 0) := (others => '0');
    signal cactus_x     : unsigned(9 downto 0) := (others => '0');
    signal cactus_y     : unsigned(9 downto 0) := (others => '0');
    
    -- Cor de fundo do cenário (vindo da PPU)
    signal r_in         : std_logic_vector(7 downto 0) := (others => '0');
    signal g_in         : std_logic_vector(7 downto 0) := (others => '0');
    signal b_in         : std_logic_vector(7 downto 0) := (others => '0');

    -- Sinais de Saída
    signal r_out        : std_logic_vector(7 downto 0);
    signal g_out        : std_logic_vector(7 downto 0);
    signal b_out        : std_logic_vector(7 downto 0);

    -- Controle de Simulação
    constant CLK_PERIOD : time := 39.72 ns; -- Clock de ~25.175 MHz do projeto original
    signal sim_done     : boolean := false;

begin
    -- Instanciando o DUT (Device Under Test)
    dut: entity work.sprite_renderer
    port map(
        clk          => clk,
        pixel_x      => pixel_x,
        pixel_y      => pixel_y,
        dino_x       => dino_x,
        dino_y       => dino_y,
        cactus_x     => cactus_x,
        cactus_y     => cactus_y,
        r_in         => r_in,
        g_in         => g_in,
        b_in         => b_in,
        r_out        => r_out,
        g_out        => g_out,
        b_out        => b_out
    );

    -- Gerador de Clock 
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
        -- 1. Inicializar posições fixas para os sprites e definir uma cor de fundo genérica
        dino_x   <= to_unsigned(200, 10);
        dino_y   <= to_unsigned(380, 10);
        
        cactus_x <= to_unsigned(400, 10);
        cactus_y <= to_unsigned(370, 10);
        
        -- Fundo cinza escuro para diferenciar facilmente no ModelSim
        r_in <= x"33";
        g_in <= x"33";
        b_in <= x"33";
        
        wait for CLK_PERIOD * 2;

        -- 2. Testar coordenada dentro do Dinossauro (Dino_W = 16, Dino_H = 20)
        -- Esperado na saída: r=FF, g=DD, b=00
        pixel_x <= to_unsigned(205, 10); -- Dentro da largura
        pixel_y <= to_unsigned(390, 10); -- Dentro da altura
        wait for CLK_PERIOD;

        -- 3. Testar coordenada exatamente na borda inferior direita do Dinossauro
        -- Esperado na saída: r=FF, g=DD, b=00
        pixel_x <= to_unsigned(215, 10); -- (200 + 16 - 1)
        pixel_y <= to_unsigned(399, 10); -- (380 + 20 - 1)
        wait for CLK_PERIOD;

        -- 4. Testar coordenada 1 pixel fora do limite direito do Dinossauro
        -- Esperado na saída: r=33, g=33, b=33 (Fundo)
        pixel_x <= to_unsigned(216, 10);
        pixel_y <= to_unsigned(390, 10);
        wait for CLK_PERIOD;

        -- 5. Testar coordenada dentro do Cacto (Cactus_W = 8, Cactus_H = 30)
        -- Esperado na saída: r=BB, g=66, b=00
        pixel_x <= to_unsigned(404, 10);
        pixel_y <= to_unsigned(385, 10);
        wait for CLK_PERIOD;

        -- 6. Testar coordenada 1 pixel fora do limite direito do Cacto
        -- Esperado na saída: r=33, g=33, b=33 (Fundo)
        -- Como cactus_x = 400 e CACTUS_WIDTH = 8, o cacto ocupa do X=400 até X=407.
        pixel_x <= to_unsigned(408, 10);
        pixel_y <= to_unsigned(385, 10);
        wait for CLK_PERIOD;

        -- Fim da simulação
        sim_done <= true;
        wait;
    end process;

end architecture tb;