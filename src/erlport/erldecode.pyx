# Copyright (c) 2009, 2010, Dmitry Vasiliev <dima@hlabs.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the name of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.


from erlterms import Atom, BitBinary
from struct import unpack
from array import array
from zlib import decompressobj


def decode_small_int(tag, string, pos):
    if not (len(string) - pos):
        raise ValueError("incomplete data: %r" % string)
    return ord(string[pos]), pos + 1


def decode_int(tag, string, pos):
    if len(string) - pos < 4:
        raise ValueError("incomplete data: %r" % string)
    i, = unpack(">i", string[pos:4 + pos])
    return i, pos + 4


def decode_nil(tag, string, pos):
    return [], pos


def decode_string(tag, string, pos):
    if len(string) - pos < 2:
        raise ValueError("incomplete data: %r" % string)
    length, = unpack(">H", string[pos:pos+2])
    pos += 2
    if len(string) - pos < length:
        raise ValueError("incomplete data: %r" % string)
    return [ord(i) for i in string[pos:pos+length]], pos + length


def decode_list(tag, string, pos):
    if len(string) - pos < 4:
        raise ValueError("incomplete data: %r" % string)
    length, = unpack(">I", string[pos:pos + 4])
    pos += 4
    lst = []
    while length > 0:
        term, pos = decode_term(string, pos)
        lst.append(term)
        length -= 1
    ignored, pos = decode_term(string, pos)
    return lst, pos

def decode_maps(tag, maps, pos):
    if len(maps) - pos < 4:
        raise ValueError("incomplete data: %r" % maps)
    length, = unpack(">I", maps[pos:pos + 4])
    pos += 4
    d = {}
    while length > 0:
        key, pos = decode_term(maps, pos)
        value, pos = decode_term(maps, pos)
        d[key] = value
        length -= 1
    return d, pos

def decode_binary(tag, string, pos):
    if len(string) - pos < 4:
        raise ValueError("incomplete data: %r" % string)
    length, = unpack(">I", string[pos:pos + 4])
    pos += 4
    if len(string) - pos < length:
        raise ValueError("incomplete data: %r" % string)
    return string[pos:pos+length], pos + length


def decode_atom(tag, string, pos):
    if len(string) - pos < 2:
        raise ValueError("incomplete data: %r" % string)
    length, = unpack(">H", string[pos:pos+2])
    pos += 2
    if len(string) - pos < length:
        raise ValueError("incomplete data: %r" % string)
    name = string[pos:pos+length]
    pos += length
    if name == "true":
        return True, pos
    elif name == "false":
        return False, pos
    elif name == "none":
        return None, pos
    return Atom(name), pos


def decode_tuple(tag, string, pos):
    if tag == 104:
        if not (len(string) - pos):
            raise ValueError("incomplete data: %r" % string)
        arity = ord(string[pos])
        pos += 1
    else:
        if len(string) - pos < 4:
            raise ValueError("incomplete data: %r" % string)
        arity, = unpack(">I", string[pos:pos + 4])
        pos += 4
    lst = []
    while arity > 0:
        term, pos = decode_term(string, pos)
        lst.append(term)
        arity -= 1
    return tuple(lst), pos


def decode_new_float(tag, string, pos):
    term, = unpack(">d", string[pos:pos+8])
    return term, pos + 8


def decode_float(tag, string, pos):
    return float(string[pos:pos+31].split("\x00", 1)[0]), pos + 31


def decode_big(tag, string, pos):
    if tag == 110:
        if len(string) - pos < 2:
            raise ValueError("incomplete data: %r" % string)
        length, sign = unpack(">BB", string[pos:pos+2])
        pos += 2
    else:
        if len(string) - pos < 5:
            raise ValueError("incomplete data: %r" % string)
        length, sign = unpack(">IB", string[pos:pos+5])
        pos += 5
    if len(string) - pos < length:
        raise ValueError("incomplete data: %r" % string)
    n = 0
    for i in array('B', string[pos+length-1:pos-1:-1]):
        n = (n << 8) | i
    if sign:
        n = -n
    return n, pos + length


def decode_bit_binary(tag, string, pos):
    if len(string) - pos < 5:
        raise ValueError("incomplete data: %r" % string)
    length, bits = unpack(">IB", string[pos:pos+5])
    pos += 5
    if len(string) - pos < length:
        raise ValueError("incomplete daata: %r" % string)
    return BitBinary(string[pos:pos+length], bits), pos + length


DECODE_MAP = {
    97:  decode_small_int,
    98:  decode_int,
    106: decode_nil,
    107: decode_string,
    108: decode_list,
    116: decode_maps,
    109: decode_binary,
    100: decode_atom,
    104: decode_tuple,
    105: decode_tuple,
    70:  decode_new_float,
    99:  decode_float,
    110: decode_big,
    111: decode_big,
    77:  decode_bit_binary
}


def decode(string):
    """Decode Erlang external term."""
    if len(string) < 1:
        raise ValueError("incomplete data: %r" % string)
    version = ord(string[0])
    if version != 131:
        raise ValueError("unknown protocol version: %i" % version)
    if string[1:2] == '\x50':
        # compressed term
        if len(string) < 6:
            raise ValueError("incomplete data: %r" % string)
        d = decompressobj()
        zlib_data = string[6:]
        term_string = d.decompress(zlib_data) + d.flush()
        uncompressed_size = unpack('>I', string[2:6])[0]
        if len(term_string) != uncompressed_size:
            raise ValueError(
                "invalid compressed tag, "
                "%d bytes but got %d" % (uncompressed_size, len(term_string)))
        return decode_term(term_string, 0)[0]
    return decode_term(string[1:], 0)[0]


def decode_term(string, pos):
    if len(string) - pos < 1:
        raise ValueError("incomplete data: %r" % string)
    tag = ord(string[pos])
    pos += 1
    fun = DECODE_MAP[tag]
    if not fun:
        raise ValueError("unsupported data tag: %i" % tag)
    return fun(tag, string, pos)
