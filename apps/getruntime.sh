#!/bin/bash

total1=0
total2=0
for i in {1..5}
do
  echo "Run $i:"
  cp .eslintrc.base.js.1 .eslintrc.base.js
  start=$(date +%s%N)
  yarn lint > /dev/null 2>&1
  end=$(date +%s%N)
  runtime=$((end-start))
  echo "Runtime 1 was $runtime nanoseconds"
  total1=$(($total1+$runtime))

  cp .eslintrc.base.js.2 .eslintrc.base.js
  start=$(date +%s%N)
  yarn lint > /dev/null 2>&1
  end=$(date +%s%N)
  runtime=$((end-start))
  echo "Runtime 2 was $runtime nanoseconds"
  total2=$(($total2+$runtime))

done

average1=$(($total1/5))
average2=$(($total2/5))

echo "Average 1 runtime was $average1 nanoseconds"
echo "Average 2 runtime was $average2 nanoseconds"
