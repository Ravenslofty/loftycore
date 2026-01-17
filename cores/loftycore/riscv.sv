/*
 *  NERV -- Naive Educational RISC-V Processor
 *
 *  Copyright (C) 2020  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

package RiscVOpcode32;
	// opcodes - see section 19 of RiscV spec
	typedef enum logic [6:0] {
		LOAD       = 7'b 00_000_11,
		STORE      = 7'b 01_000_11,
		MADD       = 7'b 10_000_11,
		BRANCH     = 7'b 11_000_11,

		LOAD_FP    = 7'b 00_001_11,
		STORE_FP   = 7'b 01_001_11,
		MSUB       = 7'b 10_001_11,
		JALR       = 7'b 11_001_11,

		CUSTOM_0   = 7'b 00_010_11,
		CUSTOM_1   = 7'b 01_010_11,
		NMSUB      = 7'b 10_010_11,
		RESERVED_0 = 7'b 11_010_11,

		MISC_MEM   = 7'b 00_011_11,
		AMO        = 7'b 01_011_11,
		NMADD      = 7'b 10_011_11,
		JAL        = 7'b 11_011_11,

		OP_IMM     = 7'b 00_100_11,
		OP         = 7'b 01_100_11,
		OP_FP      = 7'b 10_100_11,
		SYSTEM     = 7'b 11_100_11,

		AUIPC      = 7'b 00_101_11,
		LUI        = 7'b 01_101_11,
		OP_V       = 7'b 10_101_11,
		OP_VE      = 7'b 11_101_11,

		OP_IMM_32  = 7'b 00_110_11,
		OP_32      = 7'b 01_110_11,
		CUSTOM_2   = 7'b 10_110_11,
		CUSTOM_3   = 7'b 11_110_11
	} Opcode32;
endpackage

package RiscVOpcode32Load;
	typedef enum logic [2:0] {
		LB  = 3'b000, // I
		LH  = 3'b001, // I
		LW  = 3'b010, // I
		LBU = 3'b100, // I
		LHU = 3'b101  // I
	} Funct3;
endpackage

package RiscVOpcode32Branch;
	typedef enum logic [2:0] {
		BEQ  = 3'b000, // I
		BNE  = 3'b001, // I
		BLT  = 3'b100, // I
		BGE  = 3'b101, // I
		BLTU = 3'b110, // I
		BGEU = 3'b111  // I
	} Funct3;
endpackage

package RiscVOpcode32Op;
	typedef enum logic [2:0] {
		ADD  = 3'b000, // I
		SLL  = 3'b001, // I
		SLT  = 3'b010, // I
		SLTU = 3'b011, // I
		XOR  = 3'b100, // I
		SRL  = 3'b101, // I
		OR   = 3'b110, // I
		AND  = 3'b111  // I
	} Funct7Is0_Funct3;

	// PACK
	typedef enum logic [2:0] {
		PACK  = 3'b100, // Zbkb
		PACKH = 3'b111  // Zbkb
	} Funct7Is4_Funct3;

	// MINMAX/CLMUL
	typedef enum logic [2:0] {
		CLMUL  = 3'b001, // Zbc
		CLMULR = 3'b010, // Zbc
		CLMULH = 3'b011, // Zbc
		MIN    = 3'b100, // Zbb
		MINU   = 3'b101, // Zbb
		MAX    = 3'b110, // Zbb
		MAXU   = 3'b111  // Zbb
	} Funct7Is5_Funct3;

	// SH1ADD/SH2ADD/SH3ADD
	typedef enum logic [2:0] {
		SH1ADD = 3'b010, // Zba
		SH2ADD = 3'b100, // Zba
		SH3ADD = 3'b110  // Zba
	} Funct7Is16_Funct3;

	// BSET
	typedef enum logic [2:0] {
		BSET   = 3'b001, // Zbs
		XPERM4 = 3'b010, // Zbkx
		XPERM8 = 3'b100  // Zbkx
	} Funct7Is20_Funct3;

	typedef enum logic [2:0] {
		SUB  = 3'b000, // I
		XNOR = 3'b100, // Zbb
		SRA  = 3'b101, // I
		ORN  = 3'b110, // Zbb
		ANDN = 3'b111  // Zbb
	} Funct7Is32_Funct3;

	// BCLR/BEXT
	typedef enum logic [2:0] {
		BCLR = 3'b001, // Zbs
		BEXT = 3'b101  // Zbs
	} Funct7Is36_Funct3;

	// ROL/ROR
	typedef enum logic [2:0] {
		ROL  = 3'b001, // Zbb
		ROR  = 3'b101  // Zbb
	} Funct7Is48_Funct3;

	// BINV
	typedef enum logic [2:0] {
		BINV = 3'b001 // Zbs
	} Funct7Is52_Funct3;
endpackage

package RiscVOpcode32OpImm;
	typedef enum logic [2:0] {
		ADDI  = 3'b000, // I
		SLLI  = 3'b001, // I
		SLTI  = 3'b010, // I
		SLTIU = 3'b011, // I
		XORI  = 3'b100, // I
		SRLI  = 3'b101, // I
		ORI   = 3'b110, // I
		ANDI  = 3'b111  // I
	} Funct7Is0_Funct3;

	// BSETI
	typedef enum logic [2:0] {
		BSETI = 3'b001  // Zbs
	} Funct7Is20_Funct3;

	typedef enum logic [2:0] {
		SRAI = 3'b101  // I
	} Funct7Is32_Funct3;

	// BCLRI/BEXTI
	typedef enum logic [2:0] {
		BCLRI = 3'b001, // Zbs
		BEXTI = 3'b101  // Zbs
	} Funct7Is36_Funct3;

	// CLZ
	typedef enum logic [2:0] {
		CLZ  = 3'b001  // Zbb
	} Funct7Is48_Rs2Is0_Funct3;

	// CTZ
	typedef enum logic [2:0] {
		CTZ  = 3'b001  // Zbb
	} Funct7Is48_Rs2Is1_Funct3;

	// CPOP
	typedef enum logic [2:0] {
		CPOP = 3'b001  // Zbb
	} Funct7Is48_Rs2Is2_Funct3;

	// SEXT.B
	typedef enum logic [2:0] {
		SEXTB = 3'b001 // Zbb
	} Funct7Is48_Rs2Is4_Funct3;

	// SEXT.H
	typedef enum logic [2:0] {
		SEXTH = 3'b001 // Zbb
	} Funct7Is48_Rs2Is5_Funct3;

	// BINVI
	typedef enum logic [2:0] {
		BINVI = 3'b001 // Zbs
	} Funct7Is52_Funct3;

	// BREV8
	typedef enum logic [2:0] {
		BREV8 = 3'b101 // Zbb
	} Funct7Is52_Rs2Is7_Funct3;

	// REV8
	typedef enum logic [2:0] {
		REV8  = 3'b101 // Zbb
	} Funct7Is52_Rs2Is24_Funct3;

endpackage

package RiscV;
	// components of the instruction
	// split R-type instruction - see section 2.2 of RiscV spec
	typedef struct packed {
		logic [6:0] funct7;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} Insn32;

	// immediate functions
	function logic [11:0] immediate_i(Insn32 insn);
		return {insn.funct7, insn.rs2};
	endfunction

	function logic [31:0] immediate_i_sext(Insn32 insn);
		return 32'($signed(immediate_i(insn)));
	endfunction

	function logic [31:0] immediate_s(Insn32 insn);
		return 32'($signed({insn.funct7, insn.rd}));
	endfunction

	function logic [31:0] immediate_b(Insn32 insn);
		return 32'($signed({insn.funct7[6], insn.rd[0], insn.funct7[5:0], insn.rd[4:1], 1'b0}));
	endfunction

	function logic [31:0] immediate_u(Insn32 insn);
		return 32'({insn.funct7, insn.rs2, insn.rs1, insn.funct3}) << 12;
	endfunction

	function logic [31:0] immediate_j(Insn32 insn);
		return 32'($signed({insn.funct7[6], insn.rs1, insn.funct3, insn.rs2[0], insn.funct7[5:0], insn.rs2[4:1], 1'b0}));
	endfunction

	// opcode checking
	function bit opcode_is_load(Insn32 insn);
		return insn.opcode == RiscVOpcode32::LOAD;
	endfunction

	function bit opcode_is_store(Insn32 insn);
		return insn.opcode == RiscVOpcode32::STORE;
	endfunction

	function bit opcode_is_branch(Insn32 insn);
		return insn.opcode == RiscVOpcode32::BRANCH;
	endfunction

	function bit opcode_is_jalr(Insn32 insn);
		return insn.opcode == RiscVOpcode32::JALR;
	endfunction

	function bit opcode_is_jal(Insn32 insn);
		return insn.opcode == RiscVOpcode32::JAL;
	endfunction

	function bit opcode_is_op_imm(Insn32 insn);
		return insn.opcode == RiscVOpcode32::OP_IMM;
	endfunction

	function bit opcode_is_op(Insn32 insn);
		return insn.opcode == RiscVOpcode32::OP;
	endfunction

	function bit opcode_is_system(Insn32 insn);
		return insn.opcode == RiscVOpcode32::SYSTEM;
	endfunction

	function bit opcode_is_auipc(Insn32 insn);
		return insn.opcode == RiscVOpcode32::AUIPC;
	endfunction

	function bit opcode_is_lui(Insn32 insn);
		return insn.opcode == RiscVOpcode32::LUI;
	endfunction

	// instruction checking functions: LOAD opcode
	function bit is_lb(Insn32 insn);
		return opcode_is_load(insn) && insn.funct3 == RiscVOpcode32Load::LB;
	endfunction

	function bit is_lh(Insn32 insn);
		return opcode_is_load(insn) && insn.funct3 == RiscVOpcode32Load::LH;
	endfunction

	function bit is_lw(Insn32 insn);
		return opcode_is_load(insn) && insn.funct3 == RiscVOpcode32Load::LW;
	endfunction

	function bit is_lbu(Insn32 insn);
		return opcode_is_load(insn) && insn.funct3 == RiscVOpcode32Load::LBU;
	endfunction

	function bit is_lhu(Insn32 insn);
		return opcode_is_load(insn) && insn.funct3 == RiscVOpcode32Load::LHU;
	endfunction

	// instruction checking functions: BRANCH opcode
	function bit is_beq(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BEQ;
	endfunction

	function bit is_bne(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BNE;
	endfunction

	function bit is_blt(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BLT;
	endfunction

	function bit is_bge(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BGE;
	endfunction

	function bit is_bltu(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BLTU;
	endfunction

	function bit is_bgeu(Insn32 insn);
		return opcode_is_branch(insn) && insn.funct3 == RiscVOpcode32Branch::BGEU;
	endfunction

	// instruction checking functions: OP-IMM opcode
	function bit is_addi(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::ADDI;
	endfunction

	function bit is_slli(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0000000 && insn.funct3 == RiscVOpcode32OpImm::SLLI;
	endfunction

	function bit is_slti(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::SLTI;
	endfunction

	function bit is_sltiu(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::SLTIU;
	endfunction

	function bit is_xori(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::XORI;
	endfunction

	function bit is_srli(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0000000 && insn.funct3 == RiscVOpcode32OpImm::SRLI;
	endfunction

	function bit is_ori(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::ORI;
	endfunction

	function bit is_andi(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct3 == RiscVOpcode32OpImm::ANDI;
	endfunction

	function bit is_bseti(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0010100 && insn.funct3 == RiscVOpcode32OpImm::BSETI;
	endfunction

	function bit is_srai(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32OpImm::SRAI;
	endfunction

	function bit is_bclri(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0100100 && insn.funct3 == RiscVOpcode32OpImm::BCLRI;
	endfunction

	function bit is_bexti(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0100100 && insn.funct3 == RiscVOpcode32OpImm::BEXTI;
	endfunction

	function bit is_clz(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0110000 && insn.rs2 == 0 && insn.funct3 == RiscVOpcode32OpImm::CLZ;
	endfunction

	function bit is_ctz(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0110000 && insn.rs2 == 1 && insn.funct3 == RiscVOpcode32OpImm::CTZ;
	endfunction

	function bit is_binvi(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0110100 && insn.funct3 == RiscVOpcode32OpImm::BINVI;
	endfunction

	function bit is_rev8(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0110100 && insn.rs2 == 24 && insn.funct3 == RiscVOpcode32OpImm::REV8;
	endfunction

	function bit is_brev8(Insn32 insn);
		return opcode_is_op_imm(insn) && insn.funct7 == 7'b0110100 && insn.rs2 == 7 && insn.funct3 == RiscVOpcode32OpImm::BREV8;
	endfunction

	// instruction checking functions: OP opcode
	function bit is_sll(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000000 && insn.funct3 == RiscVOpcode32Op::SLL;
	endfunction

	function bit is_slt(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000000 && insn.funct3 == RiscVOpcode32Op::SLT;
	endfunction

	function bit is_srl(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000000 && insn.funct3 == RiscVOpcode32Op::SRL;
	endfunction

	function bit is_min(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000101 && insn.funct3 == RiscVOpcode32Op::MIN;
	endfunction

	function bit is_minu(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000101 && insn.funct3 == RiscVOpcode32Op::MINU;
	endfunction

	function bit is_max(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0000101 && insn.funct3 == RiscVOpcode32Op::MAX;
	endfunction

	function bit is_bset(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0010100 && insn.funct3 == RiscVOpcode32Op::BSET;
	endfunction

	function bit is_sub(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32Op::SUB;
	endfunction

	function bit is_xnor(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32Op::XNOR;
	endfunction

	function bit is_sra(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32Op::SRA;
	endfunction

	function bit is_orn(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32Op::ORN;
	endfunction

	function bit is_andn(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100000 && insn.funct3 == RiscVOpcode32Op::ANDN;
	endfunction

	function bit is_bclr(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100100 && insn.funct3 == RiscVOpcode32Op::BCLR;
	endfunction

	function bit is_bext(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0100100 && insn.funct3 == RiscVOpcode32Op::BEXT;
	endfunction

	function bit is_binv(Insn32 insn);
		return opcode_is_op(insn) && insn.funct7 == 7'b0110100 && insn.funct3 == RiscVOpcode32Op::BINV;
	endfunction
endpackage
