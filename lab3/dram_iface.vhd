library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dram_iface is
  port (
    clk          : in  std_logic;
    rst      : in  std_logic;
    addr         : in  std_logic_vector(12 downto 0);
    data_in      : in  std_logic_vector(7 downto 0);
    data_out     : out std_logic_vector(7 downto 0);
    we           : in  std_logic
  );
end dram_iface;