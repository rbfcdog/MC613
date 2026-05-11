library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dram_iface is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    SW         : in  std_logic_vector(9 downto 0);
    KEY        : in  std_logic_vector(3 downto 0);
    HEX0       : out std_logic_vector(6 downto 0);
    HEX1       : out std_logic_vector(6 downto 0);
    HEX4       : out std_logic_vector(6 downto 0);
    HEX5       : out std_logic_vector(6 downto 0);
    address    : out std_logic_vector(25 downto 0);
    write_data : out std_logic_vector(7 downto 0);
    read_data  : in  std_logic_vector(7 downto 0);
    req        : out std_logic;
    wEn        : out std_logic;
    ready      : in  std_logic
  );
end dram_iface;

architecture rtl of dram_iface is
  type state_t is (READY_ST, REQ_READ_ST, WAIT_READ_ST, REQ_WRITE_ST, WAIT_WRITE_ST);

  signal state             : state_t := READY_ST;
  signal current_address   : std_logic_vector(25 downto 0);
  signal last_address      : std_logic_vector(25 downto 0) := (others => '0');
  signal last_address_seen : std_logic := '0';
  signal read_latch        : std_logic_vector(7 downto 0) := (others => '0');
  signal req_reg           : std_logic := '0';
  signal wen_reg           : std_logic := '0';
  signal key3_prev         : std_logic := '1';

  function hex_to_7seg(value : std_logic_vector(3 downto 0)) return std_logic_vector is
  begin
    case value is
      when "0000" => return "1000000";
      when "0001" => return "1111001";
      when "0010" => return "0100100";
      when "0011" => return "0110000";
      when "0100" => return "0011001";
      when "0101" => return "0010010";
      when "0110" => return "0000010";
      when "0111" => return "1111000";
      when "1000" => return "0000000";
      when "1001" => return "0010000";
      when "1010" => return "0001000";
      when "1011" => return "0000011";
      when "1100" => return "1000110";
      when "1101" => return "0100001";
      when "1110" => return "0000110";
      when others => return "0001110";
    end case;
  end function;
begin
  current_address <= (
    25 => SW(9),
    23 => SW(8),
    22 => SW(7),
    21 => SW(6),
    1  => SW(5),
    0  => SW(4),
    others => '0'
  );

  address    <= current_address;
  write_data <= "0000" & SW(3 downto 0);
  req        <= req_reg;
  wEn        <= wen_reg;

  HEX0 <= hex_to_7seg(SW(3 downto 0));
  HEX1 <= hex_to_7seg(read_latch(3 downto 0));
  HEX4 <= hex_to_7seg(SW(7 downto 4));
  HEX5 <= hex_to_7seg("0" & SW(9 downto 8) & SW(6));

  process(clk, rst)
  begin
    if rst = '1' then
      state             <= READY_ST;
      last_address      <= (others => '0');
      last_address_seen <= '0';
      read_latch        <= (others => '0');
      req_reg           <= '0';
      wen_reg           <= '0';
      key3_prev         <= '1';
    elsif rising_edge(clk) then
      req_reg <= '0';
      wen_reg <= '0';
      key3_prev <= KEY(3);

      case state is
        when READY_ST =>
          if ready = '1' then
            if key3_prev = '1' and KEY(3) = '0' then
              req_reg <= '1';
              wen_reg <= '1';
              state   <= REQ_WRITE_ST;
            elsif last_address_seen = '0' or current_address /= last_address then
              req_reg      <= '1';
              wen_reg      <= '0';
              last_address <= current_address;
              last_address_seen <= '1';
              state        <= REQ_READ_ST;
            end if;
          end if;

        when REQ_READ_ST =>
          state <= WAIT_READ_ST;

        when WAIT_READ_ST =>
          if ready = '1' then
            read_latch <= read_data;
            state      <= READY_ST;
          end if;

        when REQ_WRITE_ST =>
          last_address      <= current_address;
          last_address_seen <= '1';
          state             <= WAIT_WRITE_ST;

        when WAIT_WRITE_ST =>
          if ready = '1' then
            req_reg <= '1';
            wen_reg <= '0';
            state   <= REQ_READ_ST;
          end if;
      end case;
    end if;
  end process;
end rtl;
            