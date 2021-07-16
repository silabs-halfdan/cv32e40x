module cv32e40x_clmul_sva
  import uvm_pkg::*;
  import cv32e40x_pkg::*;
  (// Module signals
   input logic [31:0] op_a_i,
   input logic [31:0] op_b_i,
   input logic [31:0] result_o
);

  ////////////////////////////////////////
  ////  Assertion on the algorithm    ////
  ////////////////////////////////////////

  
    function logic [31:0] clmul_spec(input [31:0] op_a_i, input [31:0] op_b_i);
      clmul_spec = '0;  
      for(integer i = 0; i < 32; i++) begin
        clmul_spec = ((op_b_i >> i) & 1) ? (clmul_spec ^ (op_a_i << i)) : clmul_spec;
      end
    endfunction : clmul_spec
  
  logic [31:0] result_expect;
  assign result_expect = clmul_spec(op_a_i, op_b_i);
  //assign result_expect = op_a_i * op_b_i;
  a_clmul_result : // check carrless multiplication result for CLMUL according to the SPEC algorithm
    assert property (
                    result_o == result_expect)
  else `uvm_error("clmult", "CLMUL result check failed")

endmodule // cv32e40x_clmul
