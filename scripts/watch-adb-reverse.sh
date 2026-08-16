#!/bin/bash
# Mantém o túnel adb reverse (porta 8000) sempre ativo.
# Deixe rodando numa aba de terminal separada durante todo o desenvolvimento.
ADB=~/Library/Android/sdk/platform-tools/adb

echo "Vigiando conexão do dispositivo e mantendo adb reverse tcp:8000 ativo..."
while true; do
  $ADB wait-for-device
  $ADB reverse tcp:8000 tcp:8000 && echo "$(date '+%H:%M:%S') - túnel ativo"
  sleep 3
done
