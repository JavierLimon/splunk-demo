#!/bin/sh
i=1
while [ "$i" -le 201 ]; do
    printf ".";
    vault token create -policy=default >> step4.log 2>&1
    i=$(( i + 1 ))
done 