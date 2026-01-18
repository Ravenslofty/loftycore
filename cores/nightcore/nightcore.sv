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

package nc_uop;

	typedef enum logic [4:0] {
		Illegal,
		JumpConditional,
		Load,
		Store,
		Add,
		SetIfLessThan,
		Xor,
		Or,
		And,
		ShiftRight,
		CountTrailingZeroes,
		CountPopulation,
		SignExtend,
		OrCombine,
		Zip,
		Unzip,
		Minimum
	} Opcode;

	typedef struct packed {
		logic        complt_valid;
		logic        complt_value;
		logic        compeq_valid;
		logic        compeq_value;
		logic        rs1_byte_reverse;
		logic        rs1_bit_reverse;
		logic        rs2_is_imm;
		logic        rs2_is_single_bit;
		logic        rs2_invert;
		logic        rd_bit_reverse; // also used to distinguish register [JALR]/immediate [JAL/B__] JumpConditional
		logic        carry_in;       // also used to distinguish rotate vs shift
		logic        is_signed;
		logic        is_frontend_decoded;
		Opcode       op;
	} Control;

	typedef struct packed {
		logic [4:0]  rs1;
		logic [4:0]  rs2;
		logic [31:0] imm;
		logic [4:0]  rd;
		logic [31:0] next_pc;
		logic [31:0] alt_next_pc;
		logic [31:0] pc;
		Control      ctrl;
	} Uop;

endpackage

module nc_fe_decoder(
	input  RiscV::Insn32 insn,
	input  logic [31:0]  pc,

	output nc_uop::Uop   uop
);
	// I - short immediates and loads
	wire [31:0] imm_i   = RiscV::immediate_i_sext(insn);

	// S - stores
	wire [31:0] imm_s   = RiscV::immediate_s(insn);

	// B - conditionals
	wire [31:0] imm_b   = RiscV::immediate_b(insn);

	// U - long immediates
	wire [31:0] imm_u   = RiscV::immediate_u(insn);

	// J - unconditional jumps
	wire [31:0] imm_j   = RiscV::immediate_j(insn);

	wire insn_has_imm_i = |{
		RiscV::opcode_is_load(insn),
		RiscV::opcode_is_jalr(insn),
		RiscV::opcode_is_op_imm(insn),
		RiscV::opcode_is_system(insn)
	};

	// we need to override shift amount to allow [B]REV8 to be implemented as shift-by-zero
	wire imm_is_zero = |{
		RiscV::is_rev8(insn),
		RiscV::is_brev8(insn)
	};

	always_comb begin
		uop.rs1 = (RiscV::opcode_is_lui(insn) || RiscV::opcode_is_auipc(insn)) ? '0 : insn.rs1;
		uop.rs2 = insn.rs2;
		uop.rd  = RiscV::opcode_is_branch(insn) ? '0 : insn.rd;
		unique if (insn_has_imm_i)
			uop.imm = imm_is_zero ? '0 : imm_i;
		else if (RiscV::opcode_is_store(insn))
			uop.imm = imm_s;
		else if (RiscV::opcode_is_lui(insn))
			uop.imm = imm_u;
		else if (RiscV::opcode_is_auipc(insn))
			uop.imm = imm_u + pc;
		else if (RiscV::opcode_is_jal(insn))
			uop.imm = imm_j;
		else
			uop.imm = '0;
	end

	// decode: next-pc/alt-pc
	wire [31:0] decode_sequential_pc = pc + 4;
	wire [31:0] decode_branch_pc     = pc + imm_b;
	wire [31:0] decode_jump_pc       = pc + imm_j;

	assign uop.next_pc     = RiscV::opcode_is_jal(insn)    ? decode_jump_pc   : decode_sequential_pc;
	assign uop.alt_next_pc = RiscV::opcode_is_branch(insn) ? decode_branch_pc : decode_sequential_pc;
	assign uop.pc          = pc;

	// uop control field
	assign uop.ctrl.complt_valid = |{
		RiscV::is_blt(insn),
		RiscV::is_bge(insn),
		RiscV::is_bltu(insn),
		RiscV::is_bgeu(insn)
	};
	assign uop.ctrl.complt_value = |{
		RiscV::is_blt(insn),
		RiscV::is_bltu(insn),
		RiscV::is_min(insn),
		RiscV::is_minu(insn)
	};
	assign uop.ctrl.compeq_valid = |{
		RiscV::is_beq(insn),
		RiscV::is_bne(insn)
	};
	assign uop.ctrl.compeq_value = |{
		RiscV::is_beq(insn)
	};

	wire is_shift_left = RiscV::is_sll(insn) || RiscV::is_slli(insn) || RiscV::is_rol(insn);
	assign uop.ctrl.rs1_byte_reverse = is_shift_left || RiscV::is_rev8(insn)  || RiscV::is_clz(insn);
	assign uop.ctrl.rs1_bit_reverse  = is_shift_left || RiscV::is_brev8(insn) || RiscV::is_clz(insn);

	assign uop.ctrl.rs2_is_imm = |{
		// upper immediates,
		RiscV::opcode_is_lui(insn),
		RiscV::opcode_is_auipc(insn),
		// immediate shifts
		RiscV::is_slli(insn),
		RiscV::is_srli(insn),
		RiscV::is_srai(insn),
		RiscV::is_bexti(insn),
		// bit/byte reverse
		RiscV::is_rev8(insn),
		RiscV::is_brev8(insn),
		// immediate comparisons
		RiscV::is_slti(insn),
		RiscV::is_sltiu(insn),
		// immediate logic ops
		RiscV::is_xori(insn),
		RiscV::is_ori(insn),
		RiscV::is_andi(insn),
		RiscV::is_addi(insn),
		RiscV::is_rori(insn),
		// immediate single-bit logic ops
		RiscV::is_bclri(insn),
		RiscV::is_bseti(insn),
		RiscV::is_binvi(insn),
		// count leading zeroes
		RiscV::is_clz(insn),
		// loads
		RiscV::opcode_is_load(insn),
		// stores
		RiscV::opcode_is_store(insn),
		// jumps
		RiscV::opcode_is_jal(insn),
		RiscV::opcode_is_jalr(insn)
	};

	// we repurpose the otherwise well-used rs2_is_single_bit to distinguish BEXT vs shift/rotate
	assign uop.ctrl.rs2_is_single_bit = |{
		RiscV::is_bclr(insn),
		RiscV::is_bclri(insn),
		RiscV::is_binv(insn),
		RiscV::is_binvi(insn),
		RiscV::is_bset(insn),
		RiscV::is_bseti(insn),
		RiscV::is_bext(insn),
		RiscV::is_bexti(insn)
	};
	assign uop.ctrl.rs2_invert = |{
		RiscV::is_sub(insn),
		RiscV::is_xnor(insn),
		RiscV::is_orn(insn),
		RiscV::is_andn(insn),
		RiscV::is_bclri(insn),
		RiscV::is_bclr(insn)
	};

	// we repurpose the otherwise-unused rd_bit_reverse to distinguish JALR vs JAL/BRANCH.
	assign uop.ctrl.rd_bit_reverse = is_shift_left || RiscV::is_jalr(insn);

	// we repurpose the otherwise-unused carry_in to distinguish shift vs rotate.
	assign uop.ctrl.carry_in = |{
		RiscV::is_sub(insn),
		RiscV::is_rol(insn),
		RiscV::is_ror(insn),
		RiscV::is_rori(insn)
	};

	assign uop.ctrl.is_signed = |{
		// signed shifts
		RiscV::is_sra(insn),
		RiscV::is_srai(insn),
		// signed comparisons
		RiscV::is_blt(insn),
		RiscV::is_bge(insn),
		RiscV::is_slt(insn),
		RiscV::is_min(insn),
		RiscV::is_max(insn),
		RiscV::is_slti(insn)
	};

	wire is_jump_conditional = |{
		RiscV::is_beq(insn),
		RiscV::is_bne(insn),
		RiscV::is_blt(insn),
		RiscV::is_bge(insn),
		RiscV::is_bltu(insn),
		RiscV::is_bgeu(insn),
		RiscV::opcode_is_jal(insn),
		RiscV::is_jalr(insn)
	};

	wire is_add_op = |{
		RiscV::is_add(insn),
		RiscV::is_addi(insn),
		RiscV::is_sub(insn),
		RiscV::opcode_is_lui(insn),
		RiscV::opcode_is_auipc(insn)
	};

	wire is_slt_op = |{
		RiscV::is_slt(insn),
		RiscV::is_slti(insn),
		RiscV::is_sltu(insn),
		RiscV::is_sltiu(insn)
	};

	wire is_xor_op = |{
		RiscV::is_xor(insn),
		RiscV::is_xori(insn),
		RiscV::is_xnor(insn),
		RiscV::is_binv(insn),
		RiscV::is_binvi(insn)
	};

	wire is_or_op = |{
		RiscV::is_or(insn),
		RiscV::is_ori(insn),
		RiscV::is_orn(insn),
		RiscV::is_bset(insn),
		RiscV::is_bseti(insn)
	};

	wire is_and_op = |{
		RiscV::is_and(insn),
		RiscV::is_andi(insn),
		RiscV::is_andn(insn),
		RiscV::is_bclr(insn),
		RiscV::is_bclri(insn)
	};

	wire is_shift_op = |{
		RiscV::is_sll(insn),
		RiscV::is_slli(insn),
		RiscV::is_srl(insn),
		RiscV::is_srli(insn),
		RiscV::is_sra(insn),
		RiscV::is_srai(insn),
		RiscV::is_rol(insn),
		RiscV::is_ror(insn),
		RiscV::is_rori(insn),
		RiscV::is_bext(insn),
		RiscV::is_bexti(insn),
		RiscV::is_rev8(insn),
		RiscV::is_brev8(insn)
	};

	wire is_ctz_op = |{
		RiscV::is_clz(insn),
		RiscV::is_ctz(insn)
	};

	wire is_min_op = |{
		RiscV::is_min(insn),
		RiscV::is_max(insn),
		RiscV::is_minu(insn),
		RiscV::is_maxu(insn)
	};

	always_comb begin
		uop.ctrl.is_frontend_decoded = 1;
		unique if (is_jump_conditional)
			uop.ctrl.op = nc_uop::JumpConditional;
		else if (is_add_op)
			uop.ctrl.op = nc_uop::Add;
		else if (is_slt_op)
			uop.ctrl.op = nc_uop::SetIfLessThan;
		else if (is_xor_op)
			uop.ctrl.op = nc_uop::Xor;
		else if (is_or_op)
			uop.ctrl.op = nc_uop::Or;
		else if (is_and_op)
			uop.ctrl.op = nc_uop::And;
		else if (is_shift_op)
			uop.ctrl.op = nc_uop::ShiftRight;
		else if (is_ctz_op)
			uop.ctrl.op = nc_uop::CountTrailingZeroes;
		else if (is_min_op)
			uop.ctrl.op = nc_uop::Minimum;
		else begin
			uop.ctrl.is_frontend_decoded = 0;
			uop.ctrl.op = nc_uop::Illegal;
		end
	end
endmodule

`define NERV_CSR

`ifdef NERV_CSR
	/**********************
	 *  CSR DECLARATIONS  *
	 **********************/

	// Note: The Memory-Mapped Machine Timers (mtime and timecmp) are not
	// part of the processor core itself. It's up to the SoC to provide
	// this part of the RISC-V M-Mode Spec.

	// FIXME: Additional instructions: ECALL, EBREAK, MRET, WFI

`define NERV_MACHINE_CSRS /* Machine Information CSRs */				\
	/* all of these CSRs are mandatory but can legally be all 0 */			\
	`NERV_CSR_VAL_MRO(mvendorid,         12'h F11, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRO(marchid,           12'h F12, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRO(mimpid,            12'h F13, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRO(mhartid,           12'h F14, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRO(mconfigptr,        12'h F15, 32'h 0000_0000)

`define NERV_TRAP_SETUP_CSRS /* Machine Trap Setup CSRs */				\
	`NERV_CSR_REG_MRW(mstatus,           12'h 300, 32'h 0000_0000)			\
											\
	/* misa can legally return all zeros */						\
	`NERV_CSR_REG_MRW(misa,              12'h 301, 32'h 0000_0000)			\
											\
	/* medeleg and mideleg should only exist if S mode is available */		\
/*	`NERV_CSR_REG_MRW(medeleg,           12'h 302, 32'h 0000_0000) */  		\
/*	`NERV_CSR_REG_MRW(mideleg,           12'h 303, 32'h 0000_0000) */  		\
											\
	`NERV_CSR_REG_MRW(mie,               12'h 304, 32'h 0000_0000)			\
											\
	/* mtvec can be implemented as read-only */					\
	`NERV_CSR_REG_MRW(mtvec,             12'h 305, 32'h 0000_0000)			\
											\
	/* mcounteren should only exist if U mode is available */			\
/*	`NERV_CSR_REG_MRW(mcounteren,        12'h 306, 32'h 0000_0000) */		\
											\
	`NERV_CSR_REG_MRW(mstatush,          12'h 310, 32'h 0000_0000)

`define NERV_TRAP_HANDLING_CSRS /* Machine Trap Handling CSRs */			\
	`NERV_CSR_REG_MRW(mscratch,          12'h 340, 32'h 0000_0000)	 		\
	`NERV_CSR_REG_MRW(mepc,              12'h 341, 32'h 0000_0000)			\
	`NERV_CSR_REG_MRW(mcause,            12'h 342, 32'h 0000_0000)			\
	`NERV_CSR_REG_MRW(mtval,             12'h 343, 32'h 0000_0000)			\
	`NERV_CSR_REG_MRW(mip,               12'h 344, 32'h 0000_0000)			\
											\
	/* mtinst and mtval2 added by hypervisor extension */				\
/*	`NERV_CSR_REG_MRW(mtinst,            12'h 34A, 32'h 0000_0000) */		\
/*	`NERV_CSR_REG_MRW(mtval2,            12'h 34B, 32'h 0000_0000) */

`define NERV_MACHINE_CONFIG_CSRS /* machine configuration CSRs */			\
	/* menvcfg should only exist if U mode is available */				\
/*	`NERV_CSR_REG_MRW(menvcfg,           12'h 30A, 32'h 0000_0000) */		\
/*	`NERV_CSR_REG_MRW(menvcfgh,          12'h 31A, 32'h 0000_0000) */		\
											\
	/* mseccfg not yet fully defined, and is not currently required */		\
/*	`NERV_CSR_REG_MRW(mseccfg,           12'h 747, 32'h 0000_0000) */		\
/*	`NERV_CSR_REG_MRW(mseccfgh,          12'h 757, 32'h 0000_0000) */

`ifdef NERV_PMP
/* PMP is optional and can be implemented with 0, 16, or 64 address CSRS */
`define NERV_PMP_CFG_CSRS /* Machine Memory Protection Config CSRs */			\
	/* PMP configuration is 8-bits long, */						\
	/* so each cfg controls four PMPs in RV32 */					\
	`NERV_CSR_VAL_MRW(pmpcfg0,           12'h 3A0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg1,           12'h 3A1, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg2,           12'h 3A2, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg3,           12'h 3A3, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg4,           12'h 3A4, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg5,           12'h 3A5, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg6,           12'h 3A6, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg7,           12'h 3A7, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg8,           12'h 3A8, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg9,           12'h 3A9, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg10,          12'h 3AA, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg11,          12'h 3AB, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg12,          12'h 3AC, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg13,          12'h 3AD, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg14,          12'h 3AE, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpcfg15,          12'h 3AF, 32'h 0000_0000)

`define NERV_PMP_ADDR_CSRS /* Machine Memory Protection Addr CSRs */			\
	`NERV_CSR_VAL_MRW(pmpaddr0,          12'h 3B0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr1,          12'h 3B1, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr2,          12'h 3B2, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr3,          12'h 3B3, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr4,          12'h 3B4, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr5,          12'h 3B5, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr6,          12'h 3B6, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr7,          12'h 3B7, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr8,          12'h 3B8, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr9,          12'h 3B9, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr10,         12'h 3BA, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr11,         12'h 3BB, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr12,         12'h 3BC, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr13,         12'h 3BD, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr14,         12'h 3BE, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr15,         12'h 3BF, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr16,         12'h 3C0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr17,         12'h 3C1, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr18,         12'h 3C2, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr19,         12'h 3C3, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr20,         12'h 3C4, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr21,         12'h 3C5, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr22,         12'h 3C6, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr23,         12'h 3C7, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr24,         12'h 3C8, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr25,         12'h 3C9, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr26,         12'h 3CA, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr27,         12'h 3CB, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr28,         12'h 3CC, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr29,         12'h 3CD, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr30,         12'h 3CE, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr31,         12'h 3CF, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr32,         12'h 3D0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr33,         12'h 3D1, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr34,         12'h 3D2, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr35,         12'h 3D3, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr36,         12'h 3D4, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr37,         12'h 3D5, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr38,         12'h 3D6, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr39,         12'h 3D7, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr40,         12'h 3D8, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr41,         12'h 3D9, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr42,         12'h 3DA, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr43,         12'h 3DB, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr44,         12'h 3DC, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr45,         12'h 3DD, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr46,         12'h 3DE, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr47,         12'h 3DF, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr48,         12'h 3E0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr49,         12'h 3E1, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr50,         12'h 3E2, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr51,         12'h 3E3, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr52,         12'h 3E4, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr53,         12'h 3E5, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr54,         12'h 3E6, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr55,         12'h 3E7, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr56,         12'h 3E8, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr57,         12'h 3E9, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr58,         12'h 3EA, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr59,         12'h 3EB, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr60,         12'h 3EC, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr61,         12'h 3ED, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr62,         12'h 3EE, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRW(pmpaddr63,         12'h 3EF, 32'h 0000_0000)

`else
`define NERV_PMP_CFG_CSRS
`define NERV_PMP_ADDR_CSRS
`endif

`define NERV_COUNTER_CSRS /* Machine Counter/Timers CSRs */				\
	`NERV_CSR_ARR_DEF(hpm_counter, 32)						\
	`NERV_CSR_ARR_MRW(hpm_counter, 0, mcycle,            12'h B00)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 2, minstret,          12'h B02)			\
											\
	/* mhpmcounter3..31 provide hardware performance monitoring */ 			\
	/* the counted event is defined by the corresponding hpm_event CSR */		\
	`NERV_CSR_ARR_MRW(hpm_counter, 3,  mhpmcounter3,     12'h B03)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 4,  mhpmcounter4,     12'h B04)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 5,  mhpmcounter5,     12'h B05)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 6,  mhpmcounter6,     12'h B06)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 7,  mhpmcounter7,     12'h B07)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 8,  mhpmcounter8,     12'h B08)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 9,  mhpmcounter9,     12'h B09)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 10, mhpmcounter10,    12'h B0A)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 11, mhpmcounter11,    12'h B0B)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 12, mhpmcounter12,    12'h B0C)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 13, mhpmcounter13,    12'h B0D)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 14, mhpmcounter14,    12'h B0E)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 15, mhpmcounter15,    12'h B0F)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 16, mhpmcounter16,    12'h B10)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 17, mhpmcounter17,    12'h B11)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 18, mhpmcounter18,    12'h B12)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 19, mhpmcounter19,    12'h B13)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 20, mhpmcounter20,    12'h B14)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 21, mhpmcounter21,    12'h B15)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 22, mhpmcounter22,    12'h B16)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 23, mhpmcounter23,    12'h B17)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 24, mhpmcounter24,    12'h B18)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 25, mhpmcounter25,    12'h B19)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 26, mhpmcounter26,    12'h B1A)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 27, mhpmcounter27,    12'h B1B)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 28, mhpmcounter28,    12'h B1C)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 29, mhpmcounter29,    12'h B1D)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 30, mhpmcounter30,    12'h B1E)			\
	`NERV_CSR_ARR_MRW(hpm_counter, 31, mhpmcounter31,    12'h B1F)			\
											\
	`NERV_CSR_ARR_DEF(hpm_counterh, 32)						\
	`NERV_CSR_ARR_MRW(hpm_counterh, 0, mcycleh,          12'h B80)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 2, minstreth,        12'h B82)			\
											\
	`NERV_CSR_ARR_MRW(hpm_counterh, 3,  mhpmcounter3h,   12'h B83)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 4,  mhpmcounter4h,   12'h B84)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 5,  mhpmcounter5h,   12'h B85)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 6,  mhpmcounter6h,   12'h B86)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 7,  mhpmcounter7h,   12'h B87)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 8,  mhpmcounter8h,   12'h B88)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 9,  mhpmcounter9h,   12'h B89)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 10, mhpmcounter10h,  12'h B8A)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 11, mhpmcounter11h,  12'h B8B)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 12, mhpmcounter12h,  12'h B8C)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 13, mhpmcounter13h,  12'h B8D)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 14, mhpmcounter14h,  12'h B8E)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 15, mhpmcounter15h,  12'h B8F)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 16, mhpmcounter16h,  12'h B90)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 17, mhpmcounter17h,  12'h B91)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 18, mhpmcounter18h,  12'h B92)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 19, mhpmcounter19h,  12'h B93)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 20, mhpmcounter20h,  12'h B94)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 21, mhpmcounter21h,  12'h B95)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 22, mhpmcounter22h,  12'h B96)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 23, mhpmcounter23h,  12'h B97)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 24, mhpmcounter24h,  12'h B98)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 25, mhpmcounter25h,  12'h B99)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 26, mhpmcounter26h,  12'h B9A)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 27, mhpmcounter27h,  12'h B9B)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 28, mhpmcounter28h,  12'h B9C)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 29, mhpmcounter29h,  12'h B9D)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 30, mhpmcounter30h,  12'h B9E)			\
	`NERV_CSR_ARR_MRW(hpm_counterh, 31, mhpmcounter31h,  12'h B9F)

`define NERV_COUNTER_SETUP_CSRS /* Machine Counter Setup CSRs */			\
	/* mcountinhibit is optional */							\
/*	`NERV_CSR_REG_MRW(mcountinhibit,     12'h 320, 32'h 0000_0000) */		\
											\
	/* mhpmevent3..31 select which hardware event the corresponding */		\
	/* mhpmcounter should be triggered by and thus count */				\
	`NERV_CSR_ARR_DEF(hpm_event, 32)						\
	`NERV_CSR_ARR_MRW(hpm_event, 3,  mhpmevent3,         12'h 323)			\
	`NERV_CSR_ARR_MRW(hpm_event, 4,  mhpmevent4,         12'h 324)			\
	`NERV_CSR_ARR_MRW(hpm_event, 5,  mhpmevent5,         12'h 325)			\
	`NERV_CSR_ARR_MRW(hpm_event, 6,  mhpmevent6,         12'h 326)			\
	`NERV_CSR_ARR_MRW(hpm_event, 7,  mhpmevent7,         12'h 327)			\
	`NERV_CSR_ARR_MRW(hpm_event, 8,  mhpmevent8,         12'h 328)			\
	`NERV_CSR_ARR_MRW(hpm_event, 9,  mhpmevent9,         12'h 329)			\
	`NERV_CSR_ARR_MRW(hpm_event, 10, mhpmevent10,        12'h 32A)			\
	`NERV_CSR_ARR_MRW(hpm_event, 11, mhpmevent11,        12'h 32B)			\
	`NERV_CSR_ARR_MRW(hpm_event, 12, mhpmevent12,        12'h 32C)			\
	`NERV_CSR_ARR_MRW(hpm_event, 13, mhpmevent13,        12'h 32D)			\
	`NERV_CSR_ARR_MRW(hpm_event, 14, mhpmevent14,        12'h 32E)			\
	`NERV_CSR_ARR_MRW(hpm_event, 15, mhpmevent15,        12'h 32F)			\
	`NERV_CSR_ARR_MRW(hpm_event, 16, mhpmevent16,        12'h 330)			\
	`NERV_CSR_ARR_MRW(hpm_event, 17, mhpmevent17,        12'h 331)			\
	`NERV_CSR_ARR_MRW(hpm_event, 18, mhpmevent18,        12'h 332)			\
	`NERV_CSR_ARR_MRW(hpm_event, 19, mhpmevent19,        12'h 333)			\
	`NERV_CSR_ARR_MRW(hpm_event, 20, mhpmevent20,        12'h 334)			\
	`NERV_CSR_ARR_MRW(hpm_event, 21, mhpmevent21,        12'h 335)			\
	`NERV_CSR_ARR_MRW(hpm_event, 22, mhpmevent22,        12'h 336)			\
	`NERV_CSR_ARR_MRW(hpm_event, 23, mhpmevent23,        12'h 337)			\
	`NERV_CSR_ARR_MRW(hpm_event, 24, mhpmevent24,        12'h 338)			\
	`NERV_CSR_ARR_MRW(hpm_event, 25, mhpmevent25,        12'h 339)			\
	`NERV_CSR_ARR_MRW(hpm_event, 26, mhpmevent26,        12'h 33A)			\
	`NERV_CSR_ARR_MRW(hpm_event, 27, mhpmevent27,        12'h 33B)			\
	`NERV_CSR_ARR_MRW(hpm_event, 28, mhpmevent28,        12'h 33C)			\
	`NERV_CSR_ARR_MRW(hpm_event, 29, mhpmevent29,        12'h 33D)			\
	`NERV_CSR_ARR_MRW(hpm_event, 30, mhpmevent30,        12'h 33E)			\
	`NERV_CSR_ARR_MRW(hpm_event, 31, mhpmevent31,        12'h 33F)

`define NERV_CUSTOM_CSRS /* Custom CSR for testing */					\
	`NERV_CSR_REG_MRW(custom,            12'h BC0, 32'h 0000_0000)			\
	`NERV_CSR_VAL_MRO(custom_ro,         12'h FC0, 32'h dead_beef)

`define NERV_CSRS			\
	`NERV_MACHINE_CSRS		\
	`NERV_TRAP_SETUP_CSRS		\
	`NERV_TRAP_HANDLING_CSRS	\
	`NERV_MACHINE_CONFIG_CSRS	\
	`NERV_PMP_CFG_CSRS		\
	`NERV_PMP_ADDR_CSRS		\
	`NERV_COUNTER_CSRS		\
	`NERV_COUNTER_SETUP_CSRS	\
	`NERV_CUSTOM_CSRS
`endif

module nightcore #(
	parameter [31:0] RESET_ADDR = 32'h 0000_0000,
	parameter integer NUMREGS = 32
) (
	input clock,
	input reset,
	input stall,
	output trap,

`ifdef NERV_RVFI
	output reg        rvfi_valid,
	output reg [63:0] rvfi_order,
	output reg [31:0] rvfi_insn,
	output reg        rvfi_trap,
	output reg        rvfi_halt,
	output reg        rvfi_intr,
	output reg [ 1:0] rvfi_mode,
	output reg [ 1:0] rvfi_ixl,
	output reg [ 4:0] rvfi_rs1_addr,
	output reg [ 4:0] rvfi_rs2_addr,
	output reg [31:0] rvfi_rs1_rdata,
	output reg [31:0] rvfi_rs2_rdata,
	output reg [ 4:0] rvfi_rd_addr,
	output reg [31:0] rvfi_rd_wdata,
	output reg [31:0] rvfi_pc_rdata,
	output reg [31:0] rvfi_pc_wdata,

`ifdef NERV_CSR
`define NERV_CSR_REG_MRW(NAME, ADDR, VALUE)			\
	output reg [31:0] rvfi_csr_``NAME``_rmask,		\
	output reg [31:0] rvfi_csr_``NAME``_wmask,		\
	output reg [31:0] rvfi_csr_``NAME``_rdata,		\
	output reg [31:0] rvfi_csr_``NAME``_wdata,

`define NERV_CSR_VAL_MRW(NAME, ADDR, VALUE)			\
	`NERV_CSR_REG_MRW(NAME, ADDR, VALUE)

`define NERV_CSR_VAL_MRO(NAME, ADDR, VALUE)			\
	`NERV_CSR_REG_MRW(NAME, ADDR, VALUE)

`define NERV_CSR_ARR_DEF(ARRAY, DEPTH)

`define NERV_CSR_ARR_MRW(ARRAY, INDEX, NAME, ADDR)		\
	output reg [31:0] rvfi_csr_``NAME``_rmask,			\
	output reg [31:0] rvfi_csr_``NAME``_wmask,			\
	output reg [31:0] rvfi_csr_``NAME``_rdata,			\
	output reg [31:0] rvfi_csr_``NAME``_wdata,

`NERV_CSRS
`undef NERV_CSR_REG_MRW
`undef NERV_CSR_VAL_MRW
`undef NERV_CSR_VAL_MRO
`undef NERV_CSR_ARR_DEF
`undef NERV_CSR_ARR_MRW
`endif

	output reg [31:0] rvfi_mem_addr,
	output reg [ 3:0] rvfi_mem_rmask,
	output reg [ 3:0] rvfi_mem_wmask,
	output reg [31:0] rvfi_mem_rdata,
	output reg [31:0] rvfi_mem_wdata,

`ifdef NERV_FAULT
	output reg        rvfi_mem_fault,
	output reg [ 3:0] rvfi_mem_fault_rmask,
	output reg [ 3:0] rvfi_mem_fault_wmask,
`endif
`endif

	// we have 2 external memories
	// one is instruction memory
	output [31:0] imem_addr,
	input  [31:0] imem_data,

	// the other is data memory
	output        dmem_valid,
	output [31:0] dmem_addr,
	output [ 3:0] dmem_wstrb,
	output [31:0] dmem_wdata,
	input  [31:0] dmem_rdata,

`ifdef NERV_FAULT
	input         imem_fault,
	input         dmem_fault,
`endif
	// interrupt inputs
	input  [31:0] irq
);

`ifndef NERV_FAULT
	wire imem_fault = 0;
	wire dmem_fault = 0;
`endif

	reg mem_wr_enable;
	reg [31:0] mem_wr_addr;
	reg [31:0] mem_wr_data;
	reg [3:0] mem_wr_strb;

	reg mem_rd_enable;
	reg [31:0] mem_rd_addr;
	reg [4:0] mem_rd_reg;
	reg [4:0] mem_rd_func;

	reg mem_rd_enable_q;
	reg [4:0] mem_rd_reg_q;
	reg [4:0] mem_rd_func_q;

	reg mem_wr_enable_q;

	// delayed copies of mem_rd (and mem_wr for NERV_FAULTS)
	always @(posedge clock) begin
		if (!stall) begin
			mem_rd_enable_q <= mem_rd_enable;
			mem_rd_reg_q <= mem_rd_reg;
			mem_rd_func_q <= mem_rd_func;
			mem_wr_enable_q <= mem_wr_enable;
		end
		if (reset) begin
			mem_rd_enable_q <= 0;
		end
	end

	// memory signals
	assign dmem_valid = mem_wr_enable || mem_rd_enable;
	assign dmem_addr  = mem_wr_enable ? mem_wr_addr : mem_rd_enable ? mem_rd_addr : 32'h x;
	assign dmem_wstrb = mem_wr_enable ? mem_wr_strb : mem_rd_enable ? 4'h 0 : 4'h x;
	assign dmem_wdata = mem_wr_enable ? mem_wr_data : 32'h x;

	// registers, instruction reg, program counter, next pc
	reg [31:0] regfile [0:NUMREGS-1];
	RiscV::Insn32 insn;
	reg [31:0] npc;
	reg [31:0] pc;

	reg [31:0] imem_addr_q;

	always @(posedge clock) begin
		imem_addr_q <= imem_addr;
	end

	// instruction memory pointer
	assign imem_addr = npc;
	assign insn = imem_data;

	// decode: miscellaneous
	nc_uop::Uop uop;
	nc_fe_decoder decoder(.*);

	// rs1 and rs2 are source for the instruction
	wire [31:0] rs1_value = (uop.rs1 == 0) ? 0 : regfile[uop.rs1];
	wire [31:0] rs2_value = (uop.rs2 == 0) ? 0 : regfile[uop.rs2];

	// setup for I, S, B & J type instructions
	// I - short immediates and loads
	wire [11:0] imm_i      = RiscV::immediate_i(insn);


	localparam MCAUSE_MACHINE_SOFTWARE_INTERRUPT = 32'h80000003;
	localparam MCAUSE_MACHINE_TIMER_INTERRUPT    = 32'h80000007;
	localparam MCAUSE_MACHINE_EXTERNAL_INTERRUPT = 32'h8000000b;

	localparam MCAUSE_INSN_ADDRESS_MISALIGNED  = 32'h00000000;
	localparam MCAUSE_INSN_ACCESS_FAULT        = 32'h00000001;
	localparam MCAUSE_INVALID_INSTRUCTION      = 32'h00000002;
	localparam MCAUSE_BREAKPOINT               = 32'h00000003;
	localparam MCAUSE_LOAD_ADDRESS_MISALIGNED  = 32'h00000004;
	localparam MCAUSE_LOAD_ACCESS_FAULT        = 32'h00000005;
	localparam MCAUSE_STORE_ADDRESS_MISALIGNED = 32'h00000006;
	localparam MCAUSE_STORE_ACCESS_FAULT       = 32'h00000007;
	localparam MCAUSE_ECALL_M_MODE             = 32'h0000000b;

	localparam IRQ_MASK = 32'hFFFF0888;

	// execute: shifter
	wire [4:0]  shift_rs2      = uop.ctrl.rs2_is_imm ? uop.imm[4:0] : rs2_value[4:0];
	wire [31:0] shift_byte_reverse;
	wire [31:0] shift_input;
	wire [31:0] shift_signed   = $signed(shift_input) >>> shift_rs2;
	wire [31:0] shift_unsigned = shift_input >> shift_rs2;
	wire [31:0] shift_rotate   = shift_input << (32 - shift_rs2);
	wire [31:0] shift_output   = (uop.ctrl.is_signed ? shift_signed : shift_unsigned) | (uop.ctrl.carry_in ? shift_rotate : 0);
	wire [31:0] shift_result;

	for (genvar i=0; i<32; i=i+1) begin: gen_bitrev
		localparam curr_byte = i / 8;
		localparam curr_bit  = i % 8;
		assign shift_byte_reverse[i] = uop.ctrl.rs1_byte_reverse ? rs1_value[8*(3-curr_byte) + curr_bit] : rs1_value[8*curr_byte + curr_bit];
		assign shift_input[i] = uop.ctrl.rs1_bit_reverse ? shift_byte_reverse[8*curr_byte + (7-curr_bit)] : shift_byte_reverse[8*curr_byte + curr_bit];
		assign shift_result[i] = uop.ctrl.rd_bit_reverse ? shift_output[31-i] : shift_output[i];
	end

	// execute: count bits
	logic [31:0] ctz_result;
	logic [31:0] cpop_result;
	always_comb begin
		ctz_result  = '0;
		cpop_result = '0;
		for (int i=32; i>0; i=i-1) ctz_result = shift_input[i-1] ? 0 : ctz_result + 1;
		for (int i=0; i<32; i=i+1) cpop_result = cpop_result + 32'(rs1_value[i]);
	end

	// execute: less than comparator
	wire [31:0] complt_rs2 = uop.ctrl.rs2_is_imm ? uop.imm : rs2_value;
	wire complt_signed     = $signed(rs1_value) < $signed(complt_rs2);
	wire complt_unsigned   = rs1_value < complt_rs2;
	wire complt_result     = uop.ctrl.is_signed ? complt_signed : complt_unsigned;

	// execute: equality comparator
	wire compeq_result     = rs1_value == rs2_value;

	// execute: arithmetic/logic unit
	wire [31:0] alu_rs2_s1 = uop.ctrl.rs2_is_imm ? 1 << uop.imm[4:0] : 1 << rs2_value[4:0];
	wire [31:0] alu_rs2_s2 = uop.ctrl.rs2_is_single_bit ? alu_rs2_s1 : complt_rs2;
	wire [31:0] alu_rs2    = uop.ctrl.rs2_invert ? ~alu_rs2_s2 : alu_rs2_s2;

	wire [31:0] add_result = rs1_value + alu_rs2 + 32'(uop.ctrl.carry_in);
	wire [31:0] xor_result = rs1_value ^ alu_rs2;
	wire [31:0] or_result  = rs1_value | alu_rs2;
	wire [31:0] and_result = rs1_value & alu_rs2;

	// next write, next destination (rd) value & register
	reg next_wr;
	reg [31:0] next_rd;
	reg [4:0] wr_rd;

	// illegal instruction registers
	reg illinsn;

	reg reset_q;
	wire running = !stall && !reset && !reset_q;

	// action to perform this cycle
	reg cycle_intr; // cycle to start fetching new PC for interrupts
	reg cycle_insn; // first non-trapping cycle of an instruction
	reg cycle_trap; // trap in the first cycle of an instruction
	reg cycle_late_wr; // 2nd cycle for mem_rd_enable instructions

`ifdef NERV_FAULT
	reg cycle_dmem_fault;
`endif

	assign trap = cycle_trap;

`ifdef NERV_CSR
	/*********************
	 *  CSR DEFINITIONS  *
	 *********************/

	reg [4:0] irq_num;

	reg        csr_ack;
	reg [31:0] csr_rdval;
	reg [31:0] csr_next;

	wire imem_valid = !mem_rd_enable_q && !mem_wr_enable_q && !imem_fault;
	wire [ 1:0] csr_mode = (running && imem_valid && irq_num == '0 && insn.opcode == RiscVOpcode32::SYSTEM) ? insn.funct3[1:0] : 2'b 00; // 00=None, 01=RW, 10=RS, 11=RC
	wire [11:0] csr_addr = imm_i;
	wire [31:0] csr_rsval = insn.funct3[2] ? 32'(uop.rs1) : rs1_value;
	wire csr_ro = csr_mode != 0 && (csr_mode != 2'b01 && uop.rs1 == 0);

	integer hpm_idx, hpm_increment, hpm_event;

`define NERV_CSR_REG_MRW(NAME, ADDR, VALUE)				\
	wire csr_``NAME``_sel = csr_mode != 0 && csr_addr == ADDR;		\
	reg [31:0] csr_``NAME``_value;					\
	reg [31:0] csr_``NAME``_wdata;					\
	reg [31:0] csr_``NAME``_next;					\
	always @(posedge clock) begin					\
		csr_``NAME``_value <= csr_``NAME``_next;		\
		if (reset || reset_q)					\
			csr_``NAME``_value <= VALUE;			\
	end

`define NERV_CSR_VAL_MRW(NAME, ADDR, VALUE)				\
	wire csr_``NAME``_sel = csr_mode != 0 && csr_addr == ADDR;		\
	wire [31:0] csr_``NAME``_wdata = csr_``NAME``_sel ? csr_next : csr_``NAME``_value; \
	localparam [31:0] csr_``NAME``_value = VALUE;

`define NERV_CSR_VAL_MRO(NAME, ADDR, VALUE)				\
	wire csr_``NAME``_sel = csr_ro != 0 && csr_addr == ADDR;		\
	localparam [31:0] csr_``NAME``_value = VALUE;

`define NERV_CSR_ARR_DEF(ARRAY, DEPTH)					\
	integer ARRAY``_idx;						\
	wire [DEPTH-1:0] csr_``ARRAY``_sel;			\
	reg [(DEPTH*32)-1:0] csr_``ARRAY``_value;			\
	reg [(DEPTH*32)-1:0] csr_``ARRAY``_wdata;			\
	reg [(DEPTH*32)-1:0] csr_``ARRAY``_next;			\
	always @(posedge clock) begin					\
		csr_``ARRAY``_value <= csr_``ARRAY``_next;		\
		if (reset || reset_q)					\
			csr_``ARRAY``_value <= 'b0;			\
	end

`define NERV_CSR_ARR_MRW(ARRAY, INDEX, NAME, ADDR)				\
	wire csr_``NAME``_sel = csr_mode != 0 && csr_addr == ADDR;			\
	wire [31:0] csr_``NAME``_value = csr_``ARRAY``_value[(INDEX)*32 +: 32];	\
	wire [31:0] csr_``NAME``_wdata = csr_``ARRAY``_wdata[(INDEX)*32 +: 32];	\
	wire [31:0] csr_``NAME``_next  = csr_``ARRAY``_next[(INDEX)*32 +: 32];  \
	assign csr_``ARRAY``_sel[INDEX] = csr_``NAME``_sel;

`NERV_CSRS
`undef NERV_CSR_REG_MRW
`undef NERV_CSR_VAL_MRW
`undef NERV_CSR_VAL_MRO
`undef NERV_CSR_ARR_DEF
`undef NERV_CSR_ARR_MRW

	// dummy out missing select lines
	assign csr_hpm_event_sel[2:0] = 0;
	assign csr_hpm_counter_sel[1] = 0;
	assign csr_hpm_counterh_sel[1] = 0;

`endif // NERV_CSR

	wire [31:0] irq_en;
	assign irq_en = irq & csr_mie_value;

	// resolve interrupt priority
	always_comb begin
		if (irq_en[31]) irq_num = 5'd31;
		else if (irq_en[30]) irq_num = 5'd30;
		else if (irq_en[29]) irq_num = 5'd29;
		else if (irq_en[28]) irq_num = 5'd28;
		else if (irq_en[27]) irq_num = 5'd27;
		else if (irq_en[26]) irq_num = 5'd26;
		else if (irq_en[25]) irq_num = 5'd25;
		else if (irq_en[24]) irq_num = 5'd24;
		else if (irq_en[23]) irq_num = 5'd23;
		else if (irq_en[22]) irq_num = 5'd22;
		else if (irq_en[21]) irq_num = 5'd21;
		else if (irq_en[20]) irq_num = 5'd20;
		else if (irq_en[19]) irq_num = 5'd19;
		else if (irq_en[18]) irq_num = 5'd18;
		else if (irq_en[17]) irq_num = 5'd17;
		else if (irq_en[16]) irq_num = 5'd16;
		else if (irq_en[11]) irq_num = 5'd11;
		else if (irq_en[7]) irq_num = 5'd7;
		else if (irq_en[3]) irq_num = 5'd3;
		else irq_num = 5'd0;
	end

	reg [31:0] mem_rdata;

	always_comb begin
		// advance pc
		npc = pc + 4;

		// defaults for read, write
		next_wr = 0;
		next_rd = 0;
		cycle_intr = 0;
		cycle_trap = 0;
		cycle_insn = 0;
		cycle_late_wr = 0;
`ifdef NERV_FAULT
		cycle_dmem_fault = 0;
`endif
		wr_rd = uop.rd;

		illinsn = 0;

		mem_wr_enable = 0;
		mem_wr_addr = 32'hx;
		mem_wr_data = 32'hx;
		mem_wr_strb = 4'hx;

		mem_rd_enable = 0;
		mem_rd_addr = 32'hx;
		mem_rd_reg = 5'hx;
		mem_rd_func = 5'hx;

`ifdef NERV_CSR
		csr_ack = 0;
		csr_rdval = 'hx;

		unique case (1'b1)
`define NERV_CSR_REG_MRW(NAME, ADDR, VALUE)		\
			csr_mode != 0 && csr_``NAME``_sel: begin		\
				csr_ack = 1;				\
				csr_rdval = csr_``NAME``_value;	\
			end

`define NERV_CSR_VAL_MRW(NAME, ADDR, VALUE)		\
			csr_mode != 0 && csr_``NAME``_sel: begin		\
				csr_ack = 1;				\
				csr_rdval = csr_``NAME``_value;	\
			end

`define NERV_CSR_VAL_MRO(NAME, ADDR, VALUE)		\
			csr_ro != 0 && csr_``NAME``_sel: begin		\
				csr_ack = 1;				\
				csr_rdval = csr_``NAME``_value;	\
			end
`define NERV_CSR_ARR_DEF(ARRAY, DEPTH)
`define NERV_CSR_ARR_MRW(ARRAY, INDEX, NAME, ADDR)		\
	`NERV_CSR_REG_MRW(NAME, ADDR, 32'h 0000_0000)

`NERV_CSRS
`undef NERV_CSR_REG_MRW
`undef NERV_CSR_VAL_MRW
`undef NERV_CSR_VAL_MRO
`undef NERV_CSR_ARR_DEF
`undef NERV_CSR_ARR_MRW

			default: /* nothing */;
		endcase

		csr_next = csr_rdval;
		case (csr_mode)
			2'b 01 /* RW */: csr_next = csr_rsval;
			2'b 10 /* RS */: csr_next = csr_next | csr_rsval;
			2'b 11 /* RC */: csr_next = csr_next & ~csr_rsval;
		endcase

`define NERV_CSR_REG_MRW(NAME, ADDR, VALUE) \
		csr_``NAME``_wdata = csr_``NAME``_sel ? csr_next : csr_``NAME``_value; \
		csr_``NAME``_next = csr_``NAME``_wdata;

`define NERV_CSR_VAL_MRW(NAME, ADDR, VALUE)
`define NERV_CSR_VAL_MRO(NAME, ADDR, VALUE)
`define NERV_CSR_ARR_DEF(ARRAY, DEPTH)								\
		for (ARRAY``_idx=0; ARRAY``_idx < DEPTH; ARRAY``_idx=ARRAY``_idx+1) begin 	\
			csr_``ARRAY``_wdata[(ARRAY``_idx)*32 +: 32] = 				\
				csr_``ARRAY``_sel[ARRAY``_idx] 					\
				? csr_next 							\
				: csr_``ARRAY``_value[(ARRAY``_idx)*32 +: 32];			\
		end										\
		csr_``ARRAY``_next = csr_``ARRAY``_wdata;

`define NERV_CSR_ARR_MRW(ARRAY, INDEX, NAME, ADDR)

`NERV_CSRS
`undef NERV_CSR_REG_MRW
`undef NERV_CSR_VAL_MRW
`undef NERV_CSR_VAL_MRO
`undef NERV_CSR_ARR_DEF
`undef NERV_CSR_ARR_MRW

		for (hpm_idx=0; hpm_idx < 32; hpm_idx=hpm_idx+1) begin
			case (hpm_idx)
				0 /* mcycle */ : hpm_event = 32'h 1;
				2 /* minstret */ : hpm_event = 32'h 2;
				default:
					hpm_event = csr_hpm_event_next[(hpm_idx)*32 +: 32];
			endcase
			case (hpm_event)
				32'h 1 /* cycle counter */: hpm_increment = 1;
				32'h 2 /* instruction counter */: hpm_increment = running ? 1 : 0;
				32'h 3 /* memory writes */: hpm_increment = mem_wr_enable_q ? 1 : 0;
				default: begin
					csr_hpm_event_next[(hpm_idx)*32 +: 32] = 0;
					hpm_increment = 0;
				end
			endcase
			{csr_hpm_counterh_next[(hpm_idx)*32 +: 32], csr_hpm_counter_next[(hpm_idx)*32 +: 32]} =
				{csr_hpm_counterh_next[(hpm_idx)*32 +: 32], csr_hpm_counter_next[(hpm_idx)*32 +: 32]} + 64'(hpm_increment);
		end

	// mstatus & mstatush - Machine Status
	csr_mstatus_next[31] = 'b0; // SD is always 0 if FS, VS, and XS are not enabled
	csr_mstatus_next[30:23] = 'b0; // WPRI
	csr_mstatus_next[22] = 'b0; // TSR = 0 if no S
	csr_mstatus_next[21] = 'b0; // TW = 0 if no U or S
	csr_mstatus_next[20] = 'b0; // TVM = 0 if no S
	csr_mstatus_next[19] = 'b0; // MXR = 0 if no S
	csr_mstatus_next[18] = 'b0; // SUM = 0 if no S
	csr_mstatus_next[17] = 'b0; // MPRV = 0 if no U
	csr_mstatus_next[16:15] = 'b0; // XS = 0 if no user extensions
	csr_mstatus_next[14:13] = 'b0; // FS = 0 if no S and no floating point extension
	csr_mstatus_next[12:11] = 2'b11; // MPP = b11 if no U
	csr_mstatus_next[10:9] = 'b0; // VS = 0 if no vector extension
	csr_mstatus_next[8] = 'b0; // SPP = 0 if no S
	//csr_mstatus_next[7] = ; // MPIE controlled by trap handling
	csr_mstatus_next[6] = 'b0; // UBE = 0 if no U
	csr_mstatus_next[5] = 'b0; // SPIE = 0 if no S
	csr_mstatus_next[4] = 'b0; // WPRI
	//csr_mstatus_next[3] = ; // MIE controlled by code
	csr_mstatus_next[2] = 'b0; // WPRI
	csr_mstatus_next[1] = 'b0; // SIE = 0 if no S
	csr_mstatus_next[0] = 'b0; // WPRI

	csr_mstatush_next[31:6] = 'b0; // WPRI
	csr_mstatush_next[5] = 1'b0; // MBE = 1 if big endian, 0 if little endian
	csr_mstatush_next[4] = 'b0; // SBE = 0 if no S
	csr_mstatush_next[3:0] = 'b0; // WPRI

	// misa - Machine ISA
	// read-only 0 for unimplemented register
	csr_misa_next[31:20] = 'b0; // MXL = 1 for XLEN=32
	csr_misa_next[29:26] = 'b0; // 0
	csr_misa_next[25:0] = 'b0; // Extensions enabled

	// mie - Machine Interrupt-Enable
	// A bit in mie must be writable if the corresponding interrupt can ever become pending.
	// Bits of mie that are not writable must be read-only 0.
	//csr_mie_next[31:16] = 'b0; // bits 16 and above for custom/platform interrupts
	csr_mie_next[15:12] = 'b0; // 0
	//csr_mie_next[11] = 'b0; // MEIE - Machine-level External Interrupt Enable
	csr_mie_next[10] = 'b0; // 0
	csr_mie_next[9] = 'b0; // SEIE = 0 if no S
	csr_mie_next[8] = 'b0; // 0
	//csr_mie_next[7] = 'b0; // MTIE - Machine Timer Interrupt Enable
	csr_mie_next[6] = 'b0; // 0
	csr_mie_next[5] = 'b0; // STIE = 0 if no S
	csr_mie_next[4] = 'b0; // 0
	//csr_mie_next[3] = 'b0; // MSIE - Machine-level Software Interrupt Enable
	csr_mie_next[2] = 'b0; // 0
	csr_mie_next[1] = 'b0; // SSIE = 0 if no S
	csr_mie_next[0] = 'b0; // 0

	// mip - Machine Interrupt-Pending
	//csr_mip_next[31:16] = 'b0; // bits 16 and above for custom/platform interrupts
	//csr_mip_next[15:12] = 'b0; // 0
	//csr_mip_next[11] = 'b0; // MEIE - Machine-level External Interrupt Pending
	//csr_mip_next[10] = 'b0; // 0
	//csr_mip_next[9] = 'b0; // SEIE = 0 if no S
	//csr_mip_next[8] = 'b0; // 0
	//csr_mip_next[7] = 'b0; // MTIE - Machine Timer Interrupt Pending
	//csr_mip_next[6] = 'b0; // 0
	//csr_mip_next[5] = 'b0; // STIE = 0 if no S
	//csr_mip_next[4] = 'b0; // 0
	//csr_mip_next[3] = 'b0; // MSIE - Machine-level Software Interrupt Pending
	//csr_mip_next[2] = 'b0; // 0
	//csr_mip_next[1] = 'b0; // SSIE = 0 if no S
	//csr_mip_next[0] = 'b0; // 0
	csr_mip_next = irq & IRQ_MASK;

	// mtvec - Machine Trap-Vector Base-Address
	csr_mtvec_next[1] = 'b0; // MODE - keep high bit always 0

	// mcause - keep these bits at 0
	csr_mcause_next[30:5] ='b0;

	// mepc - keep alignment
	csr_mepc_next[1:0] = 'b0;

`endif // NERV_CSR

	// act on opcodes
	if (uop.ctrl.is_frontend_decoded) begin
		next_wr = 1;
		case (uop.ctrl.op)
			nc_uop::JumpConditional: begin
				next_wr = uop.rd != '0;
				next_rd = uop.alt_next_pc;

				if ((uop.ctrl.compeq_valid && compeq_result == uop.ctrl.compeq_value) ||
					(uop.ctrl.complt_valid && complt_result == uop.ctrl.complt_value))
					npc = uop.alt_next_pc;
				else if (uop.ctrl.rd_bit_reverse) // JALR
					npc = add_result & ~32'b1;
				else
					npc = uop.next_pc;

				if ((npc & 32'b11) != 0) begin
					illinsn = 1;
					npc = npc & ~32'b 11;
				end
			end
			nc_uop::Add:                 begin next_rd = add_result;         end
			nc_uop::SetIfLessThan:       begin next_rd = 32'(complt_result); end
			nc_uop::Xor:                 begin next_rd = xor_result;         end
			nc_uop::Or:                  begin next_rd = or_result;          end
			nc_uop::And:                 begin next_rd = and_result;         end
			nc_uop::ShiftRight:          begin next_rd = uop.ctrl.rs2_is_single_bit ? 32'(shift_result[0]) : shift_result; end
			nc_uop::CountTrailingZeroes: begin next_rd = ctz_result;   end
			nc_uop::Minimum:             begin next_rd = complt_result == uop.ctrl.complt_value ? rs1_value : rs2_value;   end
			default: illinsn = 1;
		endcase
	end else begin
			case (insn.opcode)
				// load from memory into rd: Load Byte, Load Halfword, Load Word, Load Byte Unsigned, Load Halfword Unsigned
				RiscVOpcode32::LOAD: begin
					mem_rd_addr = add_result;
					casez ({insn.funct3, mem_rd_addr[1:0]})
						5'b 000_zz /* LB  */,
						5'b 001_z0 /* LH  */,
						5'b 010_00 /* LW  */,
						5'b 100_zz /* LBU */,
						5'b 101_z0 /* LHU */: begin
							mem_rd_enable = 1;
							mem_rd_reg = uop.rd;
							mem_rd_func = {mem_rd_addr[1:0], insn.funct3};
							mem_rd_addr = {mem_rd_addr[31:2], 2'b00};
						end
						default: illinsn = 1;
					endcase
				end
				// store to memory instructions: Store Byte, Store Halfword, Store Word
				RiscVOpcode32::STORE: begin
					mem_wr_addr = add_result;
					casez ({insn.funct3, mem_wr_addr[1:0]})
						5'b 000_zz /* SB */,
						5'b 001_z0 /* SH */,
						5'b 010_00 /* SW */: begin
							mem_wr_enable = 1;
							mem_wr_data = rs2_value;
							mem_wr_strb = 4'b 1111;
							case (insn.funct3)
								3'b 000 /* SB  */: begin mem_wr_strb = 4'b 0001; end
								3'b 001 /* SH  */: begin mem_wr_strb = 4'b 0011; end
								3'b 010 /* SW  */: begin mem_wr_strb = 4'b 1111; end
								default: illinsn = 1;
							endcase
							mem_wr_data = mem_wr_data << (8*mem_wr_addr[1:0]);
							mem_wr_strb = mem_wr_strb << mem_wr_addr[1:0];
							mem_wr_addr = {mem_wr_addr[31:2], 2'b 00};
						end
						default: illinsn = 1;
					endcase
				end
				// immediate ALU instructions: Add Immediate, Set Less Than Immediate, Set Less Than Immediate Unsigned, XOR Immediate,
				// OR Immediate, And Immediate, Shift Left Logical Immediate, Shift Right Logical Immediate, Shift Right Arithmetic Immediate
				RiscVOpcode32::OP_IMM: begin
					casez ({insn.funct7, insn.funct3})
						// Zbb: Basic bit-manipulation
						10'b 0110000_001: begin
							casez (insn[24:20])
								5'b 00000 /* CLZ    */,
								5'b 00001 /* CTZ    */: begin next_wr = 1; next_rd = 0; for (int i=32; i>0; i=i-1) next_rd = shift_input[i-1] ? 0 : next_rd + 1; end
								5'b 00010 /* CPOP   */: begin next_wr = 1; next_rd = 0; for (int i=0; i<32; i=i+1) next_rd = next_rd + 32'(rs1_value[i]); end
								5'b 00100 /* SEXT.B */: begin next_wr = 1; next_rd = 32'($signed(rs1_value[7:0])); end
								5'b 00101 /* SEXT.H */: begin next_wr = 1; next_rd = 32'($signed(rs1_value[15:0])); end
								default: illinsn = 1;
							endcase
						end
						10'b 0010100_101 /* ORC.B */: begin next_wr = insn[24:20] == 5'b 00111; illinsn = !next_wr; next_rd = 0; for (int i=0; i<4; i=i+1) next_rd[i*8 +: 8] = {8{|rs1_value[i*8 +: 8]}}; end
						10'b 0000100_001 /* ZIP   */: begin next_wr = insn[24:20] == 5'b 01111; illinsn = !next_wr; next_rd = 0; for (int i=0; i<16; i=i+1) begin next_rd[2*i] = rs1_value[i]; next_rd[2*i+1] = rs1_value[i+16]; end end
						10'b 0000100_101 /* UNZIP */: begin next_wr = insn[24:20] == 5'b 01111; illinsn = !next_wr; next_rd = 0; for (int i=0; i<16; i=i+1) begin next_rd[i] = rs1_value[2*i]; next_rd[i+16] = rs1_value[2*i+1]; end end
						default: illinsn = 1;
					endcase
				end
				RiscVOpcode32::OP: begin
				// ALU instructions: Add, Subtract, Shift Left Logical, Set Left Than, Set Less Than Unsigned, XOR, Shift Right Logical,
				// Shift Right Arithmetic, OR, AND
					case ({insn.funct7, insn.funct3})
						// Zba: Address generation
						10'b 0010000_010 /* SH1ADD */: begin next_wr = 1; next_rd = rs2_value + {rs1_value[30:0], 1'b 0}; end
						10'b 0010000_100 /* SH2ADD */: begin next_wr = 1; next_rd = rs2_value + {rs1_value[29:0], 2'b 0}; end
						10'b 0010000_110 /* SH3ADD */: begin next_wr = 1; next_rd = rs2_value + {rs1_value[28:0], 3'b 0}; end
						// Zbb: Basic bit-manipulation
						10'b 0000100_100 /* PACK   */: begin next_wr = 1; next_rd = {rs2_value[15:0], rs1_value[15:0]}; end
						10'b 0000100_111 /* PACKH  */: begin next_wr = 1; next_rd = {16'b0, rs2_value[7:0], rs1_value[7:0]}; end
						// Zbc: Carry-less multiplication
						10'b 0000101_001 /* CLMUL  */: begin next_wr = 1; next_rd = 0; for (int i=0; i<32; i=i+1) next_rd = (rs2_value[i]) ? next_rd ^ (rs1_value << i) : next_rd; end
						10'b 0000101_011 /* CLMULH */: begin next_wr = 1; next_rd = 0; for (int i=1; i<32; i=i+1) next_rd = (((rs2_value >> i) & 32'b1) != 0) ? next_rd ^ (rs1_value >> (32 - i)) : next_rd; end
						10'b 0000101_010 /* CLMULR */: begin next_wr = 1; next_rd = 0; for (int i=0; i<32; i=i+1) next_rd = (rs2_value[i]) ? next_rd ^ (rs1_value >> (32 - i - 1)) : next_rd; end
						// Zbkx: Crossbar permutations
						10'b 0010100_010 /* XPERM4 */: begin next_wr = 1; next_rd = 0; for (int i=0; i<8; i=i+1) next_rd[i*4+:4] = 4'(rs1_value >> (rs2_value[i*4+:4])); end
						10'b 0010100_100 /* XPERM8 */: begin next_wr = 1; next_rd = 0; for (int i=0; i<4; i=i+1) next_rd[i*8+:8] = 8'(rs1_value >> (rs2_value[i*8+:8])); end
						default: illinsn = 1;
					endcase
				end
	`ifdef NERV_CSR
				RiscVOpcode32::SYSTEM: begin
					case (insn.funct3)
						3'b 000 : begin
							case ({insn.funct7, insn.rs2})
								12'b 0000000_00000 /* ECALL */:
									begin
										csr_mepc_next = { pc[31:2], 2'b00 };
										npc = csr_mtvec_value & ~3;
										csr_mcause_next = MCAUSE_ECALL_M_MODE;
										csr_mstatus_next[7] = csr_mstatus_value[3];  // save MIE to MPIE
										csr_mstatus_next[3] = 0; // MIE to 0
									end
								12'b 0000000_00001 /* EBREAK */:
									begin
										csr_mepc_next = { pc[31:2], 2'b00 };
										npc = csr_mtvec_value & ~3;
										csr_mcause_next = MCAUSE_BREAKPOINT;
										csr_mstatus_next[7] = csr_mstatus_value[3];  // save MIE to MPIE
										csr_mstatus_next[3] = 0; // MIE to 0
									end
								12'b 0011000_00010 /* MRET */:
									begin
										npc = csr_mepc_value;
										csr_mcause_next = 'b0;
										csr_mstatus_next[3] = csr_mstatus_value[7];  // restore MIE from MPIE
									end
								12'b 0001000_00101 /* WFI */:
									begin
										// implemented as NOP
									end
								default: illinsn = 1;
							endcase
						end
						default : begin
							if (csr_ack) begin
								next_wr = 1;
								next_rd = csr_rdval;
							end else
								illinsn = 1;
						end
					endcase
				end
	`endif
				default: illinsn = 1;
			endcase
		end

		if (reset || reset_q) begin
			// reset has the highest priority
			npc = RESET_ADDR;
			csr_mstatus_next[3] = 0; // MIE
		end else if (stall) begin
			// if this is a stall cycle, don't perform any action
			npc = pc;
`ifdef NERV_FAULT
		end else if (mem_rd_enable_q || mem_wr_enable_q) begin
			npc = pc;

			if (dmem_fault) begin
				cycle_dmem_fault = 1;
				csr_mepc_next[31:2] = pc[31:2];
				npc = csr_mtvec_value & ~3;
				csr_mcause_next = mem_wr_enable_q ? MCAUSE_STORE_ACCESS_FAULT : MCAUSE_LOAD_ACCESS_FAULT;
				csr_mcause_wdata = csr_mcause_next;
				csr_mstatus_next[7] = csr_mstatus_value[3];  // save MIE to MPIE
				csr_mstatus_next[3] = 0; // MIE to 0
			end else begin
				cycle_late_wr = 1;

				if (mem_rd_enable_q) begin
					wr_rd = mem_rd_reg_q;
					next_rd = mem_rdata;
				end
			end
`else
		end else if (mem_rd_enable_q) begin
			// if last cycle was a memory read, then this cycle is the 2nd part of it and imem_data will not be a valid instruction
			npc = pc;
			cycle_late_wr = 1;
			wr_rd = mem_rd_reg_q;
			next_rd = mem_rdata;
`endif
		end else if (irq_num != 0) begin
			// if there's a pending IRQ, take it
			csr_mepc_next = { pc[31:2], 2'b00 };
			csr_mcause_next = 1 << 31 | 32'(irq_num);
			if (csr_mtvec_value[0])
				npc = (csr_mtvec_value & ~3) + 32'(irq_num) << 2;
			else
				npc = csr_mtvec_value & ~3;
			csr_mstatus_next[7] = 1; // MPIE to 1
			csr_mstatus_next[3] = 0; // MIE to 0

			cycle_intr = 1;
		end else if (imem_fault || illinsn) begin
			// instruction fetch memory fault
			cycle_trap = 1;
			csr_mepc_next[31:2] = pc[31:2];
			npc = csr_mtvec_value & ~3;
			csr_mcause_next = imem_fault ? MCAUSE_INSN_ACCESS_FAULT : MCAUSE_INVALID_INSTRUCTION;
			csr_mcause_wdata = csr_mcause_next;
			csr_mstatus_next[7] = csr_mstatus_value[3];  // save MIE to MPIE
			csr_mstatus_next[3] = 0; // MIE to 0
		end else begin
			// the instruction is valid and nothing else has priority
			cycle_insn = 1;
		end

		if (!cycle_insn) begin
			next_wr = cycle_late_wr && mem_rd_enable_q;
			mem_rd_enable = 0;
			mem_wr_enable = 0;
		end
	end

`ifdef NERV_RVFI
	reg next_rvfi_intr;
	reg rvfi_trap_q;

`ifdef NERV_FAULT
	wire next_rvfi_valid = (cycle_insn && !mem_rd_enable && !mem_wr_enable) || cycle_trap || cycle_dmem_fault || cycle_late_wr;
`else
	wire next_rvfi_valid = (cycle_insn && !mem_rd_enable) || cycle_trap || cycle_late_wr;
`endif

`endif

	// mem read functions: Lower and Upper Bytes, signed and unsigned
	always @* begin
		mem_rdata = dmem_rdata >> (8*mem_rd_func_q[4:3]);
		case (mem_rd_func_q[2:0])
			3'b 000 /* LB  */: begin mem_rdata = 32'($signed(mem_rdata[7:0])); end
			3'b 001 /* LH  */: begin mem_rdata = 32'($signed(mem_rdata[15:0])); end
			3'b 100 /* LBU */: begin mem_rdata = 32'(mem_rdata[7:0]); end
			3'b 101 /* LHU */: begin mem_rdata = 32'(mem_rdata[15:0]); end
		endcase
	end

	// every cycle
	always @(posedge clock) begin
		reset_q <= reset || (reset_q && stall);

		// update pc
		pc <= npc;

		if (next_wr)
			regfile[wr_rd] <= next_rd;

`ifdef NERV_RVFI
		rvfi_valid <= next_rvfi_valid;

		if (cycle_intr)
			next_rvfi_intr <= 1;

		if (cycle_insn || cycle_late_wr || cycle_trap) begin
			rvfi_rd_addr <= next_wr ? wr_rd : 0;
			rvfi_rd_wdata <= next_wr && wr_rd ? next_rd : 0;
			rvfi_mem_rdata <= dmem_rdata;
		end

		if (cycle_insn || cycle_trap) begin
			next_rvfi_intr <= cycle_trap;
			rvfi_order <= rvfi_order + 1;
			rvfi_insn <= imem_fault ? 32'b0 : insn;
			rvfi_trap <= cycle_trap;
			rvfi_halt <= 0;
			rvfi_intr <= next_rvfi_intr;
			rvfi_mode <= 3;
			rvfi_ixl <= 1;
			rvfi_rs1_addr <= uop.rs1;
			rvfi_rs2_addr <= uop.rs2;
			rvfi_rs1_rdata <= rs1_value;
			rvfi_rs2_rdata <= rs2_value;
			rvfi_pc_rdata <= pc;
			rvfi_pc_wdata <= npc;
			if (dmem_valid) begin
				rvfi_mem_addr <= dmem_addr;
				case ({mem_rd_enable, insn.funct3})
					4'b 1_000 /* LB  */,
					4'b 1_100 /* LBU */: begin rvfi_mem_rmask <= 4'b 0001 << mem_rd_func[4:3]; end
					4'b 1_001 /* LH  */,
					4'b 1_101 /* LHU */: begin rvfi_mem_rmask <= 4'b 0011 << mem_rd_func[4:3]; end
					4'b 1_010 /* LW  */: begin rvfi_mem_rmask <= 4'b 1111 << mem_rd_func[4:3]; end
					default: rvfi_mem_rmask <= 0;
				endcase
				rvfi_mem_wmask <= dmem_wstrb;
				rvfi_mem_wdata <= dmem_wdata;
			end else begin
				rvfi_mem_addr <= 0;
				rvfi_mem_rmask <= 0;
				rvfi_mem_wmask <= 0;
				rvfi_mem_wdata <= 0;
			end
`ifdef NERV_FAULT
			rvfi_mem_fault <= imem_fault;
			rvfi_mem_fault_rmask <= 0;
			rvfi_mem_fault_wmask <= 0;
`endif
		end

`ifdef NERV_FAULT
		if (cycle_dmem_fault) begin
			next_rvfi_intr <= 1;
			rvfi_trap <= 1;
			rvfi_mem_fault <= 1;
			rvfi_rd_addr <= 0;
			rvfi_rd_wdata <= 0;

			rvfi_mem_fault_rmask <= rvfi_mem_rmask;
			rvfi_mem_fault_wmask <= rvfi_mem_wmask;

			rvfi_mem_rmask <= 0;
			rvfi_mem_wmask <= 0;
		end
`endif

		if (next_rvfi_valid) begin
`ifdef NERV_CSR
`define NERV_CSR_REG_MRW(NAME, ADDR, VALUE) \
			rvfi_csr_``NAME``_rmask <= 32'h ffff_ffff;	\
			rvfi_csr_``NAME``_wmask <= 32'h ffff_ffff;	\
			rvfi_csr_``NAME``_rdata <= csr_``NAME``_value;	\
			rvfi_csr_``NAME``_wdata <= csr_``NAME``_wdata;

`define NERV_CSR_VAL_MRW(NAME, ADDR, VALUE) \
	`NERV_CSR_REG_MRW(NAME, ADDR, VALUE)

`define NERV_CSR_VAL_MRO(NAME, ADDR, VALUE) \
			rvfi_csr_``NAME``_rmask <= 32'h ffff_ffff;	\
			rvfi_csr_``NAME``_wmask <= 32'h ffff_ffff;	\
			rvfi_csr_``NAME``_rdata <= csr_``NAME``_value;	\
			rvfi_csr_``NAME``_wdata <= csr_``NAME``_value;

`define NERV_CSR_ARR_DEF(ARRAY, DEPTH)
`define NERV_CSR_ARR_MRW(ARRAY, INDEX, NAME, ADDR) \
	`NERV_CSR_REG_MRW(NAME, ADDR, 32'h 0000_0000)

`NERV_CSRS
`undef NERV_CSR_REG_MRW
`undef NERV_CSR_VAL_MRW
`undef NERV_CSR_VAL_MRO
`undef NERV_CSR_ARR_DEF
`undef NERV_CSR_ARR_MRW
`endif
		end
`endif

		// reset
		if (reset || reset_q) begin
			pc <= RESET_ADDR - (reset ? 4 : 0);
`ifdef NERV_RVFI
			next_rvfi_intr <= 0;
			rvfi_valid <= 0;
			rvfi_order <= 0;
			rvfi_trap <= 0;
`endif
		end
	end


`ifdef NERV_DBGREGS
	wire [31:0] dbg_reg_x0  = 0;
	wire [31:0] dbg_reg_x1  = regfile[1];
	wire [31:0] dbg_reg_x2  = regfile[2];
	wire [31:0] dbg_reg_x3  = regfile[3];
	wire [31:0] dbg_reg_x4  = regfile[4];
	wire [31:0] dbg_reg_x5  = regfile[5];
	wire [31:0] dbg_reg_x6  = regfile[6];
	wire [31:0] dbg_reg_x7  = regfile[7];
	wire [31:0] dbg_reg_x8  = regfile[8];
	wire [31:0] dbg_reg_x9  = regfile[9];
	wire [31:0] dbg_reg_x10 = regfile[10];
	wire [31:0] dbg_reg_x11 = regfile[11];
	wire [31:0] dbg_reg_x12 = regfile[12];
	wire [31:0] dbg_reg_x13 = regfile[13];
	wire [31:0] dbg_reg_x14 = regfile[14];
	wire [31:0] dbg_reg_x15 = regfile[15];
	wire [31:0] dbg_reg_x16 = regfile[16];
	wire [31:0] dbg_reg_x17 = regfile[17];
	wire [31:0] dbg_reg_x18 = regfile[18];
	wire [31:0] dbg_reg_x19 = regfile[19];
	wire [31:0] dbg_reg_x20 = regfile[20];
	wire [31:0] dbg_reg_x21 = regfile[21];
	wire [31:0] dbg_reg_x22 = regfile[22];
	wire [31:0] dbg_reg_x23 = regfile[23];
	wire [31:0] dbg_reg_x24 = regfile[24];
	wire [31:0] dbg_reg_x25 = regfile[25];
	wire [31:0] dbg_reg_x26 = regfile[26];
	wire [31:0] dbg_reg_x27 = regfile[27];
	wire [31:0] dbg_reg_x28 = regfile[28];
	wire [31:0] dbg_reg_x29 = regfile[29];
	wire [31:0] dbg_reg_x30 = regfile[30];
	wire [31:0] dbg_reg_x31 = regfile[31];
`endif
endmodule
