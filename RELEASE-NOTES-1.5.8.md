# ArchMind 1.5.8

Consolida a base 1.5.7-dev de caminhos unificados e o protótipo separado de
instalador único. Os pacotes anteriores não foram alterados.

## Novidades

- Arquivo `.run` com o portátil completo e checksum do conteúdo incorporado.
- GNOME Terminal, GNOME Console, Konsole e Xterm como lançadores reconhecidos.
- Plano e confirmação antes de instalar; AFI aberta somente após sucesso.
- Cancelar não instala o projeto; erros mantêm mensagem no terminal.
- `--check` e `--extract` funcionam sem abrir janela; extração não sobrescreve
  diretório ocupado. O construtor também recusa sobrescrever um `.run` existente.
- Organização opcional de cópias `.zsh` soltas pela instalação e System Settings.
- Arquivos personalizados, links e referências detectadas são preservados.
- Lotes movidos ficam em `Config/Zsh/Imported-Home`, com segunda cópia preventiva
  e comando para desfazer que recusa conflitos.
- Cópias preventivas cobrem configurações, shell e entrada do menu Abrir com;
  falhas finais de instalação também acionam a recuperação.
- Links ocultos de aliases/Powerlevel10k mantêm importações existentes.
- Backups guardam o conteúdo desses dois arquivos, não links absolutos para o
  usuário antigo, e a restauração recria links de compatibilidade ausentes.
- Destinos de integração simbólicos ou não graváveis são recusados antes da
  instalação; preferências conflitantes não são silenciosamente substituídas.
- Escapamento do caminho Exec na entrada `.desktop`, incluindo espaços.

## Testes e limites

```bash
bash install.sh --check
bash tests/test-stable.sh
bash tests/test-run-installer.sh
python3 tests/test-install-safety.py
python3 tests/test-run-flow.py
python3 tests/test-responsive.py
```

Em ambientes que só disponibilizam root, os dois testes Python de instalação
precisam de `ARCHMIND_TEST_SIMULATE=1`. Eles alteram somente cópias temporárias,
nunca a proteção do pacote original. A verificação de arquivo somente leitura
é omitida nessa simulação, porque UID 0 não respeita essa restrição da mesma
forma. Os testes devem ser repetidos com usuário normal no Arch.

O fluxo de terminal usa PTY e console substituto nos testes do instalador;
o layout da AFI real é testado separadamente. Os lançadores gráficos são
simulados. Não houve teste real do Nautilus ou instalação/restauração no CachyOS.

O organizador não consegue provar ausência de referências indiretas. Por isso
é opt-in e não promete mover todos os arquivos `.zsh`. Não há remoção automática
de arquivos personalizados. Cópias preventivas e lotes importados são mantidos.

O `.run` não supera as proteções do GNOME: no primeiro uso, pode ser necessário
`Abrir com → Executar no Terminal`. Alternativa: `bash arquivo.run`, sem sudo.
Não é criada associação padrão global que execute todo script com duplo clique.

## Referências do formato de lançamento

- https://man.archlinux.org/man/gnome-terminal.1.en
- https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html
- https://help.gnome.org/gnome-help/nautilus-behavior.html
