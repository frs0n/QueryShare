"""Run against queryshare-harness's isolated fixture, never a phone."""
import os, io, stat, sys, hashlib, threading
import paramiko
USER = os.environ.get('QS_TEST_USER', 'mobile')
HOST, PORT, PASSWORD = '127.0.0.1', 22222, 'queryshare-test-password'
def connect(password=PASSWORD):
    t = paramiko.Transport((HOST, PORT)); t.banner_timeout = 5; t.auth_timeout = 5
    t.connect(username=USER, password=password)
    return t
try:
    connect('incorrect')
    raise AssertionError('wrong password accepted')
except paramiko.AuthenticationException:
    print('PASS wrong password rejected')
t = connect(); assert b'worse_query' in (t.get_banner() or b''); print('PASS English SSH authentication banner'); s = paramiko.SFTPClient.from_transport(t); s.get_channel().settimeout(15)
direct = '--direct' in sys.argv
root = '/Containers/Apps/测试 [com.example.demo]' if '--alias' in sys.argv else ('' if direct else '/' + s.listdir('/')[0])
if '--alias' in sys.argv:
    assert 'Containers' in s.listdir('/')
    assert s.listdir('/Containers') == ['Apps']
    assert '测试 [com.example.demo]' in s.listdir('/Containers/Apps')
    print('PASS named virtual container hierarchy')
assert s.normalize('.') == '/'
base = root + '/integration'
try: s.mkdir(base)
except OSError: pass
for name in s.listdir(base): s.remove(base + "/" + name)
payload = os.urandom(2_500_123)
with s.open(base + '/中文 100%.bin', 'wb') as f:
    f.set_pipelined(True); f.write(payload)
with s.open(base + '/中文 100%.bin', 'rb') as f:
    assert f.read() == payload
print('PASS 2.5MB pipelined upload/download; Unicode, spaces, percent')
with s.open(base + '/中文 100%.bin', 'r+b') as f:
    f.seek(123456); f.write(b'EDIT'); f.flush(); f.seek(123456); assert f.read(4) == b'EDIT'
assert s.stat(base + '/中文 100%.bin').st_size == len(payload)
s.truncate(base + '/中文 100%.bin', 123460)
s.chmod(base + '/中文 100%.bin', 0o600)
s.utime(base + '/中文 100%.bin', (1700000000, 1700000001))
a = s.stat(base + '/中文 100%.bin'); assert a.st_size == 123460 and stat.S_IMODE(a.st_mode) == 0o600 and a.st_mtime == 1700000001
print('PASS random read/write, truncate, chmod, utime')
s.rename(base + '/中文 100%.bin', base + '/renamed.bin')
with s.open(base + '/dest.bin', 'wb') as f: f.write(b'old')
s.posix_rename(base + '/renamed.bin', base + '/dest.bin')
assert s.stat(base + '/dest.bin').st_size == 123460
s.chmod(base, 0o700)
assert stat.S_IMODE(s.stat(base).st_mode) == 0o700
print('PASS rename, atomic overwrite extension, directory chmod')
s.symlink('dest.bin', base + '/link')
assert s.readlink(base + '/link') == 'dest.bin'
assert stat.S_ISLNK(s.lstat(base + '/link').st_mode)
with s.open(base + '/link', 'rb') as f: assert f.read(4) == payload[:4]
print('PASS symlink and readlink')
for i in range(140):
    with s.open(base + '/small-%03d' % i, 'wb') as f: f.write(str(i).encode())
assert len(s.listdir(base)) == 142
print('PASS multi-page directory listing')
for name in s.listdir(base): s.remove(base + '/' + name)
s.rmdir(base)
try: s.stat(root + '/missing')
except FileNotFoundError: pass
else: raise AssertionError('missing file should fail')
try: s.open('/../../etc/passwd', 'rb')
except OSError: pass
else: raise AssertionError('escaped virtual root')
try: s.symlink('/etc/passwd', root + '/escape')
except OSError: pass
else:
    if not direct: raise AssertionError('escaped symlink')
    try: s.open(root + '/escape', 'rb')
    except OSError: pass
    else: raise AssertionError('escaped direct root')
    s.remove(root + '/escape')
print('PASS delete, rmdir, missing-file errors, virtual-root isolation')
s.close(); t.close()
print('ALL TESTS PASSED')
