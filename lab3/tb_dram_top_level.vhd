library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- =============================================================================
--  Integration test (self-checking) for dram_top_level.
--
--  Exercises the WHOLE board the way a user would: it drives only CLOCK_50, the
--  switches (SW) and the push-buttons (KEY) -- never req/ready/internal signals.
--  It models the real SDRAM on the DRAM_* pins (one open row per bank, storage
--  by bank/row/col, CAS latency 3, tAC read access) and checks the digit shown
--  on HEX1.
--
--  Path under test:  user (SW/KEY) -> dram_iface -> dram_controller -> SDRAM
--                    model -> read data -> HEX1 display.
--
--  Story (visible on the waveform via `test_phase`):
--    RESET            -> hold KEY0, wait for PLL lock, release reset
--    INIT             -> controller runs the SDRAM power-up (PRECHARGE, 8x
--                        AUTO REFRESH, LOAD MODE) and the iface auto-clears addr 0
--    WRITE_7_ADDR1    -> select address 1, data 7, press KEY3 -> WRITE + read-back
--    READ_ADDR2       -> select address 2 (never written) -> HEX1 must show 0
--    READ_ADDR1_AGAIN -> back to address 1 -> HEX1 must STILL show 7 (persistence)
--    REFRESH_TEST     -> left idle, the controller must issue AUTO REFRESH alone
--    DONE
--
--  Kept VHDL-2002 compatible so it elaborates both under ghdl --std=08 AND under
--  ModelSim-Altera (Quartus NativeLink RTL simulation, which compiles VHDL as
--  2002 by default). It therefore does NOT use VHDL-2008 external names: the
--  PLL's internal pll_clk / pll_locked are observable directly under the `dut`
--  hierarchy in GTKWave / ModelSim, and init success is proven by waiting for
--  the LOAD MODE REGISTER command instead of polling `locked`.
--
--  NOTE ON TIMING / "looks stuck": the SDRAM power-up wait is ~28600 controller
--  cycles. At the 143 MHz PLL clock that is ~200 us during which the bus is
--  legitimately NOP and `ready` stays 0 -- the design is initialising, not
--  wedged. The interesting commands and the HEX1 changes happen AFTER ~200 us.
-- =============================================================================
entity tb_dram_top_level is
end tb_dram_top_level;

architecture sim of tb_dram_top_level is
  -- ---------------------------------------------------------------------------
  --  Constants
  -- ---------------------------------------------------------------------------
  constant CLK50_PERIOD : time := 20 ns;     -- 50 MHz board clock (CLOCK_50)
  constant TAC          : time := 5400 ps;   -- SDRAM read access time

  -- ---------------------------------------------------------------------------
  --  Board pins (the only things the test is allowed to drive)
  -- ---------------------------------------------------------------------------
  signal CLOCK_50 : std_logic := '0';
  signal SW       : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY      : std_logic_vector(3 downto 0) := (others => '1');  -- buttons idle high
  signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(6 downto 0);

  signal DRAM_ADDR  : std_logic_vector(12 downto 0);
  signal DRAM_BA    : std_logic_vector(1 downto 0);
  signal DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N : std_logic;
  signal DRAM_DQ    : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_LDQM, DRAM_RAS_N, DRAM_UDQM, DRAM_WE_N : std_logic;

  -- ---------------------------------------------------------------------------
  --  Behavioural SDRAM model state
  -- ---------------------------------------------------------------------------
  signal tb_dq_oe   : std_logic := '0';
  signal tb_dq_data : std_logic_vector(15 downto 0) := (others => '0');
  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  signal mem      : mem_t := (others => (others => '0'));
  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row : row_t := (others => (others => '0'));
  signal read_pipeline_counter : integer range 0 to 8 := 0;
  signal rd_pending_data       : std_logic_vector(15 downto 0) := (others => '0');

  -- ---------------------------------------------------------------------------
  --  Raw command bits {CS_N,RAS_N,CAS_N,WE_N} for the model (vector form)
  -- ---------------------------------------------------------------------------
  constant CMD_ACT  : std_logic_vector(3 downto 0) := "0011";  -- ACTIVE
  constant CMD_READ : std_logic_vector(3 downto 0) := "0101";  -- READ
  constant CMD_WRIT : std_logic_vector(3 downto 0) := "0100";  -- WRITE
  signal bus_cmd : std_logic_vector(3 downto 0);

  -- ---------------------------------------------------------------------------
  --  Readable command + phase enumerations (render as text in GHW/GTKWave)
  -- ---------------------------------------------------------------------------
  type cmd_t is (
    CMD_DESELECT, CMD_NOP, CMD_ACTIVE, CMD_READ_E, CMD_WRITE_E,
    CMD_PRECHARGE, CMD_AUTO_REFRESH, CMD_LOAD_MODE, CMD_OTHER
  );
  type phase_t is (
    PH_RESET, PH_INIT, PH_WRITE_7_ADDR1, PH_READ_ADDR2,
    PH_READ_ADDR1_AGAIN, PH_REFRESH_TEST, PH_DONE
  );

  signal cur_cmd    : cmd_t   := CMD_OTHER;   -- decoded command on the pins now
  signal last_cmd   : cmd_t   := CMD_NOP;     -- last meaningful command seen
  signal test_phase : phase_t := PH_RESET;
  signal prev_idle  : boolean := true;        -- last sample was NOP/DESELECT


  -- ---------------------------------------------------------------------------
  --  Display observability
  -- ---------------------------------------------------------------------------
  signal expected_hex1       : std_logic_vector(6 downto 0) := (others => '1');
  signal expected_digit      : std_logic_vector(3 downto 0) := (others => '0');
  signal observed_digit_hex1 : std_logic_vector(3 downto 0) := (others => '0');
  signal display_ok          : std_logic := '0';

  -- ---------------------------------------------------------------------------
  --  Command counters / activity flags
  -- ---------------------------------------------------------------------------
  signal cmd_count      : integer := 0;
  signal n_active       : integer := 0;
  signal n_read         : integer := 0;
  signal n_write        : integer := 0;
  signal n_precharge    : integer := 0;
  signal n_auto_refresh : integer := 0;
  signal n_load_mode    : integer := 0;

  signal init_seen    : std_logic := '0';
  signal write_seen   : std_logic := '0';
  signal read_seen    : std_logic := '0';
  signal refresh_seen : std_logic := '0';

  -- ---------------------------------------------------------------------------
  --  Model bus / address observability
  -- ---------------------------------------------------------------------------
  signal model_dq_drive        : std_logic := '0';   -- model is driving DRAM_DQ
  signal read_pipeline_valid   : std_logic := '0';   -- a read is in the CAS pipeline
  signal model_read_data       : std_logic_vector(15 downto 0) := (others => '0');
  signal model_write_data_seen : std_logic_vector(15 downto 0) := (others => '0');
  signal last_bank : std_logic_vector(1 downto 0)  := (others => '0');
  signal last_row  : std_logic_vector(12 downto 0) := (others => '0');
  signal last_col  : std_logic_vector(12 downto 0) := (others => '0');
  signal last_addr : std_logic_vector(25 downto 0) := (others => '0');
  signal mem_idx   : integer range 0 to 1023 := 0;

  signal test_done : boolean := false;

  -- ---------------------------------------------------------------------------
  --  Helpers
  -- ---------------------------------------------------------------------------
  -- Seven-segment encoder, identical to the one in dram_iface.
  function hex7(v : std_logic_vector(3 downto 0)) return std_logic_vector is
  begin
    case v is
      when "0000" => return "1000000"; when "0001" => return "1111001";
      when "0010" => return "0100100"; when "0011" => return "0110000";
      when "0100" => return "0011001"; when "0101" => return "0010010";
      when "0110" => return "0000010"; when "0111" => return "1111000";
      when "1000" => return "0000000"; when "1001" => return "0010000";
      when "1010" => return "0001000"; when "1011" => return "0000011";
      when "1100" => return "1000110"; when "1101" => return "0100001";
      when "1110" => return "0000110"; when others => return "0001110";
    end case;
  end function;

  -- Inverse: which digit is HEX1 displaying (best effort; unknown -> 0xF).
  function decode_hex7(seg : std_logic_vector(6 downto 0)) return std_logic_vector is
  begin
    case seg is
      when "1000000" => return "0000"; when "1111001" => return "0001";
      when "0100100" => return "0010"; when "0110000" => return "0011";
      when "0011001" => return "0100"; when "0010010" => return "0101";
      when "0000010" => return "0110"; when "1111000" => return "0111";
      when "0000000" => return "1000"; when "0010000" => return "1001";
      when "0001000" => return "1010"; when "0000011" => return "1011";
      when "1000110" => return "1100"; when "0100001" => return "1101";
      when "0000110" => return "1110"; when others => return "1111";
    end case;
  end function;

  -- Index the model the same way the controller addresses a cell.
  function calc_mem_idx(bank_in, row_in, col_in : std_logic_vector) return integer is
    variable b : unsigned(1 downto 0)  := unsigned(bank_in);
    variable r : unsigned(12 downto 0) := unsigned(row_in);
    variable c : unsigned(12 downto 0) := unsigned(col_in);
  begin
    return to_integer(b & r(2 downto 0) & c(4 downto 0));
  end function;

  -- Decode {CS_N,RAS_N,CAS_N,WE_N} into a readable command (JEDEC table).
  function decode_cmd(cs, ras, cas, we : std_logic) return cmd_t is
    variable v : std_logic_vector(3 downto 0);
  begin
    if cs = '1' then
      return CMD_DESELECT;
    end if;
    v := cs & ras & cas & we;
    case v is
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

  -- Any hard 'X' bit (bus contention)?
  function has_x(v : std_logic_vector) return boolean is
  begin
    for i in v'range loop
      if v(i) = 'X' then
        return true;
      end if;
    end loop;
    return false;
  end function;
begin
  -- ---------------------------------------------------------------------------
  --  Board clock
  -- ---------------------------------------------------------------------------
  CLOCK_50 <= not CLOCK_50 after CLK50_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  --  Combinational decoding / observability
  -- ---------------------------------------------------------------------------
  bus_cmd <= DRAM_CS_N & DRAM_RAS_N & DRAM_CAS_N & DRAM_WE_N;
  cur_cmd <= decode_cmd(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

  model_dq_drive      <= tb_dq_oe;
  read_pipeline_valid <= '1' when read_pipeline_counter > 0 else '0';
  observed_digit_hex1 <= decode_hex7(HEX1);
  display_ok          <= '1' when HEX1 = expected_hex1 else '0';

  -- ---------------------------------------------------------------------------
  --  Bus-contention guards (must never fire with a correct design/model)
  -- ---------------------------------------------------------------------------
  -- The DUT drives DRAM_DQ only during WRITE; the model only during a read.
  assert not (model_dq_drive = '1' and bus_cmd = CMD_WRIT)
    report "CONTENCAO: modelo dirige DRAM_DQ durante um WRITE" severity failure;
  assert not (init_seen = '1' and has_x(DRAM_DQ))
    report "CONTENCAO: DRAM_DQ em estado 'X'" severity failure;

  -- The model drives the bus only during a read (delayed by tAC); otherwise the
  -- DUT owns it (write) or it floats high-Z.
  DRAM_DQ <= tb_dq_data after TAC when tb_dq_oe = '1' else (others => 'Z');

  -- ---------------------------------------------------------------------------
  --  DUT
  -- ---------------------------------------------------------------------------
  dut : entity work.dram_top_level
    -- Shorten only the SDRAM power-up NOP wait so all activity is visible from
    -- t=0 instead of after the real ~200 us init. Synthesis uses the default.
    generic map (INIT_WAIT_CYCLES => 50)
    port map (
      CLOCK_50 => CLOCK_50, SW => SW, KEY => KEY,
      HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2, HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5,
      DRAM_ADDR => DRAM_ADDR, DRAM_BA => DRAM_BA, DRAM_CAS_N => DRAM_CAS_N,
      DRAM_CKE => DRAM_CKE, DRAM_CLK => DRAM_CLK, DRAM_CS_N => DRAM_CS_N,
      DRAM_DQ => DRAM_DQ, DRAM_LDQM => DRAM_LDQM, DRAM_RAS_N => DRAM_RAS_N,
      DRAM_UDQM => DRAM_UDQM, DRAM_WE_N => DRAM_WE_N);

  -- ---------------------------------------------------------------------------
  --  Behavioural SDRAM model (clocked on the chip clock the top level drives).
  -- ---------------------------------------------------------------------------
  sdram_model : process(DRAM_CLK)
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

      bk := to_integer(unsigned(DRAM_BA));
      last_bank <= DRAM_BA;

      case bus_cmd is
        when CMD_ACT =>
          open_row(bk) <= DRAM_ADDR;
          last_row     <= DRAM_ADDR;

        when CMD_WRIT =>
          idx := calc_mem_idx(DRAM_BA, open_row(bk), DRAM_ADDR);
          mem(idx)              <= DRAM_DQ;
          model_write_data_seen <= DRAM_DQ;
          last_col              <= DRAM_ADDR;
          mem_idx               <= idx;
          la := (others => '0');
          la(25 downto 13) := open_row(bk);
          la(12 downto 11) := DRAM_BA;
          la(10 downto 1)  := DRAM_ADDR(9 downto 0);
          last_addr <= la;

        when CMD_READ =>
          idx := calc_mem_idx(DRAM_BA, open_row(bk), DRAM_ADDR);
          rd_pending_data       <= mem(idx);
          model_read_data       <= mem(idx);
          read_pipeline_counter <= 3;          -- CAS latency
          last_col              <= DRAM_ADDR;
          mem_idx               <= idx;
          la := (others => '0');
          la(25 downto 13) := open_row(bk);
          la(12 downto 11) := DRAM_BA;
          la(10 downto 1)  := DRAM_ADDR(9 downto 0);
          last_addr <= la;

        when others => null;
      end case;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  --  Command monitor: count commands, latch last_cmd, raise activity flags.
  --  Commands are 1-cycle pulses separated by NOP, so a "new" command is the
  --  first sample that is meaningful after an idle (NOP/DESELECT) sample.
  -- ---------------------------------------------------------------------------
  monitor : process(DRAM_CLK)
    variable c : cmd_t;
  begin
    if rising_edge(DRAM_CLK) then
      c := cur_cmd;
      if c /= CMD_NOP and c /= CMD_DESELECT and c /= CMD_OTHER and prev_idle then
        cmd_count <= cmd_count + 1;
        last_cmd  <= c;
        case c is
          when CMD_ACTIVE       => n_active       <= n_active + 1;
          when CMD_READ_E       => n_read         <= n_read + 1;        read_seen    <= '1';
          when CMD_WRITE_E      => n_write        <= n_write + 1;       write_seen   <= '1';
          when CMD_PRECHARGE    => n_precharge    <= n_precharge + 1;
          when CMD_AUTO_REFRESH => n_auto_refresh <= n_auto_refresh + 1; refresh_seen <= '1';
          when CMD_LOAD_MODE    => n_load_mode    <= n_load_mode + 1;   init_seen    <= '1';
          when others           => null;
        end case;
      end if;

      if c = CMD_NOP or c = CMD_DESELECT then
        prev_idle <= true;
      else
        prev_idle <= false;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  --  Watchdog: the whole test must finish well inside the run window.
  -- ---------------------------------------------------------------------------
  watchdog : process
  begin
    wait for 1100 us;
    assert test_done
      report "TIMEOUT: o testbench nao concluiu dentro do tempo esperado" severity failure;
    wait;
  end process;

  -- ---------------------------------------------------------------------------
  --  Stimulus / scoreboard (drives ONLY CLOCK_50/SW/KEY)
  -- ---------------------------------------------------------------------------
  stim : process
    -- Press a push-button (active low) for `dur`, then release and settle.
    procedure press_key(constant k : integer; constant dur : time) is
    begin
      KEY(k) <= '0';
      wait for dur;
      KEY(k) <= '1';
      wait for dur;
    end procedure;

    -- Select the 6-bit address shown on the address display (SW[9:4]).
    procedure set_addr(constant addr6 : std_logic_vector(5 downto 0)) is
    begin
      SW(9 downto 4) <= addr6;
    end procedure;

    -- Set the 4-bit data nibble (SW[3:0]).
    procedure set_data(constant data4 : std_logic_vector(3 downto 0)) is
    begin
      SW(3 downto 0) <= data4;
    end procedure;

    -- Wait for a specific SDRAM command, with a timeout that fails loudly.
    procedure wait_cmd(constant want : cmd_t; constant tmo : time) is
    begin
      if cur_cmd /= want then
        wait until cur_cmd = want for tmo;
      end if;
      assert cur_cmd = want
        report "TIMEOUT esperando " & cmd_t'image(want) &
               " (fase " & phase_t'image(test_phase) & ")" severity failure;
    end procedure;

    -- Wait for HEX1 to show `dig`, hold it stable, then assert.
    procedure wait_display(constant dig : std_logic_vector(3 downto 0);
                           constant tmo : time) is
    begin
      expected_digit <= dig;
      expected_hex1  <= hex7(dig);
      if HEX1 /= hex7(dig) then
        wait until HEX1 = hex7(dig) for tmo;
      end if;
      assert HEX1 = hex7(dig)
        report "DISPLAY: HEX1 errado na fase " & phase_t'image(test_phase) &
               " -- esperado digito 0x" & integer'image(to_integer(unsigned(dig))) &
               ", observado 0x" & integer'image(to_integer(unsigned(decode_hex7(HEX1))))
        severity failure;
      -- Require the digit to remain stable for a few microseconds.
      wait for 2 us;
      assert HEX1 = hex7(dig)
        report "DISPLAY: HEX1 instavel na fase " & phase_t'image(test_phase)
        severity failure;
    end procedure;

    -- User writes `data4` to `addr6`: select it, press KEY3 and catch the WRITE
    -- WHILE the button is held (the write is issued ~1 us after the press, so we
    -- must wait for it before releasing), then catch the automatic read-back.
    procedure user_write(constant addr6 : std_logic_vector(5 downto 0);
                         constant data4 : std_logic_vector(3 downto 0)) is
    begin
      set_addr(addr6);
      set_data(data4);
      wait for 3 us;                  -- let the auto-read of the new address settle
      KEY(3) <= '0';                  -- press KEY[3]
      wait_cmd(CMD_WRITE_E, 80 us);   -- the write is issued while held
      wait_cmd(CMD_READ_E, 80 us);    -- followed by the automatic read-back
      KEY(3) <= '1';                  -- release (edge-triggered, no extra write)
      wait for 2 us;
    end procedure;

    -- User just selects an address (data nibble forced to 0 to prove the display
    -- shows STORED data, not the switches): triggers an automatic read. Wait for
    -- the READ immediately so the short read pulse is not missed.
    procedure user_select_addr(constant addr6 : std_logic_vector(5 downto 0)) is
    begin
      set_addr(addr6);
      set_data("0000");
      wait_cmd(CMD_READ_E, 80 us);
    end procedure;

    variable ref0 : integer;
  begin
    report "tb_dram_top_level: inicio do teste de integracao" severity note;

    -- ---- RESET ------------------------------------------------------------
    test_phase <= PH_RESET;
    SW  <= (others => '0');
    KEY <= (others => '1');
    KEY(0) <= '0';                              -- assert board reset (active low button)

    -- Hold reset long enough for the PLL to lock. The DUT's reset path is gated
    -- by PLL lock internally (async_rst = board_rst OR not pll_locked), so the
    -- logic stays in reset until the clock is stable regardless of this hold.
    -- (pll_locked / pll_clk are visible under the `dut` hierarchy in the wave.)
    report "Reset aplicado, aguardando PLL" severity note;
    wait for 5 us;
    KEY(0) <= '1';                              -- release reset
    report "Reset liberado" severity note;

    -- ---- INIT -------------------------------------------------------------
    test_phase <= PH_INIT;
    -- LOAD MODE REGISTER is the last init command -> its arrival proves init ran.
    wait_cmd(CMD_LOAD_MODE, 400 us);
    assert n_auto_refresh >= 8
      report "INIT: menos de 8 AUTO REFRESH na inicializacao (n_auto_refresh=" &
             integer'image(n_auto_refresh) & ")" severity failure;
    report "INIT detectado (LOAD MODE emitido apos " &
           integer'image(n_auto_refresh) & " auto-refresh)" severity note;

    -- After init the iface auto-clears the current address (write 0 + read-back).
    wait_cmd(CMD_WRITE_E, 100 us);
    wait_display("0000", 100 us);
    report "Pos-init: endereco 0 zerado, HEX1 mostra 0" severity note;

    -- ---- WRITE 7 @ address 1 ---------------------------------------------
    test_phase <= PH_WRITE_7_ADDR1;
    report "Escrevendo 7 no endereco 1 (KEY[3])" severity note;
    user_write("000001", "0111");
    wait_display("0111", 100 us);
    report "Leitura do endereco 1: HEX1 mostra 7" severity note;

    -- ---- READ untouched address 2 ----------------------------------------
    test_phase <= PH_READ_ADDR2;
    report "Lendo endereco 2 (nunca escrito)" severity note;
    user_select_addr("000010");
    wait_display("0000", 100 us);
    report "Leitura do endereco 2: HEX1 mostra 0" severity note;

    -- ---- BACK to address 1 (persistence) ---------------------------------
    test_phase <= PH_READ_ADDR1_AGAIN;
    report "Voltando ao endereco 1" severity note;
    user_select_addr("000001");
    wait_display("0111", 100 us);
    report "Endereco 1 persistiu: HEX1 mostra 7 novamente" severity note;

    -- ---- AUTO REFRESH while idle -----------------------------------------
    test_phase <= PH_REFRESH_TEST;
    report "Aguardando AUTO REFRESH espontaneo" severity note;
    ref0 := n_auto_refresh;
    wait until n_auto_refresh > ref0 for 100 us;
    assert n_auto_refresh > ref0
      report "AUTO REFRESH nunca foi emitido durante o periodo ocioso" severity failure;
    report "AUTO REFRESH detectado" severity note;

    -- ---- DONE -------------------------------------------------------------
    test_phase <= PH_DONE;
    test_done  <= true;
    report "tb_dram_top_level: todos os cenarios passaram" severity note;
    report "Resumo de comandos -> ACT=" & integer'image(n_active) &
           " READ=" & integer'image(n_read) &
           " WRITE=" & integer'image(n_write) &
           " PRECHARGE=" & integer'image(n_precharge) &
           " AUTO_REFRESH=" & integer'image(n_auto_refresh) &
           " LOAD_MODE=" & integer'image(n_load_mode) &
           " (total=" & integer'image(cmd_count) & ")" severity note;
    wait;
  end process;
end sim;
