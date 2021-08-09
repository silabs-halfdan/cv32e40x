// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////
// Engineer:       Matthias Baer - baermatt@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Michael Gautschi - gautschi@iis.ee.ethz.ch                 //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                 Halfdan Bechmann - halfdan.bechmann@silabs.com             //
//                 Arjan Bink - arjan.bink@silabs.com                         //
//                                                                            //
// Design Name:    ALU                                                        //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Arithmetic logic unit of the pipelined processor           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////
// Shifter based on https://github.com/riscv/riscv-bitmanip/blob/main-history///
// verilog/rvb_shifter/rvb_shifter.v                                          //
//                                                                            //
// Copyright (C) 2019  Claire Wolf <claire@symbioticeda.com>                  //
//                                                                            //
// Permission to use, copy, modify, and/or distribute this software for any   //
// purpose with or without fee is hereby granted, provided that the above     //
// copyright notice and this permission notice appear in all copies.          //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES   //
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF           //
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR    //
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES     //
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN      //
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF    //
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.             //
////////////////////////////////////////////////////////////////////////////////

module cv32e40x_alu import cv32e40x_pkg::*;
(
  input  alu_opcode_e       operator_i,
  input  logic [31:0]       operand_a_i,
  input  logic [31:0]       operand_b_i,

  output logic [31:0]       result_o,
  output logic              cmp_result_o,

  // Divider interface towards CLZ
  input logic               div_clz_en_i,
  input logic [31:0]        div_clz_data_rev_i,
  output logic [5:0]        div_clz_result_o,

  // Divider interface towards shifter
  input logic               div_shift_en_i,
  input logic [5:0]         div_shift_amt_i,
  output logic [31:0]       div_op_b_shifted_o
);

  ////////////////////////////////////
  //     _       _     _            //
  //    / \   __| | __| | ___ _ __  //
  //   / _ \ / _` |/ _` |/ _ \ '__| //
  //  / ___ \ (_| | (_| |  __/ |    //
  // /_/   \_\__,_|\__,_|\___|_|    //
  //                                //
  ////////////////////////////////////

  // Adder is used for:
  //
  // - ALU_ADD, ALU_SUB
  // 
  // Currently not used for ALU_B_SH1ADD, ALU_B_SH2ADD, ALU_B_SH3ADD

  logic [32:0] adder_in_a, adder_in_b;
  logic [31:0] adder_result;
  logic [33:0] adder_result_expanded;
  logic        adder_subtract;

  assign adder_subtract = operator_i[3];

  // Prepare carry
  assign adder_in_a = {operand_a_i,                                 1'b1          };
  assign adder_in_b = {adder_subtract ? ~operand_b_i : operand_b_i, adder_subtract};

  // Actual adder
  assign adder_result_expanded = $unsigned(adder_in_a) + $unsigned(adder_in_b);
  assign adder_result = adder_result_expanded[32:1];

  ////////////////////////////////////////
  //  ____  _   _ ___ _____ _____       //
  // / ___|| | | |_ _|  ___|_   _|      //
  // \___ \| |_| || || |_    | |        //
  //  ___) |  _  || ||  _|   | |        //
  // |____/|_| |_|___|_|     |_|        //
  //                                    //
  ////////////////////////////////////////

  // Shifter is used for:
  //
  // - ALU_SLL, ALU_SRA, ALU_SRL
  // - ALU_B_ROL, ALU_B_ROR
  // - ALU_B_BEXT, ALU_B_BSET, ALU_B_BCLR, ALU_B_BINV 
  //
  // - DIV_DIVU, DIV_DIVU, DIV_REM, DIV_REMU

  logic [5:0]  shifter_shamt;           // Shift amount
  logic        shifter_rshift;          // Shift right
  logic [31:0] shifter_aa, shifter_bb;
  logic [63:0] shifter_tmp;
  logic [31:0] shifter_result;

  assign shifter_rshift = operator_i[2];

  always_comb begin
    if (div_shift_en_i) begin
      shifter_shamt =  {1'b0, div_shift_amt_i[4:0]};    // DIV(U), REM(U) always use shift left
    end else if (shifter_rshift) begin
      shifter_shamt = -{1'b0, operand_b_i[4:0]};
    end else begin
      shifter_shamt =  {1'b0, operand_b_i[4:0]};
    end
  end

  always_comb begin
    // Defaults (ALU_SLL, ALU_SRL, ALU_B_BEXT, DIV_DIVU, DIV_DIVU, DIV_REM, DIV_REMU)
    shifter_aa = div_shift_en_i ? operand_b_i : operand_a_i;
    shifter_bb = 32'h0;

    unique case (operator_i)
      ALU_SRA : begin
        shifter_bb = {32{operand_a_i[31]}};
      end
      ALU_B_ROL,
      ALU_B_ROR : begin
        shifter_bb = operand_a_i;
      end
      ALU_B_BSET,
      ALU_B_BCLR,
      ALU_B_BINV : begin
        shifter_aa = 32'h1;
      end
      default: ;
    endcase
  end

  always_comb begin
    shifter_tmp = {shifter_bb, shifter_aa};
    shifter_tmp = shifter_shamt[5] ? {shifter_tmp[31:0], shifter_tmp[63:32]} : shifter_tmp;
    shifter_tmp = shifter_shamt[4] ? {shifter_tmp[47:0], shifter_tmp[63:48]} : shifter_tmp;
    shifter_tmp = shifter_shamt[3] ? {shifter_tmp[55:0], shifter_tmp[63:56]} : shifter_tmp;
    shifter_tmp = shifter_shamt[2] ? {shifter_tmp[59:0], shifter_tmp[63:60]} : shifter_tmp;
    shifter_tmp = shifter_shamt[1] ? {shifter_tmp[61:0], shifter_tmp[63:62]} : shifter_tmp;
    shifter_tmp = shifter_shamt[0] ? {shifter_tmp[62:0], shifter_tmp[63:63]} : shifter_tmp;
  end

  always_comb begin
    shifter_result = shifter_tmp[31:0];

    unique case (operator_i)
      ALU_B_BEXT : shifter_result =       32'h1 &  shifter_tmp[31:0];
      ALU_B_BSET : shifter_result = operand_a_i |  shifter_tmp[31:0];
      ALU_B_BCLR : shifter_result = operand_a_i & ~shifter_tmp[31:0];
      ALU_B_BINV : shifter_result = operand_a_i ^  shifter_tmp[31:0];
      default: ;
    endcase
  end

  assign div_op_b_shifted_o = shifter_tmp[31:0];

  //////////////////////////////////////////////////////////////////
  // Shift and add

  logic [31:0] result_shnadd;
  
  assign result_shnadd = (operand_a_i << ((operator_i == ALU_B_SH1ADD) ? 1 : (operator_i == ALU_B_SH2ADD) ? 2 : 3)) + operand_b_i; // todo: consider alternatives

  //////////////////////////////////////////////////////////////////
  //   ____ ___  __  __ ____   _    ____  ___ ____   ___  _   _   //
  //  / ___/ _ \|  \/  |  _ \ / \  |  _ \|_ _/ ___| / _ \| \ | |  //
  // | |  | | | | |\/| | |_) / _ \ | |_) || |\___ \| | | |  \| |  //
  // | |__| |_| | |  | |  __/ ___ \|  _ < | | ___) | |_| | |\  |  //
  //  \____\___/|_|  |_|_| /_/   \_\_| \_\___|____/ \___/|_| \_|  //
  //                                                              //
  //////////////////////////////////////////////////////////////////

  // Comparator used for:
  //
  // - ALU_EQ, ALU_NE, ALU_GE, ALU_GEU, ALU_LT, ALU_LTU
  // - ALU_SLT, ALU_SLTU   
  // - ALU_B_MIN, ALU_B_MINU, ALU_B_MAX, ALU_B_MAXU

  logic is_equal;
  logic is_greater;     // Handles both signed and unsigned forms
  logic is_signed;

  assign is_signed = operator_i[3];
  assign is_equal = (operand_a_i == operand_b_i);
  assign is_greater = $signed({operand_a_i[31] & is_signed, operand_a_i}) > $signed({operand_b_i[31] & is_signed, operand_b_i});

  // Generate comparison result
  always_comb
  begin
    cmp_result_o = is_equal;
    unique case (operator_i)
      ALU_EQ          : cmp_result_o = is_equal;
      ALU_NE          : cmp_result_o = !is_equal;
      ALU_GE, ALU_GEU : cmp_result_o = is_greater || is_equal;
      ALU_LT, ALU_LTU : cmp_result_o = !(is_greater || is_equal);

      default: ;
    endcase
  end

  //////////////////////////////////////////////////////////////////
  // Min/max
  
  logic [31:0] min_minu_result;
  logic [31:0] max_maxu_result;

  assign min_minu_result = (!is_greater) ? operand_a_i : operand_b_i;
  assign max_maxu_result = ( is_greater) ? operand_a_i : operand_b_i;

  /////////////////////////////////////////////////////////////////////
  //   ____  _ _      ____                  _      ___               //
  //  | __ )(_) |_   / ___|___  _   _ _ __ | |_   / _ \ _ __  ___    //
  //  |  _ \| | __| | |   / _ \| | | | '_ \| __| | | | | '_ \/ __|   //
  //  | |_) | | |_  | |__| (_) | |_| | | | | |_  | |_| | |_) \__ \_  //
  //  |____/|_|\__|  \____\___/ \__,_|_| |_|\__|  \___/| .__/|___(_) //
  //                                                   |_|           //
  /////////////////////////////////////////////////////////////////////

  logic [31:0] clz_data_in;
  logic [4:0]  ff1_result; // holds the index of the first '1'
  logic        ff_no_one;  // if no ones are found
  logic [ 5:0] cpop_result;
  logic [31:0] operand_a_rev;

  assign clz_data_in = div_clz_en_i ? div_clz_data_rev_i :
                       (operator_i == ALU_B_CTZ) ? operand_a_i : operand_a_rev;

  // Bit reverse operand_a for bit counting
  generate
    genvar k;
    for (k = 0; k < 32; k++)
    begin : gen_operand_a_rev
      assign operand_a_rev[k] = operand_a_i[31-k];
    end
  endgenerate


  /////////////////
  // Bitcounting //
  /////////////////

  // The bit-counter structure computes the number of set bits in its operand. Partial results
  // (from left to right) are needed to compute the control masks for computation of bext/bdep
  // by the butterfly network, if implemented.
  // For pcnt, clz and ctz, only the end result is used.

  logic [31:0] bitcnt_bits;
  logic [31:0] bitcnt_mask_op;
  logic [31:0] bitcnt_bit_mask;
  logic [ 5:0] bitcnt_partial [32];


  // Bit-mask generation for clz and ctz:
  // The bit mask is generated by spreading the lowest-order set bit in the operand to all
  // higher order bits. The resulting mask is inverted to cover the lowest order zeros. In order
  // to create the bit mask for leading zeros, the input operand needs to be reversed.
  assign bitcnt_mask_op = clz_data_in;

  always_comb begin
    bitcnt_bit_mask = bitcnt_mask_op;
    bitcnt_bit_mask |= bitcnt_bit_mask << 1;
    bitcnt_bit_mask |= bitcnt_bit_mask << 2;
    bitcnt_bit_mask |= bitcnt_bit_mask << 4;
    bitcnt_bit_mask |= bitcnt_bit_mask << 8;
    bitcnt_bit_mask |= bitcnt_bit_mask << 16;
    bitcnt_bit_mask = ~bitcnt_bit_mask;
  end


  assign bitcnt_bits = (operator_i == ALU_B_CPOP) ? operand_a_i : bitcnt_bit_mask & ~bitcnt_mask_op;

  // The parallel prefix counter is of the structure of a Brent-Kung Adder. In the first
  // log2(width) stages, the sum of the n preceding bit lines is computed for the bit lines at
  // positions 2**n-1 (power-of-two positions) where n denotes the current stage.
  // In stage n=log2(width), the count for position width-1 (the MSB) is finished.
  // For the intermediate values, an inverse adder tree then computes the bit counts for the bit
  // lines at positions
  // m = 2**(n-1) + i*2**(n-2), where i = [1 ... width / 2**(n-1)-1] and n = [log2(width) ... 2].
  // Thus, at every subsequent stage the result of two previously unconnected sub-trees is
  // summed, starting at the node summing bits [width/2-1 : 0] and [3*width/4-1: width/2]
  // and moving to iteratively sum up all the sub-trees.
  // The inverse adder tree thus features log2(width) - 1 stages the first of these stages is a
  // single addition at position 3*width/4 - 1. It does not interfere with the last
  // stage of the primary adder tree. These stages can thus be folded together, resulting in a
  // total of 2*log2(width)-2 stages.
  // For more details refer to R. Brent, H. T. Kung, "A Regular Layout for Parallel Adders",
  // (1982).
  // For a bitline at position p, only bits
  // bitcnt_partial[max(i, such that p % log2(i) == 0)-1 : 0] are needed for generation of the
  // butterfly network control signals. The adders in the intermediate value adder tree thus need
  // not be full 5-bit adders. We leave the optimization to the synthesis tools.
  //
  // Consider the following 8-bit example for illustraton.
  //
  // let bitcnt_bits = 8'babcdefgh.
  //
  //                   a  b  c  d  e  f  g  h
  //                   | /:  | /:  | /:  | /:
  //                   |/ :  |/ :  |/ :  |/ :
  // stage 1:          +  :  +  :  +  :  +  :
  //                   |  : /:  :  |  : /:  :
  //                   |,--+ :  :  |,--+ :  :
  // stage 2:          +  :  :  :  +  :  :  :
  //                   |  :  |  : /:  :  :  :
  //                   |,-----,--+ :  :  :  : ^-primary adder tree
  // stage 3:          +  :  +  :  :  :  :  : -------------------------
  //                   :  | /| /| /| /| /|  : ,-intermediate adder tree
  //                   :  |/ |/ |/ |/ |/ :  :
  // stage 4           :  +  +  +  +  +  :  :
  //                   :  :  :  :  :  :  :  :
  // bitcnt_partial[i] 7  6  5  4  3  2  1  0

  always_comb begin
    bitcnt_partial = '{default: '0};
    // stage 1
    for (int unsigned i=1; i<32; i+=2) begin
      bitcnt_partial[i] = {5'h0, bitcnt_bits[i]} + {5'h0, bitcnt_bits[i-1]};
    end
    // stage 2
    for (int unsigned i=3; i<32; i+=4) begin
      bitcnt_partial[i] = bitcnt_partial[i-2] + bitcnt_partial[i];
    end
    // stage 3
    for (int unsigned i=7; i<32; i+=8) begin
      bitcnt_partial[i] = bitcnt_partial[i-4] + bitcnt_partial[i];
    end
    // stage 4
    for (int unsigned i=15; i <32; i+=16) begin
      bitcnt_partial[i] = bitcnt_partial[i-8] + bitcnt_partial[i];
    end
    // stage 5
    bitcnt_partial[31] = bitcnt_partial[15] + bitcnt_partial[31];
    // ^- primary adder tree
    // -------------------------------
    // ,-intermediate value adder tree
    bitcnt_partial[23] = bitcnt_partial[15] + bitcnt_partial[23];

    // stage 6
    for (int unsigned i=11; i<32; i+=8) begin
      bitcnt_partial[i] = bitcnt_partial[i-4] + bitcnt_partial[i];
    end

    // stage 7
    for (int unsigned i=5; i<32; i+=4) begin
      bitcnt_partial[i] = bitcnt_partial[i-2] + bitcnt_partial[i];
    end
    // stage 8
    bitcnt_partial[0] = {5'h0, bitcnt_bits[0]};
    for (int unsigned i=2; i<32; i+=2) begin
      bitcnt_partial[i] = bitcnt_partial[i-1] + {5'h0, bitcnt_bits[i]};
    end
  end


  // Divider assumes CLZ returning 32 when there are no zeros (as per CLZ spec)
  //assign div_clz_result_o = ff_no_one ? 6'd32 : ff1_result;
  //assign div_clz_result_o = (|bitcnt_partial[31]) ? bitcnt_partial[31] : 6'd32;
  assign div_clz_result_o = bitcnt_partial[31];

  assign cpop_result = bitcnt_partial[31];


  ////////////////////////////////////////////////////////
  //   ____                 _ _     __  __              //
  //  |  _ \ ___  ___ _   _| | |_  |  \/  |_   ___  __  //
  //  | |_) / _ \/ __| | | | | __| | |\/| | | | \ \/ /  //
  //  |  _ <  __/\__ \ |_| | | |_  | |  | | |_| |>  <   //
  //  |_| \_\___||___/\__,_|_|\__| |_|  |_|\__,_/_/\_\  //
  //                                                    //
  ////////////////////////////////////////////////////////

  always_comb
  begin
    result_o = 32'h0;

    // RV32I
    unique case (operator_i)
      // Bitwise operators
      ALU_AND    : result_o = operand_a_i &  operand_b_i;
      ALU_OR     : result_o = operand_a_i |  operand_b_i;
      ALU_XOR    : result_o = operand_a_i ^  operand_b_i;
      ALU_B_ANDN : result_o = operand_a_i & ~operand_b_i;
      ALU_B_ORN  : result_o = operand_a_i | ~operand_b_i;
      ALU_B_XNOR : result_o = operand_a_i ^ ~operand_b_i;

      // Adder Operations
      ALU_ADD,
      ALU_SUB : result_o = adder_result;

      // Shift Operations
      ALU_SLL,
      ALU_SRL,
      ALU_SRA,
      ALU_B_ROL,
      ALU_B_ROR,
      ALU_B_BSET,
      ALU_B_BCLR,
      ALU_B_BINV,
      ALU_B_BEXT   : result_o = shifter_result;

      // Comparisons
      ALU_SLT, ALU_SLTU: result_o = {31'b0, !(is_greater || is_equal)};

      // Shift and add
      ALU_B_SH1ADD,
      ALU_B_SH2ADD,
      ALU_B_SH3ADD : result_o = result_shnadd;

      ALU_B_CLZ, 
      ALU_B_CTZ    : result_o = {26'h0, div_clz_result_o};
      ALU_B_CPOP   : result_o = {26'h0, cpop_result};


      ALU_B_MIN,
      ALU_B_MINU   : result_o = min_minu_result;
      ALU_B_MAX,
      ALU_B_MAXU   : result_o = max_maxu_result;

      ALU_B_ORC_B  : result_o = {{(8){|operand_a_i[31:24]}}, {(8){|operand_a_i[23:16]}}, {(8){|operand_a_i[15:8]}}, {(8){|operand_a_i[7:0]}}};

      ALU_B_REV8   : result_o = {operand_a_i[7:0], operand_a_i[15:8], operand_a_i[23:16], operand_a_i[31:24]};

      ALU_B_SEXT_B : result_o = {{(24){operand_a_i[ 7]}}, operand_a_i[ 7:0]};
      ALU_B_SEXT_H : result_o = {{(16){operand_a_i[15]}}, operand_a_i[15:0]};

      default: ;
    endcase

  end

endmodule // cv32e40x_alu
