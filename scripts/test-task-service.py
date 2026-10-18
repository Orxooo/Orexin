#!/usr/bin/env python3
"""Local process smoke: private socket/state, no install, helper authorization or sleep.
Usage: python3 scripts/test-task-service.py /absolute/build/debug [--interface]
Only short commands and idle-display desk assertions are used. Artifacts are retained.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('binaries', type=Path)
parser.add_argument('--interface', action='store_true')
parser.add_argument('--app', type=Path, help='Packaged Orexin.app; required for UI runtime verification')
args = parser.parse_args()
root = Path(tempfile.mkdtemp(prefix='orx78-'))
root.chmod(0o700)
cli = args.binaries / 'orexin'
app = (args.app / 'Contents/MacOS/Orexin') if args.app else args.binaries / 'WakeMac'
if args.interface and not args.app:
    parser.error('--interface requires --app because native notifications require an application bundle')
env = dict(os.environ, OREXIN_SOCKET=str(root / 'control.sock'), OREXIN_STATE_DIR=str(root / 'state'))
checks = []
service_pid = None
interface = None

def call(*arguments, ok=True):
    result = subprocess.run([str(cli), *arguments, '--json'], env=env, capture_output=True, text=True, timeout=25)
    data = json.loads(result.stdout)
    if ok:
        assert result.returncode == 0 and data['ok'], (arguments, data)
    else:
        assert result.returncode != 0 and not data['ok'], (arguments, data)
    return data

def document(reply):
    import base64
    return json.loads(base64.b64decode(reply['document']))

def wait_plan(id):
    for _ in range(150):
        run = document(call('plan-status', id))
        if run['state'] not in ['running', 'cancelling']:
            return run
        time.sleep(0.1)
    raise AssertionError('Plan did not finish')

def submit(title, tasks, concurrent=2):
    path = root / (title + '.json')
    path.write_text(json.dumps(dict(version=1, title=title, tasks=tasks, maxConcurrent=concurrent, mode='desk', screen='idle', teardown='restore')))
    call('plan-validate', str(path))
    return document(call('plan-run', str(path)))['id']

def task(id, command, deps=None, condition='success'):
    return dict(id=id, command=command, directory=str(root), dependencies=deps or [], condition=condition)

try:
    starts = [subprocess.Popen([str(cli), 'service-start', '--service-executable', str(app), '--json'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
    replies = []
    for starter in starts:
        out, err = starter.communicate(timeout=25)
        assert starter.returncode == 0, (out, err)
        replies.append(json.loads(out))
    assert replies[0]['service']['pid'] == replies[1]['service']['pid']
    info = replies[0]['service']
    checks.append('concurrent startup clients share one ready service')
    service_pid = info['pid']
    time.sleep(0.2)
    assert call('service-status')['service']['instanceID'] == info['instanceID']
    checks.append('service survives launching CLI exit')
    assert call('service-start', '--service-executable', str(app))['service']['pid'] == service_pid
    checks.append('second start reuses singleton')
    handle = call('register', '--title', 'independent', '--screen', 'idle', '--lease', '60')['handle']
    owner = handle['id'] + ':' + handle['token']
    delay = '4' if args.interface else '0.4'
    group = submit('dependencies', [task('a', f'/bin/sleep {delay}; /usr/bin/touch a'), task('b', f'/bin/sleep {delay}; /usr/bin/touch b'), task('c', 'test -f a && test -f b', ['a', 'b'])])
    call('service-stop', ok=False)
    if args.interface:
        interface = subprocess.Popen([str(app)], env=env, stdout=(root / 'interface.stdout').open('w'), stderr=(root / 'interface.stderr').open('w'))
        time.sleep(2)
        assert interface.poll() is None, f'Interface exited {interface.returncode}; see {root}/interface.stderr'
        assert document(call('plan-status', group))['state'] == 'running'
        interface.terminate(); interface.wait(timeout=5); interface = None
        assert call('service-status')['service']['pid'] == service_pid
        checks.append('real UI process launch/exit leaves service alive')
    run = wait_plan(group)
    assert run['state'] == 'succeeded', run
    assert all(t['exitCode'] == 0 for t in run['tasks'])
    status = call('status', handle['id'])
    assert status['tasks'][0]['request']['state'] == 'active' and status['tasks'][0]['satisfied']
    checks.append('DAG runs after submitting CLI exit; independent request survives group teardown')
    failed = submit('failure', [task('a', '/usr/bin/false'), task('skip', '/usr/bin/touch should-not-exist', ['a']), task('recovery', '/usr/bin/touch recovered', ['a'], 'failure')])
    assert wait_plan(failed)['state'] == 'failed'
    assert not (root / 'should-not-exist').exists() and (root / 'recovered').exists()
    checks.append('failure branch and skip propagation; no success teardown')
    cancelled = submit('cancel', [task('a', '/bin/sleep 1; /usr/bin/touch drained'), task('b', '/usr/bin/touch cancelled-pending', ['a'])], 1)
    for _ in range(50):
        if document(call('plan-status', cancelled))['tasks'][0]['state'] == 'running': break
        time.sleep(0.05)
    time.sleep(0.2)
    call('plan-cancel', cancelled)
    assert wait_plan(cancelled)['state'] == 'cancelled'
    assert (root / 'drained').exists() and not (root / 'cancelled-pending').exists()
    checks.append('cancel drains running command and never launches pending command')
    call('complete', owner, '--exit-code', '0')
    protected = call('register', '--title', 'crash recovery', '--screen', 'idle', '--lease', '60')['handle']['id']
    os.kill(service_pid, signal.SIGTERM)
    time.sleep(1)
    restarted = call('service-start', '--service-executable', str(app))['service']
    service_pid = restarted['pid']
    assert restarted['instanceID'] != info['instanceID']
    assert call('status', protected)['tasks'][0]['request']['state'] == 'lost'
    assert document(call('plan-status', group))['state'] == 'succeeded'
    checks.append('service restart marks live requests lost and preserves completed history')
    assert call('service-stop')['ok']
    service_pid = None
    (root / 'result.json').write_text(json.dumps(dict(checks=checks, passed=True), indent=2))
    print(json.dumps(dict(artifact_directory=str(root), checks=checks, passed=True), indent=2))
finally:
    if interface and interface.poll() is None:
        interface.terminate(); interface.wait(timeout=5)
    if service_pid:
        try:
            call('stop-all')
            call('service-stop')
        except Exception:
            # Only the private test service created above, never an installed app.
            try: os.kill(service_pid, signal.SIGTERM)
            except ProcessLookupError: pass
