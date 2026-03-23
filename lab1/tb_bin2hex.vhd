library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_bin2hex is
end entity;

architecture sim of tb_bin2hex is

    signal BIN : std_logic_vector(3 downto 0);
    signal HEX : std_logic_vector(6 downto 0);

begin

    uut: entity work.bin2hex
    port map (
        BIN => BIN,
        HEX => HEX
    );

    stimulus: process
    begin

        -- Test all possible inputs
        for i in 0 to 15 loop
            BIN <= std_logic_vector(to_unsigned(i, 4));
            wait for 10 ns;
        end loop;

        wait;

    end process;

end sim;