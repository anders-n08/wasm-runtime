#!/usr/bin/env fish

zig build-exe wasm_test_1.zig -target wasm32-freestanding -fno-entry --export=test1 --export=test2 -O ReleaseSmall 
