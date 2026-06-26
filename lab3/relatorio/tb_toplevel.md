# Testbench do Top Level — `tb_dram_top_level`

Arquivo: `tb_dram_top_level.vhd` · DUT: `dram_top_level.vhd`
(interface + controlador + reader + PLL + roteamento dos pinos) · **compatível com
VHDL-2002** (roda no ghdl `--std=08` e no ModelSim-Altera/NativeLink em modo padrão).

## Objetivo

Teste de **integração end-to-end**: instancia o projeto completo (`dram_top_level`)
e o exercita como um usuário faria na placa — através de `CLOCK_50`, dos switches
`SW` e dos botões `KEY`, **sem nunca injetar `req`/`ready`/sinais internos** —
verificando o valor mostrado no display `HEX1` (o dado lido). Aqui tudo funciona
junto: a interface gera as requisições, o controlador fala com a memória, e o
caminho de leitura volta até o display.

Caminho sob teste: **usuário (`SW`/`KEY`) → `dram_iface` → `dram_controller` →
modelo de SDRAM → dado lido → `HEX1`**.

## Metodologia

- **Clock de placa = 20 ns (50 MHz)** em `CLOCK_50`, como na DE1-SoC.
- **Stub de PLL realista (`pll_sim_stub.vhd`):** a `pll.vhd` real é uma megafunção
  Altera/Verilog que o ghdl não elabora. O stub mantém a mesma entidade `pll`
  (`refclk`, `rst`, `outclk_0`, `locked`), mas **gera ele próprio um clock de
  ~143 MHz (7 ns)** — a frequência para a qual o controlador foi projetado — e só
  levanta `locked` depois de alguns ciclos de "aquisição". **Isto é proposital:**
  simplesmente repassar os 50 MHz do `refclk` esconderia a temporização apertada
  de captura de leitura (CAS latency + `tAC`) e faria o teste passar pelo motivo
  errado. No Quartus/ModelSim usa-se a PLL real; o stub é só para o ghdl e nunca
  é sintetizado.
- **Observação dos sinais internos da PLL:** `pll_clk` e `pll_locked` são
  internos ao `dram_top_level` e ficam visíveis diretamente sob a hierarquia
  `dut/` no GTKWave e no ModelSim (basta arrastá-los para a Wave). O testbench
  **não usa external names** (eram VHDL-2008 e impediriam a compilação no
  ModelSim-Altera padrão); em vez de checar `locked`, ele prova que a
  inicialização ocorreu esperando o comando **LOAD MODE REGISTER** (que só sai
  depois do clock estar estável), e o reset é segurado por um tempo fixo.
- **Modelo de SDRAM** nos pinos físicos (`DRAM_ADDR`, `DRAM_BA`, `DRAM_DQ`,
  comandos `DRAM_*_N`): igual ao do `tb_dram_controller` — uma linha aberta por
  banco, memória indexada por banco/linha/coluna, CAS latency 3, atraso `tAC` de
  5400 ps e barramento `DRAM_DQ` bidirecional (em `Z` quando ninguém dirige).
- **Decodificação de comandos:** uma função converte `{CS_N,RAS_N,CAS_N,WE_N}`
  (os pinos reais `DRAM_*_N`) em um enum legível (`CMD_NOP`, `CMD_ACTIVE`,
  `CMD_READ_E`, `CMD_WRITE_E`, `CMD_PRECHARGE`, `CMD_AUTO_REFRESH`,
  `CMD_LOAD_MODE`, `CMD_DESELECT`, `CMD_OTHER`) — exposto em `cur_cmd`/`last_cmd`
  e usado para contadores, asserts e sincronização.
- **Helpers de display:** `hex7(nibble)` reproduz a tabela de 7 segmentos do
  projeto (constrói `expected_hex1`); `decode_hex7(HEX1)` faz o caminho inverso
  para mostrar `observed_digit_hex1` na forma de onda; `display_ok` indica em
  tempo real se `HEX1 = expected_hex1`.
- **Sincronização por evento, não só por tempo:** embora o estímulo use esperas
  em µs para imitar o usuário, os pontos de verificação **sincronizam com eventos
  observáveis** via `wait_cmd(...)`: espera-se `CMD_LOAD_MODE` para confirmar o
  init, `CMD_WRITE_E` após pressionar `KEY[3]`, `CMD_READ_E` após trocar de
  endereço, e `CMD_AUTO_REFRESH` no teste de refresh. Isso evita "passar" por
  acaso e dá mensagens de timeout claras.

### Procedimentos de usuário (deixam o teste legível como história)

`press_key(k, dur)`, `set_addr(addr6)`, `set_data(data4)`,
`wait_cmd(cmd, timeout)`, `wait_display(digito, timeout)`,
`user_write(addr6, data4)` e `user_select_addr(addr6)`.
Detalhe importante: em `user_write` o `KEY[3]` é **mantido pressionado** até o
`CMD_WRITE_E` aparecer (a escrita sai ~1 µs após o aperto), senão o pulso de
comando passaria despercebido.

## Linha do tempo — por que os primeiros ~200 µs "parecem parados"

Esta é a observação mais importante para ler a forma de onda **e não confundir
init com travamento**:

- **Reset é ativo em nível alto** dentro do projeto. Na placa o usuário aperta
  `KEY(0)` (ativo em baixo) → `board_rst = not KEY(0)` → `rst` interno em `1`.
  Enquanto a PLL não dá `locked`, `async_rst` também segura o reset.
- O testbench **solta o reset explicitamente**: aperta `KEY(0)='0'`, espera
  segura o reset por um tempo fixo (5 µs, suficiente para a PLL travar) e solta
  `KEY(0)='1'` (reports "Reset aplicado" e "Reset liberado"). O reset interno
  fica retido até a PLL dar `locked` de qualquer forma (`async_rst`).
- Na placa, o controlador roda a **espera obrigatória de power-up do SDRAM = 28600
  ciclos** (~200 µs a 143 MHz) em `NOP`, com `ready=0`. Esse valor é o **generic
  `INIT_WAIT_CYCLES`** (default 28600, propagado do `dram_top_level` para o
  controlador e usado na síntese). **Na simulação o testbench instancia o DUT com
  `generic map (INIT_WAIT_CYCLES => 50)`**, encurtando *só* essa espera de NOP —
  nada funcional muda. Assim o init termina em **~3 µs** e toda a atividade
  (comandos, escrita, leituras, refresh, mudanças de `HEX1`) fica visível **desde
  o início**; o teste inteiro termina perto de **~19 µs**. Sem o override, só
  `CLOCK_50`/`pll_clk`/`DRAM_CLK` "oscilam" e o resto fica plano até ~200 µs.
- `ready`/saídas aparecendo como `U` **somente em t=0** é normal: é o valor
  inicial antes da primeira borda; o reset assíncrono as leva a um valor definido
  já no primeiro delta.

## Cenários testados (a "história")

1. **RESET:** aperta `KEY(0)`, segura por 5 µs (a PLL trava nesse meio tempo) e
   solta o reset.
2. **INIT:** espera `CMD_LOAD_MODE` (último comando da inicialização → prova que
   o init rodou; timeout de 400 µs). Verifica que houve **≥ 8 AUTO REFRESH** na
   inicialização. Em seguida espera a auto-limpeza pós-reset (`CMD_WRITE_E`) e
   `HEX1 = 0`.
3. **Escrita pelo usuário (`WRITE_7_ADDR1`):** seleciona endereço `0x01` e dado
   `7`, pressiona `KEY[3]` → espera `CMD_WRITE_E` e o `CMD_READ_E` de read-back →
   **`HEX1` deve mostrar 7**.
4. **Endereço virgem (`READ_ADDR2`):** muda para o endereço `0x02` (nunca
   escrito), espera o `CMD_READ_E` → **`HEX1` deve mostrar 0**.
5. **Persistência (`READ_ADDR1_AGAIN`):** volta ao endereço `0x01` (com o nibble
   de dados em 0, para provar que o display mostra o **dado armazenado**, não as
   chaves) → **`HEX1` deve continuar 7**.
6. **AUTO REFRESH (`REFRESH_TEST`):** deixado ocioso, `n_auto_refresh` tem que
   incrementar sozinho (falha se nenhum refresh ocorrer em 100 µs).

Há ainda guardas concorrentes contra **contenção no barramento** (`DRAM_DQ` em
`X`, ou o modelo dirigindo durante um WRITE) e um **watchdog** que falha se o
teste não concluir dentro da janela. A mensagem final é
`tb_dram_top_level: todos os cenarios passaram`, seguida de um resumo de
contadores de comando.

## Como rodar

```bash
docker run --rm -v "$PWD":/work -w /work hdlc/ghdl bash -c '
  mkdir -p /tmp/wd && WD=/tmp/wd
  ghdl -a --std=08 --workdir=$WD reader.vhd dram_controller.vhd dram_iface.vhd \
       pll_sim_stub.vhd dram_top_level.vhd tb_dram_top_level.vhd
  ghdl -e --std=08 --workdir=$WD tb_dram_top_level
  ghdl -r --std=08 --workdir=$WD tb_dram_top_level --stop-time=80us --wave=top_level.ghw'
```

> O testbench encurta o init via `generic map (INIT_WAIT_CYCLES => 50)`, então o
> teste todo cabe em ~19 µs e a forma de onda fica cheia de atividade desde t=0.
> O DUT mantém o default 28600 na síntese.

Se o GHW não renderizar bem os enums, gere VCD: troque `--wave=top_level.ghw`
por `--vcd=top_level.vcd`.

Resultado esperado no console:

```
tb_dram_top_level: todos os cenarios passaram
```

> Observação: o `pll_sim_stub.vhd` substitui a `pll.vhd` **apenas na simulação**.
> Não inclua o stub na síntese do Quartus.

### RTL Simulation no Quartus (NativeLink / ModelSim-Altera)

Para os sinais aparecerem na **RTL Simulation** do Quartus, a seção do testbench
no `.qsf` precisa listar **todas** as dependências, em ordem de compilação (a
falta de qualquer uma faz o ModelSim não elaborar e abrir a Wave vazia). Já
corrigido no `dram_top_level.qsf`:

```
EDA_TEST_BENCH_FILE reader.vhd          -section_id tb_dram_top_level
EDA_TEST_BENCH_FILE dram_controller.vhd -section_id tb_dram_top_level
EDA_TEST_BENCH_FILE dram_iface.vhd      -section_id tb_dram_top_level
EDA_TEST_BENCH_FILE pll_sim_stub.vhd    -section_id tb_dram_top_level
EDA_TEST_BENCH_FILE dram_top_level.vhd  -section_id tb_dram_top_level
EDA_TEST_BENCH_FILE tb_dram_top_level.vhd -section_id tb_dram_top_level
```

Como o testbench é **VHDL-2002 compatível** (sem external names), o ModelSim-Altera
o compila no modo padrão. Em *Assignments → Settings → Simulation → NativeLink
settings*, selecione `tb_dram_top_level` como *compile test bench* e rode
*Tools → Run Simulation Tool → RTL Simulation*. Os sinais internos da PLL e do
controlador aparecem na árvore `dut/` para arrastar à Wave.

## Sinais recomendados no GTKWave

Agrupe assim para um print que conta a história sozinho:

- **Usuário/relógios:** `CLOCK_50`, `dut/pll_clk` (clock ~143 MHz da PLL),
  `dut/pll_locked`, `DRAM_CLK`, `KEY`, `SW` (os dois `dut/...` vêm da hierarquia).
- **Fase/display:** `test_phase`, `HEX1`, `expected_hex1`, `expected_digit`,
  `observed_digit_hex1`, `display_ok`.
- **Comando SDRAM:** `cur_cmd`/`last_cmd` (formato enum/ASCII), `bus_cmd`,
  `cmd_count`, `n_active`, `n_read`, `n_write`, `n_precharge`, `n_auto_refresh`,
  `n_load_mode`, e os flags `init_seen`/`write_seen`/`read_seen`/`refresh_seen`.
- **Pinos SDRAM:** `DRAM_CKE`, `DRAM_CS_N`, `DRAM_RAS_N`, `DRAM_CAS_N`,
  `DRAM_WE_N`, `DRAM_BA`, `DRAM_ADDR`, `DRAM_DQ`.
- **Modelo:** `model_dq_drive`, `read_pipeline_valid`, `read_pipeline_counter`,
  `model_read_data`, `model_write_data_seen`, `last_bank`, `last_row`,
  `last_col`, `last_addr`, `mem_idx`.

Coloque `cur_cmd`, `last_cmd` e `test_phase` como **enum/ASCII** no topo. Com o
init curto, a janela **~0–19 µs** já mostra tudo em sequência: PLL locked, reset
liberado, init (PRECHARGE/8× refresh/LOAD MODE), a escrita do 7 via `KEY[3]`, o
read-back, a troca para o endereço virgem (HEX1=0), o retorno ao endereço 1
(HEX1=7) e o auto-refresh.

## O que colocar no relatório

1. **Propósito:** mostrar o sistema completo funcionando ponta a ponta, do
   switch/botão até o display, sobre um modelo realista de SDRAM.
2. **Diferença para os testes unitários:** aqui não se injeta `req`/`ready` à mão
   — usa-se a placa "de verdade" (CLOCK_50, SW, KEY) e observa-se a saída visível
   (`HEX1`) sincronizando com os comandos no barramento. É o teste que mais se
   parece com a demonstração na bancada.
3. **PLL realista:** explique por que o stub gera ~143 MHz (e não repassa 50 MHz)
   e por que isso é necessário para não mascarar a temporização de leitura; cite
   o uso de `locked` no caminho de reset (`dut/pll_locked`, observável na
   hierarquia).
4. **Linha do tempo reset → init → operações:** deixe claro que o reset é ativo
   alto (botão `KEY(0)` ativo baixo), que o init ocupa ~200 µs (espera de
   power-up do SDRAM) — explicando por que a forma de onda "parece parada" no
   começo — e que `U` em t=0 é só o valor inicial.
5. **Os cenários** (lista acima) e o que cada um demonstra: init completo;
   escrita via `KEY[3]` + read-back; endereço virgem lê 0; **persistência**; e
   **auto-refresh** espontâneo.
6. **Decodificação de comandos:** mostre `cur_cmd`/`bus_cmd` e os contadores
   confirmando a sequência ACTIVATE → WRITE/READ → PRECHARGE e os 8 refresh do
   init.
7. **Forma de onda:** print do GTKWave com os grupos acima, marcando reset
   liberado, init, escrita, as duas leituras e o auto-refresh.
8. **Resultado:** transcreva `todos os cenarios passaram` e o resumo de
   contadores, concluindo que o projeto integrado está correto.

----------------
## Análise da Forma de Onda — Testbench do Top Level

A forma de onda apresentada corresponde à simulação RTL do testbench `tb_dram_top_level`, que valida o projeto integrado completo. Neste teste, o DUT instanciado é o `dram_top_level`, contendo a interface com o usuário, o controlador SDRAM, o leitor dos displays, a PLL simulada e o roteamento dos pinos externos.

Diferente dos testes unitários, aqui o estímulo é aplicado da mesma forma que ocorreria na placa: por meio do clock externo `CLOCK_50`, dos switches `SW` e dos botões `KEY`. As operações internas de leitura e escrita não são injetadas diretamente no controlador. Elas são consequência do funcionamento conjunto da interface e do controlador.

No trecho mostrado, observa-se a fase inicial da simulação, indicada pelo sinal `test_phase = PH_INIT`. Isso significa que o sistema ainda está executando a inicialização da SDRAM. Durante essa etapa, o controlador prepara a memória para uso, emitindo comandos de configuração e refresh antes de aceitar operações normais de leitura e escrita.

O sinal `CLOCK_50` representa o clock de entrada da placa, enquanto `DRAM_CLK` representa o clock enviado à SDRAM. A presença desses dois sinais alternando mostra que o top-level está propagando corretamente os clocks necessários para o funcionamento do sistema.

Os sinais de comando da SDRAM são decodificados no testbench pelo sinal `bus_cmd`. No trecho mostrado, aparecem comandos como `CMD_AUTO_REFRESH` e `CMD_NOP`. O comando `CMD_AUTO_REFRESH` indica que o controlador está executando ciclos de refresh, necessários para manter os dados válidos em uma memória SDRAM dinâmica. Já os comandos `CMD_NOP` aparecem entre comandos reais, respeitando os tempos exigidos pelo protocolo da memória.

Também é possível observar que o barramento `DRAM_DQ` permanece em alta impedância (`Z`) durante essa fase. Esse comportamento é esperado, pois durante a inicialização e os comandos de refresh não há transferência de dados de leitura ou escrita. O barramento de dados só deve ser dirigido durante operações de escrita pelo controlador ou durante operações de leitura pelo modelo de SDRAM.

Os sinais de debug adicionados ao testbench tornam a forma de onda mais interpretável. O sinal `test_phase` indica a etapa do teste, enquanto `bus_cmd` mostra o comando SDRAM decodificado. Contadores de comandos, como os de refresh, também ajudam a confirmar que os eventos esperados realmente ocorreram no barramento.

Dessa forma, esse trecho da simulação demonstra que o top-level está integrado corretamente ao controlador SDRAM e que, após o reset, o sistema inicia a sequência de preparação da memória. A presença de comandos `AUTO_REFRESH` confirma que o controlador não está parado: ele está emitindo comandos SDRAM válidos e respeitando a lógica de inicialização/refresh.

Portanto, esta forma de onda valida a primeira parte do teste de integração: o projeto completo recebe o clock externo, mantém os sinais de interface em estado inicial, aciona o controlador de memória e executa comandos SDRAM de inicialização. Para completar a validação do top-level, devem ser analisados também os trechos posteriores da simulação, nos quais aparecem as fases de escrita via `KEY[3]`, leitura automática, atualização de `HEX1` e persistência do dado armazenado.
