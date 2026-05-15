library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dram_controller is
    port(
        clk : IN std_logic;
        rst : IN std_logic;
        SW : IN std_logic_vector (9 downto 0);
        KEY : IN std_logic_vector (3 downto 0);
        data_in : IN std_logic_vector (7 downto 0);
        data_out : OUT std_logic_vector (7 downto 0);
        HEX0 : OUT std_logic_vector (6 downto 0);
        HEX1 : OUT std_logic_vector (6 downto 0);
        HEX4 : OUT std_logic_vector (6 downto 0);
        HEX5 : OUT std_logic_vector (6 downto 0);
        adress : OUT std_logic_vector (25 downto 0);
        req : OUT std_logic;
        wEn : OUT std_logic;
        ready : OUT std_logic;
    )

architecture rtl of dram_controller is
    type state is (init, rdy, act, read, write, prech, refresh);
    signal current_state : state := init;
    signal counter : integer := 0;
    signal refresh_c : integer := 0;
    constant NOP : std_logic_vector (25 downto 0) := x"3F38000";
    constant PRE : std_logic_vector (25 downto 0) := x"3F10000"; --13 e 14 eh o banco
    constant PREALL : std_logic_vector (25 downto 0) := x"3F10400";
    constant ACT : std_logic_vector (25 downto 0) := x"3F18000"; --14...0 eh o endereço
    constant REF : std_logic_vector (25 downto 0) := x"3F88000"; --refresh all
    constant MRS : std_logic_vector (25 downto 0) := x"30"; --load mode register
    --commands
    constant READ  : std_logic_vector (25 downto 0) := x"3F28000";
    constant WRITE : std_logic_vector (25 downto 0) := x"3F20000";
    --reader
    signal buffered_req  : std_logic;
    signal buffered_wEn  : std_logic;
    signal buffered_addr : std_logic_vector(25 downto 0);
    signal buffered_data : std_logic_vector(7 downto 0);
    signal cmd_ack       : std_logic := '0';
begin
    reader_inst : entity work.reader
        port map (
            clk          => clk,
            rst          => rst,
            req_in       => req,      -- Input port from entity
            wEn_in       => wEn,      -- Input port from entity
            addr_in      => adress,   -- Input port from entity
            data_in      => data_in,  -- Input port from entity
            req_pending  => buffered_req,
            wEn_out      => buffered_wEn,
            addr_out     => buffered_addr,
            data_out     => buffered_data,
            cmd_ack      => cmd_ack
        );
    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= init;
            ready <= '0';
            counter <= 0;
            refresh_c <= 0;
            cmd_ack <= '0';
        elsif rising_edge(clk) then
            -- Garante que o ack seja um pulso de apenas 1 ciclo de clock
            cmd_ack <= '0';

            case current_state is
                -- INICIALIZACAO
                when init =>
                    if 2<counter and counter<5 then
                        adress<=NOP;
                    elsif 28599<counter and counter<28602 then --precharge all banks
                        adress<=PREALL;
                    elsif 28602<counter and counter<28619 then --autorefresh 8x
                        if refresh_c=0 then 
                            adress<=REF;
                        elsif refresh_c=2 then 
                            adress<=NOP;
                        elsif refresh_c=3 then 
                            refresh_c<=0;
                        end if;
                        refresh_c <= refresh_c + 1; -- Adicionado para evitar loop infinito na compilação
                    elsif 28619<counter and counter<28621 then --load MODE register
                        adress<=MRS;  
                    elsif 28621<counter and counter<28624 then --NOP
                        adress<=NOP;
                    elsif 28624<counter then --active
                        adress<=NOP;
                        ready<='1';
                        counter<=0; 
                        current_state<=rdy;
                    else
                        adress<=NOP; 
                    end if;
                
                -- ESTADO: READY
                when rdy =>
                    ready <= '1';
                    adress <= NOP; -- Mantém NOP enquanto ocioso
                    
                    -- Prioridade 1: Rotina de refresh periódico
                    if counter >= 1000 then 
                        ready <= '0';
                        counter <= 0;
                        current_state <= refresh;
                        
                    -- Prioridade 2: Processar requisição pendente do reader
                    elsif buffered_req = '1' then
                        ready <= '0';
                        cmd_ack <= '1'; -- Pulso para o reader limpar o request do buffer
                        adress <= ACT or buffered_addr; -- Envia ACTIVE combinando com o endereço do usuário
                        counter <= 0;
                        current_state <= act;
                    end if;

                -- ACTIVATE
                when act => -- Aguarda 3 ciclos (tRCD)
                    if counter = 2 then
                        if buffered_wEn = '1' then
                            adress <= WRITE or buffered_addr; -- Dispara WRITE
                            current_state <= write;
                        else
                            adress <= READ or buffered_addr;  -- Dispara READ
                            current_state <= read;
                        end if;
                        counter <= 0;
                    else
                        adress <= NOP;
                    end if;

                -- READ
                when read => -- Aguarda 3 ciclos (tCAS Latency)
                    if counter = 2 then
                        data_out <= data_in; -- Captura o dado que chega da DRAM
                        adress <= PREALL;    -- Inicia o precharge de todos os bancos
                        current_state <= prech;
                        counter <= 0;
                    else
                        adress <= NOP;
                    end if;
                
                -- WRITE
                when write => -- Aguarda 3 ciclos (tWR)
                    if counter = 2 then
                        adress <= PREALL;    -- Inicia o precharge após a escrita terminar
                        current_state <= prech;
                        counter <= 0;
                    else
                        adress <= NOP;
                    end if;
                
                -- PRECHARGE
                when prech => -- Aguarda 3 ciclos (tRP)
                    if counter = 2 then
                        current_state <= rdy; -- Finalizou, volta para receber novo comando
                        counter <= 0;
                    else
                        adress <= NOP;
                    end if;

                -- REFRESH
                when refresh => -- Rotina de Refresh
                    if counter = 1 then
                        adress <= PREALL;
                    elsif counter = 4 then
                        adress <= REF;
                    elsif counter = 7 then 
                        adress <= REF;
                    elsif counter = 10 then
                        current_state <= rdy;
                        counter <= 0;
                    else
                        adress <= NOP;
                    end if;

            end case;

           counter<=counter+1;
            
        end if;
    end process;
end rtl;
