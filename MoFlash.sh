#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}==============================================="
echo -e "       MOFLASH - TOOL       "
echo -e "===============================================${NC}"

echo -e "\n[1/5] Verificando dependências..."
pkg update -y && pkg upgrade -y
pkg install android-tools wget unzip gawk openssl-tool termux-api -y

echo -e "\n[2/5] Detectando aparelho..."
echo -e "${YELLOW}Conecte o celular em modo Fastboot via OTG...${NC}"

while ! fastboot devices | grep -q "fastboot"; do
    sleep 2
done

PRODUCT_NAME=$(fastboot getvar product 2>&1 | grep "product:" | awk '{print $2}')
[ -z "$PRODUCT_NAME" ] && PRODUCT_NAME="Modelo não detectado"

echo -e "${GREEN}Aparelho detectado: $PRODUCT_NAME${NC}"

echo -e "\n[3/5] Buscando Firmware Mais Recente"
echo -e "Abrindo repositório para o modelo: ${YELLOW}$PRODUCT_NAME${NC}"
sleep 2

termux-open "https://mirrors.lolinet.com/firmware/moto/$PRODUCT_NAME/official/"

echo -e "\n${CYAN}INSTRUÇÕES:${NC}"
echo -e "1. No navegador, escolha a pasta da sua operadora (ou 'RETAIL')."
echo -e "2. Copie o link do arquivo .zip mais recente."
echo -e "3. Volte aqui e cole o link."

echo -en "\n${YELLOW}Cole o link direto do firmware (.zip): ${NC}"
read ROM_URL

mkdir -p firmware_work && cd firmware_work
echo -e "${YELLOW}Iniciando download...${NC}"
wget --show-progress "$ROM_URL" -O firmware.zip

if [ ! -f "firmware.zip" ]; then
    echo -e "${RED}Erro: Arquivo não encontrado!${NC}"
    exit 1
fi

echo -e "\n${CYAN}Deseja verificar a integridade do arquivo?${NC}"
echo -e "1) MD5  2) SHA256  3) Pular"
read -p "Escolha: " hash_opt

case $hash_opt in
    1)
        read -p "Cole o MD5 esperado: " exp_md5
        echo "Verificando..."
        echo "$exp_md5  firmware.zip" | md5sum -c - || { echo -e "${RED}ERRO DE MD5!${NC}"; exit 1; }
        ;;
    2)
        read -p "Cole o SHA256 esperado: " exp_sha
        echo "Verificando..."
        echo "$exp_sha  firmware.zip" | sha256sum -c - || { echo -e "${RED}ERRO DE SHA256!${NC}"; exit 1; }
        ;;
esac

echo -e "${YELLOW}Extraindo firmware...${NC}"
unzip -o firmware.zip

echo -e "\n[4/5] Preparando Flash"
echo -e "${RED}################################################"
echo -e "AVISO: Nunca bloqueie o bootloader numa versão de"
echo -e "firmware desatualizado, ou sofrerá com brick."
echo -e "Não sou responsável pelos seus atos!"
echo -e "################################################${NC}"
read -p "Confirmar início do processo? (S/n): " confirm
[[ "$confirm" == "n" ]] && exit 1

flash_check() {
    echo -e "${YELLOW}Flashando $1...${NC}"
    $2
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERRO AO FLASHAR $1! O processo foi interrompido para sua segurança.${NC}"
        exit 1
    fi
}

ACTIVE_SLOT=$(fastboot getvar current-slot 2>&1 | awk 'NR==1{print $2}')
if [ "$ACTIVE_SLOT" = "b" ]; then
    fastboot --set-active=a
fi

fastboot oem fb_mode_set
flash_check "Partição" "fastboot flash partition gpt.bin"
flash_check "Bootloader" "fastboot flash bootloader bootloader.img"
fastboot flash --slot=all vbmeta vbmeta.img
fastboot flash --slot=all vbmeta_system vbmeta_system.img
fastboot flash radio radio.img
fastboot flash --slot=all bluetooth BTFM.bin
fastboot flash --slot=all dsp dspso.bin
fastboot flash --slot=all logo logo.bin
fastboot flash --slot=all boot boot.img
fastboot flash --slot=all vendor_boot vendor_boot.img
fastboot flash --slot=all dtbo dtbo.img

for img in super.img_sparsechunk.*; do
    [ -e "$img" ] || continue
    flash_check "$img" "fastboot flash super $img"
done

fastboot erase userdata
fastboot erase metadata
fastboot oem fb_mode_clear

echo -e "\n${GREEN}==============================================="
echo -e "          FLASH CONCLUÍDO COM SUCESSO!         "
echo -e "===============================================${NC}"

echo -e "Deseja bloquear o bootloader agora? (Sim/Não)"
echo -e "${YELLOW}Atenção: Só escolha Sim se você verificou que esta é a última versão oficial.${NC}"
read -p "Escolha: " lock_final

if [[ "$lock_final" == "Sim" || "$lock_final" == "sim" || "$lock_final" == "S" ]]; then
    echo -e "${RED}Solicitando bloqueio do bootloader...${NC}"
    fastboot oem lock
else
    echo -e "${GREEN}Mantendo bootloader desbloqueado.${NC}"
fi

echo -e "\nReiniciando o aparelho em 5 segundos..."
sleep 5
fastboot reboot
