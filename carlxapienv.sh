#!/bin/sh
curl -fsSL https://platform.activestate.com/dl/cli/_pdli02/install.sh | sh
state checkout FredCoMdLib/CarlXAPIUtils-PerlEnv .
state use CarlXAPIUtils-PerlEnv
# virtual
# state shell CarlXAPIUtils-PerlEnv
