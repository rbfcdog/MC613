library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_dram_iface is
end tb_dram_iface;

architecture sim of tb_dram_iface is
  constant CLK_PERIOD : time := 10 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal SW         : std_logic_vector(9 downto 0) := (others => '0');
  signal KEY        : std_logic_vector(3 downto 0) := (others => '1');
  signal HEX0       : std_logic_vector(6 downto 0);
  signal HEX1       : std_logic_vector(6 downto 0);
  signal HEX4       : std_logic_vector(6 downto 0);
  signal HEX5       : std_logic_vector(6 downto 0);
  signal address    : std_logic_vector(25 downto 0);
  signal write_data : std_logic_vector(7 downto 0);
  signal read_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal req        : std_logic;
  signal wEn        : std_logic;
  signal ready      : std_logic := '1';
begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.dram_iface
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

  stim : process
  begin
    rst <= '1';
    ready <= '1';
    KEY <= (others => '1');
    SW  <= (others => '0');

    wait for 4 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- Leitura inicial automatica (last_address_seen = 0)
    wait until rising_edge(clk);
    assert req = '1' and wEn = '0'
      report "dram_iface: leitura inicial automatica nao emitida" severity failure;

    -- Simula retorno de leitura
    ready <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    read_data <= x"3A";
    ready <= '1';
    wait until rising_edge(clk);

    -- Mudanca de endereco deve disparar nova leitura
    SW(9 downto 4) <= "101011";
    wait until rising_edge(clk);
    assert req = '1' and wEn = '0'
      report "dram_iface: mudanca de endereco nao disparou leitura" severity failure;

    -- Escreve com KEY[3] (borda de descida)
    SW(3 downto 0) <= "1010";
    wait until falling_edge(clk);
    KEY(3) <= '0';
    wait until rising_edge(clk);
    assert req = '1' and wEn = '1'
      report "dram_iface: escrita por KEY[3] nao emitida" severity failure;
    KEY(3) <= '1';

    -- Conclusao da escrita deve disparar leitura automatica
    ready <= '0';
    wait until rising_edge(clk);
    ready <= '1';
    wait until rising_edge(clk);
    assert req = '1' and wEn = '0'
      report "dram_iface: leitura automatica apos escrita nao ocorreu" severity failure;

    report "tb_dram_iface: testes concluidos com sucesso" severity note;
    wait;
  end process;
end sim;
