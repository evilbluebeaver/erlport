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


from erlterms import Atom, BitBinary, Binary
from struct import pack
from zlib import compress
from array import array
from datetime import datetime


def encode_tuple(term):
    arity = len(term)
    if arity <= 255:
        header = 'h%c' % arity
    elif arity <= 4294967295:
        header = pack(">BI", 105, arity)
    else:
        raise ValueError("Too large tuple arity")
    _encode_term = encode_term
    return header + "".join(_encode_term(t) for t in term)


def encode_list(term):
    if not term:
        return "j"
    length = len(term)
    if length <= 65535:
        try:
            # array coersion will allow floats as a deprecated feature
            for t in term:
                if not isinstance(t, (int, long)):
                    raise TypeError
            bytes = array('B', term).tostring()
        except(TypeError, OverflowError):
            pass
        else:
            if len(bytes) == length:
                return pack(">BH", 107, length) + bytes
    elif length > 4294967295:
        raise ValueError("Too large list lenght")
    header = pack(">BI", 108, length)
    _encode_term = encode_term
    return header + "".join(_encode_term(t) for t in term) + "j"


def encode_atom(term):
    return pack(">BH", 100, len(term)) + term


def encode_bit_binary(term):
    return pack(">BIB", 77, len(term), term.bits) + term


def encode_str(term):
    length = len(term)
    if length > 65535:
        raise ValueError("Too large string length. Use an unicode instead of an usual string")
    return pack(">BH", 107, length) + term


def encode_binary(term):
    length = len(term)
    if length > 4294967295:
        raise ValueError("Too large unicode string length")
    return pack(">BI", 109, length) + term

def encode_unicode(term):
    encoded = term.encode("utf-8")
    length = len(encoded)
    if length > 4294967295:
        raise ValueError("Too large unicode string length")
    return pack(">BI", 109, length) + encoded


def encode_bool(term):
    term = term and 'true' or 'false'
    return pack(">BH", 100, len(term)) + term


def encode_int(term):
    if 0 <= term <= 255:
        return 'a%c' % term
    elif -2147483648 <= term <= 2147483647:
        return pack(">Bi", 98, term)

    if term >= 0:
        sign = 0
    else:
        sign = 1
        term = -term

    bytes = array('B')
    while term > 0:
        bytes.append(term & 0xff)
        term >>= 8

    length = len(bytes)
    if length <= 255:
        return pack(">BBB", 110, length, sign) + bytes.tostring()
    elif length <= 4294967295:
        return pack(">BIB", 111, length, sign) + bytes.tostring()
    raise ValueError("Too large integer number")


def encode_float(term):
    return pack(">Bd", 70, term)


def encode_dict(term):
    length = len(term)
    header = pack(">BI", 116, length)
    lst = [encode_term(k) + encode_term(v) for k, v in term.items()]
    return header + "".join(lst)


def encode_none(term):
    term = 'undefined'
    return pack(">BH", 100, len(term)) + term


def encode_datetime(term):
    return encode_term(((term.year, term.month, term.day),
                        (term.hour, term.minute, term.second)))


ENCODE_MAP = {
    tuple:      encode_tuple,
    list:       encode_list,
    unicode:    encode_unicode,
    Binary:     encode_binary,
    Atom:       encode_atom,
    BitBinary:  encode_bit_binary,
    str:        encode_str,
    bool:       encode_bool,
    int:        encode_int,
    long:       encode_int,
    float:      encode_float,
    dict:       encode_dict,
    type(None): encode_none,
    datetime:   encode_datetime
    }


def encode(term, compressed=False):
    """Encode Erlang external term."""
    encoded_term = encode_term(term)
    # False and 0 do not attempt compression.
    if compressed:
        if compressed is True:
            # default compression level of 6
            compressed = 6
        zlib_term = compress(encoded_term, compressed)
        if len(zlib_term) + 5 <= len(encoded_term):
            # compressed term is smaller
            return '\x83\x50' + pack('>I', len(encoded_term)) + zlib_term
    return "\x83" + encoded_term


def encode_term(term):
    fun = ENCODE_MAP[type(term)]
    if not fun:
        raise ValueError("Unsupported data type: %s" % type(term))
    return fun(term)
