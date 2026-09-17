# ArchMind 1.5.13 — Maintenance Center

Esta versão consolida manutenção e confiabilidade sem transformar alertas em
ações automáticas de sistema. Nenhuma verificação reinicia a máquina, remove
pacotes, recompila AUR ou altera boot por conta própria.

## Maintenance Center

A AFI e o Manager clássico expõem sete módulos:

1. Hardware Profile;
2. Update Guardian;
3. Pending Tasks;
4. Rollback Center;
5. Safe Cleanup;
6. Backup Catalog;
7. Operating Profiles.

## Update Guardian e tarefas

- Mantém uma linha de base privada dos pacotes instalados.
- Detecta mudanças feitas dentro ou fora do ArchMind na próxima execução.
- Reconhece alterações relevantes de kernel, NVIDIA, GRUB, GNOME Shell e Mutter.
- Registra orientações de reinicialização, logout/login, recompilação do
  `gnome-rounded-blur`, auditoria Plymouth e reaplicação do NVIDIA Vibrance.
- Atualizações executadas pelo ArchMind acionam também um Doctor rápido somente
  leitura e salvam o relatório normal do Doctor.
- O usuário pode concluir uma tarefa; o Guardian volta a abri-la se o problema
  verificável continuar presente.

O estado dessas tarefas é específico da máquina e não entra em migrações.

## Hardware Profile

O detector identifica GPU NVIDIA/AMD/Intel, desktop ou notebook, GNOME, tipo de
sessão, UEFI, carregador de boot, ferramenta de initramfs e modo dos hooks do
mkinitcpio. A AFI oculta NVIDIA Vibrance e Plymouth quando a combinação conhecida
não é compatível. As próprias ferramentas continuam repetindo suas validações
antes de qualquer alteração.

O patch de boot permanece limitado a GRUB + mkinitcpio + hooks tradicionais
`udev`. systemd-boot, dracut e hooks `systemd` não são modificados.

## Rollback Center

- Cataloga snapshots por módulo, data e tamanho.
- Abre as rotinas registradas de Plymouth, NVIDIA Vibrance e GameMode Blur.
- Mantém as confirmações próprias de cada módulo.
- Não restaura snapshots genéricos do instalador às cegas.

## Safe Cleanup

- Mostra cache do Pacman, cache de miniaturas, journal e órfãos.
- Cada categoria é executada separadamente e exige a palavra `CLEAN`.
- O Pacman mantém duas versões em cache e remove cache de pacotes desinstalados.
- O journal é limitado por tempo somente quando essa categoria é escolhida.
- Miniaturas são removidas apenas dentro de `~/.cache/thumbnails`, sem seguir
  links, e são recriadas pelos aplicativos.
- Órfãos são apenas listados com um comando para revisão; nunca são removidos
  automaticamente.

Os tamanhos de cache são limites superiores, não promessa exata de espaço que
será recuperado.

## Backup Catalog

O catálogo usa leitura direta e limitada do arquivo tar, sem extrair seus dados.
Ele mostra origem, usuário, data, formato, modo, componentes, catálogo de
checksums, total de pacotes e diferenças em relação à máquina atual. Backups
devem continuar passando em `Validate Latest Backup` antes da restauração.

A validação existente agora reconhece tanto `manifest.json` quanto o formato
histórico `manifest.txt`.

## Operating Profiles

- Normal: Live Monitor em 1 segundo.
- Gaming: Live Monitor em 1 segundo e lembrete do `gamemoderun %command%`.
- Quiet: Live Monitor em 5 segundos.
- Diagnostic: Live Monitor em 0,5 segundo.

Os perfis não alteram governor da CPU, curva de ventoinha, overclock ou limite de
energia. A preferência é salva em `~/ArchMind/Config/Maintenance` e entra nos
backups de configuração.

## Validação

Os novos testes usam Homes, raízes de sistema, Pacman, hardware e arquivos de
backup simulados. Eles cobrem persistência privada, detecção de atualização
externa, filtros de hardware, cancelamento da limpeza, proteção contra links,
catálogo sem extração e recusa de restauração genérica.

As baterias anteriores de instalação, restauração, AFI responsiva, Live Monitor,
GameMode, NVIDIA Vibrance e Plymouth permanecem obrigatórias antes do pacote
final.
