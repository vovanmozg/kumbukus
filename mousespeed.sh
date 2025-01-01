#!/bin/bash


# При зажатии ctrl + shift движение курсора мыши станет очень медленным. Для правильной работы нужно
# получить корректные id клавиатуры и мыши (они меняются при перезагрузке)
# Скрипт запускается при старте системы, поэтому ставим небольшую задержку

sleep 20

# Идентификатор клавиатуры. Можно получить с помощью команды xinput list
keyboard_id=`xinput list | grep -i "AleksIv Sofle" | grep -v Keyboard | grep -v Control | grep keyboard | head -n 1 | grep -oP 'id=\K\d+'`
mouse_id=`xinput list | grep -i "Logitech ERGO M575" | grep -oP 'id=\K\d+'`

echo "keyboard_id: $keyboard_id, mouse_id: $mouse_id"
# Функции для изменения скорости мыши
slow_speed() {
  # 15 - идентификатор трекбола
  # 193 - код действия Coordinate Transformation Matrix (посмотреть
  #   коды: xinput --list-props 15)
  xinput set-prop $mouse_id 193 0.1 0 0 0 0.1 0 0 0 1
}

normal_speed() {
  # нормальная матрица трансформации 1 0 0 0 1 0 0 0 1
  xinput set-prop $mouse_id 193 1 0 0 0 1 0 0 0 1
}

# Инициализация начальной скорости мыши
normal_speed

# Перехват событий клавиатуры
xinput test $keyboard_id | while read line
do
  if [[ "$line" == *"key press"* && "$line" == *"37"* ]]; then
    ctrl_pressed=true
  elif [[ "$line" == *"key press"* && "$line" == *"50"* ]]; then
    shift_pressed=true
  fi

  if [[ "$line" == *"key release"* && "$line" == *"37"* ]]; then
    ctrl_pressed=false
  elif [[ "$line" == *"key release"* && "$line" == *"50"* ]]; then
    shift_pressed=false
  fi

  # Проверяем, нажаты ли обе клавиши
  if [[ "$ctrl_pressed" == true && "$shift_pressed" == true ]]; then
    slow_speed
  else
    normal_speed
  fi
  
done
