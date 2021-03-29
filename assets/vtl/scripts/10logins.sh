#!/bin/sh
i=1
while [ "$i" -le 11 ]; do
    printf ".";
    vault login -method=userpass username=learner password=vtl-password >> step4.log 2>&1
    i=$(( i + 1 ))
done 