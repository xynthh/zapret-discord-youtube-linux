#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

# Проверка прав суперпользователя
check_root

# Константы
TABLE_NAME="inet zapretunix"
CHAIN_NAME="output"
RULE_COMMENT="Added by zapret script"

# Остановка процессов nfqws
stop_nfqws_processes() {
    log "Остановка nfqws..."
    if ! sudo pkill -f nfqws; then
        log "Процессы nfqws не найдены."
    fi
}

# Очистка правил nftables
clear_firewall_rules() {
    log "Очистка nftables..."
    if sudo nft list tables | grep -q "$TABLE_NAME"; then
        if sudo nft list chain $TABLE_NAME $CHAIN_NAME &>/dev/null; then
            handles=$(sudo nft -a list chain $TABLE_NAME $CHAIN_NAME | grep "$RULE_COMMENT" | awk '{print $NF}')
            for handle in $handles; do
                sudo nft delete rule $TABLE_NAME $CHAIN_NAME handle $handle || log "Не удалось удалить правило $handle."
            done
            if ! sudo nft list chain $TABLE_NAME $CHAIN_NAME | grep -q "rule"; then
                sudo nft delete chain $TABLE_NAME $CHAIN_NAME
            fi
            if ! sudo nft list table $TABLE_NAME | grep -q "chain"; then
                sudo nft delete table $TABLE_NAME
            fi
        else
            log "Цепочка '$CHAIN_NAME' не найдена."
        fi
    else
        log "Таблица '$TABLE_NAME' не найдена."
    fi
}

# Основная функция
stop_and_clear_firewall() {
    stop_nfqws_processes
    clear_firewall_rules
}

stop_and_clear_firewall