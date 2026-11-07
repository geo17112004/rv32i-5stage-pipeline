#!/usr/bin/env python3
"""
rvasm.py - Minimal two-pass RV32I assembler (no toolchain needed)

Usage:  python rvasm.py program.s            -> program.hex + program.lst

Supports
  * all RV32I instructions (FENCE / ECALL / EBREAK encode as usual)
  * registers x0-x31 and ABI names (zero, ra, sp, t0, a0, s0 ...)
  * labels, '#' and '//' comments, .word directive
  * expressions:  label, number, label+number, label-number
  * pseudo-ops:   nop, li, la, mv, not, neg, j, jr, ret, beqz, bnez,
                  bgt, ble, bgtu, bleu
    (li / la always expand to lui + addi, so instruction sizes are fixed)
"""
import re
import sys

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
       "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
       "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
       "t3", "t4", "t5", "t6"]
REGS = {f"x{i}": i for i in range(32)}
REGS.update({name: i for i, name in enumerate(ABI)})
REGS["fp"] = 8

R_TYPE = {  # name: (funct7, funct3)
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
}
I_ALU = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
I_SHIFT = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}

OP_LUI, OP_AUIPC, OP_JAL, OP_JALR = 0x37, 0x17, 0x6F, 0x67
OP_BRANCH, OP_LOAD, OP_STORE = 0x63, 0x03, 0x23
OP_IMM, OP_REG = 0x13, 0x33


class AsmError(Exception):
    pass


def reg(tok):
    t = tok.strip().lower()
    if t not in REGS:
        raise AsmError(f"unknown register '{tok}'")
    return REGS[t]


def value(expr, labels):
    """Evaluate number | label | label+num | label-num | num+num ..."""
    expr = expr.replace(" ", "")
    if not expr:
        raise AsmError("missing operand")
    terms = re.findall(r"[+-]?[^+-]+", expr)
    total = 0
    for term in terms:
        sign = -1 if term.startswith("-") else 1
        body = term.lstrip("+-")
        if body in labels:
            v = labels[body]
        else:
            try:
                v = int(body, 0)
            except ValueError:
                raise AsmError(f"undefined label or bad number '{body}'")
        total += sign * v
    return total


def check_signed(v, bits, what):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= v <= hi:
        raise AsmError(f"{what} {v} out of range [{lo}, {hi}]")


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    check_signed(imm, 12, "I-immediate")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    check_signed(imm, 12, "S-immediate")
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(off, rs2, rs1, f3, op):
    if off % 2:
        raise AsmError("branch offset must be even")
    check_signed(off, 13, "branch offset")
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((o >> 1) & 0xF) << 8) | \
           (((o >> 11) & 1) << 7) | op


def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(off, rd, op):
    if off % 2:
        raise AsmError("jump offset must be even")
    check_signed(off, 21, "jump offset")
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | \
           (((o >> 11) & 1) << 20) | (((o >> 12) & 0xFF) << 12) | (rd << 7) | op


def mem_operand(tok):
    """'imm(rs1)' -> (imm_expr, rs1)"""
    m = re.fullmatch(r"\s*(.*)\(\s*(\w+)\s*\)\s*", tok)
    if not m:
        raise AsmError(f"expected offset(reg), got '{tok}'")
    return (m.group(1) or "0"), m.group(2)


def size_of(mnem):
    return 8 if mnem in ("li", "la") else 4


def encode(mnem, ops, pc, labels):
    """Return list of 32-bit words for one source instruction."""
    v = lambda e: value(e, labels)
    n = len(ops)

    def need(k):
        if n != k:
            raise AsmError(f"'{mnem}' expects {k} operands, got {n}")

    # ---------------- pseudo instructions ----------------
    if mnem == "nop":
        return [enc_i(0, 0, 0, 0, OP_IMM)]
    if mnem in ("li", "la"):
        need(2)
        rd, val = reg(ops[0]), v(ops[1]) & 0xFFFFFFFF
        lo = val & 0xFFF
        if lo & 0x800:
            lo -= 0x1000
        hi = ((val - lo) >> 12) & 0xFFFFF
        return [enc_u(hi, rd, OP_LUI), enc_i(lo, rd, 0, rd, OP_IMM)]
    if mnem == "mv":
        need(2); return [enc_i(0, reg(ops[1]), 0, reg(ops[0]), OP_IMM)]
    if mnem == "not":
        need(2); return [enc_i(-1, reg(ops[1]), 4, reg(ops[0]), OP_IMM)]
    if mnem == "neg":
        need(2); return [enc_r(0x20, reg(ops[1]), 0, 0, reg(ops[0]), OP_REG)]
    if mnem == "j":
        need(1); return [enc_j(v(ops[0]) - pc, 0, OP_JAL)]
    if mnem == "jr":
        need(1); return [enc_i(0, reg(ops[0]), 0, 0, OP_JALR)]
    if mnem == "ret":
        return [enc_i(0, 1, 0, 0, OP_JALR)]
    if mnem == "beqz":
        need(2); return [enc_b(v(ops[1]) - pc, 0, reg(ops[0]), 0, OP_BRANCH)]
    if mnem == "bnez":
        need(2); return [enc_b(v(ops[1]) - pc, 0, reg(ops[0]), 1, OP_BRANCH)]
    if mnem in ("bgt", "ble", "bgtu", "bleu"):   # swap operands
        need(3)
        base = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}[mnem]
        return [enc_b(v(ops[2]) - pc, reg(ops[0]), reg(ops[1]),
                      BRANCHES[base], OP_BRANCH)]

    # ---------------- real instructions ----------------
    if mnem in R_TYPE:
        need(3)
        f7, f3 = R_TYPE[mnem]
        return [enc_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), OP_REG)]
    if mnem in I_ALU:
        need(3)
        return [enc_i(v(ops[2]), reg(ops[1]), I_ALU[mnem], reg(ops[0]), OP_IMM)]
    if mnem in I_SHIFT:
        need(3)
        f7, f3 = I_SHIFT[mnem]
        sh = v(ops[2])
        if not 0 <= sh <= 31:
            raise AsmError(f"shift amount {sh} out of range")
        return [enc_r(f7, sh, reg(ops[1]), f3, reg(ops[0]), OP_IMM)]
    if mnem in LOADS:
        need(2)
        off, base = mem_operand(ops[1])
        return [enc_i(v(off), reg(base), LOADS[mnem], reg(ops[0]), OP_LOAD)]
    if mnem in STORES:
        need(2)
        off, base = mem_operand(ops[1])
        return [enc_s(v(off), reg(ops[0]), reg(base), STORES[mnem], OP_STORE)]
    if mnem in BRANCHES:
        need(3)
        return [enc_b(v(ops[2]) - pc, reg(ops[1]), reg(ops[0]),
                      BRANCHES[mnem], OP_BRANCH)]
    if mnem == "lui":
        need(2); return [enc_u(v(ops[1]), reg(ops[0]), OP_LUI)]
    if mnem == "auipc":
        need(2); return [enc_u(v(ops[1]), reg(ops[0]), OP_AUIPC)]
    if mnem == "jal":
        if n == 1:
            return [enc_j(v(ops[0]) - pc, 1, OP_JAL)]
        need(2)
        return [enc_j(v(ops[1]) - pc, reg(ops[0]), OP_JAL)]
    if mnem == "jalr":
        if n == 1:                                   # jalr rs1
            return [enc_i(0, reg(ops[0]), 0, 1, OP_JALR)]
        if n == 2:                                   # jalr rd, off(rs1)
            off, base = mem_operand(ops[1])
            return [enc_i(v(off), reg(base), 0, reg(ops[0]), OP_JALR)]
        need(3)                                      # jalr rd, rs1, off
        return [enc_i(v(ops[2]), reg(ops[1]), 0, reg(ops[0]), OP_JALR)]
    if mnem == "ecall":
        return [0x00000073]
    if mnem == "ebreak":
        return [0x00100073]
    if mnem == "fence":
        return [0x0FF0000F]
    if mnem == ".word":
        return [v(o) & 0xFFFFFFFF for o in ops]
    raise AsmError(f"unknown instruction '{mnem}'")


def parse(lines):
    """Yield (lineno, label_list, mnemonic, operands, source)."""
    for ln, raw in enumerate(lines, 1):
        line = raw.split("#")[0].split("//")[0].strip()
        labels = []
        while True:
            m = re.match(r"^([A-Za-z_.][\w.]*)\s*:\s*(.*)$", line)
            if not m:
                break
            labels.append(m.group(1))
            line = m.group(2).strip()
        mnem, ops = None, []
        if line:
            parts = line.split(None, 1)
            mnem = parts[0].lower()
            if len(parts) > 1:
                ops = [o.strip() for o in parts[1].split(",")]
        yield ln, labels, mnem, ops, raw.rstrip()


def assemble(src_lines):
    items = list(parse(src_lines))
    labels, pc = {}, 0
    for ln, labs, mnem, ops, _ in items:                 # pass 1
        for lab in labs:
            if lab in labels:
                raise AsmError(f"line {ln}: duplicate label '{lab}'")
            labels[lab] = pc
        if mnem:
            pc += 4 * len(ops) if mnem == ".word" else size_of(mnem)
    words, listing, pc = [], [], 0
    for ln, labs, mnem, ops, src in items:               # pass 2
        if not mnem:
            continue
        try:
            enc = encode(mnem, ops, pc, labels)
        except AsmError as e:
            raise AsmError(f"line {ln}: {e}\n    {src.strip()}")
        for i, w in enumerate(enc):
            listing.append(f"{pc + 4*i:08x}:  {w:08x}    {src.strip() if i == 0 else ''}")
        words.extend(enc)
        pc += 4 * len(enc)
    return words, listing, labels


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    base = src[:-2] if src.endswith(".s") else src
    with open(src) as f:
        try:
            words, listing, _ = assemble(f.readlines())
        except AsmError as e:
            print(f"error: {e}")
            sys.exit(1)
    with open(base + ".hex", "w") as f:
        f.write("\n".join(f"{w:08x}" for w in words) + "\n")
    with open(base + ".lst", "w") as f:
        f.write("\n".join(listing) + "\n")
    print(f"{src}: {len(words)} words -> {base}.hex, {base}.lst")


if __name__ == "__main__":
    main()
