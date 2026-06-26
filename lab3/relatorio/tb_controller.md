# Testbench do Controlador — `tb_dram_controller`

Arquivo: `tb_dram_controller.vhd` · DUT: `dram_controller.vhd` (+ `reader.vhd`)

## Objetivo

Validar **isoladamente** a FSM de protocolo SDRAM (`dram_controller`): a
inicialização do chip, a sequência ACTIVATE → READ/WRITE → PRECHARGE, a captura
correta do dado de leitura (o ponto crítico do laboratório) e o auto-refresh
periódico. O testbench fala diretamente com o handshake do lado da interface
(`req`/`wEn`/`addr_in`/`write_data_in`) e **modela um SDRAM real** nos pinos
`DRAM_*`.

## Metodologia — por que tem que ser fiel ao hardware

Esta é a parte mais importante: para reproduzir o bug real de leitura (ler
`0xFF` da memória), o testbench **precisa** modelar o tempo do chip:

- **Período de clock = 7 ns (~143 MHz)** — a frequência real do projeto.
- **`DRAM_CLK = not clk`** — o clock do chip está invertido em relação ao da
  FPGA (dá margem de setup), exatamente como no `dram_top_level`.
- **`tAC = 5400 ps`** — o dado de leitura só fica válido ~tAC *depois* da borda
  do clock do chip. Modelado com `DRAM_DQ <= tb_dq_data after TAC ...`.
- **CAS latency 3** — o modelo entrega o dado 3 clocks de SDRAM após o READ.
- **Barramento DQ bidirecional:** o controlador dirige `DRAM_DQ` durante o WRITE;
  o modelo dirige durante o READ (atrasado por tAC); o resto do tempo fica em `Z`.

Sem tAC e sem o período de 7 ns o teste passaria com um valor de captura errado
(4), mascarando o bug que só aparece na placa. Com o modelo fiel, **apenas a
captura na borda de descida + `READ_CAPTURE_CYCLES = 5` funciona**.

O modelo de SDRAM (`sdram_model`) é mínimo mas suficiente: guarda a linha aberta
no ACTIVATE, grava na memória no WRITE e, no READ, devolve a célula após a CAS
latency. A indexação (`mem_idx`) reproduz como o controlador endereça a célula
(banco + linha + coluna).

## Cenários testados (a "história")

1. **INIT:** depois do reset, o controlador roda toda a sequência de
   inicialização (precharge, 8 auto-refresh, load mode register) e levanta
   `ready`. O teste falha se `ready` ficar preso em 0.
2. **WRITE 0x5A em A, depois READ em A** → tem que devolver `0x5A`.
3. **Independência de endereços:** WRITE 0x3C em B, READ B (=0x3C), READ A
   (ainda 0x5A) — provando que endereços diferentes não se contaminam.
4. **AUTO REFRESH:** deixado ocioso, o controlador tem que emitir um comando de
   refresh sozinho (verificado observando `bus_cmd = CMD_AR`).

O procedimento `dram_op` encapsula a **regra de handshake**: garante partir de
`ready='1'`, pulsa `req`, espera `ready='0'` (controlador aceitou) e depois
`ready='1'` (terminou). Checar só `ready='1'` correria com o `ready` ocioso
anterior e leria o dado da operação passada (erro de atraso por 1).

## Observabilidade (sinais de debug no waveform)

Além dos pinos, o testbench exporta sinais que tornam a forma de onda
auto-explicativa, todos visíveis no GTKWave:

- **`dram_cmd_dec`** (enum `cmd_t`): comando SDRAM decodificado de
  `{CS_N,RAS_N,CAS_N,WE_N}` — `CMD_NOP`, `CMD_ACTIVE`, `CMD_READ_E`,
  `CMD_WRITE_E`, `CMD_PRECHARGE`, `CMD_AUTO_REFRESH`, `CMD_LOAD_MODE`.
- **`test_phase`** (enum): fase atual (`PH_INIT`, `PH_WRITE_A`, `PH_READ_A`,
  `PH_WRITE_B`, `PH_READ_B`, `PH_READ_A_AGAIN`, `PH_REFRESH_TEST`, `PH_DONE`).
- **Contadores:** `cmd_count`, `n_activate`, `n_read`, `n_write`, `n_precharge`,
  `n_refresh`, `n_load_mode`.
- **Modelo de SDRAM:** `model_read_data`, `model_write_data_seen`,
  `read_pipeline_counter` (pipeline da CAS latency), `dq_model_drive`/
  `dq_ctrl_drive` (quem dirige o barramento), `last_bank`, `last_row`,
  `last_col`, `last_addr`, `mem_index`.

O testbench também faz **verificações de sequência** (um monitor exige
ACTIVATE → READ/WRITE → PRECHARGE por operação), confere os comandos de
inicialização (`n_load_mode = 1`, `n_refresh ≥ 8`) e tem guardas de **contenção**
(`DRAM_DQ` nunca em `X`; modelo e controlador nunca dirigem o barramento juntos)
e um **watchdog** de timeout. A mensagem final é
`tb_dram_controller: todos os cenarios passaram`, seguida de um resumo de
contadores.

## Reset, init e por que o começo "parece parado"

Para ler a forma de onda sem confundir inicialização com travamento:

- **Reset é ativo em nível alto** (`rst='1'` reseta). O testbench inicializa
  todas as entradas (`rst='1'`, `req='0'`, `wEn='0'`, `addr_in=0`,
  `write_data_in=0`), segura o reset por alguns ciclos e **solta explicitamente**
  (`rst<='0'`, com report "reset liberado"). Em seguida espera `ready='1'` com
  **timeout** (falha clara se a init nunca terminar).
- Na placa, o controlador roda a **espera de power-up do SDRAM = 28600 ciclos**
  (~200 µs a 143 MHz) em que o barramento fica em `NOP` e `ready=0`. Esse valor é
  o **generic `INIT_WAIT_CYCLES`** do `dram_controller` (default 28600, usado na
  síntese). **Para a simulação, o testbench instancia o DUT com
  `generic map (INIT_WAIT_CYCLES => 50)`**, encurtando *só* essa espera de NOP —
  nada funcional muda (CAS latency, captura por `tAC`, intervalo de refresh ficam
  iguais). Resultado: `ready` sobe em **~1 µs (≈145 ciclos)** e toda a atividade
  (PRECHARGE, 8× AUTO REFRESH, LOAD MODE, WRITE/READ, refresh) fica visível
  **desde o início** — a forma de onda inteira termina perto de **~9 µs**. Sem
  esse override, só `clk`/`DRAM_CLK` "oscilam" e o resto fica plano até ~200 µs.
- `ready` aparecendo como `U` **apenas em t=0** é o valor inicial antes da
  primeira borda; o reset assíncrono o leva a `0` já no primeiro delta.

## Como rodar

```bash
docker run --rm -v "$PWD":/work -w /work hdlc/ghdl bash -c '
  mkdir -p /tmp/wd && WD=/tmp/wd
  ghdl -a --std=08 --workdir=$WD reader.vhd dram_controller.vhd tb_dram_controller.vhd
  ghdl -e --std=08 --workdir=$WD tb_dram_controller
  ghdl -r --std=08 --workdir=$WD tb_dram_controller --stop-time=60us --wave=controller.ghw'
```

> O testbench encurta o init via `generic map (INIT_WAIT_CYCLES => 50)`, então o
> teste todo cabe em ~9 µs e a forma de onda fica cheia de atividade desde t=0.
> O DUT em si mantém o default 28600 na síntese.

Resultado esperado no console:

```
tb_dram_controller: todos os cenarios passaram
```

## O que colocar no relatório

1. **Propósito:** verificar a FSM de protocolo SDRAM sem a interface — INIT,
   leitura/escrita e refresh.
2. **Fidelidade temporal (o ponto central do laboratório):** explique que o
   testbench modela `tAC`, o período de 143 MHz e `DRAM_CLK = not clk`, e por que
   isso é indispensável para reproduzir o problema real de leitura `0xFF`.
   - Relacione com a correção: **captura de `DRAM_DQ` na borda de descida** do
     clock + `READ_CAPTURE_CYCLES = 5`, e o mode register `0x230` (CL=3, BL=1).
     Mostre que com CL=2 (`0x220`) ou captura na subida o teste lê `0xFF`.
3. **Sequência de inicialização:** descreva os estados (precharge all, 8×
   auto-refresh, load mode register, tMRD) e mostre na forma de onda os comandos
   no barramento `dram_cmd`/`bus_cmd`. (Use a figura `init_commands.png`.)
4. **Os 4 cenários** (lista acima) e o que cada um prova:
   escrita/leitura correta, independência de endereços, refresh automático.
5. **Regra de handshake:** explique o `wait ready='0'` então `ready='1'` e o erro
   de atraso por 1 que ela evita.
6. **Forma de onda:** print do GTKWave (com o init curto, a janela ~0–9 µs já
   mostra tudo). Sinais sugeridos: `clk`, `DRAM_CLK`, `rst`, `req`, `wEn`, `ready`,
   `test_phase` e `dram_cmd_dec` (como enum/ASCII), `bus_cmd`, os contadores
   (`n_activate`/`n_read`/`n_write`/`n_precharge`/`n_refresh`/`n_load_mode`),
   `DRAM_DQ`, `dq_model_drive`/`dq_ctrl_drive`, `read_data`/`write_data`,
   `model_read_data`, `read_pipeline_counter`, `last_bank`/`last_row`/`last_col`/
   `mem_index`. Destaque um ciclo ACTIVATE→READ→(tAC)→captura→PRECHARGE e o
   instante em que o dado válido aparece dentro da janela. (Figura
   `controller.png`.)
7. **Reset/init:** explique que o reset é ativo alto e é solto explicitamente;
   que o init real ocupa 28600 ciclos (~200 µs) e que o testbench o encurta com
   o generic `INIT_WAIT_CYCLES => 50` **só na simulação** (por isso a forma de
   onda fica legível desde t=0, em vez de só `clk`/`DRAM_CLK` oscilando); e que
   `U` em t=0 é só o valor inicial — não um travamento.
8. **Resultado:** transcreva `todos os cenarios passaram` e o resumo de
   contadores.


--------

## Análise da Forma de Onda — Testbench do Controlador SDRAM

A forma de onda apresentada corresponde à simulação RTL do testbench `tb_dram_controller`, usado para validar isoladamente o módulo `dram_controller`. Diferente de uma simulação apenas visual dos pinos, este testbench adiciona sinais de depuração, como `bus_cmd`, `test_phase`, `seq_state` e contadores de comandos, permitindo observar com clareza a sequência executada pelo controlador.

No trecho mostrado, a simulação já passou pela fase inicial e entra nos cenários principais de escrita e leitura. A fase do teste é indicada pelo sinal `test_phase`, que passa de `PH_INIT` para `PH_WRITE_A` e depois para `PH_READ_A`. Isso mostra que o testbench está executando a história esperada: primeiro escreve um valor em um endereço da SDRAM e depois lê esse mesmo endereço para verificar se o dado foi armazenado corretamente.

Durante a fase `PH_WRITE_A`, o testbench solicita uma operação de escrita ao controlador. O sinal `req` é pulsado, indicando uma nova requisição, e o sinal `wEn` fica ativo, indicando que a operação solicitada é uma escrita. Em seguida, o controlador baixa `ready`, sinalizando que aceitou a operação e está ocupado executando a sequência SDRAM. Ao final da operação, `ready` volta para nível alto, indicando que o controlador terminou e está pronto para uma nova requisição.

A sequência de comandos SDRAM pode ser observada pelo sinal decodificado `bus_cmd`. Na operação de escrita, o controlador emite primeiro um comando `CMD_ACT`, que corresponde ao `ACTIVATE`, usado para abrir a linha da memória. Depois, emite `CMD_WR`, correspondente ao comando `WRITE`, no qual o dado é colocado no barramento `DRAM_DQ` e gravado no modelo de SDRAM. Por fim, aparece `CMD_PRE`, correspondente ao `PRECHARGE`, fechando a linha acessada. Entre esses comandos aparecem ciclos `CMD_NOP`, usados para respeitar os intervalos temporais exigidos pelo protocolo SDRAM.

A evolução do sinal `seq_state` confirma a organização interna da operação. O controlador sai de `SEQ_IDLE`, entra em `SEQ_ACTIVE` para abrir a linha, passa para `SEQ_ACCESS` para executar o acesso de leitura ou escrita, e retorna para `SEQ_IDLE` ao concluir a operação. Essa sequência indica que a FSM do controlador está percorrendo corretamente os estados necessários para uma operação SDRAM.

Na fase seguinte, `PH_READ_A`, o testbench solicita uma leitura no mesmo endereço. Agora `req` é pulsado com `wEn` desativado, indicando leitura. O controlador novamente baixa `ready`, executa a sequência `ACTIVATE → READ`, e depois finaliza a operação. No barramento de comandos, observa-se `CMD_ACT` seguido de `CMD_RE`, que representa o comando `READ`. Após a latência CAS e o atraso de acesso modelado no testbench, o modelo SDRAM coloca o dado lido no barramento `DRAM_DQ`, e o controlador captura esse valor para disponibilizá-lo em `read_data`.

Os contadores de comandos também ajudam a validar o comportamento. Durante a simulação, os contadores associados a `ACTIVE`, `WRITE`, `READ` e `PRECHARGE` são incrementados conforme os comandos aparecem no barramento. Isso confirma que os comandos esperados foram realmente emitidos pelo controlador, e não apenas inferidos pelo resultado final.

Portanto, esse trecho da forma de onda mostra que o controlador está executando corretamente pelo menos uma operação completa de escrita e uma operação completa de leitura. A escrita segue a sequência `ACTIVATE → WRITE → PRECHARGE`, enquanto a leitura segue a sequência `ACTIVATE → READ`, respeitando os estados internos da FSM e o handshake `req/ready`.

Com isso, a simulação fornece evidência de que o `dram_controller` aceita requisições externas, gera os comandos SDRAM corretos, controla o estado de ocupação por meio de `ready` e acessa o barramento de dados no momento esperado. Esse comportamento valida a parte central do controlador: transformar uma requisição simples de leitura ou escrita em uma sequência correta de comandos SDRAM.
