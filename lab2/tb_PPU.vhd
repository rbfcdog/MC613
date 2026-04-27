library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_PPU is
end entity;

architecture tb of tb_PPU is
    -- Sinais de Entrada
    signal clk          : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal switches     : std_logic_vector(9 downto 0) := (others => '0');
    signal buttons      : std_logic_vector(3 downto 0) := (others => '1');
    signal pixel_x      : std_logic_vector(9 downto 0) := (others => '0');
    signal pixel_y      : std_logic_vector(9 downto 0) := (others => '0');
    signal video_active : std_logic := '0';

    -- Sinais de Saída
    signal r            : std_logic_vector(7 downto 0);
    signal g            : std_logic_vector(7 downto 0);
    signal b            : std_logic_vector(7 downto 0);

    -- Controle de Simulação
    constant CLK_PERIOD : time := 39.72 ns; -- Clock de ~25.175 MHz da VGA
    signal sim_done     : boolean := false;

begin
    -- Instanciando o DUT (Device Under Test)
    dut: entity work.PPU
    port map(
        clk          => clk,
        reset_n      => reset_n,
        switches     => switches,
        buttons      => buttons,
        pixel_x      => pixel_x,
        pixel_y      => pixel_y,
        video_active => video_active,
        r            => r,
        g            => g,
        b            => b
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
        -- 1. Reset
        reset_n <= '0';
        wait for CLK_PERIOD * 2;
        reset_n <= '1';
        wait for CLK_PERIOD * 2;

        -- 2. Testar fora da área visível do monitor (Blanking region)
        video_active <= '0';
        pixel_x <= std_logic_vector(to_unsigned(800, 10)); 
        pixel_y <= std_logic_vector(to_unsigned(500, 10));
        wait for CLK_PERIOD * 2;

        -- Posição dentro da área visível, mas video_active=0, então a cor continua preta
        pixel_x <= std_logic_vector(to_unsigned(150, 10));
        pixel_y <= std_logic_vector(to_unsigned(410, 10));
        wait for CLK_PERIOD * 2;

        -- 3. Testar a área de jogo visível: Região do CHÃO (GROUND_PIXEL_Y = 400)
        video_active <= '1';
        wait for CLK_PERIOD * 2;

        -- 4. Testar a divisão exata do chão
        pixel_y <= std_logic_vector(to_unsigned(400, 10)); 
        wait for CLK_PERIOD * 2;

        -- 5. Testar a área visível de CÉU VAZIO
        -- Esperado na saída: r=70, g=C0, b=FF (Azul Céu)
        pixel_x <= std_logic_vector(to_unsigned(50, 10));
        pixel_y <= std_logic_vector(to_unsigned(50, 10));
        wait for CLK_PERIOD * 2;

        -- Testar outro quadrante do céu vazio
        pixel_x <= std_logic_vector(to_unsigned(300, 10));
        pixel_y <= std_logic_vector(to_unsigned(120, 10));
        wait for CLK_PERIOD * 2;

        -- =========================================================================
        -- TESTES DE POSICIONAMENTO DAS NUVENS (Baseado no ROM.vhd)
        -- Como a ROM da nuvem é 100% preenchida (x"FF"), o pixel_on será '1'.
        -- Esperado na saída para todas as nuvens: r=FF, g=FF, b=FF (Branco)
        -- =========================================================================

        -- 6. Testar Nuvem 1 (Coordenadas ROM: y=10, x=5)
        -- Equivale ao pixel: X = 44 (5*8 + 4), Y = 84 (10*8 + 4).
        pixel_x <= std_logic_vector(to_unsigned(44, 10));
        pixel_y <= std_logic_vector(to_unsigned(84, 10));
        wait for CLK_PERIOD * 4; 

        -- 7. Testar Nuvem 2 (Coordenadas ROM: y=12, x=35)
        -- Equivale ao pixel: X = 284 (35*8 + 4), Y = 100 (12*8 + 4).
        pixel_x <= std_logic_vector(to_unsigned(284, 10));
        pixel_y <= std_logic_vector(to_unsigned(100, 10));
        wait for CLK_PERIOD * 4; 

        -- 8. Testar Nuvem 3 (Coordenadas ROM: y=8, x=60)
        -- Equivale ao pixel: X = 484 (60*8 + 4), Y = 68 (8*8 + 4).
        pixel_x <= std_logic_vector(to_unsigned(484, 10));
        pixel_y <= std_logic_vector(to_unsigned(68, 10));
        wait for CLK_PERIOD * 4; 
        
        -- Fim da simulação
        sim_done <= true;
        wait;
    end process;

end architecture tb;