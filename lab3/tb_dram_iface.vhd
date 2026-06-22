library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- =============================================================================
--  Unit test for dram_iface (the user-facing FSM) in ISOLATION.
--
--  There is no real controller and no SDRAM here. A small "fake controller"
--  process answers the req/ready handshake and LOGS every operation the iface
--  issues. The stimulus process just drives the board inputs (SW / KEY) and
--  then checks the logged sequence of operations.
--
--  Logging the operations (instead of asserting at hand-counted clock cycles)
--  keeps the test readable and immune to the 2-stage input synchronizers and
--  the request/accept handshake latency inside dram_iface.
--
--  Expected story after reset:
--    op0  WRITE 0  -> reset auto-clears the currently selected address
--    op1  READ      -> read-back of that clear
--    op2  READ      -> caused by changing the address switches
--    op3  WRITE A  -> caused by pressing KEY[3] (data = SW[3:0])
--    op4  READ      -> automatic read-back after the write
-- =============================================================================
entity tb_dram_iface is
end tb_dram_iface;

architecture sim of tb_dram_iface is
  constant CLK_PERIOD : time := 10 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal SW         : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY        : std_logic_vector(3 downto 0) := (others => '1');
  signal HEX0, HEX1, HEX4, HEX5 : std_logic_vector(6 downto 0);
  signal address    : std_logic_vector(25 downto 0);
  signal write_data : std_logic_vector(7 downto 0);
  signal read_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal req        : std_logic;
  signal wEn        : std_logic;
  signal ready      : std_logic := '1';

  -- Log of the operations issued by the iface, filled by the fake controller.
  type op_t is record
    wen   : std_logic;
    addr  : std_logic_vector(25 downto 0);
    wdata : std_logic_vector(7 downto 0);
  end record;
  type op_log_t is array (0 to 15) of op_t;
  signal log   : op_log_t;
  signal n_ops : integer := 0;
  signal done  : boolean := false;

  -- Same address mapping dram_iface uses, so we can predict the expected bits.
  function addr_of(s : std_logic_vector(9 downto 0)) return std_logic_vector is
    variable a : std_logic_vector(25 downto 0) := (others => '0');
  begin
    a(14) := s(7); a(13) := s(6); a(12) := s(9);
    a(11) := s(8); a(2)  := s(5); a(1)  := s(4);
    return a;
  end function;
begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.dram_iface
    port map (clk => clk, rst => rst, SW => SW, KEY => KEY,
              HEX0 => HEX0, HEX1 => HEX1, HEX4 => HEX4, HEX5 => HEX5,
              address => address, write_data => write_data, read_data => read_data,
              req => req, wEn => wEn, ready => ready);

  -- Fake controller: on every request, record it, go busy for a few cycles,
  -- return a fixed read value, then signal done.
  fake_ctrl : process
  begin
    ready     <= '1';
    read_data <= x"5A";
    loop
      wait until rising_edge(clk) and req = '1' and rst = '0';
      log(n_ops) <= (wen => wEn, addr => address, wdata => write_data);
      n_ops      <= n_ops + 1;
      ready      <= '0';                              -- accept -> busy
      for i in 0 to 2 loop wait until rising_edge(clk); end loop;
      ready      <= '1';                              -- operation done
      wait until rising_edge(clk);
    end loop;
  end process;

  -- Stimulus + checks.
  stim : process
  begin
    rst <= '1'; SW <= (others => '0'); KEY <= (others => '1');
    wait for 4 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- 1) Reset auto-clears the current address: WRITE 0 then its read-back.
    wait until n_ops = 2;

    -- 2) Changing the address switches must trigger an automatic READ.
    SW(9 downto 4) <= "101011";          -- address 0x2B on SW[9:4]
    wait until n_ops = 3;

    -- 3) Pressing KEY[3] must WRITE SW[3:0], then auto read-back.
    SW(3 downto 0) <= "1010";            -- data = 0xA
    wait until rising_edge(clk);
    KEY(3) <= '0';
    wait until n_ops = 5;
    KEY(3) <= '1';

    -- -------- verify the logged sequence --------
    assert log(0).wen = '1' and log(0).wdata = x"00"
      report "op0 deveria ser o WRITE de limpeza do reset (dado 0)" severity failure;
    assert log(1).wen = '0'
      report "op1 deveria ser o read-back da limpeza" severity failure;
    assert log(2).wen = '0' and log(2).addr = addr_of("1010110000")
      report "op2 deveria ser a leitura ao trocar de endereco" severity failure;
    assert log(3).wen = '1' and log(3).wdata = x"0A"
                            and log(3).addr = addr_of("1010111010")
      report "op3 deveria ser a escrita via KEY[3] com o dado de SW[3:0]" severity failure;
    assert log(4).wen = '0'
      report "op4 deveria ser o read-back automatico apos a escrita" severity failure;

    report "tb_dram_iface: todos os cenarios passaram" severity note;
    done <= true;
    wait;
  end process;

  -- Watchdog: fail loudly if the expected sequence never completes.
  watchdog : process
  begin
    wait for 50 us;
    assert done
      report "tb_dram_iface: timeout - sequencia esperada nao ocorreu" severity failure;
    wait;
  end process;
end sim;
