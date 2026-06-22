library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- End-to-end test of the user-reported scenarios driven through SW/KEY:
--   * overwriting a cell that already holds a value, and
--   * reading back distinct addresses returns each cell's own value.
-- The SDRAM is modelled with the real clock relationship (DRAM_CLK leads the
-- system clock) so the verified timing matches the board.
entity tb_dram_switch is
end tb_dram_switch;

architecture sim of tb_dram_switch is
  constant CLK_PERIOD : time := 7 ns;   -- ~143 MHz (board clock)

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal SW         : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY        : std_logic_vector(3 downto 0) := (others => '1');
  signal HEX0, HEX1, HEX4, HEX5 : std_logic_vector(6 downto 0);
  signal address    : std_logic_vector(25 downto 0);
  signal write_data : std_logic_vector(7 downto 0);
  signal read_data  : std_logic_vector(7 downto 0);
  signal req, wEn, ready : std_logic;

  signal dram_cmd        : std_logic_vector(25 downto 0);
  signal dram_write_data : std_logic_vector(7 downto 0);

  signal DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N, DRAM_CLK : std_logic;
  signal DRAM_DQ   : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_ADDR : std_logic_vector(12 downto 0);
  signal DRAM_BA   : std_logic_vector(1 downto 0);

  signal tb_dq_oe   : std_logic := '0';
  signal tb_dq_data : std_logic_vector(15 downto 0) := (others => '0');

  type mem_t is array (0 to 8191) of std_logic_vector(15 downto 0);
  signal mem      : mem_t := (others => (others => '0'));
  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row : row_t := (others => (others => '0'));
  signal rd_pending      : integer range 0 to 16 := 0;
  signal rd_pending_data : std_logic_vector(15 downto 0) := (others => '0');

  constant CMD_ACT : std_logic_vector(3 downto 0) := "0011";
  constant CMD_READ: std_logic_vector(3 downto 0) := "0101";
  constant CMD_WRIT: std_logic_vector(3 downto 0) := "0100";

  function mem_idx(bank : std_logic_vector(1 downto 0);
                   row  : std_logic_vector(12 downto 0);
                   col  : std_logic_vector(12 downto 0)) return integer is
  begin
    return to_integer(unsigned(bank) & unsigned(row(5 downto 0)) & unsigned(col(4 downto 0)));
  end function;
begin
  clk <= not clk after CLK_PERIOD / 2;

  DRAM_DQ <= tb_dq_data when tb_dq_oe = '1' else
             (x"00" & dram_write_data) when (dram_cmd(18)='0' and dram_cmd(17)='1' and dram_cmd(16)='0' and dram_cmd(15)='0') else
             (others => 'Z');

  DRAM_ADDR  <= dram_cmd(12 downto 0);
  DRAM_BA    <= dram_cmd(14 downto 13);
  DRAM_WE_N  <= dram_cmd(15);
  DRAM_CAS_N <= dram_cmd(16);
  DRAM_RAS_N <= dram_cmd(17);
  DRAM_CS_N  <= dram_cmd(18);
  DRAM_CLK   <= not clk;

  iface_i : entity work.dram_iface
    port map (clk => clk, rst => rst, SW => SW, KEY => KEY,
              HEX0 => HEX0, HEX1 => HEX1, HEX4 => HEX4, HEX5 => HEX5,
              address => address, write_data => write_data, read_data => read_data,
              req => req, wEn => wEn, ready => ready);

  dut : entity work.dram_controller
    port map (clk => clk, rst => rst, SW => SW, KEY => KEY,
              data_in => DRAM_DQ(7 downto 0), write_data_in => write_data,
              data_out => read_data, HEX0 => open, HEX1 => open, HEX4 => open, HEX5 => open,
              adress => dram_cmd, addr_in => address, write_data_out => dram_write_data,
              req => req, wEn => wEn, ready => ready);

  mem_model : process(DRAM_CLK)
    variable bank_i : integer;
    variable idx    : integer;
    variable cmd    : std_logic_vector(3 downto 0);
  begin
    if rising_edge(DRAM_CLK) then
      tb_dq_oe <= '0';
      if rd_pending > 0 then
        rd_pending <= rd_pending - 1;
        if rd_pending = 1 then
          tb_dq_data <= rd_pending_data after 5400 ps;  -- model tAC (read access time)
          tb_dq_oe   <= '1';
        end if;
      end if;

      cmd := DRAM_CS_N & DRAM_RAS_N & DRAM_CAS_N & DRAM_WE_N;
      if cmd = CMD_ACT then
        open_row(to_integer(unsigned(DRAM_BA))) <= DRAM_ADDR;
      elsif cmd = CMD_WRIT then
        bank_i := to_integer(unsigned(DRAM_BA));
        idx := mem_idx(DRAM_BA, open_row(bank_i), DRAM_ADDR);
        mem(idx) <= DRAM_DQ;
      elsif cmd = CMD_READ then
        bank_i := to_integer(unsigned(DRAM_BA));
        idx := mem_idx(DRAM_BA, open_row(bank_i), DRAM_ADDR);
        rd_pending_data <= mem(idx);
        rd_pending      <= 3;   -- CAS latency 3
      end if;
    end if;
  end process;

  stim : process
    -- SW layout used by dram_iface: SW(9:4) = address nibble, SW(3:0) = data.
    procedure do_write(addr6 : std_logic_vector(5 downto 0);
                       data4 : std_logic_vector(3 downto 0)) is
    begin
      SW <= addr6 & data4;
      wait until rising_edge(clk);
      KEY(3) <= '0';
      wait until rising_edge(clk);
      KEY(3) <= '1';
      -- write + automatic read-back are two controller operations
      for i in 0 to 160 loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure do_read(addr6 : std_logic_vector(5 downto 0)) is
    begin
      SW <= addr6 & "0000";   -- changing the address triggers an automatic read
      for i in 0 to 160 loop wait until rising_edge(clk); end loop;
    end procedure;
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    wait until ready = '1';
    for i in 0 to 40 loop wait until rising_edge(clk); end loop;

    -- A) Write 3 to 0x01
    do_write("000001", "0011");
    assert read_data = x"03" report "FALHA A: 0x01 nao leu 3" severity failure;

    -- B) Change address to 0x02 (auto-read)
    do_read("000010");
    report "apos troca p/ 0x02: read_data=" & integer'image(to_integer(unsigned(read_data)));

    -- C) USER SCENARIO: now WRITE 7 to 0x02 (after the address change)
    do_write("000010", "0111");
    assert read_data = x"07" report "FALHA C: nao conseguiu escrever apos trocar endereco (leu " & integer'image(to_integer(unsigned(read_data))) & ")" severity failure;

    -- D) Change address back to 0x01 (auto-read) -> must show 3
    do_read("000001");
    assert read_data = x"03" report "FALHA D: 0x01 nao leu 3 (leu " & integer'image(to_integer(unsigned(read_data))) & ")" severity failure;

    -- E) Overwrite 0x01 with 9 after the change
    do_write("000001", "1001");
    assert read_data = x"09" report "FALHA E: overwrite apos troca falhou (leu " & integer'image(to_integer(unsigned(read_data))) & ")" severity failure;

    report "tb_dram_switch: overwrite e troca de endereco OK" severity note;
    wait;
  end process;
end sim;
