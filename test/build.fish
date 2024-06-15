#!/usr/bin/env fish

zig build-exe wasm_test_1.zig --stack 8192 -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall 
zig build-exe led_strip_cycle.zig --stack 8192 -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall 
