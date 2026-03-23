library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vending_machine is
end entity;

architecture tb of tb_vending_machine is
    signal KEY1 : std_logic := '1';
    signal KEY0 : std_logic := '1';
    signal SW : std_logic_vector(9 downto 0) := "0000000000";
    signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(6 downto 0);
    signal LEDR0, LEDR1 : std_logic;
    signal CLOCK_50 : std_logic := '0';
    
    constant CLK_PERIOD : time := 20 ns;
begin

    dut : entity work.vending_machine
        port map(
            KEY1 => KEY1,
            KEY0 => KEY0,
            KEY => (others => '1'),  -- Unused keys set to '1'
            SW => SW,
            HEX0 => HEX0,
            HEX1 => HEX1,
            HEX2 => HEX2,
            HEX3 => HEX3,
            HEX4 => HEX4,
            HEX5 => HEX5,
            LEDR0 => LEDR0,
            LEDR1 => LEDR1,
            CLOCK_50 => CLOCK_50
        );

    clk_gen : process
    begin
        CLOCK_50 <= '0';
        wait for CLK_PERIOD/2;
        CLOCK_50 <= '1';
        wait for CLK_PERIOD/2;
    end process;

    stim : process
    begin
        wait for 10 us;
        
        SW(3 downto 0) <= "0001";
        wait for 5 us;
        
        SW(4) <= '1';
        KEY0 <= '0';
        wait for 30 ms;
        KEY0 <= '1';
        wait for 5 us;
        
        SW(4) <= '0';
        SW(5) <= '1';
        KEY0 <= '0';
        wait for 30 ms;
        KEY0 <= '1';
        wait for 5 us;
        
        KEY0 <= '0';
        wait for 30 ms;
        KEY0 <= '1';
        wait for 60 ms;
        
        wait;
    end process;

end tb;
