# ArchMind 1.5.14 — Wine Compatibility Pack

Esta revisão acrescenta um módulo opcional para preparar prefixos Wine comuns
com runtimes e componentes amplamente usados. A instalação base do Wine e o
Compatibility Pack continuam sendo ações separadas.

## Escopo

- Prefixo padrão `~/.wine` ou outro caminho selecionado dentro da Home.
- Recusa de diretórios Proton/Steam `compatdata` e caminhos Proton `pfx`.
- Inicialização explícita com `wineboot -u`; prefixos não reconhecidos e não
  vazios nunca são convertidos ou sobrescritos.
- Core Fonts, Visual C++ 2005/2008/2010/2012/2013, D3DCompiler 43/47,
  D3DX9, D3DX10, D3DX11_43 e D3DXOF.
- Visual C++ 2015–2022 instalado por `vcrun2022` somente quando os registros
  14.x necessários à arquitetura não estão presentes.
- XACT, XACT x64 em prefixos win64, XAudio e XInput executados separadamente.
- DXVK e 7-Zip para Windows opcionais.
- `dotnet48` isolado e protegido pela confirmação literal `DOTNET48`.

## Segurança e recuperação

- Nunca usa `--force` no Winetricks.
- Nunca copia DLLs, VKD3D-Proton, DXVK-NVAPI ou arquivos de Proton GE.
- Prefixos existentes recebem uma cópia preventiva obrigatória antes da primeira
  alteração de cada ação.
- Os processos Wine são encerrados antes da cópia para evitar um snapshot
  inconsistente.
- Cópias ficam em `~/ArchMind/Installer-Backups/Wine` e são catalogadas no
  Rollback Center.
- Logs privados ficam em `~/ArchMind/Logs/Wine-Compatibility`.
- Um verb com erro não apaga componentes anteriores: os demais são testados e o
  resultado final informa falha parcial com o caminho do log.
- Avisos do novo WoW64 são preservados no log; somente o código de saída real
  determina sucesso ou falha.

## Persistência

O ArchMind salva em `~/ArchMind/Config/Wine` apenas um recibo do último uso por
prefixo. Ele entra nos backups normais. Prefixos e seus snapshots não entram no
arquivo `.archmind`, evitando backups enormes e restauração implícita de
aplicativos Windows em outra máquina.

## Dependências

O Perfil Gamer passa a incluir `cabextract`, `unzip` e `7zip` junto de Wine e
Winetricks. Isso não aplica nenhum verb. O menu do Compatibility Pack também
oferece uma instalação base separada e confirmada.

## Limites desta build

Os testes usam Wine, Winetricks, Pacman, Vulkan e registros simulados. Downloads
reais dos redistribuíveis, novo WoW64 e execução dos programas resultantes ainda
devem ser validados em um usuário normal do Arch Linux.
