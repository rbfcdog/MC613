\section{Analise de Execucao}

Apesar do funcionamento bem-sucedido na placa DE1-SoC, a validacao do projeto em simulacao ainda apresenta algumas limitacoes praticas. O comportamento em hardware e consistente, mas o ciclo completo do jogo depende de temporizacoes relativamente longas quando comparadas ao clock de 50 MHz, o que torna a observacao de eventos em tempo real mais dificil em testbench.

\subsection{Problemas Observados}

\begin{table}[h]
  \centering
  \caption{Problemas observados na execucao e validacao}
  \begin{tabular}{@{}p{4.1cm}p{5.1cm}p{5.1cm}@{}}
    \hline
    {\bfseries Problema} & {\bfseries Impacto} & {\bfseries Solucao / Mitigacao} \\
    \hline
    Validacao de video pouco automatizada & O testbench de VGA e estrutural e nao percorre um quadro completo com checagens formais dos sinais de sincronismo. & Criar um testbench auto-verificavel, com assertions para HS, VS, blanking e contagem de pixels em uma janela completa. \\
    Dinamica lenta no game loop & O \verb|FRAME_DIVISOR| faz com que os movimentos ocorram em escala muito maior que os waits normalmente usados em simulacao. & Reduzir o divisor apenas para simulacao ou parametrizar o modulo com generics distintos para FPGA e testbench. \\
    Acionamento repetido do botao & Pressionamentos longos podem gerar multiplos eventos se a entrada for lida como nivel e nao como evento. & Manter a deteccao de borda sincronizada e, se necessario, adicionar debounce de software ou hardware. \\
    Colisao sensivel a dimensoes dos sprites & Pequenas diferencas entre bounding box e sprite real podem gerar colisao antecipada ou tardia. & Ajustar as dimensoes efetivas e introduzir margens de tolerancia para dino e cacto. \\
    Reset dependente do lock do PLL & Se o lock ainda nao estiver estabilizado, alguns sinais podem iniciar em estados intermediarios. & Garantir reset sincrono liberado apenas apos lock e, se necessario, registrar o estado inicial por mais de um ciclo. \\
    Verificacao limitada da renderizacao de sprites & Erros de sobreposicao podem passar despercebidos se a analise considerar apenas os sinais de controle. & Adicionar verificacao por coordenadas e amostras de cor em pixels-chave da tela. \\
    \hline
  \end{tabular}
\end{table}

\subsection{Problemas Potenciais}

Mesmo quando o circuito sintetiza e roda corretamente na placa, alguns problemas adicionais podem aparecer durante a evolucao do projeto:

\begin{itemize}
  \item \textbf{Desalinhamento entre clock de video e logica de jogo:} se o PPU, o controlador do jogo e o renderer nao trabalharem com a mesma referencia temporal, podem surgir artefatos visuais ou atualizacoes fora de fase.
  \item \textbf{Dependencia excessiva de constantes fixas:} valores como \verb|FRAME_DIVISOR|, \verb|JUMP_SPEED| e \verb|GRAVITY| podem exigir ajuste manual quando a frequencia de clock ou a taxa de quadro mudar.
  \item \textbf{Falta de cobertura de casos extremos:} o testbench pode validar apenas o cenario feliz, deixando de fora colisao imediata, reinicio durante queda e repeticao de salto em frames consecutivos.
  \item \textbf{Saturacao ou overflow em registradores:} coordenadas e velocidades armazenadas em poucos bits podem causar wrap-around se limites de faixa nao forem respeitados.
  \item \textbf{Comportamento nao reproduzivel entre simulacao e hardware:} tempos de espera, inicializacao de memoria e leitura de botao podem divergir entre ambiente virtual e FPGA real.
\end{itemize}

\subsection{Solucoes Adotadas e Propostas}

\begin{table}[h]
  \centering
  \caption{Solucoes adotadas e melhorias possiveis}
  \begin{tabular}{@{}p{4.3cm}p{5.0cm}p{5.0cm}@{}}
    \hline
    {\bfseries Cenario} & {\bfseries Efeito Esperado} & {\bfseries Solucao} \\
    \hline
    Entrada de botao por nivel & Multiplo disparo por uma unica pressao & Usar deteccao de borda sincronizada com armazenamento do valor anterior do KEY(0). \\
    Simulacao lenta do jogo & Dificulta observar pulo, colisao e reinicio em tempo aceitavel & Reduzir o divisor de frame em simulacao e manter o valor original apenas para FPGA. \\
    Testes de VGA limitados & Falhas de temporizacao podem nao ser detectadas & Inserir assertions para periodos de sincronismo, video\_active e limites de pixel\_x/pixel\_y. \\
    Colisao pouco intuitiva & Jogo pode parecer injusto ao usuario & Ajustar a bounding box dos sprites e, se necessario, desacoplar a colisao da forma grafica exata. \\
    Reinicio durante game over & Estado pode permanecer inconsistente se a ordem de reset nao for bem definida & Centralizar a maquina de estados com reset sincrono e liberar o jogo somente apos o lock do PLL. \\
    Validacao manual excessiva & Erros sutis passam despercebidos & Criar um conjunto de testes com sequencias repetiveis para salto, colisao, fim de jogo e reinicio. \\
    \hline
  \end{tabular}
\end{table}

\subsection{Solucao de Entrada de Botao}

A deteccao de borda sincrona resolveu o problema de multiplos acionamentos indesejados, garantindo que cada pressao gere apenas um evento logico.

\begin{verbatim}
IF key_0_prev = '1' AND KEY(0) = '0' THEN
  pulse_jump <= '1';
ELSE
  pulse_jump <= '0';
END IF;
key_0_prev <= KEY(0);
\end{verbatim}

\subsubsection{Como Funciona}

\begin{itemize}
  \item \verb|key_0_prev| armazena o estado do ciclo anterior.
  \item \verb|KEY(0)| representa a entrada atual do botao, ativo em nivel baixo.
  \item A transicao de \verb|'1'| para \verb|'0'| detecta a borda de descida do pressionamento.
  \item \verb|pulse_jump| permanece em \verb|'1'| por um unico ciclo de clock, acionando exatamente um pulo ou reinicio.
\end{itemize}

\subsubsection{Beneficios}

\begin{table}[h]
  \centering
  \caption{Beneficios da logica de borda}
  \begin{tabular}{@{}ll@{}}
    \hline
    {\bfseries Caracteristica} & {\bfseries Motivo} \\
    \hline
    Sincrona & Evita logica assincrona no caminho principal. \\
    Pulso unico & Impede multiplos disparos por uma mesma pressao. \\
    Simplicidade & Baixo custo em hardware e depuracao mais direta. \\
    Deterministica & Comportamento repetivel em FPGA e simulacao. \\
    \hline
  \end{tabular}
\end{table}

\subsubsection{Conclusao Parcial}

A solucao de borda nao apenas corrige o acionamento repetido do botao, como tambem melhora a previsibilidade do fluxo do jogo. Em conjunto com a parametrizacao dos tempos de simulacao, ela torna a validacao do projeto mais confiavel e facilita a evolucao futura do sistema.
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

\section{Analise de Execucao}

Apesar do funcionamento bem-sucedido na placa DE1-SoC, a validacao do projeto em simulacao ainda apresenta algumas limitacoes praticas. O comportamento em hardware e consistente, mas o ciclo completo do jogo depende de temporizacoes relativamente longas quando comparadas ao clock de 50 MHz, o que torna a observacao de eventos em tempo real mais dificil em testbench.

\subsection{Problemas Observados}

\begin{table}[h]
    \centering
    \caption{Problemas observados na execucao e validacao}
    \begin{tabular}{@{}p{4.1cm}p{5.1cm}p{5.1cm}@{}}
      \hline
      {\bfseries Problema} & {\bfseries Impacto} & {\bfseries Solucao / Mitigacao} \\
      \hline
        Validacao de video pouco automatizada & O testbench de VGA e estrutural e nao percorre um quadro completo com checagens formais dos sinais de sincronismo. & Criar um testbench auto-verificavel, com assertions para HS, VS, blanking e contagem de pixels em uma janela completa. \\ 
        Dinamica lenta no game loop & O FRAME\_DIVISOR faz com que os movimentos ocorram em escala muito maior que os waits normalmente usados em simulacao. & Reduzir o divisor apenas para simulacao ou parametrizar o modulo com generics distintos para FPGA e testbench. \\ 
        Acionamento repetido do botao & Pressionamentos longos podem gerar multiplos eventos se a entrada for lida como nivel e nao como evento. & Manter a deteccao de borda sincronizada e, se necessario, adicionar debounce de software/hardware. \\ 
        Colisao sensivel a dimensoes dos sprites & Pequenas diferencas entre bounding box e sprite real podem gerar colisao antecipada ou tardia. & Ajustar as dimensoes efetivas e introduzir margens de tolerancia para dino e cacto. \\ 
        Reset dependente do lock do PLL & Se o lock ainda nao estiver estabilizado, alguns sinais podem iniciar em estados intermediarios. & Garantir reset sincrono liberado apenas apos lock e, se necessario, registrar o estado inicial por mais de um ciclo. \\ 
        Verificacao limitada da renderizacao de sprites & Erros de sobreposicao podem passar despercebidos se a analise considerar apenas os sinais de controle. & Adicionar verificacao por coordenadas e amostras de cor em pixels-chave da tela. \\
        \hline
    \end{tabular}
\end{table}

\subsection{Problemas Potenciais}

Mesmo quando o circuito sintetiza e roda corretamente na placa, alguns problemas adicionais podem aparecer durante a evolucao do projeto:

\begin{itemize}
    \item \textbf{Desalinhamento entre clock de video e logica de jogo:} se o PPU, o controlador do jogo e o renderer nao trabalharem com a mesma referencia temporal, podem surgir artefatos visuais ou atualizacoes fora de fase.
    \item \textbf{Dependencia excessiva de constantes fixas:} valores como \texttt{FRAME\_DIVISOR}, \texttt{JUMP\_SPEED} e \texttt{GRAVITY} podem exigir ajuste manual quando a frequencia de clock ou a taxa de quadro mudar.
    \item \textbf{Falta de cobertura de casos extremos:} o testbench pode validar apenas o cenario feliz, deixando de fora colisao imediata, reinicio durante queda e repeticao de salto em frames consecutivos.
    \item \textbf{Saturacao ou overflow em registradores:} coordenadas e velocidades armazenadas em poucos bits podem causar wrap-around se limites de faixa nao forem respeitados.
    \item \textbf{Comportamento nao reproduzivel entre simulacao e hardware:} tempos de espera, inicializacao de memoria e leitura de botao podem divergir entre ambiente virtual e FPGA real.
\end{itemize}

\subsection{Solucoes Adotadas e Propostas}

\begin{table}[h]
    \centering
    \caption{Solucoes adotadas e melhorias possiveis}
    \begin{tabular}{@{}p{4.3cm}p{5.0cm}p{5.0cm}@{}}
      \hline
      {\bfseries Cenario} & {\bfseries Efeito Esperado} & {\bfseries Solucao} \\
      \hline
        Entrada de botao por nivel & Multiplo disparo por uma unica pressao & Usar deteccao de borda sincronizada com armazenamento do valor anterior do KEY(0). \\ 
        Simulacao lenta do jogo & Dificulta observar pulo, colisao e reinicio em tempo aceitavel & Reduzir o divisor de frame em simulacao e manter o valor original apenas para FPGA. \\ 
        Testes de VGA limitados & Falhas de temporizacao podem nao ser detectadas & Inserir assertions para periodos de sincronismo, video\_active e limites de pixel\_x/pixel\_y. \\ 
        Colisao pouco intuitiva & Jogo pode parecer injusto ao usuario & Ajustar a bounding box dos sprites e, se necessario, desacoplar a colisao da forma grafica exata. \\ 
        Reinicio durante game over & Estado pode permanecer inconsistente se a ordem de reset nao for bem definida & Centralizar a maquina de estados com reset sincrono e liberar o jogo somente apos o lock do PLL. \\ 
        Validacao manual excessiva & Erros sutis passam despercebidos & Criar um conjunto de testes com sequencias repetiveis para salto, colisao, fim de jogo e reinicio. \\
        \hline
    \end{tabular}
\end{table}

\subsection{Solucao de Entrada de Botao}

A deteccao de borda sincrona resolveu o problema de multiplos acionamentos indesejados, garantindo que cada pressao gere apenas um evento logico.

\begin{verbatim}
IF key_0_prev = '1' AND KEY(0) = '0' THEN
  pulse_jump <= '1';
ELSE
  pulse_jump <= '0';
END IF;
key_0_prev <= KEY(0);
\end{verbatim}

\subsubsection{Como Funciona}

\begin{itemize}
    \item \texttt{key\_0\_prev} armazena o estado do ciclo anterior.
    \item \texttt{KEY(0)} representa a entrada atual do botao, ativo em nivel baixo.
    \item A transicao de \texttt{'1'} para \texttt{'0'} detecta a borda de descida do pressionamento.
    \item \texttt{pulse\_jump} permanece em \texttt{'1'} por um unico ciclo de clock, acionando exatamente um pulo ou reinicio.
\end{itemize}

\subsubsection{Beneficios}

\begin{table}[h]
    \centering
    \caption{Beneficios da logica de borda}
    \begin{tabular}{@{}ll@{}}
      \hline
      {\bfseries Caracteristica} & {\bfseries Motivo} \\
      \hline
        Sincrona & Evita logica assincrona no caminho principal. \\
        Pulso unico & Impede multiplos disparos por uma mesma pressao. \\
        Simplicidade & Baixo custo em hardware e depuracao mais direta. \\
        Deterministica & Comportamento repetivel em FPGA e simulacao. \\
        \hline
    \end{tabular}
\end{table}

\subsubsection{Conclusao Parcial}

A solucao de borda nao apenas corrige o acionamento repetido do botao, como tambem melhora a previsibilidade do fluxo do jogo. Em conjunto com a parametrizacao dos tempos de simulacao, ela torna a validacao do projeto mais confiavel e facilita a evolucao futura do sistema.
