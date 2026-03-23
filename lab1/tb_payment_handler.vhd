library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_payment_handler is
end entity;

architecture tb of tb_payment_handler is
    signal clk : std_logic := '0';
    signal cash_selector : std_logic_vector(5 downto 0) := "000000";
    signal confirm_signal : std_logic := '0';
    signal state : std_logic_vector(1 downto 0) := "00";
    signal product_price : std_logic_vector(9 downto 0) := "0000110010";
    signal reset_signal : std_logic := '0';
    signal current_value : std_logic_vector(9 downto 0);
    signal finish_signal : std_logic;
    
    constant CLK_PERIOD : time := 20 ns;
begin

    dut : entity work.payment_handler
        port map(
            clk => clk,
            cash_selector => cash_selector,
            confirm_signal => confirm_signal,
            state => state,
            product_price => product_price,
            reset_signal => reset_signal,
            current_value => current_value,
            finish_signal => finish_signal
        );

    clk_gen : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    stim : process
    begin
        state <= "01";
        wait for 1 us;
        
        cash_selector <= "000001";
        confirm_signal <= '1';
        wait for CLK_PERIOD;
        confirm_signal <= '0';
        wait for 1 us;
        
        cash_selector <= "000010";
        confirm_signal <= '1';
        wait for CLK_PERIOD;
        confirm_signal <= '0';
        wait for 1 us;
        
        cash_selector <= "001000";
        confirm_signal <= '1';
        wait for CLK_PERIOD;
        confirm_signal <= '0';
        wait for 1 us;
        
        reset_signal <= '1';
        wait for CLK_PERIOD;
        reset_signal <= '0';
        wait for 1 us;
    end process;

end tb;
