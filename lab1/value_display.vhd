library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity value_display is
	port(
		value : in  std_logic_vector(9 downto 0);
		hex0  : out std_logic_vector(6 downto 0);
		hex1  : out std_logic_vector(6 downto 0);
		hex2  : out std_logic_vector(6 downto 0);
		hex3  : out std_logic_vector(6 downto 0)
	);
end entity;

architecture rtl of value_display is
	signal d0, d1, d2, d3 : std_logic_vector(3 downto 0);
begin

	process(value)
		variable val_i : integer range 0 to 1023;
		variable ones, tens, hundreds, thousands : integer range 0 to 9;
	begin
		val_i := to_integer(unsigned(value));

		ones      := val_i mod 10;
		tens      := (val_i / 10) mod 10;
		hundreds  := (val_i / 100) mod 10;
		thousands := (val_i / 1000) mod 10;

		d0 <= std_logic_vector(to_unsigned(ones, 4));
		d1 <= std_logic_vector(to_unsigned(tens, 4));
		d2 <= std_logic_vector(to_unsigned(hundreds, 4));
		d3 <= std_logic_vector(to_unsigned(thousands, 4));
	end process;

	u_hex0 : entity work.bin2hex
	port map (
		bin => d0,
		hex => hex0
	);

	u_hex1 : entity work.bin2hex
	port map (
		bin => d1,
		hex => hex1
	);

	u_hex2 : entity work.bin2hex
	port map (
		bin => d2,
		hex => hex2
	);

	u_hex3 : entity work.bin2hex
	port map (
		bin => d3,
		hex => hex3
	);

end architecture;
