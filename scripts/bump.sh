#! /bin/bash

FROM_VERSION=$1
TO_VERSION=$2

find . -type f \
 | grep -v "__pycache__" \
 | grep -v ".git" \
 | grep -v "tests" \
 | grep -v ".pytest_cache" \
 | grep -v "pinthesky.egg-info" \
 | xargs sed -i "s/$FROM_VERSION/$TO_VERSION/"