library ieee;
use ieee.std_logic_1164.all;

entity tb_VGA is
end entity;

architecture tb of tb_VGA is
    -- Entradas de Controle de Clock e Reset
    signal pixel_clk    : STD_LOGIC :='0';                     -- Clock de 25.175 MHz gerado pelo PLL
    signal reset_n      : STD_LOGIC :='0';                     -- Reset assíncrono (ativo baixo)

    -- Entradas de Cor (vindos da PPU)
    signal r_in         : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do vermelho do pixel atual
    signal g_in         : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do verde do pixel atual
    signal b_in         : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do azul do pixel atual

    -- Saídas de Controle Interno (enviados para a PPU)
    signal pixel_x      : STD_LOGIC_VECTOR(9 DOWNTO 0);  -- Coordenada X atual
    signal pixel_y      : STD_LOGIC_VECTOR(9 DOWNTO 0);  -- Coordenada Y atual
    signal video_active : STD_LOGIC;                     -- '1' se estiver dentro da área visível (Active Video)

    -- Saídas Físicas (conectadas aos pinos da DE1-SoC)
    signal VGA_R        : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Vermelha
    signal VGA_G        : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Verde
    signal VGA_B        : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Azul
    signal VGA_HS       : STD_LOGIC;                     -- Sincronismo Horizontal
    signal VGA_VS       : STD_LOGIC;                     -- Sincronismo Vertical
    signal VGA_BLANK_N  : STD_LOGIC;                     -- Fora da área visível (ou seja, deve ser '0' no blanking)
    signal VGA_SYNC_N   : STD_LOGIC;                     -- Sincronização de vídeo (fixo em '1')
    signal VGA_CLK      : STD_LOGIC;

    constant CLK_PERIOD : time := 39.72 ns; --1/25.175 
    signal sim_done     : boolean := false;


begin
    dut: entity work.VGA
    port map(
        pixel_clk    => pixel_clk,
        reset_n      => reset_n,
        r_in         => r_in,
        g_in         => g_in,
        b_in         => b_in,
        pixel_x      => pixel_x,
        pixel_y      => pixel_y,
        video_active => video_active,
        VGA_R        => VGA_R,
        VGA_G        => VGA_G,
        VGA_B        => VGA_B,
        VGA_HS       => VGA_HS,
        VGA_VS       => VGA_VS,
        VGA_BLANK_N  => VGA_BLANK_N,
        VGA_SYNC_N   => VGA_SYNC_N,
        VGA_CLK      => VGA_CLK
    );
    
    clk_gen: process
        begin
        while not sim_done loop
            pixel_clk <= '0';
            wait for CLK_PERIOD / 2;
            pixel_clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;
    
    stim: process
    begin
        reset_n <= '0';
        r_in <= x"00";
        g_in <= x"00";
        b_in <= x"FF";

        wait for CLK_PERIOD * 2;
        reset_n <= '1';

        wait for 17 ms;

        wait until falling_edge(pixel_clk);
        r_in <= x"00";
        g_in <= x"FF"; -- Muda para verde

        wait for CLK_PERIOD * 800 * 5;

        sim_done <= true;
        wait;
    end process;

end architecture tb;