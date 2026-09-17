# ArchMind 1.5.7-dev — caminhos unificados

Esta revisão de trabalho centraliza os dados reais do ArchMind em
`~/ArchMind`.

## Nova árvore

- `System/Core`: aplicação, AFI, serviços, temas e ferramentas;
- `System/Toolkit`: runtime e perfis auxiliares;
- `Config`: preferências persistentes;
- `Config/Zsh`: aliases, Powerlevel10k e módulos importados;
- `Backups`, `Projects`, `Logs`, `Temp` e `Installer-Backups`: dados mutáveis.

## Migração da 1.5.6

- detecta os antigos `~/.config/archmind` e
  `~/.local/share/archmind-toolkit`;
- preserva ambos na cópia preventiva antes de instalar;
- migra `.zsh_aliases` e `.p10k.zsh` para `Config/Zsh`;
- atualiza o `.zshrc` sem duplicar carregadores;
- mantém links ocultos de compatibilidade para referências antigas;
- restaura automaticamente o estado anterior se a transação falhar.

Também foi incorporada a opção `Executar no Terminal` ao menu `Abrir com` do
GNOME/Nautilus, usando um helper armazenado dentro da nova árvore única.

## Limites intencionais

Alguns pontos precisam continuar fora de `~/ArchMind` porque são caminhos
padronizados do sistema: `.zshrc`, `.bashrc`, `~/.local/bin`, configurações de
aplicativos em `~/.config` e arquivos `.desktop` em
`~/.local/share/applications`. Nesses locais ficam apenas integrações ou links;
o código e os dados do ArchMind permanecem na raiz única.
