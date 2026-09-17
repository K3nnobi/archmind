# ArchMind 1.5.2 — rounded blur e Papirus amarelo

## GNOME e Blur My Shell

- O Perfil Base instala `gnome-rounded-blur` pelo AUR.
- A restauração GNOME garante o pacote mesmo ao usar backups antigos.
- O ArchMind verifica `rounded-blur-found` depois da configuração.
- Resultado diferente de `true` gera aviso, mas não interrompe a instalação.
- Logout/login é informado como etapa necessária para carregar a biblioteca.
- Após atualizações do GNOME Shell/Mutter, o ArchMind orienta recompilar com
  `yay -S --rebuild gnome-rounded-blur`.

## Papirus-Dark

- O Perfil Base instala `papirus-icon-theme` e `papirus-folders`.
- A cor amarela é aplicada com
  `papirus-folders -C yellow --theme Papirus-Dark`.
- A configuração é reaplicada depois de uma restauração completa ou de GNOME.

## Segurança e compatibilidade

- A integração é opcional: uma falha não cancela perfis nem restaurações.
- Nenhum hack foi acrescentado ao `gtk.css` para o recorte do blur.
- A ação **GNOME Visual Integration** está disponível no Package Center.
