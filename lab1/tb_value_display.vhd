library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_value_display is
end entity;

architecture tb of tb_value_display is
    signal value : std_logic_vector(9 downto 0);
    signal hex0, hex1, hex2, hex3 : std_logic_vector(6 downto 0);
begin

    dut : entity work.value_display
        port map(
            value => value,
            hex0 => hex0,
            hex1 => hex1,
            hex2 => hex2,
            hex3 => hex3
        );

    stim : process
    begin
        value <= "0000000000"; wait for 100 ns;
        value <= "0000000101"; wait for 100 ns;
        value <= "0000001010"; wait for 100 ns;
        value <= "0000011001"; wait for 100 ns;
        value <= "0001100100"; wait for 100 ns;
        value <= "1111111111"; wait for 100 ns;
    end process;

end tb;
