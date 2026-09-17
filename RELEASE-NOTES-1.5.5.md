# ArchMind 1.5.5 — correção visual do startup

## Problema corrigido

Algumas saídas do Fastfetch continham controles de posicionamento horizontal.
Quando eram colocadas dentro da caixa, esses controles moviam o cursor para uma
coluna absoluta, sobrescrevendo textos e deixando barras verticais soltas.

## Solução

- O Fastfetch não controla mais a largura das chaves.
- Uma separação interna segura permite ao ArchMind montar cada linha.
- Sequências CSI, OSC e controles invisíveis são removidos antes do desenho.
- Os painéis continuam lado a lado a partir de 110 colunas e empilhados abaixo.
- A configuração pessoal em `~/.config/fastfetch` continua intacta.
