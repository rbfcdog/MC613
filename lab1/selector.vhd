library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity selector is
   Port (
		SELECTOR : in STD_LOGIC_VECTOR(3 downto 0);
                STATE: in STD_LOGIC_VECTOR (1 downto 0);
                ID: out STD_LOGIC_VECTOR (3 downto 0);
		PRICE: out STD_LOGIC_VECTOR (9 downto 0)
	);
end selector;

architecture Behavioral of selector is
begin
        process(SELECTOR, STATE)
        begin
                if STATE = "00" then
                        ID <= SELECTOR;
                        case SELECTOR is
                                when "0000" => PRICE <= "0001111101";
                                when "0001" => PRICE <= "0100101100";
                                when "0010" => PRICE <= "0010101111";
                                when "0011" => PRICE <= "0111000010";
                                when "0100" => PRICE <= "0011100001";
                                when "0101" => PRICE <= "0101011110";
                                when "0110" => PRICE <= "0011111010";
                                when "0111" => PRICE <= "0110101001";
                                when "1000" => PRICE <= "0111110100";
                                when "1001" => PRICE <= "0101000101";
                                when "1010" => PRICE <= "1001011000";
                                when "1011" => PRICE <= "0100010011";
                                when "1100" => PRICE <= "1010111100";
                                when "1101" => PRICE <= "0111011011";
                                when "1110" => PRICE <= "1000001101";
                                when "1111" => PRICE <= "1100100000";
                                when others => PRICE <= "0000000000";
                        end case;
                else
                        null;
                end if;
        end process;
end Behavioral;