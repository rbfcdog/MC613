library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity payment_handler is
    port(
        clk : in std_logic;
        cash_selector : in std_logic_vector(5 downto 0);  -- SW(9 downto 4)
        confirm_signal : in std_logic;  -- debounced KEY0 pulse
        state : in std_logic_vector(1 downto 0);  -- FSM state
        product_price : in std_logic_vector(9 downto 0);  -- price in cents
        reset_signal : in std_logic;  -- reset accumulator when transitioning to s0
        current_value : out std_logic_vector(9 downto 0);  -- accumulated value
        finish_signal : out std_logic  -- '1' when value >= price
    );
end entity;

architecture rtl of payment_handler is
    signal value_accumulator : std_logic_vector(9 downto 0) := "0000000000";
    signal bit_count : integer;
    signal cash_amount : integer;
    
begin

    -- Count how many bits are set in cash_selector
    process(cash_selector)
        variable count : integer;
    begin
        count := 0;
        for i in 5 downto 0 loop
            if cash_selector(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        bit_count <= count;
    end process;

    process(cash_selector)
    begin
        cash_amount <= 0;  -- default
        
        if cash_selector(0) = '1' then  -- SW(4) = 5 cents
            cash_amount <= 5;
        elsif cash_selector(1) = '1' then  -- SW(5) = 10 cents
            cash_amount <= 10;
        elsif cash_selector(2) = '1' then  -- SW(6) = 25 cents
            cash_amount <= 25;
        elsif cash_selector(3) = '1' then  -- SW(7) = 50 cents
            cash_amount <= 50;
        elsif cash_selector(4) = '1' then  -- SW(8) = 100 cents
            cash_amount <= 100;
        elsif cash_selector(5) = '1' then  -- SW(9) = 200 cents
            cash_amount <= 200;
        end if;
    end process;

    -- Handle key press: add value or ignore
    process(clk)
        variable new_val : integer;
    begin
        if rising_edge(clk) then
            -- Reset accumulator when transitioning to s0
            if reset_signal = '1' then
                value_accumulator <= "0000000000";
            elsif confirm_signal = '1' then  -- button pressed (debouncer pulse)
                if state = "01" and bit_count <= 1 then
                    new_val := to_integer(unsigned(value_accumulator)) + cash_amount;
                    
                    -- max value (1023 cents)
                    if new_val > 1023 then
                        value_accumulator <= std_logic_vector(to_unsigned(1023, 10));
                    else
                        value_accumulator <= std_logic_vector(to_unsigned(new_val, 10));
                    end if;
                end if;
            end if;
        end if;
    end process;

    current_value <= value_accumulator;
    
    finish_signal <= '1' when to_integer(unsigned(value_accumulator)) >= to_integer(unsigned(product_price)) else '0';

end rtl;

