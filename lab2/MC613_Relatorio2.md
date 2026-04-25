# MC613 - Relatorio 2

## Planejamento

- Definir pipeline de video para VGA 640x480 @ 60 Hz com clock de pixel de 25 MHz.
- Separar arquitetura em modulos independentes: geracao de timing, cenario (tiles), logica de jogo e composicao final.
- Implementar mecanica basica no estilo Dino Runner:
  1. Dinossauro com pulo
  2. Cacto movendo da direita para a esquerda
  3. Deteccao de colisao
  4. Estado de game over com indicacao visual em LED
- Garantir integracao em top-level para uso direto na placa DE1-SoC.
- Criar testbenches para validar pelo menos os blocos criticos de timing e controle de jogo.

## Estrutura do codigo e Implementacao

O projeto e organizado em modulos VHDL hierarquicos, onde cada componente possui uma responsabilidade especifica:

- dinossaur_game (top-level)
- pll (geracao de clock de 25 MHz)
- VGA (controlador de temporizacao e sinais VGA)
- PPU (renderizacao de fundo baseada em tiles)
- rom (dados de tiles e mapa base)
- ram (mapa de tiles inicializavel)
- game_controller (fisica do pulo, movimento do obstaculo e colisao)
- sprite_renderer (sobreposicao dos sprites do dinossauro e cacto)

## Modulo Principal: dinossaur_game

O arquivo principal integra todos os componentes e conecta entradas/saidas fisicas da placa.

### Portas de entrada

- CLOCK_50: Clock de 50 MHz da placa
- KEY[0]: Botao de pulo/restart (ativo em nivel baixo)
- SW[9:0]: Chaves (conectadas a PPU, reservadas para expansao)

### Portas de saida

- VGA_SYNC_N, VGA_BLANK_N, VGA_HS, VGA_VS, VGA_CLK
- VGA_R[7:0], VGA_G[7:0], VGA_B[7:0]
- LEDR[9:0] (LEDR9 usado para indicar game over piscando)

### Funcionamento Principal

```vhdl
-- PLL gera clock de 25MHz para video
clk : pll
port map(
  refclk   => CLOCK_50,
  rst      => '0',
  outclk_0 => clk25,
  locked   => lock
);

reset_n <= lock;
```

```vhdl
-- Pisca LEDR(9) quando game_over = '1'
PROCESS(clk25, reset_n)
  VARIABLE counter : INTEGER;
BEGIN
  IF reset_n = '0' THEN
    game_over <= '0';
    counter := 0;
  ELSIF RISING_EDGE(clk25) THEN
    IF collision = '1' THEN
      game_over <= '1';
    END IF;

    counter := counter + 1;
    IF counter > 25000000 THEN
      counter := 0;
    END IF;

    IF game_over = '1' THEN
      IF counter > 12500000 THEN
        LEDR(9) <= '1';
      ELSE
        LEDR(9) <= '0';
      END IF;
    ELSE
      LEDR(9) <= '0';
    END IF;
  END IF;
END PROCESS;
```

## Controlador de Jogo: game_controller

Implementa a logica de gameplay: pulo, gravidade, movimento do cacto e condicao de colisao.

### Estados logicos usados

- game_state = '0': jogo rodando
- game_state = '1': game over

### Constantes relevantes

- DINO_START_X = 200, DINO_START_Y = 380
- GROUND_Y = 380
- JUMP_SPEED = 15
- GRAVITY = 1
- MAX_FALL_SPEED = 20
- FRAME_DIVISOR = 600000

### Deteccao de pulso do botao (borda de descida)

```vhdl
IF key_0_prev = '1' AND KEY(0) = '0' THEN
  pulse_jump <= '1';
ELSE
  pulse_jump <= '0';
END IF;
key_0_prev <= KEY(0);
```

### Logica do pulo e gravidade

```vhdl
IF pulse_jump = '1' AND is_jumping = '0' THEN
  is_jumping <= '1';
  dino_vy <= TO_SIGNED(-JUMP_SPEED, 11);
  dino_y_reg <= TO_UNSIGNED(GROUND_Y - 1, 10);

ELSIF is_jumping = '1' OR dino_y_reg < GROUND_Y THEN
  -- aplica gravidade com saturacao de velocidade de queda
  ...
END IF;
```

### Deteccao de colisao por bounding box

```vhdl
is_colliding <= '1' WHEN (
  (dino_x_reg + DINO_WIDTH > cactus_x_reg) AND
  (dino_x_reg < cactus_x_reg + CACTUS_WIDTH) AND
  (dino_y_reg + DINO_HEIGHT > cactus_y_reg) AND
  (dino_y_reg < cactus_y_reg + CACTUS_HEIGHT)
) ELSE '0';
```

## PPU (Picture Processing Unit): PPU

Responsavel por converter pixel atual em cor de fundo com base em tiles.

### Conceito de renderizacao

- Usa pixel_x/pixel_y para descobrir tile e posicao interna (linha/coluna).
- Le tile_id na RAM do mapa.
- Le bitmap da linha do tile na ROM.
- Define cor final conforme tile e bit ligado/desligado.
- Forca cor de chao para pixel_y >= 400.

### Mapeamento de pixel para tile

```vhdl
tile_x_raw := TO_INTEGER(pixel_x_u(9 DOWNTO 3));
tile_y_raw := TO_INTEGER(pixel_y_u(9 DOWNTO 3));

tile_x := (tile_x_raw * MAP_W) / ACTIVE_TILE_W;
tile_y := (tile_y_raw * MAP_H) / ACTIVE_TILE_H;

map_index := (tile_y * MAP_W) + tile_x;
map_addr <= STD_LOGIC_VECTOR(TO_UNSIGNED(map_index, 8));
```

### Renderizacao de cores

- Fundo ceu: r=x"70", g=x"C0", b=x"FF"
- Chao/grama: r=x"20", g=x"A0", b=x"20"
- Tiles especificos recebem cores proprias (nuvem, cacto, etc.)

## Memoria de Tiles: rom

Armazena padroes 8x8 dos tiles e parte do mapa base.

### Tiles definidos

- TILE_BG = 0
- TILE_CACTUS = 1
- TILE_DINO = 2
- TILE_CLOUD = 3
- TILE_GRASS = 4

### Inicializacao da ROM

- Preenche linhas dos tiles com padroes binarios.
- Preenche faixa inferior do mapa com grama.
- Insere nuvens em posicoes fixas.

## Mapa Dinamico: ram

Memoria de mapa 16x16 usada pela PPU.

### Inicializacao da RAM

```vhdl
FOR y IN 0 TO MAP_H - 1 LOOP
  FOR x IN 0 TO MAP_W - 1 LOOP
    i := (y * MAP_W) + x;
    IF y >= 14 THEN
      mem(i) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_GRASS, 8));
    ELSE
      mem(i) := STD_LOGIC_VECTOR(TO_UNSIGNED(TILE_BG, 8));
    END IF;
  END LOOP;
END LOOP;
```

## Renderizador de Sprites: sprite_renderer

Faz a sobreposicao dos objetos de jogo sobre o fundo da PPU.

### Regras de desenho

- Se pixel esta dentro do retangulo do dinossauro: cor amarela (x"FF", x"DD", x"00")
- Senao, se esta no retangulo do cacto: marrom (x"BB", x"66", x"00")
- Caso contrario: mantem cor de entrada da PPU

## Controlador VGA: VGA

Gera sincronismo e janela ativa para 640x480.

### Temporizacao implementada

- Horizontal total: 800 ciclos (0..799)
- Vertical total: 524 linhas (0..523)
- Area ativa:
  1. X: 144..783 (640 pixels)
  2. Y: 33..512 (480 linhas)

### Sinais

- VGA_HS e VGA_VS gerados por faixas de contador
- video_active = x_act and y_act
- RGB so sai quando video_active = '1'

## Fluxo de Operacao

1. O PLL converte CLOCK_50 em clk25 e libera reset_n quando locked = '1'.
2. O bloco VGA varre a tela e informa pixel_x/pixel_y/video_active.
3. A PPU calcula cor de fundo para cada pixel.
4. O game_controller atualiza posicoes do dinossauro/cacto e calcula colisao.
5. O sprite_renderer sobrepoe dinossauro/cacto no fundo.
6. Em colisao, o game entra em game over e LEDR9 passa a piscar.
7. Pressionar KEY(0) durante game over reinicia posicoes e retoma o jogo.

## Consideracoes de Implementacao

- Dominio sincrono unico: logica principal em clk25.
- Botao ativo baixo com deteccao de borda para gerar pulso de 1 ciclo.
- Fisica simples e estavel:
  1. impulso inicial negativo
  2. aceleracao gravitacional positiva
  3. saturacao da velocidade de queda
- Colisao por AABB (Axis-Aligned Bounding Box), de baixo custo em hardware.
- Renderizacao em camadas:
  1. camada de fundo (PPU)
  2. camada de sprites (sprite_renderer)

## Testbenches

Testbenches implementados no projeto:

- tb_game_controller.vhd - Testa reset, posicao inicial, pulso de pulo e sinais basicos de movimento/colisao
- tb_VGA.vhd - Testbench estrutural para instanciar o modulo VGA e inspecionar sinais em simulacao

## Validacao (testes)

### game_controller

- reset_n='0' inicializa posicoes:
  1. dino_x=200
  2. dino_y=380
  3. cactus_x=640
  4. cactus_y=370
- Apos liberar reset e gerar borda de descida em KEY(0), o pulo e acionado.
- dino_y reduz (subida) e depois retorna para 380 (queda + aterrissagem).
- A colisao e monitorada via sinal collision.

### VGA

- Instanciacao do DUT confirmada.
- Sinais de saida VGA_HS, VGA_VS, VGA_BLANK_N, pixel_x, pixel_y e video_active disponiveis para inspecao em waveform.

## Analise de Execucao

Apesar do sistema funcionar na placa e a arquitetura estar modularizada, surgiram pontos importantes:

### Problema 1

Validacao funcional ainda limitada no bloco de video. O testbench de VGA e estrutural e nao exercita o fluxo completo de temporizacao, o que reduz a verificacao automatica dos sinais de sincronismo e da janela ativa ao longo de um quadro inteiro.

### Problema 2

Janela temporal curta no tb_game_controller para observar dinamica lenta. Com FRAME_DIVISOR=600000 e clock de 50 MHz, updates completos de movimento ocorrem em escala de milissegundos, enquanto parte dos waits usados esta em microssegundos.

### Solucao (adotada no projeto para entrada de botao)

Deteccao de borda com memoria de estado no KEY(0), gerando pulso de um ciclo e evitando multiplos acionamentos por pressao continua.

```vhdl
IF key_0_prev = '1' AND KEY(0) = '0' THEN
  pulse_jump <= '1';
ELSE
  pulse_jump <= '0';
END IF;
key_0_prev <= KEY(0);
```

### Como Funciona

- key_0_prev guarda o valor do ciclo anterior.
- KEY(0) e a entrada atual do botao (ativo em nivel baixo).
- Condicao key_0_prev='1' e KEY(0)='0' detecta pressionamento (borda de descida).
- pulse_jump fica em '1' por um ciclo de clock e aciona exatamente um evento de pulo/restart.

### Principais Beneficios

O Que | Por Que
---|---
Sincrona | Sem logica assincrona adicional no caminho principal.
Pulso de ciclo unico | Evita multiplos disparos por mesma pressao.
Logica simples | Baixo custo em hardware e facil depuracao.
Deterministica | Comportamento repetivel em FPGA e simulacao.

### Por Que Isso Resolveu o Problema

- Estabilidade da logica de entrada para controle de pulo/reinicio
- Menor chance de eventos duplicados por acionamento manual
- Comportamento previsivel da logica de jogo
- Integracao direta com a atualizacao sincrona do game_controller
