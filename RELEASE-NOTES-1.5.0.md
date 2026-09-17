# ArchMind 1.5.0 — AFI responsiva

## Interface

- Redesenho automático ao alterar largura ou altura do terminal.
- Tempo de resposta de até aproximadamente 100 ms sem uso intenso de CPU.
- Layout completo em janelas amplas, padrão em alturas intermediárias e
  compacto em terminais baixos.
- Menu rolável mantém a seleção atual visível.
- Aviso de tamanho mínimo substitui painéis quando não há espaço seguro.
- Viewers, notificações e confirmações recalculam tamanho e posição.

## Correções de desenho

- A geometria agora vem de `/dev/tty`, evitando o falso `80x24` observado
  quando um loop de renderização redirecionava stdin.
- Cada quadro usa uma única geometria congelada, evitando misturar medidas
  antigas e novas durante um redimensionamento rápido.
- A última coluna física continua reservada para impedir quebra automática.

## Compatibilidade

O mecanismo usa recursos ANSI/PTY comuns e foi mantido compatível com GNOME
Terminal, Kitty, Alacritty, WezTerm e Konsole. O GNOME Terminal permanece como
terminal padrão do perfil Terminal.

Todas as correções de instalação e restauração da versão 1.4.2 continuam
incorporadas nesta versão.
