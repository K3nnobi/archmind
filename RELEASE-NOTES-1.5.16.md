# ArchMind 1.5.16 — Caps Lock No Delay

Esta revisão acrescenta somente o patch opcional **Caps Lock No Delay**, já
validado em Arch Linux com GNOME 50.4 e Wayland.

## Comportamento

- Instala `keyd` pelo Pacman apenas quando o usuário ativa o patch.
- Adiciona `capslock = macro(capslock)` em `/etc/keyd/default.conf`.
- Habilita e inicia `keyd.service`, recarregando a configuração sem exigir
  logout ou reinicialização.
- Está disponível no Package Center, no Manager clássico e no Rollback Center.

## Preservação e segurança

- Uma configuração existente recebe cópia preventiva em
  `~/ArchMind/Installer-Backups/Caps-Lock-No-Delay`.
- Se já houver outro remapeamento ativo de Caps Lock, o patch informa o conflito
  e não altera o arquivo.
- Aplicações repetidas não duplicam marcador, regra ou `macro_timeout`.
- O rollback só restaura a cópia se o arquivo ainda tiver exatamente o hash
  gravado pelo ArchMind; alterações posteriores provocam recusa segura.
- A remoção não desinstala `keyd`, pois outros remapeamentos podem depender dele.
- Nenhum arquivo interno do XKB é modificado.
