# ArchMind 1.5.11 — GameMode + Blur My Shell

Esta build adiciona uma integração opcional para suspender efeitos do Blur My
Shell enquanto jogos usam GameMode e restaurar o estado ao término.

## Comportamento

- O Perfil Gamer garante `gamemode` e `lib32-gamemode`.
- O bloco administrado é acrescentado a `~/.config/gamemode.ini` sem remover
  configurações ou scripts personalizados existentes.
- O hook central fica em
  `~/ArchMind/System/Core/tools/gamemode-blur.sh`.
- Apenas extensões que estavam habilitadas são reativadas ao final.
- Chamadas duplicadas de início não apagam o estado necessário à restauração.
- A política padrão contém `blur-my-shell@aunetx` e aceita outros UUIDs em
  `~/ArchMind/Config/GameMode/extensions.conf`.
- Backups completos já preservam o `gamemode.ini` e a árvore
  `~/ArchMind/Config`; durante uma migração o caminho absoluto do hook é
  regenerado para o novo usuário.

## Interface

Use `Package Center → GameMode Blur Integration` para configurar, testar,
consultar o estado ou remover apenas os hooks gerenciados pelo ArchMind.

Para jogos Steam:

```bash
gamemoderun %command%
```

## Limites desta build

O teste automatizado do pacote usa comandos simulados e cobre configuração,
idempotência, preservação de hooks, desativação e restauração. A confirmação
final ainda deve ser feita numa sessão GNOME real com Blur My Shell habilitado.

A advertência de governor `powersave` não impede os hooks e não é alterada por
esta build. Ajustes de governor ficam fora do escopo para evitar aplicar uma
política inadequada ao hardware do usuário.
