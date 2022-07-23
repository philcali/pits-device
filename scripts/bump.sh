#! /bin/bash

FROM_VERSION=$1
TO_VERSION=$2

find . -type f \
 | grep -v "__pycache__" \
 | grep -v ".git" \
 | grep -v "tests" \
 | grep -v "diagram" \
 | grep -v ".pytest_cache" \
 | grep -v "pinthesky.egg-info" \
 | grep -v ".json" \
 | xargs sed -i "s/$FROM_VERSION/$TO_VERSION/"
