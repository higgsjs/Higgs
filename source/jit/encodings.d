//
// Code auto-generated from "jit/encodings.py". Do not modify.
//

module jit.encodings;
import jit.x86;

immutable X86Op add = {
    "add",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [5], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 0, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 0, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [1], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [3], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [5], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 0, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 0, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [1], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [3], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [5], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 0, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 0, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [1], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [3], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [4], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 0, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [0], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [2], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr ADD = &add;
immutable X86Op addsd = {
    "addsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 88], 0xFF, 64, false, false }
    ]
};
immutable X86OpPtr ADDSD = &addsd;
immutable X86Op and = {
    "and",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [37], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [33], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [35], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [37], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [33], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [35], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [37], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [33], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [35], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [36], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 4, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [32], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [34], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr AND = &and;
immutable X86Op call = {
    "call",
    [
        { [X86Enc.R_OR_M], [64], [], [255], 2, 64, false, false },
        { [X86Enc.REL], [32], [], [232], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr CALL = &call;
immutable X86Op cwd = {
    "cwd",
    [
        { [], [], [], [153], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CWD = &cwd;
immutable X86Op cdq = {
    "cdq",
    [
        { [], [], [], [153], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr CDQ = &cdq;
immutable X86Op cqo = {
    "cqo",
    [
        { [], [], [], [153], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr CQO = &cqo;
immutable X86Op cmova = {
    "cmova",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 71], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 71], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 71], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVA = &cmova;
immutable X86Op cmovae = {
    "cmovae",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 67], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 67], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 67], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVAE = &cmovae;
immutable X86Op cmovb = {
    "cmovb",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 66], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 66], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 66], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVB = &cmovb;
immutable X86Op cmovbe = {
    "cmovbe",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 70], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 70], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 70], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVBE = &cmovbe;
immutable X86Op cmovc = {
    "cmovc",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 66], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 66], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 66], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVC = &cmovc;
immutable X86Op cmove = {
    "cmove",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 68], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 68], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 68], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVE = &cmove;
immutable X86Op cmovg = {
    "cmovg",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 79], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 79], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 79], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVG = &cmovg;
immutable X86Op cmovge = {
    "cmovge",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 77], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 77], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 77], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVGE = &cmovge;
immutable X86Op cmovl = {
    "cmovl",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 76], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 76], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 76], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVL = &cmovl;
immutable X86Op cmovle = {
    "cmovle",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 78], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 78], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 78], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVLE = &cmovle;
immutable X86Op cmovna = {
    "cmovna",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 70], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 70], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 70], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNA = &cmovna;
immutable X86Op cmovnae = {
    "cmovnae",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 66], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 66], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 66], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNAE = &cmovnae;
immutable X86Op cmovnb = {
    "cmovnb",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 67], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 67], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 67], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNB = &cmovnb;
immutable X86Op cmovnbe = {
    "cmovnbe",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 71], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 71], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 71], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNBE = &cmovnbe;
immutable X86Op cmovnc = {
    "cmovnc",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 67], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 67], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 67], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNC = &cmovnc;
immutable X86Op cmovne = {
    "cmovne",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 69], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 69], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 69], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNE = &cmovne;
immutable X86Op cmovng = {
    "cmovng",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 78], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 78], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 78], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNG = &cmovng;
immutable X86Op cmovnge = {
    "cmovnge",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 76], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 76], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 76], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNGE = &cmovnge;
immutable X86Op cmovnl = {
    "cmovnl",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 77], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 77], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 77], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNL = &cmovnl;
immutable X86Op cmovnle = {
    "cmovnle",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 79], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 79], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 79], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNLE = &cmovnle;
immutable X86Op cmovno = {
    "cmovno",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 65], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 65], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 65], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNO = &cmovno;
immutable X86Op cmovnp = {
    "cmovnp",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 75], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 75], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 75], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNP = &cmovnp;
immutable X86Op cmovns = {
    "cmovns",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 73], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 73], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 73], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNS = &cmovns;
immutable X86Op cmovnz = {
    "cmovnz",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 69], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 69], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 69], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVNZ = &cmovnz;
immutable X86Op cmovo = {
    "cmovo",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 64], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 64], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 64], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVO = &cmovo;
immutable X86Op cmovp = {
    "cmovp",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 74], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 74], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 74], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVP = &cmovp;
immutable X86Op cmovpe = {
    "cmovpe",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 74], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 74], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 74], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVPE = &cmovpe;
immutable X86Op cmovpo = {
    "cmovpo",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 75], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 75], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 75], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVPO = &cmovpo;
immutable X86Op cmovs = {
    "cmovs",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 72], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 72], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 72], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVS = &cmovs;
immutable X86Op cmovz = {
    "cmovz",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 68], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 68], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 68], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr CMOVZ = &cmovz;
immutable X86Op cmp = {
    "cmp",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [61], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 7, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 7, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [57], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [59], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [61], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 7, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 7, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [57], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [59], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [61], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 7, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 7, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [57], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [59], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [60], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 7, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [56], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [58], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr CMP = &cmp;
immutable X86Op cvtsi2sd = {
    "cvtsi2sd",
    [
        { [X86Enc.XMM, X86Enc.R_OR_M], [128, 64], [242], [15, 42], 0xFF, 64, false, true },
        { [X86Enc.XMM, X86Enc.R_OR_M], [128, 32], [242], [15, 42], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr CVTSI2SD = &cvtsi2sd;
immutable X86Op cvtsd2si = {
    "cvtsd2si",
    [
        { [X86Enc.R, X86Enc.XMM_OR_M], [64, 64], [242], [15, 45], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.XMM_OR_M], [32, 64], [242], [15, 45], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr CVTSD2SI = &cvtsd2si;
immutable X86Op dec = {
    "dec",
    [
        { [X86Enc.R_OR_M], [64], [], [255], 1, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [255], 1, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [255], 1, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [254], 1, 8, false, false }
    ]
};
immutable X86OpPtr DEC = &dec;
immutable X86Op div = {
    "div",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 6, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 6, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 6, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 6, 8, false, false }
    ]
};
immutable X86OpPtr DIV = &div;
immutable X86Op divsd = {
    "divsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 94], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr DIVSD = &divsd;
immutable X86Op fstp = {
    "fstp",
    [
        { [X86Enc.M], [64], [], [221], 3, 64, false, false }
    ]
};
immutable X86OpPtr FSTP = &fstp;
immutable X86Op idiv = {
    "idiv",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 7, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 7, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 7, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 7, 8, false, false }
    ]
};
immutable X86OpPtr IDIV = &idiv;
immutable X86Op imul = {
    "imul",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 5, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [15, 175], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [64, 64, 8], [], [107], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [64, 64, 32], [], [105], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 5, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [15, 175], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [32, 32, 8], [], [107], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [32, 32, 32], [], [105], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 5, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [15, 175], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [16, 16, 8], [], [107], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M, X86Enc.IMM], [16, 16, 16], [], [105], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 5, 8, false, false }
    ]
};
immutable X86OpPtr IMUL = &imul;
immutable X86Op inc = {
    "inc",
    [
        { [X86Enc.R_OR_M], [64], [], [255], 0, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [255], 0, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [255], 0, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [254], 0, 8, false, false }
    ]
};
immutable X86OpPtr INC = &inc;
immutable X86Op ja = {
    "ja",
    [
        { [X86Enc.REL], [32], [], [15, 135], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [119], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JA = &ja;
immutable X86Op jae = {
    "jae",
    [
        { [X86Enc.REL], [32], [], [15, 131], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [115], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JAE = &jae;
immutable X86Op jb = {
    "jb",
    [
        { [X86Enc.REL], [32], [], [15, 130], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [114], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JB = &jb;
immutable X86Op jbe = {
    "jbe",
    [
        { [X86Enc.REL], [32], [], [15, 134], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [118], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JBE = &jbe;
immutable X86Op jc = {
    "jc",
    [
        { [X86Enc.REL], [32], [], [15, 130], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [114], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JC = &jc;
immutable X86Op je = {
    "je",
    [
        { [X86Enc.REL], [32], [], [15, 132], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [116], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JE = &je;
immutable X86Op jg = {
    "jg",
    [
        { [X86Enc.REL], [32], [], [15, 143], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [127], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JG = &jg;
immutable X86Op jge = {
    "jge",
    [
        { [X86Enc.REL], [32], [], [15, 141], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [125], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JGE = &jge;
immutable X86Op jl = {
    "jl",
    [
        { [X86Enc.REL], [32], [], [15, 140], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [124], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JL = &jl;
immutable X86Op jle = {
    "jle",
    [
        { [X86Enc.REL], [32], [], [15, 142], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [126], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JLE = &jle;
immutable X86Op jna = {
    "jna",
    [
        { [X86Enc.REL], [32], [], [15, 134], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [118], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNA = &jna;
immutable X86Op jnae = {
    "jnae",
    [
        { [X86Enc.REL], [32], [], [15, 130], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [114], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNAE = &jnae;
immutable X86Op jnb = {
    "jnb",
    [
        { [X86Enc.REL], [32], [], [15, 131], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [115], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNB = &jnb;
immutable X86Op jnbe = {
    "jnbe",
    [
        { [X86Enc.REL], [32], [], [15, 135], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [119], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNBE = &jnbe;
immutable X86Op jnc = {
    "jnc",
    [
        { [X86Enc.REL], [32], [], [15, 131], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [115], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNC = &jnc;
immutable X86Op jne = {
    "jne",
    [
        { [X86Enc.REL], [32], [], [15, 133], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [117], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNE = &jne;
immutable X86Op jng = {
    "jng",
    [
        { [X86Enc.REL], [32], [], [15, 142], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [126], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNG = &jng;
immutable X86Op jnge = {
    "jnge",
    [
        { [X86Enc.REL], [32], [], [15, 140], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [124], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNGE = &jnge;
immutable X86Op jnl = {
    "jnl",
    [
        { [X86Enc.REL], [32], [], [15, 141], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [125], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNL = &jnl;
immutable X86Op jnle = {
    "jnle",
    [
        { [X86Enc.REL], [32], [], [15, 143], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [127], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNLE = &jnle;
immutable X86Op jno = {
    "jno",
    [
        { [X86Enc.REL], [32], [], [15, 129], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [113], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNO = &jno;
immutable X86Op jnp = {
    "jnp",
    [
        { [X86Enc.REL], [32], [], [15, 139], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [123], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNP = &jnp;
immutable X86Op jns = {
    "jns",
    [
        { [X86Enc.REL], [32], [], [15, 137], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [121], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNS = &jns;
immutable X86Op jnz = {
    "jnz",
    [
        { [X86Enc.REL], [32], [], [15, 133], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [117], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JNZ = &jnz;
immutable X86Op jo = {
    "jo",
    [
        { [X86Enc.REL], [32], [], [15, 128], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [112], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JO = &jo;
immutable X86Op jp = {
    "jp",
    [
        { [X86Enc.REL], [32], [], [15, 138], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [122], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JP = &jp;
immutable X86Op jpe = {
    "jpe",
    [
        { [X86Enc.REL], [32], [], [15, 138], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [122], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JPE = &jpe;
immutable X86Op jpo = {
    "jpo",
    [
        { [X86Enc.REL], [32], [], [15, 139], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [123], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JPO = &jpo;
immutable X86Op js = {
    "js",
    [
        { [X86Enc.REL], [32], [], [15, 136], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [120], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JS = &js;
immutable X86Op jz = {
    "jz",
    [
        { [X86Enc.REL], [32], [], [15, 132], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [116], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JZ = &jz;
immutable X86Op jmp = {
    "jmp",
    [
        { [X86Enc.R_OR_M], [64], [], [255], 4, 64, false, true },
        { [X86Enc.REL], [32], [], [233], 0xFF, 32, false, false },
        { [X86Enc.REL], [8], [], [235], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr JMP = &jmp;
immutable X86Op lea = {
    "lea",
    [
        { [X86Enc.R, X86Enc.M], [64, 0], [], [141], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.M], [32, 0], [], [141], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr LEA = &lea;
immutable X86Op mov = {
    "mov",
    [
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [137], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [139], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.MOFFS], [64, 64], [], [161], 0xFF, 64, false, true },
        { [X86Enc.MOFFS, X86Enc.REGA], [64, 64], [], [163], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.IMM], [64, 64], [], [184], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [199], 0, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [137], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [139], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.MOFFS], [32, 32], [], [161], 0xFF, 32, false, false },
        { [X86Enc.MOFFS, X86Enc.REGA], [32, 32], [], [163], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.IMM], [32, 32], [], [184], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [199], 0, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [137], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [139], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.IMM], [16, 16], [], [184], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [199], 0, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [136], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [138], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.IMM], [8, 8], [], [176], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [198], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr MOV = &mov;
immutable X86Op movapd = {
    "movapd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 128], [102], [15, 40], 0xFF, 128, false, false },
        { [X86Enc.XMM_OR_M, X86Enc.XMM], [128, 128], [102], [15, 41], 0xFF, 128, false, false }
    ]
};
immutable X86OpPtr MOVAPD = &movapd;
immutable X86Op movsd = {
    "movsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 16], 0xFF, 64, false, true },
        { [X86Enc.XMM_OR_M, X86Enc.XMM], [64, 128], [242], [15, 17], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr MOVSD = &movsd;
immutable X86Op movsx = {
    "movsx",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 8], [], [15, 190], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 16], [], [15, 191], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 8], [], [15, 190], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 16], [], [15, 191], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 8], [], [15, 190], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr MOVSX = &movsx;
immutable X86Op movsxd = {
    "movsxd",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 32], [], [99], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr MOVSXD = &movsxd;
immutable X86Op movupd = {
    "movupd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 128], [102], [15, 16], 0xFF, 128, false, false },
        { [X86Enc.XMM_OR_M, X86Enc.XMM], [128, 128], [102], [15, 17], 0xFF, 128, false, false }
    ]
};
immutable X86OpPtr MOVUPD = &movupd;
immutable X86Op movzx = {
    "movzx",
    [
        { [X86Enc.R, X86Enc.R_OR_M], [64, 8], [], [15, 182], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 16], [], [15, 183], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 8], [], [15, 182], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 16], [], [15, 183], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 8], [], [15, 182], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr MOVZX = &movzx;
immutable X86Op mul = {
    "mul",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 4, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 4, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 4, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 4, 8, false, false }
    ]
};
immutable X86OpPtr MUL = &mul;
immutable X86Op mulsd = {
    "mulsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 89], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr MULSD = &mulsd;
immutable X86Op neg = {
    "neg",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 3, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 3, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 3, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 3, 8, false, false }
    ]
};
immutable X86OpPtr NEG = &neg;
immutable X86Op nop = {
    "nop",
    [
        { [], [], [], [144], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr NOP = &nop;
immutable X86Op not = {
    "not",
    [
        { [X86Enc.R_OR_M], [64], [], [247], 2, 64, false, true },
        { [X86Enc.R_OR_M], [32], [], [247], 2, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [247], 2, 16, true, false },
        { [X86Enc.R_OR_M], [8], [], [246], 2, 8, false, false }
    ]
};
immutable X86OpPtr NOT = &not;
immutable X86Op or = {
    "or",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [13], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 1, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 1, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [9], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [11], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [13], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 1, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 1, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [9], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [11], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [13], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 1, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 1, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [9], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [11], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [12], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 1, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [8], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [10], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr OR = &or;
immutable X86Op pop = {
    "pop",
    [
        { [X86Enc.R_OR_M], [64], [], [143], 0, 64, false, true },
        { [X86Enc.R], [64], [], [88], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M], [16], [], [143], 0, 16, true, false },
        { [X86Enc.R], [16], [], [88], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr POP = &pop;
immutable X86Op popf = {
    "popf",
    [
        { [], [], [], [157], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr POPF = &popf;
immutable X86Op popfq = {
    "popfq",
    [
        { [], [], [], [157], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr POPFQ = &popfq;
immutable X86Op push = {
    "push",
    [
        { [X86Enc.R_OR_M], [64], [], [255], 6, 64, false, true },
        { [X86Enc.R], [64], [], [80], 0xFF, 64, false, true },
        { [X86Enc.IMM], [32], [], [104], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M], [16], [], [255], 6, 16, true, false },
        { [X86Enc.R], [16], [], [80], 0xFF, 16, true, false },
        { [X86Enc.IMM], [8], [], [106], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr PUSH = &push;
immutable X86Op pushf = {
    "pushf",
    [
        { [], [], [], [156], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr PUSHF = &pushf;
immutable X86Op pushfq = {
    "pushfq",
    [
        { [], [], [], [156], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr PUSHFQ = &pushfq;
immutable X86Op rdpmc = {
    "rdpmc",
    [
        { [], [], [], [15, 51], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr RDPMC = &rdpmc;
immutable X86Op rdtsc = {
    "rdtsc",
    [
        { [], [], [], [15, 49], 0xFF, 32, false, false }
    ]
};
immutable X86OpPtr RDTSC = &rdtsc;
immutable X86Op ret = {
    "ret",
    [
        { [], [], [], [195], 0xFF, 32, false, false },
        { [X86Enc.IMM], [16], [], [194], 0xFF, 16, true, false }
    ]
};
immutable X86OpPtr RET = &ret;
immutable X86Op roundsd = {
    "roundsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M, X86Enc.IMM], [128, 64, 8], [102], [15, 58, 11], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr ROUNDSD = &roundsd;
immutable X86Op sal = {
    "sal",
    [
        { [X86Enc.R_OR_M, X86Enc.CST1], [64, 8], [], [209], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.REGC], [64, 8], [], [211], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [193], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.CST1], [32, 8], [], [209], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [32, 8], [], [211], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [193], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [16, 8], [], [209], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [16, 8], [], [211], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [193], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [8, 8], [], [208], 4, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [8, 8], [], [210], 4, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [192], 4, 8, false, false }
    ]
};
immutable X86OpPtr SAL = &sal;
immutable X86Op sar = {
    "sar",
    [
        { [X86Enc.R_OR_M, X86Enc.CST1], [64, 8], [], [209], 7, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.REGC], [64, 8], [], [211], 7, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [193], 7, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.CST1], [32, 8], [], [209], 7, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [32, 8], [], [211], 7, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [193], 7, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [16, 8], [], [209], 7, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [16, 8], [], [211], 7, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [193], 7, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [8, 8], [], [208], 7, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [8, 8], [], [210], 7, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [192], 7, 8, false, false }
    ]
};
immutable X86OpPtr SAR = &sar;
immutable X86Op shl = {
    "shl",
    [
        { [X86Enc.R_OR_M, X86Enc.CST1], [64, 8], [], [209], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.REGC], [64, 8], [], [211], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [193], 4, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.CST1], [32, 8], [], [209], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [32, 8], [], [211], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [193], 4, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [16, 8], [], [209], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [16, 8], [], [211], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [193], 4, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [8, 8], [], [208], 4, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [8, 8], [], [210], 4, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [192], 4, 8, false, false }
    ]
};
immutable X86OpPtr SHL = &shl;
immutable X86Op shr = {
    "shr",
    [
        { [X86Enc.R_OR_M, X86Enc.CST1], [64, 8], [], [209], 5, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.REGC], [64, 8], [], [211], 5, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [193], 5, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.CST1], [32, 8], [], [209], 5, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [32, 8], [], [211], 5, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [193], 5, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [16, 8], [], [209], 5, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [16, 8], [], [211], 5, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [193], 5, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.CST1], [8, 8], [], [208], 5, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.REGC], [8, 8], [], [210], 5, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [192], 5, 8, false, false }
    ]
};
immutable X86OpPtr SHR = &shr;
immutable X86Op sqrtsd = {
    "sqrtsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 81], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr SQRTSD = &sqrtsd;
immutable X86Op sub = {
    "sub",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [45], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 5, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 5, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [41], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [43], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [45], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 5, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 5, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [41], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [43], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [45], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 5, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 5, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [41], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [43], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [44], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 5, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [40], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [42], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr SUB = &sub;
immutable X86Op subsd = {
    "subsd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [242], [15, 92], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr SUBSD = &subsd;
immutable X86Op test = {
    "test",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [169], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [247], 0, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [133], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [169], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [247], 0, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [133], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [169], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [247], 0, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [133], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [168], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [246], 0, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [132], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr TEST = &test;
immutable X86Op ucomisd = {
    "ucomisd",
    [
        { [X86Enc.XMM, X86Enc.XMM_OR_M], [128, 64], [102], [15, 46], 0xFF, 64, false, true }
    ]
};
immutable X86OpPtr UCOMISD = &ucomisd;
immutable X86Op xchg = {
    "xchg",
    [
        { [X86Enc.REGA, X86Enc.R], [64, 64], [], [144], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.REGA], [64, 32], [], [144], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [135], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [135], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.R], [32, 32], [], [144], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.REGA], [32, 32], [], [144], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [135], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [135], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.R], [16, 16], [], [144], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.REGA], [16, 16], [], [144], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [135], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [135], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [134], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [134], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr XCHG = &xchg;
immutable X86Op xor = {
    "xor",
    [
        { [X86Enc.REGA, X86Enc.IMM], [64, 32], [], [53], 0xFF, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 32], [], [129], 6, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.IMM], [64, 8], [], [131], 6, 64, false, true },
        { [X86Enc.R_OR_M, X86Enc.R], [64, 64], [], [49], 0xFF, 64, false, true },
        { [X86Enc.R, X86Enc.R_OR_M], [64, 64], [], [51], 0xFF, 64, false, true },
        { [X86Enc.REGA, X86Enc.IMM], [32, 32], [], [53], 0xFF, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 32], [], [129], 6, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [32, 8], [], [131], 6, 32, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [32, 32], [], [49], 0xFF, 32, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [32, 32], [], [51], 0xFF, 32, false, false },
        { [X86Enc.REGA, X86Enc.IMM], [16, 16], [], [53], 0xFF, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 16], [], [129], 6, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [16, 8], [], [131], 6, 16, true, false },
        { [X86Enc.R_OR_M, X86Enc.R], [16, 16], [], [49], 0xFF, 16, true, false },
        { [X86Enc.R, X86Enc.R_OR_M], [16, 16], [], [51], 0xFF, 16, true, false },
        { [X86Enc.REGA, X86Enc.IMM], [8, 8], [], [52], 0xFF, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.IMM], [8, 8], [], [128], 6, 8, false, false },
        { [X86Enc.R_OR_M, X86Enc.R], [8, 8], [], [48], 0xFF, 8, false, false },
        { [X86Enc.R, X86Enc.R_OR_M], [8, 8], [], [50], 0xFF, 8, false, false }
    ]
};
immutable X86OpPtr XOR = &xor;
