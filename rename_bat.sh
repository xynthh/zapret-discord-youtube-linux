#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

# Проверка прав суперпользователя
check_root

# Директория для обработки
TARGET_DIR="zapret-latest"

# Функция транслитерации кириллицы в латиницу
transliterate() {
    echo "$1" | sed -e 's/[аА]/a/g' -e 's/[бБ]/b/g' -e 's/[вВ]/v/g' -e 's/[гГ]/g/g' \
    -e 's/[дД]/d/g' -e 's/[еЕ]/e/g' -e 's/[ёЁ]/yo/g' -e 's/[жЖ]/zh/g' \
    -e 's/[зЗ]/z/g' -e 's/[иИ]/i/g' -e 's/[йЙ]/y/g' -e 's/[кК]/k/g' \
    -e 's/[лЛ]/l/g' -e 's/[мМ]/m/g' -e 's/[нН]/n/g' -e 's/[оО]/o/g' \
    -e 's/[пП]/p/g' -e 's/[рР]/r/g' -e 's/[сС]/s/g' -e 's/[тТ]/t/g' \
    -e 's/[уУ]/u/g' -e 's/[фФ]/f/g' -e 's/[хХ]/h/g' -e 's/[цЦ]/ts/g' \
    -e 's/[чЧ]/ch/g' -e 's/[шШ]/sh/g' -e 's/[щЩ]/sch/g' -e 's/[ъЪ]//g' \
    -e 's/[ыЫ]/y/g' -e 's/[ьЬ]//g' -e 's/[эЭ]/e/g' -e 's/[юЮ]/yu/g' \
    -e 's/[яЯ]/ya/g'
}

# Обработка .bat-файлов
find "$TARGET_DIR" -type f -name "*.bat" | while read -r file; do
    dir=$(dirname "$file")
    old_name=$(basename "$file")
    new_name=$(transliterate "$old_name" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]()]\+/_/g' | sed 's/__\+/_/g' | sed 's/_\+\.bat/.bat/g')
    if [ "$old_name" != "$new_name" ]; then
        if [ -w "$dir" ]; then
            if [ -f "$dir/$new_name" ]; then
                log "Предупреждение: Файл '$new_name' уже существует."
            else
                mv "$file" "$dir/$new_name" && log "Переименовано: '$old_name' -> '$new_name'"
            fi
        else
            handle_error "Нет прав на запись в директорию '$dir'."
        fi
    fi
done