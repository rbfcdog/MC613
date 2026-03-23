library ieee;
use ieee.std_logic_1164.all;

entity tb_led is
end entity;

architecture tb of tb_led is
    signal condition : std_logic;
    signal led_out : std_logic;
begin

    dut : entity work.led
        port map(condition => condition, led_out => led_out);

    stim : process
    begin
        condition <= '0'; wait for 100 ns;
        condition <= '1'; wait for 100 ns;
        condition <= '0'; wait for 100 ns;
        condition <= '1'; wait for 100 ns;
    end process;

end tb;
