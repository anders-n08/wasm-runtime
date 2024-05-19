#!/usr/bin/env fish

zig build-exe wasm_test_1.zig -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall 
# zig build-exe wasm_test_1.zig -target wasm32-freestanding -fno-entry -rdynamic 
