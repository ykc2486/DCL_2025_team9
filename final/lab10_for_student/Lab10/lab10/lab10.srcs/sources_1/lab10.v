module tetris_top(
    input  clk,          // 50MHz
    input  reset_n,      // Active Low
    input  [3:0] usr_btn,// {Rot, Right, Left, Down}
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
);

    // --- 參數 ---
    localparam BLK_SIZE = 20;
    localparam MEM_BG_SIZE = 76800; 
    localparam VBUF_W = 320; 
    localparam MEM_BLK_SIZE = 3200; 
    localparam TEX_W = 20;
    localparam TEX_H = 20;

    // SRAM 控制
    wire mem_we = 1'b0;     
    wire mem_en = 1'b1;     
    wire [11:0] zero_data = 12'h0;

    // 訊號
    wire video_on, p_tick;
    wire [9:0] pixel_x, pixel_y;
    wire [3:0] btn_clean;
    wire [2:0] core_blk_id; 
    wire [7:0] core_score;

    reg  [16:0] addr_bg;
    reg  [11:0] addr_blk;
    wire [11:0] data_bg;    
    wire [11:0] data_blk;   

    // --- 關鍵修正：二級 Pipeline Delay ---
    // SRAM 讀取有延遲，所以判斷訊號也要跟著延遲，不然畫面會閃爍
    reg [2:0] blk_id_d1, blk_id_d2; 
    reg score_on_d1, score_on_d2;

    // --- 模組實例化 ---
    clk_divider#(2) cd0 (.clk(clk), .reset(~reset_n), .clk_out(vga_clk));
    
    // VGA Sync (直接接 clk，內部會自己除頻)
    vga_sync vs0 (
        .clk(clk), .reset(~reset_n), 
        .visible(video_on), .p_tick(p_tick),
        .pixel_x(pixel_x), .pixel_y(pixel_y), 
        .oHS(VGA_HSYNC), .oVS(VGA_VSYNC)
    );

    // Debounce
    debounce db3 (.clk(clk), .reset_n(reset_n), .btn_in(~usr_btn[3]), .btn_out(btn_clean[3])); 
    debounce db2 (.clk(clk), .reset_n(reset_n), .btn_in(~usr_btn[2]), .btn_out(btn_clean[2])); 
    debounce db1 (.clk(clk), .reset_n(reset_n), .btn_in(~usr_btn[1]), .btn_out(btn_clean[1])); 
    debounce db0 (.clk(clk), .reset_n(reset_n), .btn_in(~usr_btn[0]), .btn_out(btn_clean[0])); 

    // Core
    tetris_core core (
        .clk(clk), .rst(~reset_n), 
        .btn(btn_clean), 
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_block_id(core_blk_id),
        .score(core_score)
    );

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(MEM_BG_SIZE), .FILE("images.mem"))
        ram_bg (.clk(clk), .we(mem_we), .en(mem_en), .addr(addr_bg), .data_i(zero_data), .data_o(data_bg));

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(12), .RAM_SIZE(MEM_BLK_SIZE), .FILE("blocks.mem"))
        ram_blk (.clk(clk), .we(mem_we), .en(mem_en), .addr(addr_blk), .data_i(zero_data), .data_o(data_blk));

    // Score Gen
    wire score_active;
    wire [9:0] sx = pixel_x;
    wire [9:0] sy = pixel_y;
    wire s_on_hun, s_on_ten, s_on_unit;
    localparam SC_X = 460;
    localparam SC_Y = 150;
    
    score_gen g1 (.digit((core_score/100)%10), .rel_x(sx - SC_X),      .rel_y(sy - SC_Y), .seg_on(s_on_hun));
    score_gen g2 (.digit((core_score/10)%10),  .rel_x(sx - SC_X - 30), .rel_y(sy - SC_Y), .seg_on(s_on_ten));
    score_gen g3 (.digit(core_score%10),       .rel_x(sx - SC_X - 60), .rel_y(sy - SC_Y), .seg_on(s_on_unit));
    
    assign score_active = (sx >= SC_X && sx < SC_X + 20 && sy >= SC_Y && sy < SC_Y + 40 && s_on_hun) ||
                          (sx >= SC_X + 30 && sx < SC_X + 50 && sy >= SC_Y && sy < SC_Y + 40 && s_on_ten) ||
                          (sx >= SC_X + 60 && sx < SC_X + 80 && sy >= SC_Y && sy < SC_Y + 40 && s_on_unit);


    // --- AGU & Delay Logic ---
    wire [4:0] tex_u = (pixel_x - 220) % BLK_SIZE;
    wire [4:0] tex_v = (pixel_y - 40)  % BLK_SIZE;

    always @(posedge clk) begin
        if (~reset_n) begin
            addr_bg <= 0;
            addr_blk <= 0;
            blk_id_d1 <= 0; blk_id_d2 <= 0;
            score_on_d1 <= 0; score_on_d2 <= 0;
        end else begin
            // 1. 計算位址 (Stage 1)
            addr_bg <= (pixel_y[9:1]) * VBUF_W + (pixel_x[9:1]);
            addr_blk <= (core_blk_id * TEX_H + tex_v) * TEX_W + tex_u;

            // 2. 傳遞 ID 訊號 (Stage 1)
            blk_id_d1 <= core_blk_id;
            score_on_d1 <= score_active;

            // 3. 傳遞 ID 訊號 (Stage 2 - 配合 SRAM 資料吐出的時間)
            blk_id_d2 <= blk_id_d1;
            score_on_d2 <= score_on_d1;
        end
    end

    // --- Mixer ---
    reg [11:0] rgb_out;
    
    always @(*) begin
        if (!video_on) begin
            rgb_out = 12'h000;
        end else begin
            // 這裡必須用 d2 (延遲兩次) 的訊號，因為 data_blk 是延遲兩次才出來的
            if (score_on_d2) rgb_out = 12'hFFF; 
            else if (blk_id_d2 > 0) rgb_out = data_blk; 
            else rgb_out = data_bg;
        end
    end

    reg [11:0] rgb_reg;
    always @(posedge clk) if (p_tick) rgb_reg <= rgb_out;
    assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

endmodule