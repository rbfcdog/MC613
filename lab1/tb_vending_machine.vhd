library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vending_machine is
end entity;

architecture tb of tb_vending_machine is
    signal KEY : std_logic_vector(3 downto 0) := "1111";
    signal SW : std_logic_vector(9 downto 0) := "0000000000";
    signal HEX0, HEX1, HEX2, HEX3, HEX5 : std_logic_vector(6 downto 0);
    signal LEDR : std_logic_vector(9 downto 0) := (others => '0');
    signal CLOCK_50 : std_logic := '0';
    
    constant CLK_PERIOD : time := 20 ns;
begin

    dut : entity work.vending_machine
        port map(
            KEY => KEY,
            SW => SW,
            HEX0 => HEX0,
            HEX1 => HEX1,
            HEX2 => HEX2,
            HEX3 => HEX3,
            HEX5 => HEX5,
            LEDR => LEDR,
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

        --confirmar
        KEY(0) <= '0'; wait for 60 ns;
        KEY(0) <= '1'; wait for 40 ns;
        
        SW(4) <= '1';
        KEY(0) <= '0';
        wait for 30 ns;
        KEY(0) <= '1';
        wait for 5 ns;
        
        SW(4) <= '0';
        SW(5) <= '1';
        KEY(0) <= '0';
        wait for 30 ns;
        KEY(0) <= '1';
        wait for 5 ns;
        
        KEY(0) <= '0';
        wait for 30 ns;
        KEY(0) <= '1';
        wait for 60 ns;
        
        wait;
    end process;

end tb;
