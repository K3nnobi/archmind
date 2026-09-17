# ArchMind 1.5.9 — progresso de instalação

- Barra ciano animada durante a instalação interativa, compatível com o tema.
- Progresso por marcos reais: pacote validado, cópia preventiva, arquivos
  preparados/instalados e integrações configuradas.
- Exibição mínima de 5 segundos: aproximadamente 4,5 s de progressão e 0,5 s
  para visualizar o sucesso. Não adiciona 5 s inteiros a uma instalação lenta.
- O percentual representa etapas, não bytes copiados ou previsão de tempo.
- A animação nunca ultrapassa a etapa que o instalador realmente concluiu.
- Falhas antes da conclusão não exibem 100% e continuam acionando a recuperação.
- O console abre depois da confirmação visual de sucesso.
- Barra ajustada à largura disponível, sem esconder o cursor.
- `--check`, `--dry-run`, saída redirecionada e TERM=dumb não têm animação/atraso.
- `./install.sh --no-progress` desativa o efeito no uso manual.

A verificação inicial e a confirmação do plano pelo `.run` continuam rápidas;
o tempo visual mínimo começa na instalação confirmada. A instalação do Zsh,
caso necessário, pode levar mais tempo e acontece antes da barra.

São preservadas as proteções, a organização dos .zsh e a estrutura da 1.5.8.
Testes de fluxo usam PTY; funcionais no ambiente UID 0 usam cópias descartáveis
com guardas adaptadas. O pacote original continua recusando instalação como root.
Não foi realizada interação com um GNOME real neste ambiente.
