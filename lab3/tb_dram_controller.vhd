library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_dram_controller is
end tb_dram_controller;

architecture sim of tb_dram_controller is
  constant CLK_PERIOD : time := 10 ns;

  constant C_INIT_WAIT : integer := 2;
  constant C_TRCD      : integer := 2;
  constant C_TCAS      : integer := 3;
  constant C_TRP       : integer := 2;
  constant C_TDPL      : integer := 2;
  constant C_TRC       : integer := 4;
  constant C_TMRD      : integer := 2;
  constant C_TREFI     : integer := 20;

  constant CMD_ACT : std_logic_vector(3 downto 0) := "0011";
  constant CMD_READ: std_logic_vector(3 downto 0) := "0101";
  constant CMD_WRIT: std_logic_vector(3 downto 0) := "0100";
  constant CMD_AR  : std_logic_vector(3 downto 0) := "0001";

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal address     : std_logic_vector(25 downto 0) := (others => '0');
  signal write_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal read_data   : std_logic_vector(7 downto 0);
  signal req         : std_logic := '0';
  signal wEn         : std_logic := '0';
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

  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
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
    variable idx_v : unsigned(9 downto 0);
  begin
    idx_v := unsigned(bank & row(2 downto 0) & col(4 downto 0));
    return to_integer(idx_v);
  end function;
begin
  clk <= not clk after CLK_PERIOD / 2;

  DRAM_DQ <= tb_dq_data when tb_dq_oe = '1' else (others => 'Z');

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
        rd_pending_data <= mem(idx);
        rd_pending      <= C_TCAS;
      end if;
    end if;
  end process;

  stim : process
    variable cycle      : integer;
    variable cmd        : std_logic_vector(3 downto 0);
    variable refresh_at : integer := -1;
  begin
    rst <= '1';
    req <= '0';
    wEn <= '0';
    address <= (others => '0');
    write_data <= (others => '0');

    wait for 4 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- Espera fim da inicializacao
    cycle := 0;
    while ready = '0' loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      assert cycle < 200 report "dram_controller: timeout na inicializacao" severity failure;
    end loop;

    -- WRITE unitario
    address <= "10" & "0000000000000" & "00000100101";
    write_data <= x"0A";
    req <= '1';
    wEn <= '1';
    wait until rising_edge(clk);
    req <= '0';
    wEn <= '0';

    while ready = '0' loop
      wait until rising_edge(clk);
    end loop;

    -- READ unitario do mesmo endereco
    req <= '1';
    wEn <= '0';
    wait until rising_edge(clk);
    req <= '0';

    while ready = '0' loop
      wait until rising_edge(clk);
    end loop;

    assert read_data = x"0A"
      report "dram_controller: leitura nao retornou valor escrito" severity failure;

    -- REFRESH automatico
    cycle := 0;
    refresh_at := -1;
    while cycle < 200 loop
      wait until rising_edge(clk);
      cycle := cycle + 1;
      cmd := cmd_now(DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N);
      if (refresh_at = -1) and (cmd = CMD_AR) then
        refresh_at := cycle;
      elsif (refresh_at /= -1) and (ready = '1') then
        exit;
      end if;
    end loop;

    assert refresh_at /= -1
      report "dram_controller: refresh automatico nao detectado" severity failure;

    report "tb_dram_controller: testes concluidos com sucesso" severity note;
    wait;
  end process;
end sim;
