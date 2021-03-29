#!/bin/sh
i=1
while [ "$i" -le 11 ]; do
    printf ".";
    vault kv put kv/$i-secret-10 id="$(uuidgen)" >> step4.log 2>&1;
    i=$(( i + 1 ))
done 