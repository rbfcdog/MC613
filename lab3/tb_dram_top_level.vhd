library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- =============================================================================
--  Integration test for dram_top_level (iface + controller + SDRAM model).
--
--  It drives the board the way a user would -- CLOCK_50, the switches and the
--  keys -- models the real SDRAM on the DRAM_* pins (CAS latency 3, tAC, the
--  bidirectional DQ bus), and checks the value shown on the HEX1 display.
--
--  Story:
--    1. Reset (KEY0), wait for the controller to initialise the SDRAM.
--    2. Select address 0x01, write 7 with KEY[3]  -> HEX1 must show 7.
--    3. Select address 0x02 (untouched)           -> HEX1 must show 0.
--    4. Go back to address 0x01                    -> HEX1 must still show 7.
--
--  Note: in Quartus/ModelSim the real PLL is used; in ghdl a small PLL stub is
--  bound as work.pll, so CLOCK_50 is driven straight through as the core clock.
-- =============================================================================
entity tb_dram_top_level is
end tb_dram_top_level;

architecture sim of tb_dram_top_level is
  constant CLK_PERIOD : time := 20 ns;     -- 50 MHz board clock
  constant TAC        : time := 5400 ps;   -- SDRAM read access time

  signal CLOCK_50 : std_logic := '0';
  signal SW       : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY      : std_logic_vector(3 downto 0) := (others => '1');
  signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(6 downto 0);

  signal DRAM_ADDR  : std_logic_vector(12 downto 0);
  signal DRAM_BA    : std_logic_vector(1 downto 0);
  signal DRAM_CAS_N, DRAM_CKE, DRAM_CLK, DRAM_CS_N : std_logic;
  signal DRAM_DQ    : std_logic_vector(15 downto 0) := (others => 'Z');
  signal DRAM_LDQM, DRAM_RAS_N, DRAM_UDQM, DRAM_WE_N : std_logic;

  -- SDRAM model state
  signal tb_dq_oe   : std_logic := '0';
  signal tb_dq_data : std_logic_vector(15 downto 0) := (others => '0');
  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  signal mem      : mem_t := (others => (others => '0'));
  type row_t is array (0 to 3) of std_logic_vector(12 downto 0);
  signal open_row : row_t := (others => (others => '0'));
  signal rd_pending      : integer range 0 to 8 := 0;
  signal rd_pending_data : std_logic_vector(15 downto 0) := (others => '0');

  constant CMD_ACT  : std_logic_vector(3 downto 0) := "0011";
  constant CMD_READ : std_logic_vector(3 downto 0) := "0101";
  constant CMD_WRIT : std_logic_vector(3 downto 0) := "0100";
  constant CMD_MRS  : std_logic_vector(3 downto 0) := "0000";
  signal bus_cmd : std_logic_vector(3 downto 0);

  -- Same seven-segment encoding the design uses, to build expected displays.
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

  function mem_idx(bank_in, row_in, col_in : std_logic_vector) return integer is
    variable b : unsigned(1 downto 0)  := unsigned(bank_in);
    variable r : unsigned(12 downto 0) := unsigned(row_in);
    variable c : unsigned(12 downto 0) := unsigned(col_in);
  begin
    return to_integer(b & r(2 downto 0) & c(4 downto 0));
  end function;
begin
  CLOCK_50 <= not CLOCK_50 after CLK_PERIOD / 2;
  bus_cmd  <= DRAM_CS_N & DRAM_RAS_N & DRAM_CAS_N & DRAM_WE_N;

  -- The model drives DQ only during a read (delayed by tAC); the rest of the
  -- time the top level owns the bus (write) or it floats.
  DRAM_DQ <= tb_dq_data after TAC when tb_dq_oe = '1' else (others => 'Z');

  dut : entity work.dram_top_level
    port map (
      CLOCK_50 => CLOCK_50, SW => SW, KEY => KEY,
      HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2, HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5,
      DRAM_ADDR => DRAM_ADDR, DRAM_BA => DRAM_BA, DRAM_CAS_N => DRAM_CAS_N,
      DRAM_CKE => DRAM_CKE, DRAM_CLK => DRAM_CLK, DRAM_CS_N => DRAM_CS_N,
      DRAM_DQ => DRAM_DQ, DRAM_LDQM => DRAM_LDQM, DRAM_RAS_N => DRAM_RAS_N,
      DRAM_UDQM => DRAM_UDQM, DRAM_WE_N => DRAM_WE_N);

  -- SDRAM model (clocked on the chip clock the top level drives).
  sdram_model : process(DRAM_CLK)
    variable bk : integer;
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

      bk := to_integer(unsigned(DRAM_BA));
      case bus_cmd is
        when CMD_ACT  => open_row(bk) <= DRAM_ADDR;
        when CMD_WRIT => mem(mem_idx(DRAM_BA, open_row(bk), DRAM_ADDR)) <= DRAM_DQ;
        when CMD_READ =>
          rd_pending_data <= mem(mem_idx(DRAM_BA, open_row(bk), DRAM_ADDR));
          rd_pending      <= 3;
        when others => null;
      end case;
    end if;
  end process;

  stim : process
  begin
    -- 1) Reset, then wait for the SDRAM init to reach the mode-register step.
    KEY(0) <= '0';                          -- assert reset
    SW <= (others => '0');
    wait for 10 * CLK_PERIOD;
    KEY(0) <= '1';                          -- release reset
    wait until bus_cmd = CMD_MRS for 800 us;
    assert bus_cmd = CMD_MRS report "INIT nao chegou ao LOAD MODE REGISTER" severity failure;
    wait for 10 us;                         -- let the post-reset auto-clear finish

    -- 2) Address 0x01, data 7, press KEY[3] -> write, auto read-back.
    SW <= "000001" & "0111";                -- SW[9:4]=0x01, SW[3:0]=7
    wait for 3 us;
    KEY(3) <= '0';
    wait for 3 us;
    KEY(3) <= '1';
    wait for 3 us;
    assert HEX1 = hex7("0111")
      report "HEX1 deveria mostrar 7 apos escrever no 0x01" severity failure;

    -- 3) Address 0x02 was never written -> reads 0.
    SW <= "000010" & "0000";
    wait for 5 us;
    assert HEX1 = hex7("0000")
      report "HEX1 deveria mostrar 0 no endereco 0x02" severity failure;

    -- 4) Back to 0x01 -> the 7 is still there.
    SW <= "000001" & "0000";
    wait for 5 us;
    assert HEX1 = hex7("0111")
      report "HEX1 deveria manter 7 ao voltar para 0x01" severity failure;

    report "tb_dram_top_level: todos os cenarios passaram" severity note;
    wait;
  end process;
end sim;
