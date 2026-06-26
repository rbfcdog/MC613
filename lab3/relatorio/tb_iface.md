# Testbench da Interface — `tb_dram_iface`

Arquivo: `tb_dram_iface.vhd` · DUT: `dram_iface.vhd`

## Objetivo

Validar **isoladamente** a FSM de interface com o usuário (`dram_iface`), que
traduz os switches (`SW`), os botões (`KEY`) e o handshake `req`/`ready` em
operações de leitura e escrita, e que dirige os displays de 7 segmentos.
Aqui **não há controlador real nem SDRAM**: o objetivo é provar que a lógica de
decisão da interface está correta, sem depender do tempo do protocolo SDRAM.

## Metodologia

- **Clock:** 10 ns (100 MHz é irrelevante aqui — a interface é só lógica
  síncrona; o período só precisa ser estável).
- **Controlador falso (`fake_ctrl`):** um processo que substitui o
  `dram_controller`. A cada `req='1'`, ele:
  1. **registra a operação** num log (`wEn`, `address`, `write_data`);
  2. baixa `ready` (aceita / fica ocupado) por alguns ciclos;
  3. devolve um `read_data` fixo (`0x5A`) e volta `ready='1'` (operação concluída).
- **Por que registrar em log em vez de checar em ciclos contados:** a interface
  tem dois estágios de sincronização nas entradas assíncronas (`SW`/`KEY`) e uma
  latência de handshake variável. Comparar a *sequência de operações emitida*
  torna o teste robusto e legível, em vez de depender do ciclo exato.
- **Função `addr_of`:** reproduz, no testbench, o mesmo mapeamento de `SW` para o
  vetor de endereço de 26 bits que a interface usa, para prever os bits esperados.

## Cenários testados (a "história")

| op | Tipo | Origem do estímulo | Verificação |
|----|------|--------------------|-------------|
| op0 | WRITE 0x00 | **Reset** auto-limpa o endereço selecionado | `wEn=1`, dado `0x00` |
| op1 | READ | read-back automático da limpeza | `wEn=0` |
| op2 | READ | **mudança dos switches de endereço** (`SW[9:4]=0x2B`) | `wEn=0`, endereço `addr_of(0x2B)` |
| op3 | WRITE 0x0A | **pressionar `KEY[3]`** (dado = `SW[3:0]`) | `wEn=1`, dado `0x0A`, endereço correto |
| op4 | READ | read-back automático após a escrita | `wEn=0` |

Há ainda um **watchdog** (50 µs) que falha o teste caso a sequência esperada
nunca se complete.

## Como rodar

```bash
docker run --rm -v "$PWD":/work -w /work hdlc/ghdl bash -c '
  mkdir -p /tmp/wd && WD=/tmp/wd
  ghdl -a --std=08 --workdir=$WD reader.vhd dram_controller.vhd dram_iface.vhd tb_dram_iface.vhd
  ghdl -e --std=08 --workdir=$WD tb_dram_iface
  ghdl -r --std=08 --workdir=$WD tb_dram_iface --stop-time=60us'
```

Resultado esperado no console:

```
tb_dram_iface: todos os cenarios passaram
```

Para ver as ondas, acrescente `--wave=iface.ghw` à execução e abra em GTKWave.

## O que colocar no relatório

1. **Propósito do teste:** mostrar que a interface, sozinha, gera a sequência
   correta de operações a partir de switches/botões — independentemente do
   controlador e da memória.
2. **Decisões de projeto do testbench:**
   - uso de um *controlador falso* que apenas responde ao handshake e registra
     as operações;
   - por que registrar a sequência é mais robusto do que checar ciclo a ciclo
     (sincronizadores de 2 estágios + latência de handshake).
3. **Tabela dos 5 cenários** (a tabela acima) explicando o que cada operação
   prova:
   - **reset zera a célula atual** (op0/op1) — comportamento pedido no enunciado;
   - **trocar o endereço dispara leitura automática** (op2);
   - **`KEY[3]` escreve `SW[3:0]`** e a interface faz read-back sozinha (op3/op4).
4. **Forma de onda:** inclua um print do GTKWave destacando `SW`, `KEY(3)`,
   `req`, `wEn`, `address`, `write_data`, `ready` e os 5 pulsos de `req`.
   Aponte no waveform cada uma das 5 operações.
5. **Resultado:** transcreva a mensagem `todos os cenarios passaram` e conclua
   que a lógica de interface está correta.
6. **Observação sobre robustez:** mencione que a interface sincroniza `SW`/`KEY`
   com 2 flip-flops (anti-metaestabilidade) e que o teste é imune a essa latência
   justamente por verificar a sequência de operações, não o instante exato.

-------------------------------------

# Testbench da Interface — `tb_dram_iface`

Arquivo: `tb_dram_iface.vhd` · DUT: `dram_iface.vhd`

## Objetivo

Validar **isoladamente** a FSM de interface com o usuário (`dram_iface`), responsável por traduzir os switches (`SW`), os botões (`KEY`) e o handshake `req`/`ready` em operações de leitura e escrita.

Neste teste **não há controlador SDRAM real nem memória SDRAM**. O objetivo é verificar se a lógica de decisão da interface está correta, independentemente do tempo e dos detalhes do protocolo SDRAM. Os displays de 7 segmentos (`HEX0`, `HEX1`, `HEX4` e `HEX5`) são instanciados e podem ser observados na forma de onda, mas a verificação automática deste testbench está focada na sequência de operações emitidas pela interface.

## Metodologia

A simulação utiliza um clock de período igual a 10 ns. Como o teste avalia apenas a lógica síncrona da interface, o valor exato da frequência não é crítico; basta que o clock seja estável.

Para substituir o controlador de DRAM real, foi implementado um **controlador falso** (`fake_ctrl`). Esse processo responde ao protocolo de handshake da interface. A cada requisição `req='1'`, o controlador falso:

1. registra a operação emitida pela interface em um log, armazenando `wEn`, `address` e `write_data`;
2. coloca `ready='0'` por alguns ciclos, simulando que o controlador aceitou a operação e está ocupado;
3. fornece um valor fixo em `read_data`, igual a `0x5A`;
4. retorna `ready='1'`, indicando que a operação foi concluída.

A escolha de registrar as operações em um log, em vez de verificar sinais em ciclos fixos, torna o teste mais robusto. A interface possui sincronizadores de entrada para os sinais assíncronos `SW` e `KEY`, além da latência natural do handshake `req`/`ready`. Por isso, verificar a **sequência lógica de operações** é mais adequado do que depender do ciclo exato em que cada evento ocorre.

O testbench também define a função `addr_of`, que reproduz o mesmo mapeamento de bits utilizado pelo `dram_iface` para converter os switches em um endereço de 26 bits. Assim, o testbench consegue calcular o endereço esperado e comparar com o endereço gerado pela interface.

## Cenários testados

A simulação verifica a seguinte sequência de operações:

| Operação | Tipo         | Origem do estímulo                                       | Verificação                                          |
| -------- | ------------ | -------------------------------------------------------- | ---------------------------------------------------- |
| `op0`    | `WRITE 0x00` | Saída do reset                                           | `wEn='1'` e `write_data=0x00`                        |
| `op1`    | `READ`       | Leitura automática após a limpeza inicial                | `wEn='0'`                                            |
| `op2`    | `READ`       | Mudança dos switches de endereço, com `SW[9:4]="101011"` | `wEn='0'` e endereço igual a `addr_of("1010110000")` |
| `op3`    | `WRITE 0x0A` | Pressionamento de `KEY[3]`, com dado vindo de `SW[3:0]`  | `wEn='1'`, `write_data=0x0A` e endereço correto      |
| `op4`    | `READ`       | Leitura automática após a escrita                        | `wEn='0'`                                            |

As operações `op1` e `op4` representam leituras automáticas disparadas pela interface após uma escrita. Como o controlador falso não implementa uma memória real, o testbench não verifica o conteúdo armazenado na SDRAM. O valor retornado em `read_data` é fixo (`0x5A`) e serve apenas para simular uma resposta de leitura do controlador.

Além disso, o testbench possui um **watchdog** de 50 µs. Caso a sequência esperada não seja concluída dentro desse intervalo, a simulação falha com uma mensagem de timeout. Isso evita que erros na FSM deixem a simulação presa indefinidamente.

## Execução da simulação

A simulação pode ser executada com GHDL pelo seguinte comando:

```bash
docker run --rm -v "$PWD":/work -w /work hdlc/ghdl bash -c '
  mkdir -p /tmp/wd && WD=/tmp/wd
  ghdl -a --std=08 --workdir=$WD reader.vhd dram_controller.vhd dram_iface.vhd tb_dram_iface.vhd
  ghdl -e --std=08 --workdir=$WD tb_dram_iface
  ghdl -r --std=08 --workdir=$WD tb_dram_iface --stop-time=60us'
```

O resultado esperado no console é:

```text
tb_dram_iface: todos os cenarios passaram
```

Para gerar o arquivo de ondas, pode-se acrescentar a opção `--wave=iface.ghw` à execução e abrir o arquivo no GTKWave.

## Análise da forma de onda

Na forma de onda da simulação RTL, é possível observar os cinco pulsos principais de `req`, correspondentes às cinco operações emitidas pela interface.

Inicialmente, o sinal `rst` permanece ativo por alguns ciclos. Após a desativação do reset, a interface gera uma escrita de limpeza (`op0`), com `wEn='1'` e `write_data=0x00`. Em seguida, é gerada uma leitura automática (`op1`), com `wEn='0'`.

Depois, quando os bits de endereço dos switches são alterados para `SW[9:4]="101011"`, a interface detecta a mudança de endereço e emite uma nova leitura (`op2`). O endereço gerado é comparado com o valor esperado calculado pela função `addr_of`.

Em seguida, o testbench define `SW[3:0]="1010"` e pressiona `KEY[3]`, que é ativo em nível baixo. A interface interpreta esse evento como um comando de escrita e gera `op3`, com `wEn='1'` e `write_data=0x0A`. Após essa escrita, a interface emite automaticamente uma nova leitura (`op4`), com `wEn='0'`.

Durante cada operação, o controlador falso baixa `ready` por alguns ciclos, simulando o período em que o controlador estaria ocupado. Quando `ready` volta para nível alto, a interface pode prosseguir para a próxima operação.

## Resultado

A simulação terminou com a mensagem:

```text
tb_dram_iface: todos os cenarios passaram
```

Isso indica que todas as asserções do testbench foram satisfeitas. Portanto, a FSM da interface gerou corretamente a sequência esperada de operações: limpeza após reset, leitura automática após a limpeza, leitura após mudança de endereço, escrita via `KEY[3]` usando o dado de `SW[3:0]` e leitura automática após a escrita.

## Conclusão

O testbench valida que o módulo `dram_iface`, quando testado isoladamente, emite corretamente as operações de leitura e escrita esperadas a partir dos estímulos de usuário e do handshake com o controlador.

A estratégia de registrar a sequência de operações em um log torna o teste robusto contra variações de latência causadas pelos sincronizadores de entrada e pelo protocolo `req`/`ready`. Assim, o teste comprova o comportamento funcional da FSM da interface sem depender de um controlador SDRAM real ou de uma memória física.

