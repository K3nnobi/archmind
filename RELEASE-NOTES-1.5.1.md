# ArchMind 1.5.1 — integração Nautilus

## Nautilus

- Pastas aparecem antes dos arquivos.
- Executáveis do Windows usam o ícone embutido como miniatura.
- O fundo quadriculado de miniaturas transparentes é removido no GTK4.
- O CSS usa marcador próprio e não é duplicado em execuções repetidas.
- O cache de miniaturas não entra no backup e é reconstruído quando necessário.

## Instalação e interface

- O Perfil Base instala `python-pillow`, `icoutils` e `icoextract`.
- O Package Center oferece a ação **Nautilus Integration**.
- A instalação de todos os perfis recebe a integração pelo Perfil Base.
- Ausência do Nautilus ou falha opcional produz aviso sem interromper o restante.

## Backup e restauração

- `~/.config/gtk-4.0/gtk.css` continua preservado pela árvore `~/.config`.
- `~/.local/share/thumbnailers` agora é incluído explicitamente.
- Backups que contêm o thumbnailer exigem as dependências antes da restauração.
- Ao final, a configuração é reaplicada para restaurar o GSettings e renovar o cache.

Nenhum código do patch antigo baseado no Manager 1.4.1 foi aplicado.
