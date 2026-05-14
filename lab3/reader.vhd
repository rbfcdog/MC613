library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity reader is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Inputs from dram_iface
        req_in       : in  std_logic;
        wEn_in       : in  std_logic;
        addr_in      : in  std_logic_vector(25 downto 0);
        data_in      : in  std_logic_vector(7 downto 0);
        
        -- Outputs to dram_controller state machine
        req_pending  : out std_logic;
        wEn_out      : out std_logic;
        addr_out     : out std_logic_vector(25 downto 0);
        data_out     : out std_logic_vector(7 downto 0);
        
        -- Acknowledge from dram_controller to clear the buffer
        cmd_ack      : in  std_logic
    );
end reader;

architecture rtl of reader is
    signal pending_reg : std_logic := '0';
    signal wEn_reg     : std_logic := '0';
    signal addr_reg    : std_logic_vector(25 downto 0) := (others => '0');
    signal data_reg    : std_logic_vector(7 downto 0) := (others => '0');
begin

    -- Route internal registers to output ports
    req_pending <= pending_reg;
    wEn_out     <= wEn_reg;
    addr_out    <= addr_reg;
    data_out    <= data_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            pending_reg <= '0';
            wEn_reg     <= '0';
            addr_reg    <= (others => '0');
            data_reg    <= (others => '0');
        elsif rising_edge(clk) then
            
            -- If the controller acknowledges the command, clear the pending flag
            if cmd_ack = '1' then
                pending_reg <= '0';
            end if;

            -- If a new request comes in and we aren't currently holding an unacknowledged one
            -- (or if it's being acknowledged this exact clock cycle, allowing continuous operation)
            if req_in = '1' and (pending_reg = '0' or cmd_ack = '1') then
                pending_reg <= '1';
                wEn_reg     <= wEn_in;
                addr_reg    <= addr_in;
                data_reg    <= data_in;
            end if;
            
        end if;
    end process;
end rtl;
