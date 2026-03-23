library ieee;
use ieee.std_logic_1164.all;

entity led is
    port(
        condition : in std_logic;
        led_out : out std_logic
    );
end entity;

architecture rtl of led is
begin
    led_out <= condition;
end rtl;