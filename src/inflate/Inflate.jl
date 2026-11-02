# DEFLATE (RFC 1951) / gzip (RFC 1952) decoder. Decoding one stream is a serial chain of
# dependent table lookups that leaves a wide core mostly idle, so `gzip_decompress!` can
# decode several independent members in lockstep to overlap their chains.
# Table layout and fast-loop structure follow libdeflate.
module Inflate

using libdeflate_jll: libdeflate

export InflateError, gzip_decompress!

struct InflateError <: Exception
    msg::String
end
Base.showerror(io::IO, e::InflateError) = print(io, "InflateError: ", e.msg)
@noinline bad(msg::String) = throw(InflateError(msg))

# Table entry (UInt32):
#   bits 0-4   bits to consume: codeword + extra bits (subtable pointer: main-table bits)
#   bits 8-11  codeword length (subtable pointer: subtable bits)
#   bit 12 INVALID, 13 SUBTABLE, 14 EXCEPTIONAL (subtable pointer, end of block, invalid), 15 LITERAL
#   bits 16-31 literal byte, length/offset base, precode symbol, or subtable start
const INVALID = UInt32(1) << 12
const SUBTABLE = UInt32(1) << 13
const EXCEPTIONAL = UInt32(1) << 14
const LITERAL = UInt32(1) << 15

const LITLEN_TABLEBITS = 11
const OFFSET_TABLEBITS = 8
const PRECODE_TABLEBITS = 7
# Worst-case main table + subtables for complete codes (zlib's `enough 288 11 15`, `enough 32 8 15`).
const LITLEN_ENOUGH = 2342
const OFFSET_ENOUGH = 402
const PRECODE_ENOUGH = 1 << PRECODE_TABLEBITS

const LENGTH_BASE = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
const LENGTH_EXTRA = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0)
const OFFSET_BASE = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577)
const OFFSET_EXTRA = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13)
const PRECODE_ORDER = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15)

# Per-symbol entries before codeword lengths are added; bits 0-4 hold the extra-bit count.
const LITLEN_RESULTS = UInt32[
    (UInt32(s) << 16 | LITERAL for s in 0:255)...,
    EXCEPTIONAL,  # end of block
    (UInt32(LENGTH_BASE[i]) << 16 | UInt32(LENGTH_EXTRA[i]) for i in 1:29)...,
    EXCEPTIONAL | INVALID, EXCEPTIONAL | INVALID,
]
const OFFSET_RESULTS = UInt32[
    (UInt32(OFFSET_BASE[i]) << 16 | UInt32(OFFSET_EXTRA[i]) for i in 1:30)...,
    EXCEPTIONAL | INVALID, EXCEPTIONAL | INVALID,
]
const PRECODE_RESULTS = UInt32[UInt32(s) << 16 for s in 0:18]

const HEADER, HUFFMAN, DONE = 0, 1, 2

mutable struct Stream
    bitbuf::UInt64      # bits above `bitsleft` are zero or the next input bytes
    bitsleft::UInt64
    inp::Ptr{UInt8}
    out::Ptr{UInt8}
    in_end::Ptr{UInt8}
    out_start::Ptr{UInt8}
    out_end::Ptr{UInt8}
    overread::Int       # zero bytes fed past `in_end`
    state::Int
    final::Bool
    lit::Ptr{UInt32}
    off::Ptr{UInt32}
    littab::Vector{UInt32}
    offtab::Vector{UInt32}
    pretab::Vector{UInt32}
    lens::Vector{UInt8}
    counts::Vector{Int}
    offs::Vector{Int}
    lencount::Vector{Int}
    sorted::Vector{UInt16}
end

Stream() = Stream(
    0, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, 0, HEADER, false, C_NULL, C_NULL,
    Vector{UInt32}(undef, LITLEN_ENOUGH), Vector{UInt32}(undef, OFFSET_ENOUGH),
    Vector{UInt32}(undef, PRECODE_ENOUGH), Vector{UInt8}(undef, 288 + 32),
    Vector{Int}(undef, 64), Vector{Int}(undef, 64), Vector{Int}(undef, 15), Vector{UInt16}(undef, 288),
)

function reset!(s::Stream, out::Ptr{UInt8}, outlen::Int, inp::Ptr{UInt8}, inlen::Int)
    s.bitbuf = 0
    s.bitsleft = 0
    s.inp = inp
    s.in_end = inp + inlen
    s.out = s.out_start = out
    s.out_end = out + outlen
    s.overread = 0
    s.state = HEADER
    s.final = false
    return s
end

# Bit-reversed increment of a codeword
@inline function next_codeword(codeword::Int, all_ones::Int)
    bit = 1 << (63 - leading_zeros(codeword ⊻ all_ones))
    return (codeword & (bit - 1)) | bit
end

# Canonical Huffman decode table for `lens[lo+1:lo+nsyms]`; false if the code is invalid.
# Incomplete codes are accepted (as zlib does) only with zero codewords or a single 1-bit one.
# Follows libdeflate's build_decode_table: each codeword is written once and the table is
# replicated by doubling; counting and sorting run over 4 interleaved symbol ranges because
# runs of equal lengths otherwise serialize on one counter's store-to-load forwarding.
function build_table!(s::Stream, table::Vector{UInt32}, lo::Int, nsyms::Int, results::Vector{UInt32}, tb::Int, allow_incomplete::Bool)
    lens, counts, offs, lencount, sorted = s.lens, s.counts, s.offs, s.lencount, s.sorted
    q = nsyms >> 2
    @inbounds begin
        fill!(counts, 0)  # counts[4len + part], part 1:4 covers symbols ((part-1)q, part*q] (last takes the rest)
        for k in 1:q
            counts[4lens[lo + k] + 1] += 1
            counts[4lens[lo + q + k] + 2] += 1
            counts[4lens[lo + 2q + k] + 3] += 1
            counts[4lens[lo + 3q + k] + 4] += 1
        end
        for k in (4q + 1):nsyms
            counts[4lens[lo + k] + 4] += 1
        end
        left = 1
        o = 0
        for l in 1:15
            c = counts[4l + 1] + counts[4l + 2] + counts[4l + 3] + counts[4l + 4]
            lencount[l] = c
            left = 2left - c
            left < 0 && return false
            for part in 1:4
                offs[4l + part] = o
                o += counts[4l + part]
            end
        end
        ncodes = o
        for part in 1:4  # unused symbols sort after the codewords, so the sort needs no branch
            offs[part] = o
            o += counts[part]
        end
        if left > 0
            (allow_incomplete && (ncodes == 0 || (ncodes == 1 && lencount[1] == 1))) || return false
            fill!(view(table, 1:(1 << tb)), EXCEPTIONAL | INVALID)
            if ncodes == 1
                sym = 0
                while lens[lo + sym + 1] == 0
                    sym += 1
                end
                e = results[sym + 1] + UInt32(1) + (UInt32(1) << 8)
                for i in 0:2:((1 << tb) - 1)
                    table[i + 1] = e
                end
            end
            return true
        end
        for k in 1:q
            sorted[offs[4lens[lo + k] + 1] += 1] = k - 1
            sorted[offs[4lens[lo + q + k] + 2] += 1] = q + k - 1
            sorted[offs[4lens[lo + 2q + k] + 3] += 1] = 2q + k - 1
            sorted[offs[4lens[lo + 3q + k] + 4] += 1] = 3q + k - 1
        end
        for k in (4q + 1):nsyms
            sorted[offs[4lens[lo + k] + 4] += 1] = k - 1
        end

        # Codewords are bit-reversed, so a length-`len` codeword's entries repeat every 2^len
        # slots: write it once in the first 2^len, then double the table at each new length.
        len = 1
        while lencount[len] == 0
            len += 1
        end
        cur_end = 1 << len
        remaining = lencount[len]
        codeword = 0
        k = 1
        while len <= tb
            while true
                table[codeword + 1] = results[sorted[k] + 1] + UInt32(len) + (UInt32(len) << 8)
                k += 1
                if codeword == cur_end - 1  # all ones: the last codeword
                    while len < tb
                        unsafe_copyto!(table, cur_end + 1, table, 1, cur_end)
                        cur_end <<= 1
                        len += 1
                    end
                    return true
                end
                codeword = next_codeword(codeword, cur_end - 1)
                (remaining -= 1) == 0 && break
            end
            while true
                len += 1
                if len <= tb
                    unsafe_copyto!(table, cur_end + 1, table, 1, cur_end)
                    cur_end <<= 1
                end
                (remaining = lencount[len]) == 0 || break
            end
        end

        # Longer codewords go to subtables, one per distinct `tb`-bit prefix.
        mask = (1 << tb) - 1
        prefix = -1
        sub_start = 0
        while true
            if codeword & mask != prefix
                prefix = codeword & mask
                sub_start = cur_end
                sub_bits = len - tb
                used = remaining
                while used < (1 << sub_bits)
                    sub_bits += 1
                    used = (used << 1) + lencount[tb + sub_bits]
                end
                cur_end = sub_start + (1 << sub_bits)
                cur_end > length(table) && return false
                table[prefix + 1] = UInt32(sub_start) << 16 | EXCEPTIONAL | SUBTABLE | UInt32(sub_bits) << 8 | UInt32(tb)
            end
            rl = len - tb
            e = results[sorted[k] + 1] + UInt32(rl) + (UInt32(rl) << 8)
            k += 1
            i = sub_start + (codeword >> tb)
            while i < cur_end
                table[i + 1] = e
                i += 1 << rl
            end
            codeword == (1 << len) - 1 && return true
            codeword = next_codeword(codeword, (1 << len) - 1)
            remaining -= 1
            while remaining == 0
                len += 1
                remaining = lencount[len]
            end
        end
    end
end

function fixed_tables()
    s = Stream()
    s.lens[1:288] .= [fill(0x08, 144); fill(0x09, 112); fill(0x07, 24); fill(0x08, 8)]
    s.lens[289:320] .= 0x05
    build_table!(s, s.littab, 0, 288, LITLEN_RESULTS, LITLEN_TABLEBITS, false) || error("fixed litlen")
    build_table!(s, s.offtab, 288, 32, OFFSET_RESULTS, OFFSET_TABLEBITS, false) || error("fixed offset")
    return s.littab, s.offtab
end
const FIXED_LIT, FIXED_OFF = fixed_tables()

@inline tload(t::Ptr{UInt32}, i::UInt64) = unsafe_load(t + (i << 2))
@inline lowbits(x::UInt64, n::UInt64) = x & ((UInt64(1) << (n & 63)) - 1)

# Hot-loop registers, kept out of the mutable `Stream` so they live in registers.
struct Regs
    bitbuf::UInt64
    bitsleft::UInt64
    inp::Ptr{UInt8}
    out::Ptr{UInt8}
end
@inline regs(s::Stream) = Regs(s.bitbuf, s.bitsleft, s.inp, s.out)
@inline function store!(s::Stream, r::Regs)
    s.bitbuf, s.bitsleft, s.inp, s.out = r.bitbuf, r.bitsleft, r.inp, r.out
    return s
end
@inline consume(r::Regs, n::UInt64) = Regs(r.bitbuf >> (n & 63), r.bitsleft - n, r.inp, r.out)
# Entry bits 5-7 are zero, so the shift needs no mask beyond the one `lsr`/`shr` apply anyway.
@inline consume(r::Regs, e::UInt32) = Regs(r.bitbuf >> (UInt64(e) & 63), r.bitsleft - UInt64(e & 0x1f), r.inp, r.out)

# Branchless refill to 56-63 bits; needs 8 readable bytes at `inp`.
@inline function refill_fast(r::Regs)
    w = ltoh(unsafe_load(Ptr{UInt64}(r.inp)))
    return Regs(r.bitbuf | (w << (r.bitsleft & 63)), r.bitsleft | 56, r.inp + ((63 - r.bitsleft) >> 3), r.out)
end

function refill_slow(r::Regs, s::Stream)
    bb, bl, inp = r.bitbuf, r.bitsleft, r.inp
    while bl < 56
        if inp < s.in_end
            bb |= UInt64(unsafe_load(inp)) << bl
            inp += 1
        else
            # A valid stream never looks more than a bitbuffer past its end.
            (s.overread += 1) > 8 && bad("truncated deflate stream")
        end
        bl += 8
    end
    return Regs(bb, bl, inp, r.out)
end

@inline refill(r::Regs, s::Stream) = s.in_end - r.inp >= 8 ? refill_fast(r) : refill_slow(r, s)

# Per iteration the fast loop refills twice (≤ 7 bytes each, 8-byte loads) and writes
# ≤ 3 literals + a 258-byte match with ≤ 15 bytes of word-copy overrun.
const IN_MARGIN = 16
const OUT_MARGIN = 3 + 258 + 16

@inline fast_ok(r::Regs, s::Stream) = s.in_end - r.inp >= IN_MARGIN && s.out_end - r.out >= OUT_MARGIN

const OK, EOB, BAD = 0, 1, 2

@inline function put_literal(r::Regs, e::UInt32)
    r = consume(r, e)
    unsafe_store!(r.out, (e >> 16) % UInt8)
    return Regs(r.bitbuf, r.bitsleft, r.inp, r.out + 1)
end

# Copy a `len`-byte match from `dist` back; may write up to 15 bytes past the end.
@inline function copy_match(out::Ptr{UInt8}, dist::UInt64, len::UInt64)
    src = out - dist
    stop = out + len
    if dist >= 8
        unsafe_store!(Ptr{UInt64}(out), unsafe_load(Ptr{UInt64}(src)))
        unsafe_store!(Ptr{UInt64}(out + 8), unsafe_load(Ptr{UInt64}(src + 8)))
        out += 16
        src += 16
        while out < stop
            unsafe_store!(Ptr{UInt64}(out), unsafe_load(Ptr{UInt64}(src)))
            out += 8
            src += 8
        end
    elseif dist == 1
        v = UInt64(unsafe_load(src)) * 0x0101010101010101
        unsafe_store!(Ptr{UInt64}(out), v)
        unsafe_store!(Ptr{UInt64}(out + 8), v)
        out += 16
        while out < stop
            unsafe_store!(Ptr{UInt64}(out), v)
            out += 8
        end
    else
        # Each 8-byte copy is correct in its first `dist` bytes; the next overwrites the rest.
        while out < stop
            unsafe_store!(Ptr{UInt64}(out), unsafe_load(Ptr{UInt64}(src)))
            out += dist
            src += dist
        end
    end
    return
end

@inline litentry(lit::Ptr{UInt32}, r::Regs) = tload(lit, r.bitbuf & ((1 << LITLEN_TABLEBITS) - 1))
@inline offentry(off::Ptr{UInt32}, r::Regs) = tload(off, r.bitbuf & ((1 << OFFSET_TABLEBITS) - 1))

# Consume subtable pointer `e` and look up the rest of the codeword.
@inline function enter_subtable(t::Ptr{UInt32}, r::Regs, e::UInt32)
    r = consume(r, e)
    return r, tload(t, UInt64(e >> 16) + lowbits(r.bitbuf, UInt64((e >> 8) & 0xf)))
end

# Consume length/offset entry `e`; its value is the base plus the extra bits above the codeword.
@inline function take_value(r::Regs, e::UInt32)
    extra = lowbits(r.bitbuf, UInt64(e & 0x1f)) >> ((e >> 8) & 0xf)
    return consume(r, e), UInt64(e >> 16) + extra
end

# One fast-loop step: ≤ 3 literals or one match. Entries are looked up before the refill
# they follow, taking it off the dependency chain: a fast refill leaves 64 real bits in
# `bitbuf` (those above `bitsleft` are the next input bytes) and a step consumes ≤ 42 bits
# between refills (2 literals + subtable + length extra bits), so every lookup sees real bits.
@inline function fast_step(r::Regs, e::UInt32, lit::Ptr{UInt32}, off::Ptr{UInt32}, out_start::Ptr{UInt8})
    r = refill_fast(r)
    if e & LITERAL != 0
        r = put_literal(r, e)
        e = litentry(lit, r)
        if e & LITERAL != 0
            r = put_literal(r, e)
            e = litentry(lit, r)
            if e & LITERAL != 0
                r = put_literal(r, e)
                return r, litentry(lit, r), OK
            end
        end
    end
    if e & EXCEPTIONAL != 0
        if e & SUBTABLE != 0
            r, e = enter_subtable(lit, r, e)
            if e & LITERAL != 0
                r = put_literal(r, e)
                return r, litentry(lit, r), OK
            end
            e & EXCEPTIONAL != 0 || @goto length
        end
        e & INVALID != 0 && return r, e, BAD
        return consume(r, e), e, EOB
    end
    @label length
    r, len = take_value(r, e)
    e = offentry(off, r)
    r = refill_fast(r)
    e & SUBTABLE != 0 && ((r, e) = enter_subtable(off, r, e))
    e & EXCEPTIONAL != 0 && return r, e, BAD
    r, dist = take_value(r, e)
    dist > UInt64(r.out - out_start) && return r, e, BAD
    copy_match(r.out, dist, len)
    r = Regs(r.bitbuf, r.bitsleft, r.inp, r.out + len)
    return r, litentry(lit, r), OK
end

end_block!(s::Stream) = (s.state = s.final ? DONE : HEADER)

function after_step!(s::Stream, status::Int)
    status == BAD && bad("invalid deflate data")
    status == EOB && end_block!(s)
    return
end

@generated function fast_steps(rs::NTuple{N,Regs}, es, lits, offs, starts) where {N}
    steps = (:(fast_step(rs[$k], es[$k], lits[$k], offs[$k], starts[$k])) for k in 1:N)
    return Expr(:block, Expr(:meta, :inline), Expr(:tuple, steps...))
end

@inline can_step(rs::NTuple{N,Regs}, in_lims, out_lims) where {N} =
    all(ntuple(k -> rs[k].inp <= in_lims[k] && rs[k].out <= out_lims[k], Val(N)))

# Run the fast loops of `ss` in lockstep until any stream ends its block or nears a buffer
# end. Callers ensure `fast_ok`; the initial refill makes the bits above `bitsleft` real.
function run_fast!(ss::NTuple{N,Stream}) where {N}
    lits, offs, starts = map(s -> s.lit, ss), map(s -> s.off, ss), map(s -> s.out_start, ss)
    in_lims, out_lims = map(s -> s.in_end - IN_MARGIN, ss), map(s -> s.out_end - OUT_MARGIN, ss)
    rs = map(s -> refill_fast(regs(s)), ss)
    es = map(litentry, lits, rs)
    status = ntuple(_ -> OK, Val(N))
    while can_step(rs, in_lims, out_lims)
        steps = fast_steps(rs, es, lits, offs, starts)
        rs, es, status = map(first, steps), map(x -> x[2], steps), map(last, steps)
        reduce(|, status) == OK || break
    end
    foreach(store!, ss, rs)
    foreach(after_step!, ss, status)
    return
end

# Decode the rest of the current block one symbol at a time, with exact bounds checks.
function run_slow!(s::Stream)
    lit, off = s.lit, s.off
    r = regs(s)
    while true
        r = refill(r, s)
        e = litentry(lit, r)
        e & SUBTABLE != 0 && ((r, e) = enter_subtable(lit, r, e))
        if e & LITERAL != 0
            r.out < s.out_end || bad("deflate output exceeds expected size")
            r = put_literal(r, e)
            continue
        end
        if e & EXCEPTIONAL != 0
            e & INVALID != 0 && bad("invalid literal/length symbol")
            r = consume(r, e)
            break
        end
        r, len = take_value(r, e)
        r = refill(r, s)
        e = offentry(off, r)
        e & SUBTABLE != 0 && ((r, e) = enter_subtable(off, r, e))
        e & EXCEPTIONAL != 0 && bad("invalid offset symbol")
        r, dist = take_value(r, e)
        dist > UInt64(r.out - s.out_start) && bad("match distance too far back")
        len > UInt64(s.out_end - r.out) && bad("deflate output exceeds expected size")
        # Near the input end of a highly compressed stream this loop still emits most bytes.
        if UInt64(s.out_end - r.out) >= len + 16
            copy_match(r.out, dist, len)
        else
            src = r.out - dist
            for i in 0:(Int(len) - 1)
                unsafe_store!(r.out + i, unsafe_load(src + i))
            end
        end
        r = Regs(r.bitbuf, r.bitsleft, r.inp, r.out + len)
    end
    store!(s, r)
    end_block!(s)
    return
end

function read_header!(s::Stream)
    r = refill(regs(s), s)
    s.final = r.bitbuf & 1 != 0
    btype = (r.bitbuf >> 1) & 3
    r = consume(r, UInt64(3))
    if btype == 0
        r = stored_block!(s, r)
        end_block!(s)
    elseif btype == 1
        s.lit, s.off = pointer(FIXED_LIT), pointer(FIXED_OFF)
        s.state = HUFFMAN
    elseif btype == 2
        r = dynamic_header!(s, r)
        s.lit, s.off = pointer(s.littab), pointer(s.offtab)
        s.state = HUFFMAN
    else
        bad("invalid block type")
    end
    store!(s, r)
    return
end

function next_input(s::Stream, r::Regs)
    buffered = Int(r.bitsleft >> 3) - s.overread
    buffered < 0 && bad("truncated deflate stream")
    return r.inp - buffered
end

function stored_block!(s::Stream, r::Regs)
    r = consume(r, r.bitsleft & 7)
    r = refill(r, s)
    len = Int(r.bitbuf & 0xffff)
    nlen = Int((r.bitbuf >> 16) & 0xffff)
    nlen == xor(len, 0xffff) || bad("corrupt stored block length")
    r = consume(r, UInt64(32))
    inp = next_input(s, r)
    len <= s.in_end - inp || bad("truncated stored block")
    len <= s.out_end - r.out || bad("deflate output exceeds expected size")
    unsafe_copyto!(r.out, inp, len)
    s.overread = 0
    return Regs(0, 0, inp + len, r.out + len)
end

function dynamic_header!(s::Stream, r::Regs)
    lens = s.lens
    r = refill(r, s)
    hlit = Int(r.bitbuf & 31) + 257
    hdist = Int((r.bitbuf >> 5) & 31) + 1
    hclen = Int((r.bitbuf >> 10) & 15) + 4
    r = consume(r, UInt64(14))
    (hlit <= 286 && hdist <= 30) || bad("too many length or distance symbols")
    for k in 1:19
        lens[k] = 0x00
    end
    for i in 1:hclen
        r.bitsleft < 3 && (r = refill(r, s))
        lens[PRECODE_ORDER[i] + 1] = r.bitbuf & 7
        r = consume(r, UInt64(3))
    end
    build_table!(s, s.pretab, 0, 19, PRECODE_RESULTS, PRECODE_TABLEBITS, false) || bad("invalid code lengths code")
    n = hlit + hdist
    i = 0
    GC.@preserve s begin
        p, pre = pointer(lens), pointer(s.pretab)
        while i < n
            r.bitsleft < 14 && (r = refill(r, s))
            e = tload(pre, r.bitbuf & ((1 << PRECODE_TABLEBITS) - 1))
            r = consume(r, e)
            sym = e >> 16
            if sym < 16
                unsafe_store!(p, sym % UInt8, i += 1)
                continue
            elseif sym == 16
                i == 0 && bad("repeat with no previous length")
                v = unsafe_load(p, i)
                rep = 3 + Int(r.bitbuf & 3)
                r = consume(r, UInt64(2))
            elseif sym == 17
                v = 0x00
                rep = 3 + Int(r.bitbuf & 7)
                r = consume(r, UInt64(3))
            else
                v = 0x00
                rep = 11 + Int(r.bitbuf & 127)
                r = consume(r, UInt64(7))
            end
            i + rep > n && bad("code lengths overflow")
            for k in 1:rep
                unsafe_store!(p, v, i + k)
            end
            i += rep
        end
    end
    lens[257] == 0 && bad("missing end-of-block code")
    build_table!(s, s.littab, 0, hlit, LITLEN_RESULTS, LITLEN_TABLEBITS, true) || bad("invalid literal/length code")
    build_table!(s, s.offtab, hlit, hdist, OFFSET_RESULTS, OFFSET_TABLEBITS, true) || bad("invalid distance code")
    return r
end

# Advance until the stream can run the fast loop or is done.
function prepare!(s::Stream)
    while s.state != DONE
        if s.state == HEADER
            read_header!(s)
        elseif fast_ok(regs(s), s)
            return
        else
            run_slow!(s)
        end
    end
    return
end

# Once a stream finishes, the rest continue in lockstep without it.
function inflate!(ss::NTuple{N,Stream}) where {N}
    while true
        foreach(prepare!, ss)
        i = findfirst(s -> s.state == DONE, ss)
        if i !== nothing
            N > 1 && inflate!(ntuple(k -> ss[k < i ? k : k + 1], Val(N - 1)))
            return
        end
        run_fast!(ss)
    end
end

crc32(p::Ptr{UInt8}, n::Integer) = ccall((:libdeflate_crc32, libdeflate), UInt32, (UInt32, Ptr{UInt8}, Csize_t), 0, p, n)

# Returns the deflate payload start; header CRC16 (FHCRC) is skipped, not verified.
function gzip_header(p::Ptr{UInt8}, n::Int)
    n >= 18 || bad("gzip member too short")
    (unsafe_load(p) == 0x1f && unsafe_load(p, 2) == 0x8b && unsafe_load(p, 3) == 0x08) || bad("not a gzip member")
    flg = unsafe_load(p, 4)
    pos = 10
    if flg & 0x04 != 0
        pos += 2 + (Int(unsafe_load(p, pos + 1)) | Int(unsafe_load(p, pos + 2)) << 8)
    end
    for bit in (0x08, 0x10)  # FNAME, FCOMMENT: zero-terminated
        flg & bit == 0 && continue
        while pos < n && unsafe_load(p, pos += 1) != 0x00 end
    end
    flg & 0x02 != 0 && (pos += 2)
    pos + 8 <= n || bad("gzip header overruns member")
    return p + pos
end

function gzip_start!(s::Stream, out::Ptr{UInt8}, outlen::Int, inp::Ptr{UInt8}, inlen::Int)
    payload = gzip_header(inp, inlen)
    # The trailer follows the deflate stream, so the stream ends at least 8 bytes early.
    return reset!(s, out, outlen, payload, Int(inp + inlen - 8 - payload))
end

function gzip_finish(s::Stream, outlen::Int)
    s.out == s.out_end || bad("decompressed size mismatch")
    trailer = next_input(s, regs(s))
    crc = ltoh(unsafe_load(Ptr{UInt32}(trailer)))
    isize = ltoh(unsafe_load(Ptr{UInt32}(trailer + 4)))
    isize == outlen % UInt32 || bad("gzip ISIZE mismatch")
    crc == crc32(s.out_start, outlen) || bad("gzip CRC32 mismatch")
    return
end

# Reused across calls: a Stream carries ~12 KB of tables.
const POOL = Stream[]
const POOL_LOCK = ReentrantLock()
take_stream() = @lock POOL_LOCK isempty(POOL) ? Stream() : pop!(POOL)
give_stream(s::Stream) = (@lock POOL_LOCK push!(POOL, s); nothing)

const Member = Tuple{Ptr{UInt8},Int,Ptr{UInt8},Int}

# Decompress the gzip member at `in` into exactly `outlen` bytes at `out`; throws `InflateError`.
# The tuple form decodes independent `(out, outlen, in, inlen)` members in lockstep.
gzip_decompress!(out::Ptr{UInt8}, outlen::Integer, inp::Ptr{UInt8}, inlen::Integer) =
    gzip_decompress!(((out, Int(outlen), inp, Int(inlen)),))

function gzip_decompress!(members::NTuple{N,Member}) where {N}
    ss = ntuple(_ -> take_stream(), Val(N))
    GC.@preserve ss begin
        foreach((s, m) -> gzip_start!(s, m...), ss, members)
        inflate!(ss)
        foreach((s, m) -> gzip_finish(s, m[2]), ss, members)
    end
    foreach(give_stream, ss)
    return
end

end
