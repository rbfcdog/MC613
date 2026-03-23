library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_selector is
end entity;

architecture sim of tb_selector is

    signal SELECTOR : std_logic_vector(3 downto 0);
    signal STATE    : std_logic_vector(1 downto 0);
    signal ID       : std_logic_vector(3 downto 0);
    signal PRICE    : std_logic_vector(9 downto 0);

begin

    uut: entity work.selector
    port map (
        SELECTOR => SELECTOR,
        STATE    => STATE,
        ID       => ID,
        PRICE    => PRICE
    );

    stimulus: process
    begin

        for i in 0 to 15 loop
            SELECTOR <= std_logic_vector(to_unsigned(i, 4));
            wait for 10 ns;
        end loop;

        wait;

    end process;

end sim;