library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity VGA is
    port (
    -- Entradas de Controle de Clock e Reset
    pixel_clk    : IN  STD_LOGIC;                     -- Clock de 25.175 MHz gerado pelo PLL
    reset_n      : IN  STD_LOGIC;                     -- Reset assíncrono (ativo baixo)

    -- Entradas de Cor (vindos da PPU)
    r_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do vermelho do pixel atual
    g_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do verde do pixel atual
    b_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Intensidade do azul do pixel atual

    -- Saídas de Controle Interno (enviados para a PPU)
    pixel_x      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);  -- Coordenada X atual
    pixel_y      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);  -- Coordenada Y atual
    video_active : OUT STD_LOGIC;                     -- '1' se estiver dentro da área visível (Active Video)

    -- Saídas Físicas (conectadas aos pinos da DE1-SoC)
    VGA_R        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Vermelha
    VGA_G        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Verde
    VGA_B        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Saída VGA Azul
    VGA_HS       : OUT STD_LOGIC;                     -- Sincronismo Horizontal
    VGA_VS       : OUT STD_LOGIC;                     -- Sincronismo Vertical
    VGA_BLANK_N  : OUT STD_LOGIC;                     -- Fora da área visível (ou seja, deve ser '0' no blanking)
    VGA_SYNC_N   : OUT STD_LOGIC;                     -- Sincronização de vídeo (fixo em '1')
    VGA_CLK      : OUT STD_LOGIC                      -- Clock do pixel (espelho do pixel_clk)
  );
end VGA;

architecture rtl of VGA is
    signal x_act: STD_LOGIC : '0'
    signal y_act: STD_LOGIC : '0'

begin

    architecture rtl of VGA is
    signal x_act : STD_LOGIC := '0';
    signal y_act : STD_LOGIC := '0';

    signal count_x : integer range 0 to 1023 := 0;
    signal count_y : integer range 0 to 1023 := 0;

begin

    process(pixel_clk, reset_n)
    begin
        if reset_n = '0' then
            count_x <= 0;
            count_y <= 0;
            
        elsif rising_edge(pixel_clk) then
        
            -- Y Sync and Porches
            if count_y < 2 then --V sync
                VGA_VS <= '0';
                y_act  <= '0';
            elsif count_y < 33 then --back porch Y
                VGA_VS <= '1';
                y_act  <= '0';
            elsif count_y < 513 then --y active
                VGA_VS <= '1';
                y_act  <= '1';
            else -- front porch y
                VGA_VS <= '1';
                y_act  <= '0';
            end if;
                
            if count_x < 96 then --H sync
                VGA_HS <= '0';
                x_act  <= '0';
            elsif count_x < 144 then --back porch X
                VGA_HS <= '1';
                x_act  <= '0';
            elsif count_x < 784 then  --x active
                VGA_HS <= '1';
                x_act  <= '1';
            else -- front porch x
                VGA_HS <= '1';
                x_act  <= '0';
            end if;

            -- Coordinate Counters
            if count_x = 799 then 
                count_x <= 0;     -- Wrap X back to 0
                
                --Y only increments when a full X line is drawn
                if count_y = 524 then 
                    count_y <= 0;
                else
                    count_y <= count_y + 1;
                end if;
                
            else
                count_x <= count_x + 1
            end if;

        end if;
    end process;

    -- Map internal signals to outputs using numeric_std conversion
    pixel_x <= std_logic_vector(to_unsigned(count_x, 10));
    pixel_y <= std_logic_vector(to_unsigned(count_y, 10));

    VGA_CLK<=pixel_clk;
    VGA_SYNC_N<='1';
    video_active<=x_act and y_act; 
    VGA_BLANK_N<= not video_active;
    VGA_R <= r_in when (video_active) else (others => '0');
    VGA_G <= g_in when (video_active) else (others => '0');
    VGA_B <= b_in when (video_active) else (others => '0');

end rtl