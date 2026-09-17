# ArchMind 1.5.15 — GNOME Drag Hover

Esta revisão acrescenta um patch experimental, opcional e reversível para
aproximar o arraste de arquivos no GNOME/Wayland do comportamento do Windows.
Nada é aplicado durante a instalação base ou pelos perfis.

## Comportamento

- Hover por aproximadamente 400 ms sobre um ícone do Dash to Dock eleva a
  primeira janela relevante do aplicativo em execução.
- Fora do dock, o mesmo atraso eleva a janela visível sob o ponteiro.
- O arquivo continua preso ao cursor: o patch não solta botão, move ponteiro,
  simula clique nem recria a operação Drag and Drop.
- Não usa `xdotool`, `wmctrl` ou integração X11.

## Segurança

- Atua somente numa cópia do Dash to Dock gravável pelo usuário.
- Recusa links simbólicos, instalações gerenciadas em `/usr`, anchors ausentes
  ou ambíguos e marcadores parciais.
- Versões 105 e 106 do Dash to Dock são reconhecidas como validadas. Uma versão
  diferente exige confirmação adicional mesmo com anchors compatíveis.
- O `dash.js` é transformado em memória, validado e substituído atomicamente.
- Cada aplicação salva original, versão e hashes em
  `~/ArchMind/Installer-Backups/GNOME-Drag-Hover`.
- Antes de uma restauração, o arquivo patchado atual também recebe uma cópia
  preventiva independente.
- Remoção e restauração só substituem o arquivo se o hash atual for exatamente
  o resultado daquele snapshot. Um arquivo atualizado nunca recebe um backup
  antigo automaticamente.

## Manutenção

Uma atualização do Dash to Dock pode apagar o patch. Nesse caso, o ArchMind
Doctor mostra `Needs reapply or manual review`; a ação `GNOME Drag Hover`
revalida o arquivo novo antes de oferecer reaplicação.

Depois de instalar ou remover, é necessário logout/login no Wayland. O ArchMind
apenas informa essa necessidade e nunca encerra a sessão automaticamente.

## Limites da validação automática

Os testes do portátil cobrem transformação, idempotência, snapshots, hashes,
remoção exata, atualização do Dash to Dock, anchors incompatíveis e recusa de
links. O comportamento real do GNOME Shell precisa ser confirmado numa sessão
Wayland com arraste do Nautilus, pois não pode ser reproduzido no ambiente
isolado de build.
