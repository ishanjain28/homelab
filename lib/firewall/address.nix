{ lib }:
let
  fail = message: throw "homelab firewall: ${message}";
  hex = value: lib.toLower (lib.toHexString value);
  number =
    base: value:
    let
      chars = lib.stringToCharacters (lib.toLower value);
      digits = lib.stringToCharacters "0123456789abcdef";
      digit = c: lib.lists.findFirstIndex (x: x == c) (-1) digits;
    in
    if chars == [ ] || lib.any (c: digit c < 0 || digit c >= base) chars then
      fail "invalid number '${value}'"
    else
      lib.foldl' (acc: c: acc * base + digit c) 0 chars;
  ipv4 =
    value:
    let
      parts = lib.splitString "." value;
      nums = map (number 10) parts;
    in
    if builtins.length parts != 4 || lib.any (n: n > 255) nums then fail "invalid IPv4 '${value}'" else nums;
  ipv6 =
    value:
    let
      halves = lib.splitString "::" value;
      words = part: if part == "" then [ ] else lib.splitString ":" part;
      left = words (builtins.head halves);
      right = if builtins.length halves == 2 then words (builtins.elemAt halves 1) else [ ];
      missing = 8 - builtins.length left - builtins.length right;
      expanded = if builtins.length halves == 1 then left else left ++ lib.replicate (lib.max 0 missing) "0" ++ right;
      nums = map (number 16) expanded;
    in
    if
      builtins.length halves > 2
      || builtins.length expanded != 8
      || (builtins.length halves == 2 && missing < 1)
      || lib.any (w: builtins.stringLength w > 4) expanded
    then
      fail "invalid IPv6 '${value}'"
    else
      nums;
  render6 = nums: lib.concatMapStringsSep ":" hex nums;
  splitPrefix =
    value:
    let
      parts = lib.splitString "/" value;
    in
    if builtins.length parts != 2 then
      fail "expected CIDR '${value}'"
    else
      {
        address = builtins.head parts;
        length = number 10 (builtins.elemAt parts 1);
      };
  cidr =
    value:
    let
      p = splitPrefix value;
      v6 = lib.hasInfix ":" p.address;
      nums = if v6 then ipv6 p.address else ipv4 p.address;
    in
    if p.length > (if v6 then 128 else 32) then fail "invalid prefix '${value}'" else builtins.deepSeq nums value;
  contains4 =
    prefix: address:
    let
      p = splitPrefix prefix;
      int = nums: lib.foldl' (a: b: a * 256 + b) 0 nums;
      divisor = lib.foldl' (a: _: a * 2) 1 (lib.range 1 (32 - p.length));
    in
    builtins.deepSeq (cidr prefix) (
      builtins.div (int (ipv4 address)) divisor == builtins.div (int (ipv4 p.address)) divisor
    );
  eui64 =
    mac:
    let
      octets = lib.splitString ":" (lib.toLower mac);
      nums = map (number 16) octets;
      first = builtins.bitXor (builtins.head nums) 2;
      byte = n: lib.fixedWidthString 2 "0" (hex n);
      bytes = [ (byte first) ] ++ builtins.tail octets;
    in
    if builtins.length octets != 6 || lib.any (x: builtins.stringLength x != 2) octets then
      fail "invalid MAC '${mac}'"
    else
      builtins.deepSeq nums [
        (number 16 "${builtins.elemAt bytes 0}${builtins.elemAt bytes 1}")
        (number 16 "${builtins.elemAt bytes 2}ff")
        (number 16 "fe${builtins.elemAt bytes 3}")
        (number 16 "${builtins.elemAt bytes 4}${builtins.elemAt bytes 5}")
      ];
  fromMac =
    prefix: mac:
    let
      p = splitPrefix prefix;
      nums = ipv6 p.address;
    in
    if p.length != 64 || lib.any (n: n != 0) (lib.drop 4 nums) then
      fail "EUI-64 requires a network-aligned /64: '${prefix}'"
    else
      render6 (lib.take 4 nums ++ eui64 mac);
in
{
  inherit
    fail
    ipv4
    ipv6
    cidr
    contains4
    fromMac
    render6
    eui64
    ;
  linkLocal =
    mac:
    render6 (
      [
        65152
        0
        0
        0
      ]
      ++ eui64 mac
    );
  host =
    value:
    if lib.hasInfix ":" value then
      "${render6 (ipv6 value)}/128"
    else
      "${lib.concatMapStringsSep "." toString (ipv4 value)}/32";
}
