module cv32e40x_alu_b_clmul(
  input logic [31:0] op_a_i,
  input logic [31:0] op_b_i,
  output logic [31:0] result_o
);
  logic [63:0] temp;
  
  always_comb begin
    temp = {'0, op_b_i};
  for(integer i = 0; i < 32; i++) begin
      temp[63:32] = (temp[0]) ? temp[63:32] ^ op_a_i : temp[63:32];
      temp = temp >> 1;
  	end
  end
    assign result_o = temp[32:0];
endmodule
