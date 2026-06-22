library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dram_controller is
    port(
        clk     : IN std_logic;
        rst     : IN std_logic;
        SW      : IN std_logic_vector (9 downto 0);
        KEY     : IN std_logic_vector (3 downto 0);
        data_in : IN std_logic_vector (7 downto 0);
        write_data_in : IN std_logic_vector (7 downto 0);
        data_out : OUT std_logic_vector (7 downto 0);
        HEX0    : OUT std_logic_vector (6 downto 0);
        HEX1    : OUT std_logic_vector (6 downto 0);
        HEX4    : OUT std_logic_vector (6 downto 0);
        HEX5    : OUT std_logic_vector (6 downto 0);
        adress  : OUT std_logic_vector (25 downto 0);
        addr_in : IN std_logic_vector (25 downto 0);
        write_data_out : OUT std_logic_vector (7 downto 0);
        req     : IN std_logic;
        wEn     : IN std_logic;
        ready   : OUT std_logic
    );
end dram_controller;

architecture rtl of dram_controller is
    type op_state_t is (
        st_init_wait_start,
        st_init_wait,
        st_init_trp,
        st_init_refresh_cmd,
        st_init_refresh_wait,
        st_init_tmrd,
        st_ready,
        st_activate_wait,
        st_read_wait,
        st_write_wait,
        st_precharge_wait,
        st_refresh_trp,
        st_refresh_wait
    );

    type timer_state_t is (
        timer_idle,
        timer_count
    );

    signal op_state : op_state_t := st_init_wait_start;
    signal timer_state : timer_state_t := timer_idle;

    signal timer_start : std_logic := '0';
    signal timer_done : std_logic := '0';
    signal timer_cycles : integer range 0 to 28600 := 0;
    signal timer_counter : integer range 0 to 28600 := 0;

    signal init_refresh_count : integer range 0 to 7 := 0;
    signal refresh_counter : integer range 0 to 1117 := 0;
    signal refresh_due : std_logic := '0';

    signal active_addr : std_logic_vector(25 downto 0) := (others => '0');
    signal active_wen : std_logic := '0';
    signal active_data : std_logic_vector(7 downto 0) := (others => '0');

    constant CMD_NOP       : std_logic_vector(25 downto 0) := "11" & x"F38000";
    constant CMD_PREALL    : std_logic_vector(25 downto 0) := "11" & x"F10400";
    constant CMD_ACTIVATE  : std_logic_vector(25 downto 0) := "11" & x"F18000";
    constant CMD_REFRESH   : std_logic_vector(25 downto 0) := "11" & x"F88000";
    constant CMD_MRS       : std_logic_vector(25 downto 0) := "00" & x"000220";
    constant CMD_READ      : std_logic_vector(25 downto 0) := "11" & x"F28000";
    constant CMD_WRITE     : std_logic_vector(25 downto 0) := "11" & x"F20000";

    constant INIT_WAIT_CYCLES       : integer := 28600;
    constant TRCD_WAIT_CYCLES       : integer := 3;
    constant TRP_WAIT_CYCLES        : integer := 3;
    constant WRITE_REC_WAIT_CYCLES  : integer := 3;
    -- CAS Latency = 3: the DRAM drives valid read data 3 clocks after it
    -- registers the READ command. With DRAM_CLK = not pll_clk (half-cycle
    -- phase shift) the data is centered on the controller's sampling edge
    -- when we wait the full CAS latency. The previous value (3) sampled the
    -- still-idle bus and captured 0xFF.
    constant READ_CAPTURE_CYCLES    : integer := 4;
    constant RFC_WAIT_CYCLES        : integer := 10;
    constant TMRD_WAIT_CYCLES       : integer := 2;
    constant REFRESH_INTERVAL_CYCLES : integer := 1117;

    signal buffered_req  : std_logic;
    signal buffered_wen  : std_logic;
    signal buffered_addr : std_logic_vector(25 downto 0);
    signal buffered_data : std_logic_vector(7 downto 0);
    signal cmd_ack       : std_logic := '0';

    function row_address(logical_addr : std_logic_vector(25 downto 0))
        return std_logic_vector is
    begin
        return logical_addr(25 downto 13);
    end function;

    function bank_address(logical_addr : std_logic_vector(25 downto 0))
        return std_logic_vector is
    begin
        return logical_addr(12 downto 11);
    end function;

    function column_address(logical_addr : std_logic_vector(25 downto 0))
        return std_logic_vector is
        variable addr : std_logic_vector(12 downto 0) := (others => '0');
    begin
        addr(9 downto 0) := logical_addr(10 downto 1);
        addr(10) := '0';
        return addr;
    end function;

    function command_with_address(
        cmd          : std_logic_vector(25 downto 0);
        logical_addr : std_logic_vector(25 downto 0);
        dram_addr    : std_logic_vector(12 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(25 downto 0);
    begin
        result := cmd;
        result(14 downto 13) := bank_address(logical_addr);
        result(12 downto 0) := dram_addr;
        return result;
    end function;
begin
    HEX0 <= (others => '1');
    HEX1 <= (others => '1');
    HEX4 <= (others => '1');
    HEX5 <= (others => '1');

    write_data_out <= active_data;

    timer_done <= '1' when
        (timer_state = timer_idle and timer_start = '1' and timer_cycles <= 1) or
        (timer_state = timer_count and timer_counter <= 1)
        else '0';

    reader_inst : entity work.reader
        port map (
            clk          => clk,
            rst          => rst,
            req_in       => req,
            wEn_in       => wEn,
            addr_in      => addr_in,
            data_in      => write_data_in,
            req_pending  => buffered_req,
            wEn_out      => buffered_wen,
            addr_out     => buffered_addr,
            data_out     => buffered_data,
            cmd_ack      => cmd_ack
        );

    timing_fsm : process(clk, rst)
    begin
        if rst = '1' then
            timer_state <= timer_idle;
            timer_counter <= 0;
        elsif rising_edge(clk) then
            case timer_state is
                when timer_idle =>
                    if timer_start = '1' then
                        if timer_cycles <= 1 then
                            timer_counter <= 0;
                        else
                            timer_counter <= timer_cycles - 1;
                            timer_state <= timer_count;
                        end if;
                    end if;

                when timer_count =>
                    if timer_counter <= 1 then
                        timer_counter <= 0;
                        timer_state <= timer_idle;
                    else
                        timer_counter <= timer_counter - 1;
                    end if;
            end case;
        end if;
    end process timing_fsm;

    operation_fsm : process(clk, rst)
    begin
        if rst = '1' then
            op_state <= st_init_wait_start;
            adress <= CMD_NOP;
            ready <= '0';
            data_out <= (others => '0');
            timer_start <= '0';
            timer_cycles <= 0;
            init_refresh_count <= 0;
            refresh_counter <= 0;
            refresh_due <= '0';
            active_addr <= (others => '0');
            active_wen <= '0';
            active_data <= (others => '0');
            cmd_ack <= '0';
        elsif rising_edge(clk) then
            adress <= CMD_NOP;
            ready <= '0';
            cmd_ack <= '0';
            timer_start <= '0';

            if op_state = st_ready or op_state = st_activate_wait or
               op_state = st_read_wait or op_state = st_write_wait or
               op_state = st_precharge_wait then
                if refresh_due = '0' then
                    if refresh_counter >= REFRESH_INTERVAL_CYCLES then
                        refresh_due <= '1';
                    else
                        refresh_counter <= refresh_counter + 1;
                    end if;
                end if;
            end if;

            case op_state is
                when st_init_wait_start =>
                    timer_cycles <= INIT_WAIT_CYCLES;
                    timer_start <= '1';
                    op_state <= st_init_wait;

                when st_init_wait =>
                    if timer_done = '1' then
                        adress <= CMD_PREALL;
                        timer_cycles <= TRP_WAIT_CYCLES;
                        timer_start <= '1';
                        init_refresh_count <= 0;
                        op_state <= st_init_trp;
                    end if;

                when st_init_trp =>
                    if timer_done = '1' then
                        adress <= CMD_REFRESH;
                        timer_cycles <= RFC_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_init_refresh_wait;
                    end if;

                when st_init_refresh_cmd =>
                    adress <= CMD_REFRESH;
                    timer_cycles <= RFC_WAIT_CYCLES;
                    timer_start <= '1';
                    op_state <= st_init_refresh_wait;

                when st_init_refresh_wait =>
                    if timer_done = '1' then
                        if init_refresh_count = 7 then
                            adress <= CMD_MRS;
                            timer_cycles <= TMRD_WAIT_CYCLES;
                            timer_start <= '1';
                            op_state <= st_init_tmrd;
                        else
                            init_refresh_count <= init_refresh_count + 1;
                            op_state <= st_init_refresh_cmd;
                        end if;
                    end if;

                when st_init_tmrd =>
                    if timer_done = '1' then
                        refresh_counter <= 0;
                        refresh_due <= '0';
                        op_state <= st_ready;
                    end if;

                when st_ready =>
                    ready <= '1';

                    if refresh_due = '1' then
                        ready <= '0';
                        adress <= CMD_PREALL;
                        timer_cycles <= TRP_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_refresh_trp;
                    elsif buffered_req = '1' then
                        ready <= '0';
                        cmd_ack <= '1';
                        active_addr <= buffered_addr;
                        active_wen <= buffered_wen;
                        active_data <= buffered_data;
                        adress <= command_with_address(
                            CMD_ACTIVATE,
                            buffered_addr,
                            row_address(buffered_addr)
                        );
                        timer_cycles <= TRCD_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_activate_wait;
                    end if;

                when st_activate_wait =>
                    if timer_done = '1' then
                        if active_wen = '1' then
                            adress <= command_with_address(
                                CMD_WRITE,
                                active_addr,
                                column_address(active_addr)
                            );
                            timer_cycles <= WRITE_REC_WAIT_CYCLES;
                            timer_start <= '1';
                            op_state <= st_write_wait;
                        else
                            adress <= command_with_address(
                                CMD_READ,
                                active_addr,
                                column_address(active_addr)
                            );
                            timer_cycles <= READ_CAPTURE_CYCLES;
                            timer_start <= '1';
                            op_state <= st_read_wait;
                        end if;
                    end if;

                when st_read_wait =>
                    if timer_done = '1' then
                        data_out <= data_in;
                        adress <= CMD_PREALL;
                        timer_cycles <= TRP_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_precharge_wait;
                    end if;

                when st_write_wait =>
                    if timer_done = '1' then
                        adress <= CMD_PREALL;
                        timer_cycles <= TRP_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_precharge_wait;
                    end if;

                when st_precharge_wait =>
                    if timer_done = '1' then
                        op_state <= st_ready;
                    end if;

                when st_refresh_trp =>
                    if timer_done = '1' then
                        adress <= CMD_REFRESH;
                        timer_cycles <= RFC_WAIT_CYCLES;
                        timer_start <= '1';
                        op_state <= st_refresh_wait;
                    end if;

                when st_refresh_wait =>
                    if timer_done = '1' then
                        refresh_counter <= 0;
                        refresh_due <= '0';
                        op_state <= st_ready;
                    end if;
            end case;
        end if;
    end process operation_fsm;
end rtl;
