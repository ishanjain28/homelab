"""Real-kernel bridge tests. Run only in a disposable user/network namespace.

Usage: unshare -Urn python3 tests/firewall/netns.py RULES REVOKED AUDIT
Uses only Python's standard library, iproute2, nftables and util-linux.
"""
import json
import os
import pathlib
import socket
import struct
import subprocess as sp
import sys
import time


def run(*cmd, check=True, **kwargs):
    return sp.run(cmd, check=check, text=True, stdout=sp.PIPE, stderr=sp.PIPE, **kwargs)


def ip(*args):
    return run("ip", *args)


# Refuse to run in the host network namespace, even when accidentally invoked as root.
uid_map = pathlib.Path("/proc/self/uid_map").read_text().split()
assert os.getuid() == 0 and uid_map[1] != "0" and uid_map[2] == "1", "use unshare -Urn as an unprivileged user"
rules, revoked, audit = sys.argv[1:]
children = []
peers = {}


def peer(name, *cmd, **kwargs):
    if name == "host":
        return run(*cmd, **kwargs)
    return run("nsenter", "-t", str(peers[name]), "-n", *cmd, **kwargs)


def connect(name, address, port=8080):
    code = "import socket,sys; s=socket.create_connection((sys.argv[1],int(sys.argv[2])),.5); s.sendall(b'hello'); assert s.recv(5)==b'hello'"
    return peer(name, sys.executable, "-c", code, address, str(port), check=False).returncode == 0


def install(path):
    # The deletion and replacement are a single transaction, as in NixOS.
    text = "table bridge homelab_services\ndelete table bridge homelab_services\n" + pathlib.Path(path).read_text()
    run("nft", "-f", "-", input=text)


def server(name, port):
    code = '''import socket,threading,time,sys
s=socket.socket(socket.AF_INET6); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,0); s.bind(('::',int(sys.argv[1]))); s.listen()
def echo(c):
 try:
  while True:
   d=c.recv(4096)
   if not d: break
   c.sendall(d)
 finally: c.close()
while True:
 c,_=s.accept(); threading.Thread(target=echo,args=(c,),daemon=True).start()
'''
    prefix = [] if name == "host" else ["nsenter", "-t", str(peers[name]), "-n"]
    proc = sp.Popen(prefix + [sys.executable, "-c", code, str(port)])
    children.append(proc)


def udp(name, address):
    code = "import socket,sys; s=socket.socket(socket.AF_INET6 if ':' in sys.argv[1] else socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(.5); s.sendto(b'hello',(sys.argv[1],53)); assert s.recv(5)==b'hello'"
    return peer(name, sys.executable, "-c", code, address, check=False).returncode == 0


def udp_server():
    code = "import socket; s=socket.socket(socket.AF_INET6,socket.SOCK_DGRAM); s.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,0); s.bind(('::',53))\nwhile True:\n d,a=s.recvfrom(4096); s.sendto(d,a)"
    children.append(sp.Popen([sys.executable, "-c", code]))


def denied_count():
    data = json.loads(run("nft", "-j", "list", "table", "bridge", "homelab_services").stdout)
    return sum(expr["counter"]["packets"] for item in data["nftables"]
               if "rule" in item and item["rule"]["chain"].startswith("deny_")
               for expr in item["rule"]["expr"] if "counter" in expr)


def send_frame(frame, name="a"):
    code = "import socket,sys; s=socket.socket(socket.AF_PACKET,socket.SOCK_RAW); s.bind(('eth0',0)); s.send(bytes.fromhex(sys.argv[1]))"
    peer(name, sys.executable, "-c", code, frame.hex())


def checksum(payload):
    if len(payload) % 2: payload += b"\0"
    total = sum(struct.unpack("!%dH" % (len(payload)//2), payload))
    while total >> 16: total = (total & 65535) + (total >> 16)
    return (~total) & 65535


def ipv6_frame(icmp, source="fd42:50::ff:fe00:2", fragment=False):
    src = socket.inet_pton(socket.AF_INET6, source)
    dst = socket.inet_pton(socket.AF_INET6, "ff02::1")
    pseudo = src + dst + struct.pack("!I3xB",len(icmp),58)
    icmp = icmp[:2] + struct.pack("!H", checksum(pseudo + icmp)) + icmp[4:]
    body = (struct.pack("!BBHI",58,0,0,123) if fragment else b"") + icmp
    header = struct.pack("!IHBB", 6 << 28, len(body), 44 if fragment else 58, 255) + src + dst
    return bytes.fromhex("33330000000102000000000286dd") + header + body


try:
    ip("link", "add", "br0", "type", "bridge", "vlan_filtering", "1", "vlan_default_pvid", "0")
    ip("link", "set", "br0", "up")
    for name, number in [("a", 2), ("b", 3), ("u", 4)]:
        proc = sp.Popen(["unshare", "-n", "sleep", "infinity"])
        children.append(proc)
        for _ in range(100):
            if os.readlink(f"/proc/{proc.pid}/ns/net") != os.readlink("/proc/self/ns/net"):
                break
            time.sleep(.01)
        peers[name] = proc.pid
        ip("link", "add", "p" + name, "type", "veth", "peer", "name", "eth0", "netns", str(proc.pid))
        ip("link", "set", "p" + name, "master", "br0")
        run("bridge", "vlan", "add", "dev", "p" + name, "vid", "50", "pvid", "untagged")
        ip("link", "set", "p" + name, "up")
        peer(name, "ip", "link", "set", "lo", "up")
        peer(name, "ip", "link", "set", "eth0", "address", f"02:00:00:00:00:0{number}")
        peer(name, "ip", "link", "set", "eth0", "up")
        peer(name, "ip", "addr", "add", f"10.50.0.{number}/24", "dev", "eth0")
        peer(name, "ip", "-6", "addr", "add", f"fd42:50::ff:fe00:{number}/64", "dev", "eth0", "nodad")
    run("bridge", "vlan", "add", "dev", "br0", "vid", "50", "self")
    ip("link", "add", "link", "br0", "name", "br0.50", "type", "vlan", "id", "50")
    ip("link", "set", "br0.50", "address", "02:00:00:00:00:01")
    ip("link", "set", "br0.50", "up")
    ip("addr", "add", "10.50.0.1/24", "dev", "br0.50")
    ip("-6", "addr", "add", "fd42:50::1/64", "dev", "br0.50", "nodad")
    install(rules)
    if os.environ.get("FIREWALL_TRACE"):
        run("nft", "-f", "-", input='table bridge debug { chain pre { type filter hook prerouting priority -400; meta nftrace set 1; }; chain out { type filter hook output priority -400; meta nftrace set 1; }; }')
        children.append(sp.Popen(["nft", "monitor", "trace"], stdout=open("/tmp/firewall-trace.log", "w")))
    udp_server()
    server("host", 8080)
    server("a", 8080)
    server("b", 8080)
    server("b", 8081)
    time.sleep(.2)
    assert connect("a", "10.50.0.3"), "allowed IPv4 + replies"
    assert connect("a", "fd42:50::ff:fe00:3"), "allowed IPv6 + ND + replies"
    assert not connect("a", "10.50.0.3", 8081), "unlisted port"
    assert not connect("b", "10.50.0.2"), "unsolicited reverse connection"
    assert not connect("u", "10.50.0.3"), "unlisted incoming source"
    print("PASS: dual-stack same-VLAN grants, replies, port/source denial, reverse denial", flush=True)

    assert connect("a", "10.50.0.1"), "container -> host"
    assert connect("a", "fd42:50::1"), "IPv6 container -> host"
    assert connect("host", "10.50.0.2"), "host -> container"
    assert connect("host", "fd42:50::ff:fe00:2"), "IPv6 host -> container"
    assert not connect("host", "10.50.0.3"), "unlisted host ingress"
    assert udp("a", "10.50.0.1"), "allowed UDP + reply"
    assert udp("a", "fd42:50::1"), "allowed IPv6 UDP + reply"
    assert not udp("b", "10.50.0.1"), "unlisted UDP egress"
    print("PASS: dual-stack host/container input and output hooks, UDP grants/replies", flush=True)

    # MAC and source address impersonation must fail despite valid destination grant.
    peer("a", "ip", "link", "set", "eth0", "address", "02:00:00:00:00:09")
    assert not connect("a", "10.50.0.3"), "MAC spoof"
    peer("a", "ip", "link", "set", "eth0", "address", "02:00:00:00:00:02")
    peer("a", "ip", "addr", "del", "10.50.0.2/24", "dev", "eth0")
    peer("a", "ip", "addr", "add", "10.50.0.9/24", "dev", "eth0")
    assert not connect("a", "10.50.0.3"), "IPv4 spoof"
    peer("a", "ip", "addr", "del", "10.50.0.9/24", "dev", "eth0")
    peer("a", "ip", "addr", "add", "10.50.0.2/24", "dev", "eth0")
    print("PASS: source MAC and IPv4 validation", flush=True)

    # A known off-mode container must not impersonate an enforced service.
    peer("u", "ip", "addr", "del", "10.50.0.4/24", "dev", "eth0")
    peer("u", "ip", "addr", "add", "10.50.0.2/24", "dev", "eth0")
    before = denied_count()
    assert not connect("u", "10.50.0.3"), "off-mode peer impersonation"
    assert denied_count() > before
    peer("u", "ip", "addr", "del", "10.50.0.2/24", "dev", "eth0")
    peer("u", "ip", "addr", "add", "10.50.0.4/24", "dev", "eth0")
    print("PASS: off-mode local peer cannot impersonate a managed identity", flush=True)

    # A valid source IP/MAC must not authorize forged neighbour targets/options.
    target_b = socket.inet_pton(socket.AF_INET6, "fd42:50::ff:fe00:3")
    target_a = socket.inet_pton(socket.AF_INET6, "fd42:50::ff:fe00:2")
    own_option = bytes.fromhex("0201020000000002")
    bad_option = bytes.fromhex("0201020000000009")
    packets = {
        "forged NA target": ipv6_frame(struct.pack("!BBHI",136,0,0,0x20000000) + target_b + own_option),
        "forged NA option": ipv6_frame(struct.pack("!BBHI",136,0,0,0x20000000) + target_a + bad_option),
        "rogue RA": ipv6_frame(struct.pack("!BBHBBHII",134,0,0,64,0,1800,0,0), source="fe80::ff:fe00:2"),
        "fragmented ND": ipv6_frame(struct.pack("!BBHI",136,0,0,0x20000000) + target_a + own_option, fragment=True),
        "forged ARP": bytes.fromhex("ffffffffffff0200000000020806") + struct.pack("!HHBBH",1,0x800,6,4,2)
             + bytes.fromhex("020000000002") + socket.inet_aton("10.50.0.3") + bytes(6) + socket.inet_aton("10.50.0.4"),
    }
    for label, packet in packets.items():
        before = denied_count()
        send_frame(packet)
        time.sleep(.05)
        assert denied_count() > before, label
    off_na = ipv6_frame(struct.pack("!BBHI",136,0,0,0x20000000) + target_a + bytes.fromhex("0201020000000004"), source="fd42:50::ff:fe00:4")
    off_na = off_na[:6] + bytes.fromhex("020000000004") + off_na[12:]
    before = denied_count()
    send_frame(off_na, "u")
    time.sleep(.05)
    assert denied_count() > before, "off-mode forged neighbour target"
    off_ra = ipv6_frame(struct.pack("!BBHBBHII",134,0,0,64,0,1800,0,0), source="fe80::1")
    off_ra = off_ra[:6] + bytes.fromhex("020000000001") + off_ra[12:]
    before = denied_count()
    send_frame(off_ra, "u")
    time.sleep(.05)
    assert denied_count() > before, "off-mode router impersonation"
    print("PASS: forged ARP/NA, rogue RA, fragmented ND", flush=True)

    # Hold a connection across removal of B ingress; A egress remains allowed.
    code = '''import socket,sys
s=socket.create_connection(('10.50.0.3',8080),2); s.sendall(b'hello'); assert s.recv(5)==b'hello'
print('ready',flush=True); sys.stdin.readline(); s.settimeout(.8)
try:
 s.sendall(b'again'); result=s.recv(5); sys.exit(1 if result==b'again' else 0)
except (TimeoutError,OSError): sys.exit(0)
'''
    session = sp.Popen(["nsenter", "-t", str(peers["a"]), "-n", sys.executable, "-c", code], stdin=sp.PIPE, stdout=sp.PIPE, text=True)
    children.append(session)
    assert session.stdout.readline().strip() == "ready"
    install(revoked)
    session.communicate("go\n", timeout=5)
    assert session.returncode == 0, "existing session revocation"
    assert not connect("a", "10.50.0.3"), "A allow must not bypass B deny"
    print("PASS: two-sided policy and established session revocation", flush=True)

    before = run("nft", "-j", "list", "table", "bridge", "homelab_services").stdout
    failed = run("nft", "-f", "-", input="delete table bridge homelab_services\ntable bridge homelab_services { broken nonsense }", check=False)
    assert failed.returncode != 0
    after = run("nft", "-j", "list", "table", "bridge", "homelab_services").stdout
    def without_counts(value):
        if isinstance(value, list):
            return [without_counts(item) for item in value]
        if isinstance(value, dict):
            return {key: ({} if key == "counter" else without_counts(item)) for key, item in value.items()}
        return value
    assert without_counts(json.loads(before)) == without_counts(json.loads(after)), "failed transaction changed rules"
    assert not connect("a", "10.50.0.3")
    install(audit)
    assert connect("a", "10.50.0.3"), "audit blocked traffic"
    install(revoked)
    assert not connect("a", "10.50.0.3"), "audit->enforce leaked traffic"
    print("PASS: failed transaction, audit and enforce transition", flush=True)
finally:
    for child in reversed(children):
        child.terminate()
    for child in reversed(children):
        try:
            child.wait(timeout=2)
        except sp.TimeoutExpired:
            child.kill()
