# ArchMind 1.4.2 — versão estável unificada

## Problemas observados após a formatação

1. O instalador avisava que `~/.local/bin` não estava no `PATH` porque a
   máquina ainda iniciava em Bash e a orientação tratava apenas `~/.zshrc`.
2. O plano de restauração era exibido, mas a confirmação não aparecia porque
   `show_restore_plan()` terminava com código de falha no modo real.
3. A restauração parou ao encontrar `~/.zshrc` sem permissão de escrita.
4. Os 143 pacotes oficiais eram enviados em um único lote. Um nome removido ou
   renomeado podia cancelar o lote inteiro sem um resumo claro.
5. Pacotes AUR podiam ficar ausentes quando o `yay` ainda não estava instalado.
6. `sort` usava `LC_ALL=C`, mas `comm` usava o locale da sessão, produzindo a
   mensagem de entrada não ordenada.
7. Os plugins `zsh-autosuggestions`, `zsh-syntax-highlighting` e
   `zsh-completions` podiam não voltar, mesmo com o `.zshrc` restaurado.
8. `~/.zsh_aliases` existia no backup, mas uma restauração interrompida não
   garantia o arquivo nem a linha que o carrega no `.zshrc`.
9. O backup do próprio projeto podia sobrescrever a instalação corrigida com
   uma cópia antiga do Manager.

## Correções incorporadas

- configura `~/.local/bin` no Bash e no Zsh sem duplicar linhas;
- exige confirmação antes de executar o plano real;
- oferece corrigir a propriedade de arquivos da Home antes de sobrescrevê-los;
- atualiza o sistema, filtra pacotes disponíveis e registra pendências em
  `~/ArchMind/Logs`;
- tenta novamente pacotes oficiais separadamente quando o lote falha;
- instala e usa `yay` para o AUR, mantendo um relatório do que falhar;
- usa `LC_ALL=C` em `sort` e `comm`;
- garante os plugins do Zsh, Powerlevel10k, completions e `~/.zsh_aliases`;
- separa configurações, runtime e projeto para impedir downgrade acidental;
- quando o backup é mais antigo, guarda o projeto antigo em
  `~/ArchMind/Recovered-Projects` e preserva a versão estável instalada;
- mantém os modelos do menu `Novo documento` no perfil Base.

## Instalação ou atualização

Execute como usuário normal, sem `sudo`:

```bash
./install.sh --check
./install.sh --dry-run
./install.sh
```

Depois reabra o terminal ou execute:

```bash
export PATH="$HOME/.local/bin:$PATH"
archmind-console
```

Na máquina recém-formatada, use:

```text
Restauração → Recuperar sistema após formatação
```

Confira o resumo final e os relatórios antes de considerar a migração concluída.
