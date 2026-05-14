library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_dram_system is
end tb_dram_system;

architecture sim of tb_dram_system is
  constant CLK_PERIOD : time := 10 ns;

  constant C_INIT_WAIT : integer := 2;
  constant C_TRCD      : integer := 2;
  constant C_TCAS      : integer := 3;
  constant C_TRP       : integer := 2;
  constant C_TDPL      : integer := 2;
  constant C_TRC       : integer := 4;
  constant C_TMRD      : integer := 2;
  constant C_TREFI     : integer := 24;

  constant CMD_NOP : std_logic_vector(3 downto 0) := "0111";
  constant CMD_ACT : std_logic_vector(3 downto 0) := "0011";
  constant CMD_READ: std_logic_vector(3 downto 0) := "0101";
  constant CMD_WRIT: std_logic_vector(3 downto 0) := "0100";
  constant CMD_PRE : std_logic_vector(3 downto 0) := "0010";
  constant CMD_AR  : std_logic_vector(3 downto 0) := "0001";
  constant CMD_MRS : std_logic_vector(3 downto 0) := "0000";

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal SW          : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY         : std_logic_vector(3 downto 0) := (others => '1');
  signal HEX0        : std_logic_vector(6 downto 0);
  signal HEX1        : std_logic_vector(6 downto 0);
  signal HEX4        : std_logic_vector(6 downto 0);
  signal HEX5        : std_logic_vector(6 downto 0);
  signal address     : std_logic_vector(25 downto 0);
  signal write_data  : std_logic_vector(7 downto 0);
  signal read_data   : std_logic_vector(7 downto 0);
  signal req         : std_logic;
  signal wEn         : std_logic;
  signal ready       : std_logic;

  signal DRAM_ADDR   : std_logic_vector(12 downto 0);
  signal DRAM_BA     : std_logic_vector(1 downto 0);
  signal DRAM_CAS_N  : std_logic;
  signal DRAM_CKE    : std_logic;
  signal DRAM_CLK    : std_logic;
  signal DRAM_CS_N   : std_logic;
  signal DRAM_DQ     : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_LDQM   : std_logic;
  signal DRAM_RAS_N  : std_logic;
  signal DRAM_UDQM   : std_logic;
  signal DRAM_WE_N   : std_logic;

  signal tb_dq_oe    : std_logic := '0';
  signal tb_dq_data  : std_logic_vector(15 downto 0) := (others => '0');

  type mem_t is array (0 to 8191) of std_logic_vector(15 downto 0);
  signal mem         : mem_t := (others => (others => '0'));

  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row    : row_t := (others => (others => '0'));

  signal rd_pending      : integer range 0 to 16 := 0;
  signal rd_pending_data : std_logic_vector(15 downto 0) := (others => '0');

  function cmd_now(
    cs_n  : std_logic;
    ras_n : std_logic;
    cas_n : std_logic;
    we_n  : std_logic
  ) return std_logic_vector is
  begin
    return cs_n & ras_n & cas_n & we_n;
  end function;

  function mem_idx(bank : std_logic_vector(1 downto 0);
                   row  : std_logic_vector(12 downto 0);
                   col  : std_logic_vector(12 downto 0)) return integer is
    variable idx_v : unsigned(12 downto 0);
  begin
    idx_v := unsigned(bank & row(5 downto 0) & col(4 downto 0));
    return to_integer(idx_v);
  end function;

begin
  clk <= not clk after CLK_PERIOD / 2;

  DRAM_DQ <= tb_dq_data when tb_dq_oe = '1' else (others => 'Z');

  iface_i : entity work.dram_iface
    port map (
      clk        => clk,
      rst        => rst,
      SW         => SW,
      KEY        => KEY,
      HEX0       => HEX0,
      HEX1       => HEX1,
      HEX4       => HEX4,
      HEX5       => HEX5,
      address    => address,
      write_data => write_data,
      read_data  => read_data,
      req        => req,
      wEn        => wEn,
      ready      => ready
    );

  dut : entity work.dram_controller
    generic map (
      G_INIT_WAIT_CYCLES => C_INIT_WAIT,
      G_TRCD_CYCLES      => C_TRCD,
      G_TCAS_CYCLES      => C_TCAS,
      G_TRP_CYCLES       => C_TRP,
      G_TDPL_CYCLES      => C_TDPL,
      G_TRC_CYCLES       => C_TRC,
      G_TMRD_CYCLES      => C_TMRD,
      G_TREFI_CYCLES     => C_TREFI
    )
    port map (
      clk         => clk,
      rst         => rst,
      address     => address,
      write_data  => write_data,
      read_data   => read_data,
      req         => req,
      wEn         => wEn,
      ready       => ready,
      DRAM_ADDR   => DRAM_ADDR,
      DRAM_BA     => DRAM_BA,
      DRAM_CAS_N  => DRAM_CAS_N,
      DRAM_CKE    => DRAM_CKE,
      DRAM_CLK    => DRAM_CLK,
      DRAM_CS_N   => DRAM_CS_N,
      DRAM_DQ     => DRAM_DQ,
      DRAM_LDQM   => DRAM_LDQM,
      DRAM_RAS_N  => DRAM_RAS_N,
      DRAM_UDQM   => DRAM_UDQM,
      DRAM_WE_N   => DRAM_WE_N
    );

  mem_model : process(clk)
    variable bank_i   : integer;
    variable idx      : integer;
    variable cmd      : std_logic_vector(3 downto 0);
    variable col_addr : std_logic_vector(12 downto 0);
  begin
    if rising_edge(clk) then
      tb_dq_oe <= '0';

      if rd_pending > 0 then
        rd_pending <= rd_pending - 1;
        if rd_pending = 1 then
          tb_dq_data <= rd_pending_data;
          tb_dq_oe   <= '1';
        end if;
      end if;

      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

      if cmd = CMD_ACT then
        bank_i := to_integer(unsigned(DRAM_BA));
        open_row(bank_i) <= DRAM_ADDR;
      elsif cmd = CMD_WRIT then
        bank_i := to_integer(unsigned(DRAM_BA));
        col_addr := DRAM_ADDR;
        idx := mem_idx(DRAM_BA, open_row(bank_i), col_addr);
        mem(idx) <= DRAM_DQ;
      elsif cmd = CMD_READ then
        bank_i := to_integer(unsigned(DRAM_BA));
        col_addr := DRAM_ADDR;
        idx := mem_idx(DRAM_BA, open_row(bank_i), col_addr);
        if mem(idx) = x"0000" then
          rd_pending_data <= x"003C";
        else
          rd_pending_data <= mem(idx);
        end if;
        rd_pending      <= C_TCAS;
      end if;
    end if;
  end process;

  stim : process
    variable cycle             : integer := 0;
    variable stage             : integer := 0;
    variable pre_c             : integer := -1;
    variable ar1_c             : integer := -1;
    variable ar2_c             : integer := -1;
    variable mrs_c             : integer := -1;
    variable ready_c           : integer := -1;
    variable act_c             : integer := -1;
    variable read_c            : integer := -1;
    variable data_c            : integer := -1;
    variable write_c           : integer := -1;
    variable pre_after_write_c : integer := -1;
    variable refresh_c         : integer := -1;
    variable cmd               : std_logic_vector(3 downto 0);
    variable old_read          : std_logic_vector(7 downto 0);
  begin
    rst <= '1';
    KEY <= (others => '1');
    SW  <= (others => '0');
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- INIT: PRECHARGE -> REFRESH -> REFRESH -> MRS -> ready
    cycle := 0;
    stage := 0;
    while ready = '0' loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

      if (stage = 0) and (cmd = CMD_PRE) then
        pre_c := cycle;
        stage := 1;
      elsif (stage = 1) and (cmd = CMD_AR) then
        ar1_c := cycle;
        stage := 2;
      elsif (stage = 2) and (cmd = CMD_AR) then
        ar2_c := cycle;
        stage := 3;
      elsif (stage = 3) and (cmd = CMD_MRS) then
        mrs_c := cycle;
        stage := 4;
      end if;

      assert cycle < 200 report "Timeout na inicializacao" severity failure;
    end loop;
    ready_c := cycle;

    assert stage = 4 report "INIT incompleto: sequencia de comandos invalida" severity failure;
    assert (ar1_c - pre_c) >= C_TRP report "INIT violou intervalo PRECHARGE->REFRESH" severity failure;
    assert (ar2_c - ar1_c) >= C_TRC report "INIT violou intervalo REFRESH1->REFRESH2" severity failure;
    assert (mrs_c - ar2_c) >= C_TRC report "INIT violou intervalo REFRESH2->MRS" severity failure;
    assert ready_c > mrs_c report "ready subiu antes do fim da inicializacao" severity failure;

    -- READ: troca endereco via SW e espera ACTIVATE -> READ
    old_read := read_data;
    SW(9 downto 0) <= "1101010011";

    cycle := 0;
    act_c := -1;
    read_c := -1;
    data_c := -1;
    while cycle < 200 loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

      if (act_c = -1) and (cmd = CMD_ACT) then
        act_c := cycle;
      elsif (act_c /= -1) and (read_c = -1) and (cmd = CMD_READ) then
        read_c := cycle;
      end if;

      if (read_c /= -1) and (data_c = -1) and (read_data /= old_read) then
        data_c := cycle;
      end if;

      exit when (read_c /= -1) and (data_c /= -1);
    end loop;

    assert act_c /= -1 report "READ: ACTIVATE nao encontrado" severity failure;
    assert read_c /= -1 report "READ: comando READ nao encontrado" severity failure;
    assert (read_c - act_c) >= C_TRCD report "READ: intervalo ACTIVATE->READ menor que tRCD" severity failure;
    assert data_c /= -1 report "READ: dado nao capturado" severity failure;
    assert (data_c - read_c) >= C_TCAS report "READ: dado capturado antes da CAS latency" severity failure;

    -- WRITE: pressiona KEY[3] e verifica ACTIVATE -> WRITE -> PRECHARGE
    SW(3 downto 0) <= "1010";
    wait until rising_edge(clk);
    KEY(3) <= '0';
    wait until rising_edge(clk);
    KEY(3) <= '1';

    cycle := 0;
    act_c := -1;
    write_c := -1;
    pre_after_write_c := -1;
    while cycle < 200 loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

      if (act_c = -1) and (cmd = CMD_ACT) then
        act_c := cycle;
      elsif (act_c /= -1) and (write_c = -1) and (cmd = CMD_WRIT) then
        write_c := cycle;
        assert DRAM_DQ(7 downto 0) = "00001010" report "WRITE: dado incorreto no barramento DQ" severity failure;
      elsif (write_c /= -1) and (pre_after_write_c = -1) and (cmd = CMD_PRE) then
        pre_after_write_c := cycle;
      end if;

      exit when pre_after_write_c /= -1;
    end loop;

    assert act_c /= -1 report "WRITE: ACTIVATE nao encontrado" severity failure;
    assert write_c /= -1 report "WRITE: comando WRITE nao encontrado" severity failure;
    assert (write_c - act_c) >= C_TRCD report "WRITE: intervalo ACTIVATE->WRITE menor que tRCD" severity failure;
    assert pre_after_write_c /= -1 report "WRITE: PRECHARGE apos escrita nao encontrado" severity failure;
    assert (pre_after_write_c - write_c) >= C_TDPL report "WRITE: PRECHARGE emitido antes de tDPL" severity failure;

    -- REFRESH: aguarda contador interno e verifica AUTO REFRESH + retorno ao READY apos tRC
    cycle := 0;
    refresh_c := -1;
    while cycle < 400 loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);

      if (refresh_c = -1) and (cmd = CMD_AR) and (req = '0') then
        refresh_c := cycle;
      elsif (refresh_c /= -1) and (ready = '1') then
        exit;
      end if;
    end loop;

    assert refresh_c /= -1 report "REFRESH: AUTO REFRESH nao encontrado" severity failure;
    assert cycle - refresh_c >= C_TRC report "REFRESH: retorno ao READY antes de tRC" severity failure;

    -- WRITE seguido de READ automatico
    SW(3 downto 0) <= "0110";
    wait until rising_edge(clk);
    KEY(3) <= '0';
    wait until rising_edge(clk);
    KEY(3) <= '1';

    cycle := 0;
    write_c := -1;
    read_c := -1;
    while cycle < 300 loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);
      if (write_c = -1) and (cmd = CMD_WRIT) then
        write_c := cycle;
      elsif (write_c /= -1) and (read_c = -1) and (cmd = CMD_READ) then
        read_c := cycle;
      end if;
      exit when read_c /= -1;
    end loop;

    assert write_c /= -1 report "WRITE->READ: WRITE nao encontrado" severity failure;
    assert read_c /= -1 report "WRITE->READ: leitura automatica nao ocorreu" severity failure;
    assert read_c > write_c report "WRITE->READ: ordem invalida" severity failure;

    report "tb_dram_system: todos os cenarios passaram" severity note;
    wait;
  end process;
end sim;
