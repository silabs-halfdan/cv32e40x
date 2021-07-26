
// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Andreas Traber - atraber@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                                                                            //
// Design Name:    cv32e40x_ff_one                                            //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Find First One                                             //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module cv32e40x_ff_one
#(
  parameter LEN = 32
)
(
  input  logic [LEN-1:0]         in_i,

  output logic [$clog2(LEN)-1:0] first_one_o,
  output logic                   no_ones_o
);
  
  logic [LEN/2**1-1:0] s3;
  logic [LEN/2**2-1:0] s2;
  logic [LEN/2**3-1:0] s1;
  logic [LEN/2**4-1:0] s0;
  
  always_comb begin
    
    if(in_i[31:16] == 16'h0000) begin
      first_one_o[4] = 1;
      s3 = in_i[15:0]; end
    else begin
      first_one_o[4] = 0;
      s3 = in_i[31:16];
    end //if
    
    if(s3[15:8] == 8'h00) begin
      first_one_o[3] = 1;
      s2 = s3[7:0]; end
    else begin
      first_one_o[3] = 0;
      s2 = s3[15:8];
    end //if
    
    if(s2[7:4] == 4'h0) begin
      first_one_o[2] = 1;
      s1 = s2[3:0]; end
    else begin
      first_one_o[2] = 0;
      s1 = s2[7:4];
    end //if
    
    if(s1[3:2] == 2'b00) begin
      first_one_o[1] = 1;
      s0 = s1[1:0]; end
    else begin
      first_one_o[1] = 0;
      s0 = s1[3:2];
    end //if
   
    first_one_o[0] = !s0[1];
  end //always
  assign no_ones_o = &first_one_o & !in_i;

endmodule
