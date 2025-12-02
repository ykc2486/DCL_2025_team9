module debounce (
    input clk,
    input reset_n, // Active Low Reset
    input btn_in,
    output reg btn_out
);
    // Debounce 時間參數 (50MHz 下約 40ms)
    parameter DEBOUNCE_PERIOD = 2_000_000;
    
    reg [$clog2(DEBOUNCE_PERIOD):0] counter;
    reg btn_prev;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 0;
            btn_prev <= 1'b0;
            btn_out <= 1'b0;
        end else begin
            // 狀態發生變化，重置計數器
            if (btn_in != btn_prev) begin
                counter <= 0;
                btn_prev <= btn_in;
            end 
            // 狀態穩定，開始計數
            else if (counter < DEBOUNCE_PERIOD) begin
                counter <= counter + 1;
            end 
            // 計數完成，更新輸出
            else begin
                btn_out <= btn_prev;
            end
        end
    end
endmodule