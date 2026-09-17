#!/usr/bin/env bash

ROOT="$HOME/ArchMind/System/Core"

echo
echo "=============================================="
echo " ArchMind Translation Audit"
echo "=============================================="
echo

grep -RniE \
'á|à|â|ã|é|ê|í|ó|ô|õ|ú|ç|ção|ções|Atualização|Atualizações|Informações|Configuração|Configurações|Deseja|Falhou|Concluído|Cancelar|Continuar|Erro|Aviso|Restauração|Backup criado|Pronto|Disponível|Indisponível|Sucesso|Falha|Restaurar|Instalação|Monitoramento|Diagnóstico|Modelo|Projeto|Diretório|Último|Nenhum|Selecionado|Pressione|Voltar|Sair|Sistema' \
"$ROOT"

echo
echo "=============================================="
echo " Finished"
echo "=============================================="
