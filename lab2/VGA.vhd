library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity VGA is
    port (
    pixel_clk    : IN  STD_LOGIC;
    reset_n      : IN  STD_LOGIC;
    r_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
    g_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
    b_in         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
    pixel_x      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
    pixel_y      : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
    video_active : OUT STD_LOGIC;
    VGA_R        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    VGA_G        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    VGA_B        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    VGA_HS       : OUT STD_LOGIC;
    VGA_VS       : OUT STD_LOGIC;
    VGA_BLANK_N  : OUT STD_LOGIC;
    VGA_SYNC_N   : OUT STD_LOGIC;
    VGA_CLK      : OUT STD_LOGIC
  );
end VGA;

architecture rtl of VGA is
    signal x_act : STD_LOGIC := '0';
    signal y_act : STD_LOGIC := '0';
    signal video_active_i : STD_LOGIC := '0';
    signal count_x : integer range 0 to 1023 := 0;
    signal count_y : integer range 0 to 1023 := 0;
begin

    process(pixel_clk, reset_n)
    begin
        if reset_n = '0' then
            count_x <= 0;
            count_y <= 0;
            
        elsif rising_edge(pixel_clk) then
        
            if count_y < 2 then
                VGA_VS <= '0';
                y_act  <= '0';
            elsif count_y < 33 then
                VGA_VS <= '1';
                y_act  <= '0';
            elsif count_y < 513 then
                VGA_VS <= '1';
                y_act  <= '1';
            else
                VGA_VS <= '1';
                y_act  <= '0';
            end if;
                
            if count_x < 96 then
                VGA_HS <= '0';
                x_act  <= '0';
            elsif count_x < 144 then
                VGA_HS <= '1';
                x_act  <= '0';
            elsif count_x < 784 then
                VGA_HS <= '1';
                x_act  <= '1';
            else
                VGA_HS <= '1';
                x_act  <= '0';
            end if;

            if count_x = 799 then 
                count_x <= 0;
                
                if count_y = 523 then 
                    count_y <= 0;
                else
                    count_y <= count_y + 1;
                end if;
                
            else
                count_x <= count_x + 1;
            end if;

        end if;
    end process;

    pixel_x <= std_logic_vector(to_unsigned(count_x - 144, 10)) when count_x >= 144 else (others => '0');
    pixel_y <= std_logic_vector(to_unsigned(count_y - 33, 10)) when count_y >= 33 else (others => '0');

    VGA_CLK<=pixel_clk;
    VGA_SYNC_N<='1';
    video_active_i <= x_act and y_act;
    video_active <= video_active_i;
    VGA_BLANK_N <= video_active_i;
    VGA_R <= r_in when video_active_i = '1' else (others => '0');
    VGA_G <= g_in when video_active_i = '1' else (others => '0');
    VGA_B <= b_in when video_active_i = '1' else (others => '0');

end rtl;