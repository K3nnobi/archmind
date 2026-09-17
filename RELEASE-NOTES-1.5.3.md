# ArchMind 1.5.3 — correção do startup no GNOME Terminal

## Correções

- Cabeçalho, títulos, separadores e status voltaram a usar cores visíveis.
- Foram removidas referências a variáveis `ARCHMIND_ANSI_*` inexistentes.
- A paleta possui fallbacks ANSI 256 para não depender do perfil do terminal.
- A leitura da memória funciona em sistemas com locale `pt_BR.UTF-8`.
- O rodapé recomenda o lançador principal `archmind-console`.

## Compatibilidade

- O Fastfetch permanece opcional e não foi removido.
- Preferências e configurações atuais continuam preservadas pelo instalador.
- A AFI responsiva, Nautilus, rounded blur e Papirus-Dark permanecem inalterados.
