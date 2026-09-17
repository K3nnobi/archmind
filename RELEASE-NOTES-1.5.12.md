# ArchMind 1.5.12 — NVIDIA Vibrance e Plymouth / Boot Visual

Esta build adiciona duas integrações independentes. O Digital Vibrance trabalha
na sessão do usuário; o patch Plymouth altera arquivos do sistema somente após
confirmação explícita.

## NVIDIA Vibrance

- Detecta uma GPU NVIDIA antes de instalar ou configurar.
- Aceita os pacotes AUR `nvibrant` ou `nvibrant-bin` e exige o executável
  `/usr/bin/nvibrant`.
- Mantém o valor em `~/ArchMind/Config/NVIDIA/vibrance.conf`.
- Cria `~/.config/systemd/user/nvibrant.service` com atraso de cinco segundos.
- Permite aplicar, alterar intensidade, reaplicar, consultar e remover.
- Preserva um serviço anterior e o restaura na remoção feita na mesma máquina.
- O Perfil Gamer chama a integração como recurso opcional e não bloqueante.

## Plymouth

O pacote `plymouth` foi acrescentado ao Perfil Base. Isso, sozinho, não muda
`mkinitcpio`, GRUB nem o tema.

O patch separado `Plymouth / Boot Visual`:

1. valida Plymouth, GRUB, mkinitcpio, tema spinner e arquivos regulares;
2. define `Theme=spinner` preservando outras chaves;
3. mantém um único hook `plymouth` imediatamente depois de `udev`;
4. acrescenta somente `quiet` e `splash` ausentes;
5. oculta apenas os dois `echo` associados às mensagens de Linux e initramfs;
6. cria snapshots em `~/ArchMind/Installer-Backups/Plymouth`;
7. executa `mkinitcpio -P` e `grub-mkconfig`;
8. restaura o snapshot automaticamente se a reconstrução falhar;
9. detecta quando uma atualização do GRUB removeu as marcações;
10. remove apenas mudanças registradas para a máquina atual.

O patch não edita `/boot/grub/grub.cfg` diretamente e recusa variantes que não
contenham o padrão esperado. Não há suporte automático a systemd-boot, dracut ou
mkinitcpio com hooks `systemd` nesta build.

## Validação

Os testes usam uma raiz descartável e comandos simulados. Eles cobrem repetição,
reversão exata, hook Plymouth preexistente, layout GRUB desconhecido, falha do
`mkinitcpio`, serviço nvibrant preexistente e intensidade inválida. Nenhum teste
automatizado escreve no `/etc` ou `/boot` da máquina de desenvolvimento.

O teste definitivo do splash continua sendo uma reinicialização real da máquina
de destino. Não interrompa a reconstrução do initramfs ou do GRUB.
