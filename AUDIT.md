# Auditoria do pacote ArchMind 1.5.6

Fonte recebida: `archmind-auditoria-1.4.1.tar.gz`

SHA-256 da fonte:

```text
6da044d887cf16710c947cab145e34f7fa1febbd1d059999b1c8875e01a4a241
```

## Correções aplicadas

- incorporado o projeto AFI completo ao instalador;
- definido `archmind-console` como lançador canônico;
- mantido `archmind` apenas como atalho para a mesma AFI;
- removidos serviço, ação e referências da versão legacy;
- trocados caminhos pessoais fixos por valores derivados de `$HOME`;
- substituído o link absoluto original por links criados no momento da instalação;
- removidos históricos `*.backup-*`, `*.bak`, caches Python e logs de execução;
- adicionadas validação de integridade, simulação e cópia preventiva;
- adicionada recuperação automática em caso de falha durante a atualização.
- incorporado o toolkit completo com os cinco perfis pós-formatação;
- substituído Kitty por GNOME Terminal no perfil Terminal;
- atualizados os perfis Base, Gamer, Áudio e Desenvolvimento;
- corrigidas as entradas AUR e a atualização parcial `pacman -Sy`;
- alinhadas as listas efetivamente usadas pelo ArchMind Manager;
- corrigidos o quadro `LOCATION` e a borda inferior dos viewers.
- adicionados modelos de arquivos ao perfil Base para ativar o menu
  `Novo documento` no Nemo e no Arquivos do GNOME;
- protegidos modelos existentes contra sobrescrita durante reinstalações.
- configurado `~/.local/bin` para Bash e Zsh;
- corrigido o retorno prematuro antes da confirmação de restauração;
- filtrados pacotes obsoletos antes da instalação e criado relatório de pendências;
- padronizados `sort` e `comm` com `LC_ALL=C`;
- garantidos plugins do Zsh, Powerlevel10k e o vínculo de `~/.zsh_aliases`;
- impedido que um backup antigo substitua a versão estável instalada.
- substituída a leitura bloqueante por eventos de tecla/redimensionamento;
- implementados layouts completo, padrão, compacto e aviso de tamanho mínimo;
- corrigida a leitura instável de `80x24` causada por stdin redirecionado;
- congelada a geometria do PTY durante cada quadro para impedir bordas mistas;
- adicionada janela rolável do menu para terminais de pouca altura;
- tornados responsivos viewers, notificações e diálogos.
- integrada a configuração idempotente do Nautilus ao Perfil Base e à AFI;
- adicionados `python-pillow`, `icoutils` e `icoextract` aos perfis e à restauração;
- incluído `~/.local/share/thumbnailers` no backup e na cópia preventiva;
- preservado o CSS GTK4 sem duplicar o bloco ArchMind;
- tornadas não fatais as falhas opcionais da integração do Nautilus.
- integrado `gnome-rounded-blur` ao Perfil Base, AFI e restauração de GNOME;
- adicionada verificação pós-instalação da detecção pelo Blur My Shell;
- adicionados `papirus-icon-theme` e `papirus-folders` com pastas amarelas no
  `Papirus-Dark`;
- preservada a separação entre recorte do blur e o CSS GTK4 das miniaturas.
- corrigidas variáveis de cor inexistentes no painel de inicialização;
- adicionados fallbacks ANSI 256 para fundos escuros e transparentes;
- tornada a leitura de memória independente do idioma do sistema;
- atualizado o atalho apresentado para `archmind-console`.
- transformado o Fastfetch em painel compacto sem logotipo ASCII;
- combinados ArchMind e Fastfetch em um startup responsivo;
- adicionado empilhamento automático para terminais mais estreitos;
- isolada a configuração compacta sem modificar o arquivo pessoal do Fastfetch.
- removidas sequências CSI/OSC e controles C0 da saída capturada do Fastfetch;
- substituído o alinhamento por cursor pelo delimitador interno seguro `::`;
- adicionada regressão que simula `ESC[10G`, origem das barras deslocadas.
- removidas larguras fixas dos painéis de inicialização;
- calculadas as paredes pela maior frase presente em cada painel;
- modo lado a lado decidido pela soma real das duas caixas e da margem;
- limite de largura aplicado somente quando o terminal exige empilhamento.

## Testes concluídos

- sintaxe de todos os arquivos Zsh ativos;
- sintaxe do ArchMind Manager e dos lançadores Bash;
- integridade individual de todos os arquivos do payload;
- instalação nova em uma Home descartável;
- atualização preservando as configurações pessoais;
- remoção de arquivos obsoletos da instalação ativa;
- carga integral dos componentes AFI;
- bloqueio de execução do instalador como root;
- rollback forçado com restauração do projeto, runtime e dois lançadores.
- validação estrutural e sintática dos cinco perfis;
- sintaxe de todos os módulos Bash do toolkit;
- instalação dos perfis simulada sem executar Pacman ou AUR.
- criação dos quatro modelos em Home descartável e repetição idempotente.
- instalação e restauração completas em Home descartável com Pacman/Yay simulados;
- repetição da restauração sem duplicar o vínculo de `~/.zsh_aliases`;
- pacote oficial e AUR obsoletos isolados sem cancelar os itens válidos;
- preservação do Manager 1.5.6 diante de um backup de projeto 1.4.1.
- testes PTY em `44x173`, `80x24`, `55x10`, `30x6` e `110x35`;
- redimensionamento em tempo real sem tecla e sem escrita fora da tela;
- redimensionamento de viewers e diálogos entre modos normal e compacto.
- restauração repetida do thumbnailer e CSS sem duplicação;
- instalação simulada das dependências Pacman/AUR do thumbnailer;
- reaplicação de GSettings, limpeza do cache e reinício do Nautilus simulados;
- confirmação de que o backup completo contém o thumbnailer local.
- instalação e restauração simuladas de `gnome-rounded-blur` e Papirus;
- diagnóstico `true`/`false` do rounded blur sem interromper a restauração;
- aplicação idempotente de pastas amarelas no `Papirus-Dark`;
- confirmação de que nenhum hack de blur foi inserido no `gtk.css`.
- renderização do startup com códigos ANSI 45 e 99 presentes;
- leitura simulada de `free` em português sem mostrar memória indisponível.
- Fastfetch simulado lado a lado em 140 colunas e empilhado em 90 colunas;
- confirmação de `--config none`, `--logo none` e ausência do logotipo ASCII.
- confirmação de que cada parede coincide com a frase mais longa do painel.
