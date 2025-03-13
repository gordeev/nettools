#!/bin/bash

# Список MAC адресов, которые нужно исключить (например, ноутбук коллеги с виртуалкой)
EXCLUDED_MACS=("11:22:33:44:55:66" "00:11:22:33:44:55")
# Построение регулярного выражения для исключения (адреса объединяются через "|")
EXCLUDE_PATTERN=$(IFS="|"; echo "${EXCLUDED_MACS[*]}")

BASELINE_TTL=""

while true; do
    clear
    echo "====== Состояние на $(date) ======"
    
    # Получаем ARP-таблицу
    arp_data=$(arp -a)
    
    # Находим дублирующиеся MAC-адреса (исключая указанные в списке)
    duplicate_macs=$(echo "$arp_data" | awk '{print $4}' \
                     | grep -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' \
                     | grep -Eiv "$EXCLUDE_PATTERN" \
                     | sort | uniq -c | awk '$1>1 {print $2}')
    
    if [ -z "$duplicate_macs" ]; then
        echo "ARP: Нет дублирующихся MAC адресов."
    else
        echo "ARP: Обнаружены дублирующиеся MAC адреса:"
        echo ""
        # Заголовок таблицы
        printf "%-10s | %-20s | %s\n" "Время" "MAC адрес" "IP адреса"
        printf "%-10s-+-%-20s-+-%s\n" "----------" "--------------------" "--------------------------"
        for mac in $duplicate_macs; do
            ips=$(echo "$arp_data" | awk -v m="$mac" '$4 == m {print $2}' | tr -d '()')
            printf "%-10s | %-20s | %s\n" "$(date +'%H:%M:%S')" "$mac" "$ips"
        done
    fi
    
    # Определяем адрес шлюза через netstat
    GATEWAY_IP=$(netstat -nr | awk '$1=="default" && $2 ~ /^[0-9]+\./ {print $2; exit}')
    if [ -n "$GATEWAY_IP" ]; then
        echo ""
        echo "Найден шлюз: $GATEWAY_IP"
    else
        echo ""
        echo "Default gateway не найден."
        sleep 60
        continue
    fi
    
    # Проверяем TTL для шлюза
    gateway_ping=$(ping -c 1 "$GATEWAY_IP" 2>/dev/null)
    current_ttl=$(echo "$gateway_ping" | sed -En 's/.*ttl=([0-9]+).*/\1/p')
    if [ -n "$current_ttl" ]; then
        if [ -z "$BASELINE_TTL" ]; then
            BASELINE_TTL=$current_ttl
            echo "Базовый TTL для шлюза $GATEWAY_IP установлен в $BASELINE_TTL"
        else
            if [ "$current_ttl" -lt "$BASELINE_TTL" ]; then
                echo "[!] Возможно, перехват трафика (MITM) - TTL шлюза изменился: $BASELINE_TTL -> $current_ttl"
            else
                echo "TTL шлюза $GATEWAY_IP стабилен: $current_ttl"
            fi
        fi
    else
        echo "Не удалось получить TTL для шлюза $GATEWAY_IP"
    fi
    
    sleep 60
done
