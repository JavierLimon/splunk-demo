#!/bin/sh
i=1
while [ "$i" -le 26 ]; do
    printf ".";
    vault kv put kv/$i-secret-25 id="$(uuidgen)" >> step4.log 2>&1
    i=$(( i + 1 ))
done