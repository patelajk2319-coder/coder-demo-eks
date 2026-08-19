#!/usr/bin/env bash
# ANSI colour codes for consistent script output

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[info]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
section() { echo -e "${BLUE}[----]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }
