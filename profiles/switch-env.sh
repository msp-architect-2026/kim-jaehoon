#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 [home|academy]"
    echo ""
    echo "Available profiles:"
    ls -1 profiles/ | grep -v "README\|switch"
    exit 1
fi

PROFILE=$1

if [ ! -f "profiles/$PROFILE/lab.env" ]; then
    echo "❌ Error: Profile '$PROFILE' not found"
    echo ""
    echo "Available profiles:"
    ls -1 profiles/ | grep -v "README\|switch"
    exit 1
fi

cp profiles/$PROFILE/lab.env config/lab.env
echo "✅ Switched to '$PROFILE' environment"
echo ""
echo "Current settings:"
grep "^ENVIRONMENT\|^MINI_PC_IP\|^K8S_MASTER_IP" config/lab.env
