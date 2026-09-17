# ArchMind 1.5.4 — Fastfetch compacto integrado

## Interface inicial

- O painel ArchMind ocupa 48 colunas e o Fastfetch compacto ocupa 58.
- A partir de 110 colunas, os dois painéis aparecem lado a lado.
- Abaixo desse limite, o Fastfetch é colocado sob o ArchMind sem cortar linhas.
- O logotipo ASCII do Fastfetch foi desativado para reduzir altura e largura.
- São mostrados OS, kernel, uptime, pacotes, shell, desktop, gerenciador de
  janelas, terminal, memória, CPU, GPU e monitor.

## Compatibilidade

- O painel usa `--config none`, então não depende de um tema pessoal grande.
- Nenhum arquivo em `~/.config/fastfetch` é criado, editado ou removido.
- Se o Fastfetch não estiver instalado, o painel ArchMind continua funcionando.
- Todas as correções da AFI 1.5.3, Nautilus, rounded blur e Papirus permanecem.
