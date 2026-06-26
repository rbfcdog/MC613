library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
-- NOTE: kept VHDL-2002 compatible on purpose so it elaborates both under
-- ghdl --std=08 AND under ModelSim-Altera (NativeLink RTL simulation, which
-- compiles VHDL as 2002 by default). Avoid 2008-only std.env.finish/to_hstring.

-- =============================================================================
--  Unit test (self-checking) for dram_controller.
--
--  It drives the iface-side handshake directly (req / wEn / addr_in / write_data)
--  and models a simplified behavioural SDRAM on the DRAM_* pins:
--    * DRAM_CLK = not clk          (the chip clock leads, like the board)
--    * CAS latency 3               (read data appears 3 SDRAM clocks later)
--    * tAC = 5.4 ns read access    (data is valid ~tAC after the clock edge)
--    * one open row per bank, storage indexed by bank/row/col
--    * DRAM_DQ is high-Z unless somebody must drive it
--
--  Test phases (visible on the waveform via `test_phase`):
--    INIT          -> controller runs its power-up sequence and raises ready
--    WRITE_A       -> WRITE 0x5A to address A
--    READ_A        -> READ A back, must return 0x5A
--    WRITE_B       -> WRITE 0x3C to address B
--    READ_B        -> READ B, must return 0x3C
--    READ_A_AGAIN  -> READ A, must STILL return 0x5A (addresses are independent)
--    REFRESH_TEST  -> left idle, the controller must issue AUTO REFRESH on its own
--    DONE
--
--  All the interesting internal state is exported as testbench signals so a
--  GHW/VCD dump tells the whole story without guessing.
-- =============================================================================
entity tb_dram_controller is
end tb_dram_controller;

architecture sim of tb_dram_controller is
  -- ---------------------------------------------------------------------------
  --  Timing constants (preserved from the original intent)
  -- ---------------------------------------------------------------------------
  constant CLK_PERIOD : time := 7 ns;     -- ~143 MHz
  constant TAC        : time := 5400 ps;  -- SDRAM read access time

  -- ---------------------------------------------------------------------------
  --  DUT handshake / data
  -- ---------------------------------------------------------------------------
  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal addr_in    : std_logic_vector(25 downto 0) := (others => '0');
  signal write_data : std_logic_vector(7 downto 0)  := (others => '0');
  signal read_data  : std_logic_vector(7 downto 0);
  signal req        : std_logic := '0';
  signal wEn        : std_logic := '0';
  signal ready      : std_logic;

  signal SW_tie  : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY_tie : std_logic_vector(3 downto 0) := (others => '1');

  -- ---------------------------------------------------------------------------
  --  DUT <-> SDRAM pins
  -- ---------------------------------------------------------------------------
  signal dram_cmd        : std_logic_vector(25 downto 0);   -- raw command word
  signal dram_write_data : std_logic_vector(7 downto 0);
  signal DRAM_DQ         : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_CLK        : std_logic;

  -- ---------------------------------------------------------------------------
  --  Behavioural SDRAM model state
  -- ---------------------------------------------------------------------------
  signal tb_dq_oe   : std_logic := '0';
  signal tb_dq_data : std_logic_vector(15 downto 0) := (others => '0');
  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  signal mem        : mem_t := (others => (others => '0'));
  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row   : row_t := (others => (others => '0'));

  -- Read CAS-latency pipeline (3 = CAS latency); exported for the waveform.
  signal read_pipeline_counter : integer range 0 to 8 := 0;
  signal rd_pending_data       : std_logic_vector(15 downto 0) := (others => '0');

  -- ---------------------------------------------------------------------------
  --  Raw command bits on the bus: {CS_N, RAS_N, CAS_N, WE_N} = dram_cmd(18..15)
  -- ---------------------------------------------------------------------------
  constant CMD_ACT  : std_logic_vector(3 downto 0) := "0011";  -- ACTIVATE
  constant CMD_READ : std_logic_vector(3 downto 0) := "0101";  -- READ
  constant CMD_WRIT : std_logic_vector(3 downto 0) := "0100";  -- WRITE
  constant CMD_AR   : std_logic_vector(3 downto 0) := "0001";  -- AUTO REFRESH
  signal bus_cmd : std_logic_vector(3 downto 0);

  -- ---------------------------------------------------------------------------
  --  Human-readable command + phase enumerations (show up nicely in GHW/GTKWave)
  -- ---------------------------------------------------------------------------
  type cmd_t is (
    CMD_NOP, CMD_ACTIVE, CMD_READ_E, CMD_WRITE_E,
    CMD_PRECHARGE, CMD_AUTO_REFRESH, CMD_LOAD_MODE, CMD_OTHER
  );
  type phase_t is (
    PH_INIT, PH_WRITE_A, PH_READ_A, PH_WRITE_B, PH_READ_B,
    PH_READ_A_AGAIN, PH_REFRESH_TEST, PH_DONE
  );
  -- Sequence-checker FSM: ACTIVATE -> READ/WRITE -> PRECHARGE per operation.
  type seq_t is (SEQ_IDLE, SEQ_ACTIVE, SEQ_ACCESS);

  signal dram_cmd_dec : cmd_t   := CMD_NOP;   -- decoded current command
  signal test_phase   : phase_t := PH_INIT;   -- current test phase ("op_name")
  signal seq_state    : seq_t   := SEQ_IDLE;
  signal prev_cmd_is_nop : boolean := true;   -- last sampled command was NOP

  -- ---------------------------------------------------------------------------
  --  Debug / observability signals
  -- ---------------------------------------------------------------------------
  signal init_done : std_logic := '0';   -- '1' once the controller first raised ready

  signal dq_model_drive : std_logic := '0';  -- model is driving DRAM_DQ (read data)
  signal dq_ctrl_drive  : std_logic := '0';  -- controller is driving DRAM_DQ (write data)

  signal model_read_data       : std_logic_vector(15 downto 0) := (others => '0');
  signal model_write_data_seen : std_logic_vector(15 downto 0) := (others => '0');

  signal last_addr : std_logic_vector(25 downto 0) := (others => '0');
  signal last_bank : std_logic_vector(1 downto 0)  := (others => '0');
  signal last_row  : std_logic_vector(12 downto 0) := (others => '0');
  signal last_col  : std_logic_vector(12 downto 0) := (others => '0');
  signal mem_index : integer range 0 to 1023 := 0;

  -- Command counters
  signal cmd_count   : integer := 0;
  signal n_activate  : integer := 0;
  signal n_read      : integer := 0;
  signal n_write     : integer := 0;
  signal n_precharge : integer := 0;
  signal n_refresh   : integer := 0;
  signal n_load_mode : integer := 0;

  signal test_done : boolean := false;

  -- ---------------------------------------------------------------------------
  --  Helpers
  -- ---------------------------------------------------------------------------
  -- Build a 26-bit logical address from row/bank/column fields.
  function make_addr(row, bank, col : integer) return std_logic_vector is
    variable a : std_logic_vector(25 downto 0) := (others => '0');
  begin
    a(25 downto 13) := std_logic_vector(to_unsigned(row, 13));
    a(12 downto 11) := std_logic_vector(to_unsigned(bank, 2));
    a(10 downto 1)  := std_logic_vector(to_unsigned(col, 10));
    return a;
  end function;

  -- Index the model the same way the controller addresses a cell.
  function mem_idx(bank_in, row_in, col_in : std_logic_vector) return integer is
    variable b : unsigned(1 downto 0)  := unsigned(bank_in);
    variable r : unsigned(12 downto 0) := unsigned(row_in);
    variable c : unsigned(12 downto 0) := unsigned(col_in);
  begin
    return to_integer(b & r(2 downto 0) & c(4 downto 0));
  end function;

  -- Decode {CS_N,RAS_N,CAS_N,WE_N} into a readable command.
  function decode_cmd(cmd_word : std_logic_vector(25 downto 0)) return cmd_t is
    variable code : std_logic_vector(3 downto 0);
  begin
    code := cmd_word(18 downto 15);
    if code(3) = '1' then            -- CS_N = 1 -> command inhibit (NOP)
      return CMD_NOP;
    end if;
    case code is
      when "0111" => return CMD_NOP;
      when "0011" => return CMD_ACTIVE;
      when "0101" => return CMD_READ_E;
      when "0100" => return CMD_WRITE_E;
      when "0010" => return CMD_PRECHARGE;
      when "0001" => return CMD_AUTO_REFRESH;
      when "0000" => return CMD_LOAD_MODE;
      when others => return CMD_OTHER;
    end case;
  end function;

  -- Hex string of a std_logic_vector (VHDL-2002 safe replacement for to_hstring).
  function to_hex(v : std_logic_vector) return string is
    constant nibbles : integer := (v'length + 3) / 4;
    variable padded  : std_logic_vector(nibbles * 4 - 1 downto 0) := (others => '0');
    variable result  : string(1 to nibbles);
    variable nyb     : integer;
    constant digits  : string(1 to 16) := "0123456789ABCDEF";
  begin
    padded(v'length - 1 downto 0) := v;
    for i in 0 to nibbles - 1 loop
      nyb := to_integer(unsigned(padded(i * 4 + 3 downto i * 4)));
      result(nibbles - i) := digits(nyb + 1);
    end loop;
    return result;
  end function;

  -- Does the vector contain any hard 'X' bit (bus contention)?
  function has_hard_x(v : std_logic_vector) return boolean is
  begin
    for i in v'range loop
      if v(i) = 'X' then
        return true;
      end if;
    end loop;
    return false;
  end function;

  constant ADDR_A : std_logic_vector(25 downto 0) := make_addr(1, 0, 5);
  constant ADDR_B : std_logic_vector(25 downto 0) := make_addr(2, 1, 7);
begin
  -- ---------------------------------------------------------------------------
  --  Clocks
  -- ---------------------------------------------------------------------------
  clk      <= not clk after CLK_PERIOD / 2;
  DRAM_CLK <= not clk;

  -- ---------------------------------------------------------------------------
  --  Combinational decoding / observability
  -- ---------------------------------------------------------------------------
  bus_cmd      <= dram_cmd(18) & dram_cmd(17) & dram_cmd(16) & dram_cmd(15);
  dram_cmd_dec <= decode_cmd(dram_cmd);

  dq_model_drive <= tb_dq_oe;
  dq_ctrl_drive  <= '1' when bus_cmd = CMD_WRIT else '0';

  -- Bidirectional DQ: the controller drives it during a WRITE; the model drives
  -- it during a READ (delayed by tAC); otherwise high-Z.
  DRAM_DQ <= tb_dq_data after TAC when tb_dq_oe = '1' else
             (x"00" & dram_write_data) when bus_cmd = CMD_WRIT else
             (others => 'Z');

  -- ---------------------------------------------------------------------------
  --  Bus-contention guards (must never fire with a correct controller/model)
  -- ---------------------------------------------------------------------------
  assert not (dq_model_drive = '1' and dq_ctrl_drive = '1')
    report "CONTENCAO: modelo e controlador dirigindo DRAM_DQ ao mesmo tempo"
    severity failure;

  assert not (init_done = '1' and has_hard_x(DRAM_DQ))
    report "CONTENCAO: DRAM_DQ em estado 'X'"
    severity failure;

  -- ---------------------------------------------------------------------------
  --  DUT
  -- ---------------------------------------------------------------------------
  dut : entity work.dram_controller
    -- Shorten only the power-up NOP wait so the waveform is readable from t=0
    -- instead of hiding all activity behind the real 28600-cycle (~200 us) init.
    -- Everything else (CAS latency, tAC capture, refresh interval) is unchanged.
    generic map (INIT_WAIT_CYCLES => 50)
    port map (
      clk => clk, rst => rst, SW => SW_tie, KEY => KEY_tie,
      data_in => DRAM_DQ(7 downto 0), write_data_in => write_data,
      data_out => read_data, HEX0 => open, HEX1 => open, HEX4 => open, HEX5 => open,
      adress => dram_cmd, addr_in => addr_in, write_data_out => dram_write_data,
      req => req, wEn => wEn, ready => ready);

  -- ---------------------------------------------------------------------------
  --  init_done latch: '1' once the controller first finishes its power-up.
  -- ---------------------------------------------------------------------------
  init_latch : process(clk)
  begin
    if rising_edge(clk) then
      if ready = '1' then
        init_done <= '1';
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  --  Behavioural SDRAM model
  --    latch the open row on ACTIVATE, store on WRITE, and on READ present the
  --    cell after the CAS latency (3 SDRAM clocks), data valid ~tAC later.
  -- ---------------------------------------------------------------------------
  sdram_model : process(DRAM_CLK)
    variable col : std_logic_vector(12 downto 0);
    variable bk  : integer;
    variable idx : integer;
    variable la  : std_logic_vector(25 downto 0);
  begin
    if rising_edge(DRAM_CLK) then
      tb_dq_oe <= '0';

      -- CAS-latency read pipeline.
      if read_pipeline_counter > 0 then
        read_pipeline_counter <= read_pipeline_counter - 1;
        if read_pipeline_counter = 1 then
          tb_dq_data <= rd_pending_data;
          tb_dq_oe   <= '1';
        end if;
      end if;

      bk  := to_integer(unsigned(dram_cmd(14 downto 13)));
      col := dram_cmd(12 downto 0);
      last_bank <= dram_cmd(14 downto 13);

      case bus_cmd is
        when CMD_ACT =>
          open_row(bk) <= dram_cmd(12 downto 0);
          last_row     <= dram_cmd(12 downto 0);

        when CMD_WRIT =>
          idx := mem_idx(dram_cmd(14 downto 13), open_row(bk), col);
          mem(idx)              <= DRAM_DQ;
          model_write_data_seen <= DRAM_DQ;
          last_col              <= col;
          mem_index             <= idx;
          la := (others => '0');
          la(25 downto 13) := open_row(bk);
          la(12 downto 11) := dram_cmd(14 downto 13);
          la(10 downto 1)  := col(9 downto 0);
          last_addr <= la;

        when CMD_READ =>
          idx := mem_idx(dram_cmd(14 downto 13), open_row(bk), col);
          rd_pending_data       <= mem(idx);
          model_read_data       <= mem(idx);
          read_pipeline_counter <= 3;          -- CAS latency
          last_col              <= col;
          mem_index             <= idx;
          la := (others => '0');
          la(25 downto 13) := open_row(bk);
          la(12 downto 11) := dram_cmd(14 downto 13);
          la(10 downto 1)  := col(9 downto 0);
          last_addr <= la;

        when others => null;
      end case;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  --  Command monitor: counts commands and checks ordering.
  --    Commands are 1-cycle pulses separated by NOP, so a new command is the
  --    edge where the decoded command becomes meaningful after a NOP.
  --    Sampled on rising DRAM_CLK, where the command word is stable.
  -- ---------------------------------------------------------------------------
  monitor : process(DRAM_CLK)
    variable c : cmd_t;
  begin
    if rising_edge(DRAM_CLK) then
      c := dram_cmd_dec;

      if c /= CMD_NOP and c /= CMD_OTHER and prev_cmd_is_nop then
        cmd_count <= cmd_count + 1;
        case c is
          when CMD_ACTIVE       => n_activate  <= n_activate  + 1;
          when CMD_READ_E       => n_read      <= n_read      + 1;
          when CMD_WRITE_E      => n_write     <= n_write     + 1;
          when CMD_PRECHARGE    => n_precharge <= n_precharge + 1;
          when CMD_AUTO_REFRESH => n_refresh   <= n_refresh   + 1;
          when CMD_LOAD_MODE    => n_load_mode <= n_load_mode + 1;
          when others           => null;
        end case;

        -- Sequence checks apply only to operational commands (after INIT).
        if init_done = '1' then
          case c is
            when CMD_ACTIVE =>
              assert seq_state = SEQ_IDLE
                report "SEQUENCIA: ACTIVATE fora de ordem (PRECHARGE faltando apos READ/WRITE?)"
                severity failure;
              seq_state <= SEQ_ACTIVE;

            when CMD_READ_E | CMD_WRITE_E =>
              assert seq_state = SEQ_ACTIVE
                report "SEQUENCIA: READ/WRITE sem ACTIVATE previo"
                severity failure;
              seq_state <= SEQ_ACCESS;

            when CMD_PRECHARGE =>
              -- Ends an access, or is the PRECHARGE-ALL before an auto refresh.
              seq_state <= SEQ_IDLE;

            when CMD_AUTO_REFRESH =>
              assert seq_state = SEQ_IDLE
                report "SEQUENCIA: AUTO REFRESH fora de ordem"
                severity failure;
              seq_state <= SEQ_IDLE;

            when others => null;
          end case;
        end if;
      end if;

      if c = CMD_NOP then
        prev_cmd_is_nop <= true;
      else
        prev_cmd_is_nop <= false;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  --  Watchdog: the whole test must complete well inside the run window.
  -- ---------------------------------------------------------------------------
  watchdog : process
  begin
    wait for 450 us;
    assert test_done
      report "TIMEOUT: o testbench nao concluiu dentro do tempo esperado"
      severity failure;
    wait;
  end process;

  -- ---------------------------------------------------------------------------
  --  Stimulus / scoreboard
  -- ---------------------------------------------------------------------------
  stim : process
    -- Issue one operation following the full handshake protocol:
    --   set inputs -> pulse req -> wait ready='0' (controller accepted the op)
    --   -> wait ready='1' (operation finished) -> data is then valid.
    -- Waiting only for ready='1' would be ambiguous with the previous idle
    -- state, so we explicitly observe the falling edge first.
    procedure dram_op(is_write : std_logic;
                      addr     : std_logic_vector(25 downto 0);
                      data     : std_logic_vector(7 downto 0)) is
    begin
      -- Make sure we start from a clean idle/ready state.
      if ready /= '1' then
        wait until ready = '1';
      end if;
      addr_in    <= addr;
      write_data <= data;
      wEn        <= is_write;
      req        <= '1';
      wait until rising_edge(clk);
      req <= '0';
      wait until ready = '0';   -- controller left st_ready: the op was accepted
      wait until ready = '1';   -- controller is back in st_ready: op finished
      wait until rising_edge(clk);  -- let read_data settle
    end procedure;

    variable cyc       : integer;
    variable refresh_0 : integer;
  begin
    -- Reset.
    test_phase <= PH_INIT;
    rst <= '1';
    wait for 4 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    report "INIT: reset liberado, aguardando inicializacao do controlador" severity note;

    -- 1) INIT: the controller must finish initialising and raise ready.
    cyc := 0;
    while ready = '0' loop
      wait until rising_edge(clk);
      cyc := cyc + 1;
      assert cyc < 40000
        report "INIT nunca terminou (ready preso em 0)" severity failure;
    end loop;
    report "INIT: ready subiu apos " & integer'image(cyc) & " ciclos" severity note;

    -- The init sequence must have issued PRECHARGE-ALL, 8 AUTO REFRESH and the
    -- LOAD MODE REGISTER command before going ready.
    assert n_precharge >= 1
      report "INIT: nenhum PRECHARGE emitido na inicializacao" severity failure;
    assert n_refresh >= 8
      report "INIT: menos de 8 AUTO REFRESH na inicializacao (n_refresh=" &
             integer'image(n_refresh) & ")" severity failure;
    assert n_load_mode = 1
      report "INIT: LOAD MODE REGISTER nao foi emitido exatamente uma vez (n_load_mode=" &
             integer'image(n_load_mode) & ")" severity failure;
    report "INIT: comandos de inicializacao OK (precharge/refresh/load-mode)" severity note;

    -- 2) WRITE then READ the same address.
    test_phase <= PH_WRITE_A;
    report "WRITE_A: escrevendo 0x5A em A" severity note;
    dram_op('1', ADDR_A, x"5A");

    test_phase <= PH_READ_A;
    report "READ_A: lendo A" severity note;
    dram_op('0', ADDR_A, x"00");
    assert read_data = x"5A"
      report "READ de A nao retornou o valor escrito (leu 0x" &
             to_hex(read_data) & ", esperado 0x5A)" severity failure;
    report "READ_A: OK (0x" & to_hex(read_data) & ")" severity note;

    -- 3) A second address is independent, and A keeps its value.
    test_phase <= PH_WRITE_B;
    report "WRITE_B: escrevendo 0x3C em B" severity note;
    dram_op('1', ADDR_B, x"3C");

    test_phase <= PH_READ_B;
    report "READ_B: lendo B" severity note;
    dram_op('0', ADDR_B, x"00");
    assert read_data = x"3C"
      report "READ de B incorreto (leu 0x" & to_hex(read_data) &
             ", esperado 0x3C)" severity failure;
    report "READ_B: OK (0x" & to_hex(read_data) & ")" severity note;

    test_phase <= PH_READ_A_AGAIN;
    report "READ_A_AGAIN: relendo A para checar independencia" severity note;
    dram_op('0', ADDR_A, x"00");
    assert read_data = x"5A"
      report "A perdeu o valor apos escrever B (leu 0x" & to_hex(read_data) &
             ", esperado 0x5A)" severity failure;
    report "READ_A_AGAIN: OK, A manteve 0x" & to_hex(read_data) severity note;

    -- 4) Auto refresh must happen on its own while idle.
    test_phase <= PH_REFRESH_TEST;
    report "REFRESH_TEST: aguardando AUTO REFRESH espontaneo" severity note;
    refresh_0 := n_refresh;
    cyc := 0;
    while n_refresh = refresh_0 loop
      wait until rising_edge(clk);
      cyc := cyc + 1;
      assert cyc < 4000
        report "AUTO REFRESH nunca foi emitido durante o periodo ocioso" severity failure;
    end loop;
    report "REFRESH_TEST: AUTO REFRESH detectado apos " & integer'image(cyc) &
           " ciclos ociosos" severity note;

    -- Done.
    test_phase <= PH_DONE;
    test_done  <= true;
    report "tb_dram_controller: todos os cenarios passaram" severity note;
    report "Resumo de comandos -> ACT=" & integer'image(n_activate) &
           " READ=" & integer'image(n_read) &
           " WRITE=" & integer'image(n_write) &
           " PRECHARGE=" & integer'image(n_precharge) &
           " REFRESH=" & integer'image(n_refresh) &
           " LOAD_MODE=" & integer'image(n_load_mode) &
           " (total=" & integer'image(cmd_count) & ")" severity note;
    -- Stop the stimulus. The clocks keep toggling; the run is bounded by the
    -- simulator (ghdl --stop-time / ModelSim run length), which keeps this
    -- testbench compatible with both ghdl and ModelSim-Altera default VHDL.
    wait;
  end process;
end sim;
