#!/usr/bin/env python3
"""Run the real kernel in QEMU and verify scheduling and completion."""
import subprocess
import sys

qemu, kernel = sys.argv[1:]
command = [qemu, '-machine', 'virt', '-smp', '1', '-nographic',
           '-bios', 'none', '-kernel', kernel]
try:
    result = subprocess.run(command, capture_output=True, text=True, timeout=10)
except subprocess.TimeoutExpired as exc:
    print('FAIL: QEMU timed out', exc.stdout, exc.stderr)
    sys.exit(1)
output = result.stdout.replace('\r\n', '\n')
print(output, end='')
expected = [
    '[sched] run pid=1 (alpha)', '[alpha] step 1',
    '[sched] yield pid=1 (alpha)', '[sched] run pid=2 (beta)',
    '[beta]  step 1', '[sched] yield pid=2 (beta)',
    '[sched] run pid=1 (alpha)', '[alpha] step 2',
    '[sched] yield pid=1 (alpha)', '[sched] run pid=2 (beta)',
    '[beta]  step 2', '[sched] yield pid=2 (beta)',
    '[sched] run pid=1 (alpha)', '[alpha] step 3; context intact',
    '[sched] exit pid=1 (alpha)', '[sched] run pid=2 (beta)',
    '[beta]  step 3; context intact', '[sched] exit pid=2 (beta)',
    '[kernel] all processes exited; PASS',
]
lines = output.splitlines()
position = 0
for line in lines:
    if position < len(expected) and line == expected[position]:
        position += 1
if result.returncode != 0 or position != len(expected) or 'FAILED' in output:
    print(f'FAIL: exit={result.returncode}, matched={position}/{len(expected)}', file=sys.stderr)
    print(result.stderr, file=sys.stderr)
    sys.exit(1)
print('QEMU scheduling test passed')
