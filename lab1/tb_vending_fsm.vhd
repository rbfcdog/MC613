library ieee;
use ieee.std_logic_1164.all;

entity tb_vending_fsm is
end entity;

architecture sim of tb_vending_fsm is

    signal clk           : std_logic := '0';
    signal proceed_key   : std_logic := '1';
    signal reset_key     : std_logic := '1';
    signal finish_signal : std_logic := '0';
    signal state_out     : std_logic_vector(1 downto 0);

begin

    uut: entity work.vending_fsm
    port map (
        clk           => clk,
        pulse_advance   => proceed_key,
        pulse_reset     => reset_key,
        finish_signal => finish_signal,
        state_out     => state_out
    );

    -- Clock generation (50 MHz equivalent → 20 ns period)
    clk_process: process
    begin
        while true loop
            clk <= '0';
            wait for 10 ns;
            clk <= '1';
            wait for 10 ns;
        end loop;
    end process;

    stimulus: process
    begin

        reset_key<='0';

        -- Press button (go to s1)
        proceed_key <= '1';
        wait for 20 ns;
        proceed_key <= '0';
        wait for 20 ns;
        
        -- Press again (go to s3)
        reset_key <= '1';
        wait for 20 ns;
        reset_key <= '0';
        wait for 20 ns;

        wait for 120 ns; --deveria ser 1s, mas o compilador da simu n aceita
        
        -- Press again (s0=>s1)
        proceed_key <= '1';
        wait for 20 ns;
        proceed_key <= '0';
        wait for 20 ns;

        -- Press again (go to s2)
        finish_signal <= '1';
        wait for 20 ns;
        finish_signal <= '0';
        wait for 20 ns;

        wait;

    end process;

end sim;