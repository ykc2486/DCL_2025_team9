module sram
#(parameter DATA_WIDTH = 12, ADDR_WIDTH = 18, RAM_SIZE = 76800, FILE = "images.mem")
 (input clk, input we, input en,
  input  [ADDR_WIDTH-1 : 0] addr,
  input  [DATA_WIDTH-1 : 0] data_i,
  output reg [DATA_WIDTH-1 : 0] data_o);

// Declareation of the memory cells
(* ram_style = "block" *) reg [DATA_WIDTH-1 : 0] RAM [RAM_SIZE - 1:0];

// ------------------------------------
// SRAM cell initialization
// ------------------------------------
initial begin
    $readmemh(FILE, RAM); // 使用參數 FILE 來決定讀哪個檔
end

// ------------------------------------
// SRAM read operation
// ------------------------------------
always@(posedge clk)
begin
  if (en & we)
    data_o <= data_i;
  else
    data_o <= RAM[addr];
end

// ------------------------------------
// SRAM write operation
// ------------------------------------
always@(posedge clk)
begin
  if (en & we)
    RAM[addr] <= data_i;
end

endmodule