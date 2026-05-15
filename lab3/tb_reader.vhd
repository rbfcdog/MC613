library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_reader is
end tb_reader;

architecture sim of tb_reader is
  constant CLK_PERIOD : time := 10 ns;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal req_in      : std_logic := '0';
  signal wEn_in      : std_logic := '0';
  signal addr_in     : std_logic_vector(25 downto 0) := (others => '0');
  signal data_in     : std_logic_vector(7 downto 0) := (others => '0');
  signal req_pending : std_logic;
  signal wEn_out     : std_logic;
  signal addr_out    : std_logic_vector(25 downto 0);
  signal data_out    : std_logic_vector(7 downto 0);
  signal cmd_ack     : std_logic := '0';
begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.reader
    port map (
      clk         => clk,
      rst         => rst,
      req_in      => req_in,
      wEn_in      => wEn_in,
      addr_in     => addr_in,
      data_in     => data_in,
      req_pending => req_pending,
      wEn_out     => wEn_out,
      addr_out    => addr_out,
      data_out    => data_out,
      cmd_ack     => cmd_ack
    );

  stim : process
  begin
    rst <= '1';
    wait for 3 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    wait until rising_edge(clk);
    req_in  <= '1';
    wEn_in  <= '1';
    addr_in <= "10" & x"012345";
    data_in <= x"5A";

    wait until rising_edge(clk);
    req_in <= '0';

    wait until rising_edge(clk);
    assert req_pending = '1'
      report "reader: comando nao ficou pendente" severity failure;
    assert wEn_out = '1' and addr_out = ("10" & x"012345") and data_out = x"5A"
      report "reader: comando bufferizado incorretamente" severity failure;

    cmd_ack <= '1';
    wait until rising_edge(clk);
    cmd_ack <= '0';

    wait until rising_edge(clk);
    assert req_pending = '0'
      report "reader: cmd_ack nao limpou comando pendente" severity failure;

    req_in  <= '1';
    wEn_in  <= '0';
    addr_in <= "01" & x"000111";
    data_in <= x"22";
    cmd_ack <= '1';

    wait until rising_edge(clk);
    req_in  <= '0';
    cmd_ack <= '0';

    wait until rising_edge(clk);
    assert req_pending = '1' and wEn_out = '0' and addr_out = ("01" & x"000111")
      report "reader: novo comando no ciclo de ack nao foi capturado" severity failure;

    report "tb_reader: testes concluidos com sucesso" severity note;
    wait;
  end process;
end sim;
