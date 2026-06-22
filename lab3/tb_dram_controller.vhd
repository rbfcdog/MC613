library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- =============================================================================
--  Unit test for dram_controller.
--
--  It drives the iface-side handshake directly (req / wEn / addr_in / data) and
--  models the real SDRAM on the DRAM_* pins:
--    * DRAM_CLK = not clk          (the chip clock leads, like the board)
--    * CAS latency 3               (read data appears 3 SDRAM clocks later)
--    * tAC read access delay       (data is valid ~tAC after the clock edge)
--
--  Story:
--    1. After reset the controller runs its INIT sequence and raises ready.
--    2. WRITE 0x5A to address A, READ it back  -> must return 0x5A.
--    3. WRITE 0x3C to address B, READ B then A -> values are independent.
--    4. Left idle, the controller must issue an AUTO REFRESH on its own.
-- =============================================================================
entity tb_dram_controller is
end tb_dram_controller;

architecture sim of tb_dram_controller is
  constant CLK_PERIOD : time := 7 ns;     -- ~143 MHz
  constant TAC        : time := 5400 ps;  -- SDRAM read access time

  -- DUT handshake / data
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

  -- DUT <-> SDRAM pins
  signal dram_cmd        : std_logic_vector(25 downto 0);
  signal dram_write_data : std_logic_vector(7 downto 0);
  signal DRAM_DQ         : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_CLK        : std_logic;

  -- SDRAM model state
  signal tb_dq_oe   : std_logic := '0';
  signal tb_dq_data : std_logic_vector(15 downto 0) := (others => '0');
  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  signal mem        : mem_t := (others => (others => '0'));
  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row   : row_t := (others => (others => '0'));
  signal rd_pending      : integer range 0 to 8 := 0;
  signal rd_pending_data : std_logic_vector(15 downto 0) := (others => '0');

  -- command on the bus (CS,RAS,CAS,WE)
  constant CMD_ACT  : std_logic_vector(3 downto 0) := "0011";
  constant CMD_READ : std_logic_vector(3 downto 0) := "0101";
  constant CMD_WRIT : std_logic_vector(3 downto 0) := "0100";
  constant CMD_AR   : std_logic_vector(3 downto 0) := "0001";
  signal bus_cmd : std_logic_vector(3 downto 0);

  -- Build a 26-bit address from row/bank/column fields.
  function make_addr(row, bank, col : integer) return std_logic_vector is
    variable a : std_logic_vector(25 downto 0) := (others => '0');
  begin
    a(25 downto 13) := std_logic_vector(to_unsigned(row, 13));
    a(12 downto 11) := std_logic_vector(to_unsigned(bank, 2));
    a(10 downto 1)  := std_logic_vector(to_unsigned(col, 10));
    return a;
  end function;

  -- Index the model the same way the controller addresses a cell.
  -- (Arguments are normalised to 0-based ranges so callers can pass slices.)
  function mem_idx(bank_in, row_in, col_in : std_logic_vector) return integer is
    variable b : unsigned(1 downto 0)  := unsigned(bank_in);
    variable r : unsigned(12 downto 0) := unsigned(row_in);
    variable c : unsigned(12 downto 0) := unsigned(col_in);
  begin
    return to_integer(b & r(2 downto 0) & c(4 downto 0));
  end function;

  constant ADDR_A : std_logic_vector(25 downto 0) := make_addr(1, 0, 5);
  constant ADDR_B : std_logic_vector(25 downto 0) := make_addr(2, 1, 7);
begin
  clk      <= not clk after CLK_PERIOD / 2;
  DRAM_CLK <= not clk;

  -- Decoded command on the pins.
  bus_cmd <= dram_cmd(18) & dram_cmd(17) & dram_cmd(16) & dram_cmd(15);

  -- Bidirectional DQ: the controller drives it during a WRITE; the model drives
  -- it during a READ (delayed by tAC); otherwise high-Z.
  DRAM_DQ <= tb_dq_data after TAC when tb_dq_oe = '1' else
             (x"00" & dram_write_data) when bus_cmd = CMD_WRIT else
             (others => 'Z');

  dut : entity work.dram_controller
    port map (
      clk => clk, rst => rst, SW => SW_tie, KEY => KEY_tie,
      data_in => DRAM_DQ(7 downto 0), write_data_in => write_data,
      data_out => read_data, HEX0 => open, HEX1 => open, HEX4 => open, HEX5 => open,
      adress => dram_cmd, addr_in => addr_in, write_data_out => dram_write_data,
      req => req, wEn => wEn, ready => ready);

  -- SDRAM model: latch the open row on ACTIVATE, store on WRITE, and on READ
  -- present the cell after the CAS latency (3 SDRAM clocks).
  sdram_model : process(DRAM_CLK)
    variable col : std_logic_vector(12 downto 0);
    variable bk  : integer;
  begin
    if rising_edge(DRAM_CLK) then
      tb_dq_oe <= '0';
      if rd_pending > 0 then
        rd_pending <= rd_pending - 1;
        if rd_pending = 1 then
          tb_dq_data <= rd_pending_data;
          tb_dq_oe   <= '1';
        end if;
      end if;

      bk  := to_integer(unsigned(dram_cmd(14 downto 13)));
      col := dram_cmd(12 downto 0);
      case bus_cmd is
        when CMD_ACT  => open_row(bk) <= dram_cmd(12 downto 0);
        when CMD_WRIT => mem(mem_idx(dram_cmd(14 downto 13), open_row(bk), col)) <= DRAM_DQ;
        when CMD_READ =>
          rd_pending_data <= mem(mem_idx(dram_cmd(14 downto 13), open_row(bk), col));
          rd_pending      <= 3;          -- CAS latency
        when others => null;
      end case;
    end if;
  end process;

  stim : process
    -- Issue one operation and wait for the controller to accept (ready low)
    -- and then finish it (ready high again).
    procedure dram_op(is_write : std_logic;
                      addr     : std_logic_vector(25 downto 0);
                      data     : std_logic_vector(7 downto 0)) is
    begin
      addr_in    <= addr;
      write_data <= data;
      wEn        <= is_write;
      req        <= '1';
      wait until rising_edge(clk);
      req <= '0';
      wait until ready = '0';
      wait until ready = '1';
    end procedure;

    variable cyc : integer;
  begin
    rst <= '1';
    wait for 4 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- 1) INIT: the controller must finish initialising and raise ready.
    cyc := 0;
    while ready = '0' loop
      wait until rising_edge(clk);
      cyc := cyc + 1;
      assert cyc < 40000 report "INIT nunca terminou (ready preso em 0)" severity failure;
    end loop;

    -- 2) WRITE then READ the same address.
    dram_op('1', ADDR_A, x"5A");
    dram_op('0', ADDR_A, x"00");
    assert read_data = x"5A"
      report "READ de A nao retornou o valor escrito (leu " &
             integer'image(to_integer(unsigned(read_data))) & ")" severity failure;

    -- 3) A second address is independent, and A keeps its value.
    dram_op('1', ADDR_B, x"3C");
    dram_op('0', ADDR_B, x"00");
    assert read_data = x"3C" report "READ de B incorreto" severity failure;
    dram_op('0', ADDR_A, x"00");
    assert read_data = x"5A" report "A perdeu o valor apos escrever B" severity failure;

    -- 4) Auto refresh must happen on its own while idle.
    cyc := 0;
    while bus_cmd /= CMD_AR loop
      wait until rising_edge(clk);
      cyc := cyc + 1;
      assert cyc < 4000 report "AUTO REFRESH nunca foi emitido" severity failure;
    end loop;

    report "tb_dram_controller: todos os cenarios passaram" severity note;
    wait;
  end process;
end sim;
