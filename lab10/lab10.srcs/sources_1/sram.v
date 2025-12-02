module sram #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 17,
    parameter RAM_SIZE = 76800,
    parameter FILE = "none.mem"
)(
    input clk,
    input we,
    input en,
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] data_i,
    output reg [DATA_WIDTH-1:0] data_o
);

    // -------------------------------------------------------------------------
    // 關鍵修正：加入 (* ram_style = "block" *)
    // 這行指令告訴 Vivado：「請把這個陣列放進 BRAM，不要用 LUT 做！」
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) 
    reg [DATA_WIDTH-1:0] RAM [0:RAM_SIZE-1];

    // 初始化記憶體內容
    initial begin
        if (FILE != "none.mem") begin
            $readmemh(FILE, RAM);
        end
    end

    // 同步讀寫 (BRAM 需要在 Clock edge 動作)
    always @(posedge clk) begin
        if (en) begin
            if (we)
                RAM[addr] <= data_i;
            
            // 讀取操作
            data_o <= RAM[addr];
        end
    end

endmodule