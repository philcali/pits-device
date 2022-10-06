#!/bin/bash

USER=$1
shift 1
VERSION=${1:-""}

echo "Upgrading pinthesky software"
if [ -z "$VERSION" ] || [ "$VERSION" = '$version' ]; then
    python3 -m pip install --upgrade pinthesky
else
    python3 -m pip uninstall -y pinthesky
    python3 -m pip install "pinthesky$VERSION"
fi