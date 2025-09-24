#!/usr/bin/env bash

source .env

echo "POSTGRES_URL=\"postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:${POSTGRES_PORT}/${POSTGRES_DB}\""