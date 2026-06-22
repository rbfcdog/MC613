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
  signal address_reg       : std_logic_vector(25 downto 0) := (others => '0');
  signal write_data_reg    : std_logic_vector(7 downto 0) := (others => '0');
  signal last_address      : std_logic_vector(25 downto 0) := (others => '0');
  signal last_address_seen : std_logic := '0';
  signal read_latch        : std_logic_vector(7 downto 0) := (others => '0');
  signal req_reg           : std_logic := '0';
  signal wen_reg           : std_logic := '0';
  signal key3_prev         : std_logic := '1';
  signal pending_write     : std_logic := '0';
  signal pending_address   : std_logic_vector(25 downto 0) := (others => '0');
  signal pending_data      : std_logic_vector(7 downto 0) := (others => '0');

  -- Two-stage synchronizers for the asynchronous board inputs. Sampling SW and
  -- KEY directly with the 143 MHz clock lets a switch/button change near a
  -- clock edge drive the FSM metastable, which can wedge it until reset.
  signal sw_meta   : std_logic_vector(9 downto 0) := (others => '0');
  signal sw_sync   : std_logic_vector(9 downto 0) := (others => '0');
  signal key_meta  : std_logic_vector(3 downto 0) := (others => '1');
  signal key_sync  : std_logic_vector(3 downto 0) := (others => '1');

  -- Set by reset: the first thing the iface does after a reset is write 0 to
  -- the currently selected address, so that "reset" actually zeroes the value
  -- at the current address instead of re-reading whatever the SDRAM still holds.
  signal startup_clear : std_logic := '1';

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
    14 => sw_sync(7),
    13 => sw_sync(6),
    12 => sw_sync(9),
    11 => sw_sync(8),
    2  => sw_sync(5),
    1  => sw_sync(4),
    others => '0'
  );

  address    <= address_reg;
  write_data <= write_data_reg;
  req        <= req_reg;
  wEn        <= wen_reg;

  HEX0 <= hex_to_7seg(sw_sync(3 downto 0));
  HEX1 <= hex_to_7seg(read_latch(3 downto 0));
  -- Address SW[9:4] shown as a 6-bit value across two hex digits:
  --   HEX4 = low nibble  = SW7 SW6 SW5 SW4  (weights 8 4 2 1)
  --   HEX5 = high nibble = SW9 SW8          (weights 32 16)
  -- The old HEX5 also OR-ed in SW6, double-counting it (SW6 wrongly bumped
  -- the high digit), which is why the third switch read 0x14 instead of 0x04.
  HEX4 <= hex_to_7seg(sw_sync(7 downto 4));
  HEX5 <= hex_to_7seg("00" & sw_sync(9 downto 8));

  process(clk, rst)
    variable write_edge_v : boolean;
    variable write_addr_v : std_logic_vector(25 downto 0);
    variable write_data_v : std_logic_vector(7 downto 0);
  begin
    if rst = '1' then
      state             <= READY_ST;
      address_reg       <= (others => '0');
      write_data_reg    <= (others => '0');
      last_address      <= (others => '0');
      last_address_seen <= '0';
      read_latch        <= (others => '0');
      req_reg           <= '0';
      wen_reg           <= '0';
      key3_prev         <= '1';
      pending_write     <= '0';
      pending_address   <= (others => '0');
      pending_data      <= (others => '0');
      sw_meta           <= (others => '0');
      sw_sync           <= (others => '0');
      key_meta          <= (others => '1');
      key_sync          <= (others => '1');
      startup_clear     <= '1';
    elsif rising_edge(clk) then
      -- Synchronize the asynchronous board inputs (two flip-flop stages).
      sw_meta  <= SW;
      sw_sync  <= sw_meta;
      key_meta <= KEY;
      key_sync <= key_meta;

      write_edge_v := (key3_prev = '1' and key_sync(3) = '0');

      req_reg <= '0';
      wen_reg <= '0';
      key3_prev <= key_sync(3);

      if write_edge_v then
        pending_write   <= '1';
        pending_address <= current_address;
        pending_data    <= "0000" & sw_sync(3 downto 0);
      end if;

      case state is
        when READY_ST =>
          if ready = '1' then
            if startup_clear = '1' then
              -- First action after reset: zero the currently selected cell.
              address_reg       <= current_address;
              write_data_reg    <= (others => '0');
              last_address      <= current_address;
              last_address_seen <= '1';
              startup_clear     <= '0';
              req_reg           <= '1';
              wen_reg           <= '1';
              state             <= REQ_WRITE_ST;
            elsif pending_write = '1' or write_edge_v then
              if write_edge_v then
                write_addr_v := current_address;
                write_data_v := "0000" & sw_sync(3 downto 0);
              else
                write_addr_v := pending_address;
                write_data_v := pending_data;
              end if;

              address_reg       <= write_addr_v;
              write_data_reg    <= write_data_v;
              last_address      <= write_addr_v;
              last_address_seen <= '1';
              pending_write     <= '0';
              req_reg           <= '1';
              wen_reg           <= '1';
              state             <= REQ_WRITE_ST;
            elsif last_address_seen = '0' or current_address /= last_address then
              address_reg <= current_address;
              write_data_reg <= "0000" & sw_sync(3 downto 0);
              req_reg      <= '1';
              wen_reg      <= '0';
              last_address <= current_address;
              last_address_seen <= '1';
              state        <= REQ_READ_ST;
            end if;
          end if;

        when REQ_READ_ST =>
          -- Wait until the controller has actually accepted the request
          -- (ready goes low) before waiting for completion. Otherwise we
          -- would see the leftover ready='1' from the previous idle state
          -- and latch the previous operation's read_data.
          if ready = '0' then
            state <= WAIT_READ_ST;
          end if;

        when WAIT_READ_ST =>
          if ready = '1' then
            read_latch <= read_data;
            state      <= READY_ST;
          end if;

        when REQ_WRITE_ST =>
          -- Same handshake guard as REQ_READ_ST: only advance once the
          -- controller has taken the request and dropped ready.
          if ready = '0' then
            state <= WAIT_WRITE_ST;
          end if;

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
            
