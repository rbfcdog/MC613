library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dram_controller is
  generic (
    G_INIT_WAIT_CYCLES : positive := 20000;
    G_TRCD_CYCLES      : positive := 3;
    G_TCAS_CYCLES      : positive := 3;
    G_TRP_CYCLES       : positive := 3;
    G_TDPL_CYCLES      : positive := 2;
    G_TRC_CYCLES       : positive := 10;
    G_TMRD_CYCLES      : positive := 2;
    G_TREFI_CYCLES     : positive := 1117
  );
  port (
    clk         : in    std_logic;
    rst         : in    std_logic;
    address     : in    std_logic_vector(25 downto 0);
    write_data  : in    std_logic_vector(7 downto 0);
    read_data   : out   std_logic_vector(7 downto 0);
    req         : in    std_logic;
    wEn         : in    std_logic;
    ready       : out   std_logic;
    DRAM_ADDR   : out   std_logic_vector(12 downto 0);
    DRAM_BA     : out   std_logic_vector(1 downto 0);
    DRAM_CAS_N  : out   std_logic;
    DRAM_CKE    : out   std_logic;
    DRAM_CLK    : out   std_logic;
    DRAM_CS_N   : out   std_logic;
    DRAM_DQ     : inout std_logic_vector(15 downto 0);
    DRAM_LDQM   : out   std_logic;
    DRAM_RAS_N  : out   std_logic;
    DRAM_UDQM   : out   std_logic;
    DRAM_WE_N   : out   std_logic
  );
end dram_controller;

architecture rtl of dram_controller is
  type state_t is (
    ST_INIT_WAIT,
    ST_INIT_PRECHARGE,
    ST_INIT_TRP,
    ST_INIT_AR1,
    ST_INIT_TRC1,
    ST_INIT_AR2,
    ST_INIT_TRC2,
    ST_INIT_MRS,
    ST_INIT_TMRD,
    ST_READY,
    ST_READ_ACT,
    ST_READ_TRCD,
    ST_READ_CAS,
    ST_READ_TRP,
    ST_WRITE_ACT,
    ST_WRITE_TRCD,
    ST_WRITE_TDPL,
    ST_WRITE_TRP,
    ST_REFRESH_CMD,
    ST_REFRESH_TRC
  );

  constant CMD_NOP_CS_N     : std_logic := '0';
  constant CMD_NOP_RAS_N    : std_logic := '1';
  constant CMD_NOP_CAS_N    : std_logic := '1';
  constant CMD_NOP_WE_N     : std_logic := '1';
  constant CMD_ACTIVE_RAS_N : std_logic := '0';
  constant CMD_ACTIVE_CAS_N : std_logic := '1';
  constant CMD_ACTIVE_WE_N  : std_logic := '1';
  constant CMD_READ_RAS_N   : std_logic := '1';
  constant CMD_READ_CAS_N   : std_logic := '0';
  constant CMD_READ_WE_N    : std_logic := '1';
  constant CMD_WRITE_RAS_N  : std_logic := '1';
  constant CMD_WRITE_CAS_N  : std_logic := '0';
  constant CMD_WRITE_WE_N   : std_logic := '0';
  constant CMD_PRE_RAS_N    : std_logic := '0';
  constant CMD_PRE_CAS_N    : std_logic := '1';
  constant CMD_PRE_WE_N     : std_logic := '0';
  constant CMD_AR_RAS_N     : std_logic := '0';
  constant CMD_AR_CAS_N     : std_logic := '0';
  constant CMD_AR_WE_N      : std_logic := '1';
  constant CMD_MRS_RAS_N    : std_logic := '0';
  constant CMD_MRS_CAS_N    : std_logic := '0';
  constant CMD_MRS_WE_N     : std_logic := '0';

  constant MODE_REG_VALUE : std_logic_vector(12 downto 0) := "0001001100000";

  signal state           : state_t := ST_INIT_WAIT;
  signal wait_counter    : natural range 0 to 65535 := 0;
  signal refresh_counter : natural range 0 to 65535 := 0;
  signal refresh_pending : std_logic := '0';

  signal buffered_req    : std_logic;
  signal buffered_wEn    : std_logic;
  signal buffered_addr   : std_logic_vector(25 downto 0);
  signal buffered_data   : std_logic_vector(7 downto 0);
  signal cmd_ack         : std_logic := '0';

  signal latched_addr    : std_logic_vector(25 downto 0) := (others => '0');
  signal latched_wdata   : std_logic_vector(7 downto 0)  := (others => '0');

  signal dq_out          : std_logic_vector(15 downto 0) := (others => '0');
  signal dq_oe           : std_logic := '0';
  signal addr_reg        : std_logic_vector(12 downto 0) := (others => '0');
  signal ba_reg          : std_logic_vector(1 downto 0)  := (others => '0');
  signal cs_n_reg        : std_logic := CMD_NOP_CS_N;
  signal ras_n_reg       : std_logic := CMD_NOP_RAS_N;
  signal cas_n_reg       : std_logic := CMD_NOP_CAS_N;
  signal we_n_reg        : std_logic := CMD_NOP_WE_N;

  function get_bank(addr : std_logic_vector(25 downto 0)) return std_logic_vector is
  begin
    return addr(25 downto 24);
  end function;

  function get_row(addr : std_logic_vector(25 downto 0)) return std_logic_vector is
  begin
    return addr(23 downto 11);
  end function;

  function get_col(addr : std_logic_vector(25 downto 0)) return std_logic_vector is
    variable col : std_logic_vector(12 downto 0);
  begin
    col := (others => '0');
    col(8 downto 0) := addr(10 downto 2);
    return col;
  end function;
begin
  reader_i : entity work.reader
    port map (
      clk         => clk,
      rst         => rst,
      req_in      => req,
      wEn_in      => wEn,
      addr_in     => address,
      data_in     => write_data,
      req_pending => buffered_req,
      wEn_out     => buffered_wEn,
      addr_out    => buffered_addr,
      data_out    => buffered_data,
      cmd_ack     => cmd_ack
    );

  ready <= '1' when state = ST_READY else '0';

  DRAM_ADDR  <= addr_reg;
  DRAM_BA    <= ba_reg;
  DRAM_CS_N  <= cs_n_reg;
  DRAM_RAS_N <= ras_n_reg;
  DRAM_CAS_N <= cas_n_reg;
  DRAM_WE_N  <= we_n_reg;
  DRAM_CKE   <= '1';
  DRAM_CLK   <= clk;
  DRAM_LDQM  <= '0';
  DRAM_UDQM  <= '0';
  DRAM_DQ    <= dq_out when dq_oe = '1' else (others => 'Z');

  process(clk, rst)
  begin
    if rst = '1' then
      state           <= ST_INIT_WAIT;
      wait_counter    <= G_INIT_WAIT_CYCLES;
      refresh_counter <= 0;
      refresh_pending <= '0';
      cmd_ack         <= '0';
      latched_addr    <= (others => '0');
      latched_wdata   <= (others => '0');
      read_data       <= (others => '0');
      dq_out          <= (others => '0');
      dq_oe           <= '0';
      addr_reg        <= (others => '0');
      ba_reg          <= (others => '0');
      cs_n_reg        <= CMD_NOP_CS_N;
      ras_n_reg       <= CMD_NOP_RAS_N;
      cas_n_reg       <= CMD_NOP_CAS_N;
      we_n_reg        <= CMD_NOP_WE_N;
    elsif rising_edge(clk) then
      cmd_ack   <= '0';
      cs_n_reg  <= CMD_NOP_CS_N;
      ras_n_reg <= CMD_NOP_RAS_N;
      cas_n_reg <= CMD_NOP_CAS_N;
      we_n_reg  <= CMD_NOP_WE_N;
      addr_reg  <= (others => '0');
      ba_reg    <= (others => '0');
      dq_oe     <= '0';

      if state = ST_READY then
        if refresh_counter >= (G_TREFI_CYCLES - 1) then
          refresh_counter <= 0;
          refresh_pending <= '1';
        else
          refresh_counter <= refresh_counter + 1;
        end if;
      end if;

      case state is
        when ST_INIT_WAIT =>
          if wait_counter = 0 then
            state <= ST_INIT_PRECHARGE;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_INIT_PRECHARGE =>
          ras_n_reg <= CMD_PRE_RAS_N;
          cas_n_reg <= CMD_PRE_CAS_N;
          we_n_reg  <= CMD_PRE_WE_N;
          addr_reg(10) <= '1';
          wait_counter <= G_TRP_CYCLES - 1;
          state <= ST_INIT_TRP;

        when ST_INIT_TRP =>
          if wait_counter = 0 then
            state <= ST_INIT_AR1;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_INIT_AR1 =>
          ras_n_reg <= CMD_AR_RAS_N;
          cas_n_reg <= CMD_AR_CAS_N;
          we_n_reg  <= CMD_AR_WE_N;
          wait_counter <= G_TRC_CYCLES - 1;
          state <= ST_INIT_TRC1;

        when ST_INIT_TRC1 =>
          if wait_counter = 0 then
            state <= ST_INIT_AR2;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_INIT_AR2 =>
          ras_n_reg <= CMD_AR_RAS_N;
          cas_n_reg <= CMD_AR_CAS_N;
          we_n_reg  <= CMD_AR_WE_N;
          wait_counter <= G_TRC_CYCLES - 1;
          state <= ST_INIT_TRC2;

        when ST_INIT_TRC2 =>
          if wait_counter = 0 then
            state <= ST_INIT_MRS;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_INIT_MRS =>
          ras_n_reg <= CMD_MRS_RAS_N;
          cas_n_reg <= CMD_MRS_CAS_N;
          we_n_reg  <= CMD_MRS_WE_N;
          addr_reg  <= MODE_REG_VALUE;
          ba_reg    <= "00";
          wait_counter <= G_TMRD_CYCLES - 1;
          state <= ST_INIT_TMRD;

        when ST_INIT_TMRD =>
          if wait_counter = 0 then
            state <= ST_READY;
            refresh_counter <= 0;
            refresh_pending <= '0';
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_READY =>
          if refresh_pending = '1' then
            refresh_pending <= '0';
            state <= ST_REFRESH_CMD;
          elsif buffered_req = '1' then
            cmd_ack       <= '1';
            latched_addr  <= buffered_addr;
            latched_wdata <= buffered_data;
            if buffered_wEn = '1' then
              state <= ST_WRITE_ACT;
            else
              state <= ST_READ_ACT;
            end if;
          end if;

        when ST_READ_ACT =>
          ras_n_reg <= CMD_ACTIVE_RAS_N;
          cas_n_reg <= CMD_ACTIVE_CAS_N;
          we_n_reg  <= CMD_ACTIVE_WE_N;
          ba_reg    <= get_bank(latched_addr);
          addr_reg  <= get_row(latched_addr);
          wait_counter <= G_TRCD_CYCLES - 1;
          state <= ST_READ_TRCD;

        when ST_READ_TRCD =>
          if wait_counter = 0 then
            ras_n_reg <= CMD_READ_RAS_N;
            cas_n_reg <= CMD_READ_CAS_N;
            we_n_reg  <= CMD_READ_WE_N;
            ba_reg    <= get_bank(latched_addr);
            addr_reg  <= get_col(latched_addr);
            wait_counter <= G_TCAS_CYCLES - 1;
            state <= ST_READ_CAS;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_READ_CAS =>
          if wait_counter = 0 then
            read_data <= DRAM_DQ(7 downto 0);
            ras_n_reg <= CMD_PRE_RAS_N;
            cas_n_reg <= CMD_PRE_CAS_N;
            we_n_reg  <= CMD_PRE_WE_N;
            addr_reg(10) <= '1';
            wait_counter <= G_TRP_CYCLES - 1;
            state <= ST_READ_TRP;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_READ_TRP =>
          if wait_counter = 0 then
            state <= ST_READY;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_WRITE_ACT =>
          ras_n_reg <= CMD_ACTIVE_RAS_N;
          cas_n_reg <= CMD_ACTIVE_CAS_N;
          we_n_reg  <= CMD_ACTIVE_WE_N;
          ba_reg    <= get_bank(latched_addr);
          addr_reg  <= get_row(latched_addr);
          wait_counter <= G_TRCD_CYCLES - 1;
          state <= ST_WRITE_TRCD;

        when ST_WRITE_TRCD =>
          if wait_counter = 0 then
            ras_n_reg <= CMD_WRITE_RAS_N;
            cas_n_reg <= CMD_WRITE_CAS_N;
            we_n_reg  <= CMD_WRITE_WE_N;
            ba_reg    <= get_bank(latched_addr);
            addr_reg  <= get_col(latched_addr);
            dq_out(7 downto 0)  <= latched_wdata;
            dq_out(15 downto 8) <= (others => '0');
            dq_oe <= '1';
            wait_counter <= G_TDPL_CYCLES - 1;
            state <= ST_WRITE_TDPL;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_WRITE_TDPL =>
          if wait_counter = 0 then
            ras_n_reg <= CMD_PRE_RAS_N;
            cas_n_reg <= CMD_PRE_CAS_N;
            we_n_reg  <= CMD_PRE_WE_N;
            addr_reg(10) <= '1';
            wait_counter <= G_TRP_CYCLES - 1;
            state <= ST_WRITE_TRP;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_WRITE_TRP =>
          if wait_counter = 0 then
            state <= ST_READY;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when ST_REFRESH_CMD =>
          ras_n_reg <= CMD_AR_RAS_N;
          cas_n_reg <= CMD_AR_CAS_N;
          we_n_reg  <= CMD_AR_WE_N;
          wait_counter <= G_TRC_CYCLES - 1;
          state <= ST_REFRESH_TRC;

        when ST_REFRESH_TRC =>
          if wait_counter = 0 then
            state <= ST_READY;
            refresh_counter <= 0;
          else
            wait_counter <= wait_counter - 1;
          end if;
      end case;
    end if;
  end process;
end rtl;
