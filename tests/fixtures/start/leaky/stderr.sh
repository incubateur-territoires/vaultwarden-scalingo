#!/bin/sh
# Broken start script on purpose: prints the S3 secret key on stderr.
echo "debug: $AWS_SECRET_ACCESS_KEY" >&2
