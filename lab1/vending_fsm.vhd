library ieee;
use ieee.std_logic_1164.all;

entity vending_fsm is
	port(
		clk    : in  std_logic;
		pulse_advance    : in  std_logic;  -- corresponds to KEY0 (active low)
		pulse_reset  : in  std_logic;  -- corresponds to KEY1 (active low)
		finish_signal : in std_logic;  -- from selector, indicates product fully paid 
		state_out : out std_logic_vector(1 downto 0)
	);
end entity;

architecture rtl of vending_fsm is

	type state_type is (s0, s1, s2, s3);
	signal state : state_type := s0;
	signal counter : integer := 0;
	constant ONE_SECOND : integer := 50000000;  -- 50MHz clock

begin
	-- State transition logic
	process (clk)
	begin
		if rising_edge(clk) then

			if state = s1 and pulse_reset = '1' then
				state <= s3;
				counter <= 0;

			elsif pulse_advance = '1' and state = s0 then
				state <= s1;
				counter <= 0;

			elsif state = s1 and finish_signal = '1' then
				state <= s2;
				counter <= 0;

			elsif state = s2 then
				if counter < ONE_SECOND then
					counter <= counter + 1;
				else
					state <= s0;
					counter <= 0;
				end if;

			elsif state = s3 then
				if counter < ONE_SECOND then
					counter <= counter + 1;
				else
					state <= s0;
					counter <= 0;
				end if;

			end if;
		end if;
	end process;

	-- Moore output (depends only on state)
	process (state)
	begin
		case state is
			when s0 =>
				state_out <= "00";
			when s1 =>
				state_out <= "01";
			when s2 =>
				state_out <= "10";
			when s3 =>
				state_out <= "11";
		end case;
	end process;

end rtl;