library ieee;
use ieee.std_logic_1164.all;

entity tb_VGA is
end entity;

architecture tb of tb_VGA is
    -- Entradas de Controle de Clock e Reset
    signal pixel_clk    : STD_LOGIC;                     -- Clock de 25.175 MHz gerado pelo PLL
    signal reset_n      : STD_LOGIC;                     -- Reset assíncrono (ativo baixo)

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
    signal VGA_CLK      : STD_LOGIC


begin
    dut: entity work.VGA
    port map();
    