# Documentação do Projeto: Máquina de Vendas (Vending Machine)

## Visão Geral

Este projeto implementa um sistema de máquina de vendas em VHDL, integrado em uma placa FPGA Cyclone V. O sistema gerencia a seleção de produtos, processamento de pagamentos e exibição de informações através de displays de 7 segmentos e LEDs.

---

## Estrutura do Código

O projeto é organizado em módulos VHDL hierárquicos, onde cada componente possui uma responsabilidade específica:

```
vending_machine (top-level)
├── vending_fsm (Máquina de Estados)
├── selector (Seletor de Produtos)
├── payment_handler (Manipulador de Pagamento)
├── value_display (Exibição de Valores)
│   └── bin2hex × 4 (Conversores para 7 Segmentos)
└── led (Controlador de LEDs)
```

### 1. **Módulo Principal: vending_machine** 
[vending_machine.vhd](vending_machine.vhd)

O arquivo principal que integra todos os componentes. Define as entradas (botões, chaves seletoras, clock) e saídas (displays, LEDs) da placa.

**Portas de Entrada:**
- `KEY1, KEY0`: Botões de controle (ativos em nível baixo)
- `SW[9:0]`: Chaves seletoras para produto e valor de moeda
- `CLOCK_50`: Clock de 50 MHz

**Portas de Saída:**
- `HEX0-HEX3, HEX5`: Displays de 7 segmentos
- `LEDR0, LEDR1`: LEDs de indicação

**Funcionamento Principal:**

```vhdl
-- Detecção de pulso de botão (transição de alto para baixo)
process(CLOCK_50)
begin
    if rising_edge(CLOCK_50) then
        key_0 <= KEY0;
        key_1 <= KEY1;

        -- Gera pulso de um ciclo quando o botão é pressionado
        pulse_advance <= '0';
        if key_0 = '1' and KEY0 = '0' then
            pulse_advance <= '1';  -- Transição de nível alto para baixo detectada
        end if;
        
        pulse_reset <= '0';
        if key_1 = '1' and KEY1 = '0' then
            pulse_reset <= '1';
        end if;
    end if;
end process;
```

**Sinal de Reset Global:**

```vhdl
-- Reset quando transição de s2/s3 para s0 (voltando ao estado inicial)
reset_values <= '1' when (state_prev /= "00" and state_sig = "00") else '0';
```

---

### 2. **Máquina de Estados Finita: vending_fsm**
[vending_fsm.vhd](vending_fsm.vhd)

Implementa a lógica de controle da máquina de vendas através de 4 estados:

| Estado | Código | Significado |
|--------|--------|------------|
| **s0** | "00" | Aguardando seleção de produto |
| **s1** | "01" | Aguardando pagamento completo |
| **s2** | "10" | Pagamento completo - exibindo por 1 segundo |
| **s3** | "11" | Cancelamento - reset por 1 segundo |

**Implementação da Máquina de Estados:**

```vhdl
architecture rtl of vending_fsm is
    type state_type is (s0, s1, s2, s3);
    signal state : state_type := s0;
    signal counter : integer := 0;
    constant ONE_SECOND : integer := 50000000;  -- 50MHz clock = 50M ciclos em 1s
begin
    -- Lógica de transição de estados
    process (clk)
    begin
        -- Reset prioritário: se em s1 e botão reset é pressionado
        if state = s1 and pulse_reset = '1' then
            state <= s3;
            counter <= 0;

        elsif rising_edge(clk) then
            -- Transição de s0 para s1: quando botão avança é pressionado
            if pulse_advance = '1' and state = s0 then
                state <= s1;
                counter <= 0;

            -- Transição de s1 para s2: quando pagamento é completado
            elsif state = s1 and finish_signal = '1' then
                state <= s2;
                counter <= 0;

            -- Transição de s2 para s0: após 1 segundo
            elsif state = s2 then
                if counter < ONE_SECOND then
                    counter <= counter + 1;
                else
                    state <= s0;
                    counter <= 0;
                end if;

            -- Transição de s3 para s0: após 1 segundo (reset timeout)
            elsif state = s3 then
                if counter < ONE_SECOND then
                    counter <= counter + 1;
                else
                    state <= s0;
                    counter <= 0;
                end if;
            end if;
        end if;
    end process;

    -- Saída combinacional (Moore output)
    process (state)
    begin
        case state is
            when s0 => state_out <= "00";
            when s1 => state_out <= "01";
            when s2 => state_out <= "10";
            when s3 => state_out <= "11";
        end case;
    end process;
end rtl;
```

---

### 3. **Seletor de Produtos: selector**
[selector.vhd](selector.vhd)

Mapeia a seleção de produto (4 bits de entrada) para seu preço correspondente. Só opera quando em estado `s0`.

```vhdl
process(SELECTOR, STATE)
begin
    if STATE = "00" then  -- Só permite seleção em s0
        ID <= SELECTOR;
        case SELECTOR is
            when "0000" => PRICE <= "0001111101";  -- Produto 0: 125 centavos
            when "0001" => PRICE <= "0100101100";  -- Produto 1: 300 centavos
            -- ... mais produtos ...
            when others => PRICE <= "0000000000";
        end case;
    else
        null;  -- Ignora entrada em outros estados
    end if;
end process;
```

---

### 4. **Manipulador de Pagamento: payment_handler**
[payment_handler.vhd](payment_handler.vhd)

Acumula os valores de moedas selecionadas e verifica se o pagamento é suficiente para o produto.

**Mapeamento de Valores (bits 4-9 das chaves):**

| Switch | Valor |
|--------|-------|
| SW[4]  | 5 centavos |
| SW[5]  | 10 centavos |
| SW[6]  | 25 centavos |
| SW[7]  | 50 centavos |
| SW[8]  | 100 centavos (1 real) |
| SW[9]  | 200 centavos (2 reais) |

**Acumulação de Valores:**

```vhdl
-- Processo para identificar qual moeda foi selecionada
process(cash_selector)
begin
    cash_amount <= 0;  -- padrão
    
    if cash_selector(0) = '1' then      -- 5 centavos
        cash_amount <= 5;
    elsif cash_selector(1) = '1' then   -- 10 centavos
        cash_amount <= 10;
    elsif cash_selector(2) = '1' then   -- 25 centavos
        cash_amount <= 25;
    -- ... mais valores ...
    end if;
end process;

-- Acumula valor quando botão é pressionado (apenas em s1)
process(clk)
    variable new_val : integer;
begin
    if rising_edge(clk) then
        if reset_signal = '1' then
            value_accumulator <= "0000000000";  -- Reset quando volta a s0
        elsif confirm_key = '1' then  -- Botão pressionado
            if state = "01" and bit_count <= 1 then  -- Apenas em s1 e 1 switch selecionado
                new_val := to_integer(unsigned(value_accumulator)) + cash_amount;
                
                -- Limita ao máximo 1023 centavos
                if new_val > 1023 then
                    value_accumulator <= std_logic_vector(to_unsigned(1023, 10));
                else
                    value_accumulator <= std_logic_vector(to_unsigned(new_val, 10));
                end if;
            end if;
        end if;
    end if;
end process;

-- Gera sinal de conclusão quando valor >= preço
finish_signal <= '1' when to_integer(unsigned(value_accumulator)) >= 
                          to_integer(unsigned(product_price)) else '0';
```

---

### 5. **Exibição de Valores: value_display**
[value_display.vhd](value_display.vhd)

Converte um valor inteiro de 10 bits (0-1023) em 4 dígitos decimais para exibição nos displays HEX0-HEX3.

```vhdl
process(value)
    variable val_i : integer range 0 to 1023;
    variable ones, tens, hundreds, thousands : integer range 0 to 9;
begin
    val_i := to_integer(unsigned(value));

    -- Descomposição em dígitos decimais
    ones      := val_i mod 10;           -- Dígito das unidades
    tens      := (val_i / 10) mod 10;    -- Dígito das dezenas
    hundreds  := (val_i / 100) mod 10;   -- Dígito das centenas
    thousands := (val_i / 1000) mod 10;  -- Dígito dos milhares

    -- Conversão para std_logic_vector
    d0 <= std_logic_vector(to_unsigned(ones, 4));
    d1 <= std_logic_vector(to_unsigned(tens, 4));
    d2 <= std_logic_vector(to_unsigned(hundreds, 4));
    d3 <= std_logic_vector(to_unsigned(thousands, 4));
end process;

-- Instancia 4 conversores bin2hex para cada dígito
u_hex0 : entity work.bin2hex port map (bin => d0, hex => hex0);
u_hex1 : entity work.bin2hex port map (bin => d1, hex => hex1);
u_hex2 : entity work.bin2hex port map (bin => d2, hex => hex2);
u_hex3 : entity work.bin2hex port map (bin => d3, hex => hex3);
```

---

### 6. **Conversor Binário para Hexadecimal: bin2hex**
[bin2hex.vhd](bin2hex.vhd)

Converte 4 bits (0-15) em código de 7 segmentos para exibição em displays LCD/LED.

```vhdl
-- Mapeamento direto de valor binário para código de 7 segmentos
with BIN select
    HEX <= "1000000" when "0000", -- 0: seg a,b,c,d,e,f (sem g)
           "1111001" when "0001", -- 1: seg b,c
           "0100100" when "0010", -- 2: seg a,b,d,e,g
           "0110000" when "0011", -- 3: seg a,b,c,d,g
           "0011001" when "0100", -- 4: seg b,c,f,g
           "0010010" when "0101", -- 5: seg a,c,d,f,g
           "0000010" when "0110", -- 6: seg a,c,d,e,f,g (sem b)
           "1111000" when "0111", -- 7: seg a,b,c
           "0000000" when "1000", -- 8: todos os segmentos
           "0010000" when "1001", -- 9: seg a,b,c,d,f,g (sem e)
           "0001000" when "1010", -- A: seg a,b,c,e,f,g
           "0000011" when "1011", -- B: seg c,d,e,f,g
           "1000110" when "1100", -- C: seg a,d,e,f
           "0100001" when "1101", -- D: seg b,c,d,e,g
           "0000110" when "1110", -- E: seg a,d,e,f,g
           "0001110" when "1111", -- F: seg a,e,f,g
           "1111111" when others; -- Apagado
```

---

### 7. **Controlador de LEDs: led**
[led.vhd](led.vhd)

Módulo simples que controla os LEDs conforme condições da máquina.

```vhdl
architecture rtl of led is
begin
    led_out <= condition;  -- Passa diretamente a condição para o LED
end rtl;
```

**Lógica de Controle de LEDs:**
- **LEDR0**: Acende quando há valor acumulado > 0
- **LEDR1**: Acende quando pagamento é completo (finish_signal = '1')

---

## Fluxo de Operação

1. **Estado s0 (Seleção):** Usuário seleciona produto via chaves. Ao pressionar KEY0, transita para s1.

2. **Estado s1 (Pagamento):** Usuário seleciona moedas e pressiona KEY0 para adicionar à conta. Quando valor acumulado ≥ preço do produto, `finish_signal` vai para '1', transitando para s2.

3. **Estado s2 (Confirmação):** Sistema exibe o valor pago por 1 segundo, depois retorna a s0.

4. **Estado s3 (Cancelamento):** Se KEY1 for pressionado em s1, o sistema cancela a operação, exibe por 1 segundo e retorna a s0.

---

## Considerações de Implementação

- **Detecção de Borda:** Transições de botão são detectadas via mudança de nível (high-to-low) para gerar pulsos de um ciclo.
- **Temporizador:** Usa contador que incrementa a cada ciclo de clock. Para 1 segundo a 50MHz: 50.000.000 ciclos.
- **Saturação:** Valor máximo acumulado é 1023 centavos (10,23 reais).
- **Modo Seleção Única:** Em s1, apenas uma moeda pode ser selecionada por vez (`bit_count <= 1`).

---

## Testbenches

Testbenches foram implementados para cada módulo principal:

- [tb_vending_fsm.vhd](tb_vending_fsm.vhd) - Testa transições de estado
- [tb_selector.vhd](tb_selector.vhd) - Verifica mapeamento de preços
- [tb_payment_handler.vhd](tb_payment_handler.vhd) - Valida acumulação e finish_signal
- [tb_value_display.vhd](tb_value_display.vhd) - Testa conversão para dígitos decimais
- [tb_bin2hex.vhd](tb_bin2hex.vhd) - Verifica todos os códigos de 7 segmentos
- [tb_vending_machine.vhd](tb_vending_machine.vhd) - Testa integração completa
