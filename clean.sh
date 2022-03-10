#!/bin/bash
rm -f *.txt
rm -f *.xml
rm -f networkplan.drawio
rm -f model.json
for f in *; do
    if [ -d "$f" ]; then
        rm -rf "$f"
    fi
done
