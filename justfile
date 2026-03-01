set shell := ["sh", "-c"]
set windows-shell := ["powershell", "-c"]

zc := "./zig-out/bin/zc.exe"

_main:
    @just --list

build program="helloworld":
    {{ zc }} build --cc zig {{ program }}.zc -o {{ program }}

release program="helloworld":
    {{ zc }} build --cc zig -Os -W -s {{ program }}.zc -o {{ program }}

run program="helloworld":
    {{ zc }} run --cc zig {{ program }}.zc -o {{ program }}
