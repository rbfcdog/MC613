library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vending_machine is
	port(
	  KEY : in std_logic_vector(3 downto 0);

	  SW : in std_logic_vector(9 downto 0);
	  
	  HEX0 : out std_logic_vector(6 downto 0);
	  HEX1 : out std_logic_vector(6 downto 0);
	  HEX2 : out std_logic_vector(6 downto 0);
	  HEX3 : out std_logic_vector(6 downto 0);
	  HEX5 : out std_logic_vector(6 downto 0);

	  LEDR : out std_logic_vector(9 downto 0);
	  
	  CLOCK_50 : in std_logic
	);
end entity;

architecture rtl of vending_machine is

    signal state_sig : std_logic_vector(1 downto 0);
    signal state_prev : std_logic_vector(1 downto 0) := "00";
    signal selector_value : std_logic_vector(9 downto 0);
    signal current_product_id : std_logic_vector(3 downto 0) := "0000";

    signal current_value : std_logic_vector(9 downto 0) := "0000000000";
    signal accumulated_value : std_logic_vector(9 downto 0);
    signal display_value : std_logic_vector(9 downto 0) := "0000000000";
    signal finish_signal : std_logic := '0';
    signal ledr1_condition : std_logic;
    signal ledr0_condition : std_logic;
    signal reset_values : std_logic;

    signal key_0 : std_logic := '1';
    signal key_1 : std_logic := '1';
    signal pulse_advance : std_logic := '0';
    signal pulse_reset : std_logic := '0';
    signal startup_counter : integer := 0;

begin

	 process(CLOCK_50)
    begin
		if rising_edge(CLOCK_50) then
             -- debounce logic: only consider a button press if the previous state was '1' (not pressed) and current state is '0' (pressed)

			 if key_0 = '1' and KEY(0) = '0' then
				  pulse_advance <= '1';
			 else 
				pulse_advance <= '0';
			 end if;
			 

			 if key_1 = '1' and KEY(1) = '0' then
				  pulse_reset <= '1';
			 else
				pulse_reset <= '0';
			 end if;
			 
			 
			 key_0 <= KEY(0);
			 key_1 <= KEY(1);
		end if;
		
	end process;

	-- Track previous state for detecting state transitions
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			state_prev <= state_sig;
		end if;
	end process;
		
    -- Reset signal: '1' only when transitioning to s0 (back to idle)
    -- Keep accumulated_value for change calculation in s2
    reset_values <= '1' when (state_prev /= "00" and state_sig = "00") else '0';

    -- FSM instance
    fsm_inst : entity work.vending_fsm
    port map(
        clk   => CLOCK_50,
        pulse_advance => pulse_advance,
        pulse_reset => pulse_reset,
        finish_signal => finish_signal,
        state_out => state_sig
    );

    -- Selector
    selector_inst : entity work.selector
    port map (
        SELECTOR => SW(3 downto 0),
        STATE => state_sig,
        ID => current_product_id,
        PRICE => current_value
    );

    payment_handler_inst : entity work.payment_handler
    port map (
        clk => CLOCK_50,
        cash_selector => SW(9 downto 4),
        state => state_sig,
        confirm_signal => pulse_advance,
        product_price => current_value,
        reset_signal => reset_values,
        current_value => accumulated_value,
        finish_signal => finish_signal
    );

    -- Value Display
    value_display_inst : entity work.value_display
    port map (
        value => display_value,
        hex0 => HEX0,
        hex1 => HEX1,
        hex2 => HEX2,
        hex3 => HEX3
    );

    -- State Display disabled
    HEX2hex_inst : entity work.bin2hex
    port map (
        BIN => current_product_id,
        HEX => HEX5
    );

    -- LEDs for finish and change indication
    led1_inst : entity work.led
    port map (
        condition => ledr1_condition,
        led_out => LEDR(1)
    );
    
    led0_inst : entity work.led
    port map (
        condition => ledr0_condition,
        led_out => LEDR(0)
    );

    ledr1_condition <= '1' when ((state_sig = "11" and accumulated_value /= "0000000000") or 
                                  (state_sig = "01" and to_integer(unsigned(accumulated_value)) > to_integer(unsigned(current_value))))
                      else '0';  -- On when there's change due (accumulated > price)
    ledr0_condition <= finish_signal;  -- On when purchase succeeded (accumulated >= price)

    process(state_sig, accumulated_value, current_value)
        variable difference : integer;
    begin
        case state_sig is
            when "00" =>  -- s0: show price of selected product
                display_value <= current_value;

            when "01" =>  -- s1: show accumulated value (money paid so far)
                display_value <= accumulated_value;

            when "10" =>  -- s2: show accumulated - product_price (change/balance)
                difference := to_integer(unsigned(accumulated_value)) - to_integer(unsigned(current_value));
                display_value <= std_logic_vector(to_unsigned(difference, 10));
                            
            when "11" =>  -- s3: show accumulated_value (total paid)
                display_value <= accumulated_value;
            
            when others =>
                display_value <= "0000000000";
        end case;
    end process;

end rtl;