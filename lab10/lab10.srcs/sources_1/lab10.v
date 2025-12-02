module tetris_top(
    input  clk,          // 100MHz
    input  reset_n,      // Active Low
    input  [3:0] usr_btn,// {Rot, Right, Left, Down}
    input  [3:0] usr_sw,
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
    
    // 遊戲區位置與大小
    localparam OFF_X = 220;
    localparam OFF_Y = 40;
    localparam GAME_W = 200; // 10 cols * 20
    localparam GAME_H = 400; // 20 rows * 20

    // 0. 時脈生成 (100MHz -> 50MHz)
    wire vga_clk;
    clk_divider#(2) cd0 (.clk(clk), .reset(~reset_n), .clk_out(vga_clk));

    // 1. SRAM 控制 (旋轉鍵觸發寫入，平時唯讀)
    wire mem_we = usr_sw[3]; 
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

    // Pipeline Registers
    reg [2:0] blk_id_d1, blk_id_d2;
    reg score_on_d1, score_on_d2;
    // [新增] 區域遮罩延遲訊號
    reg in_game_d1, in_game_d2; 

    // --- 2. 安全座標計算 (Critical Fix) ---
    // 判斷目前掃描點是否在遊戲框框內
    wire in_game_region = (pixel_x >= OFF_X && pixel_x < OFF_X + GAME_W && 
                           pixel_y >= OFF_Y && pixel_y < OFF_Y + GAME_H);

    // 只有在範圍內才計算除法，否則送 0。這避免了負數溢位造成的錯誤座標。
    wire [9:0] safe_grid_x = (in_game_region) ? (pixel_x - OFF_X) / 20 : 0;
    wire [9:0] safe_grid_y = (in_game_region) ? (pixel_y - OFF_Y) / 20 : 0;
    
    // 紋理座標 (0-19)
    wire [4:0] tex_u = (in_game_region) ? (pixel_x - OFF_X) % 20 : 0;
    wire [4:0] tex_v = (in_game_region) ? (pixel_y - OFF_Y) % 20 : 0;

    // --- 模組實例化 ---

    vga_sync vs0 (
        .clk(vga_clk), .reset(~reset_n), 
        .visible(video_on), .p_tick(p_tick),
        .pixel_x(pixel_x), .pixel_y(pixel_y), 
        .oHS(VGA_HSYNC), .oVS(VGA_VSYNC)
    );

    debounce db3 (.clk(vga_clk), .reset_n(reset_n), .btn_in(~usr_btn[3]), .btn_out(btn_clean[3])); 
    debounce db2 (.clk(vga_clk), .reset_n(reset_n), .btn_in(~usr_btn[2]), .btn_out(btn_clean[2])); 
    debounce db1 (.clk(vga_clk), .reset_n(reset_n), .btn_in(~usr_btn[1]), .btn_out(btn_clean[1])); 
    debounce db0 (.clk(vga_clk), .reset_n(reset_n), .btn_in(~usr_btn[0]), .btn_out(btn_clean[0])); 

    // 傳入安全的 safe_grid_x/y
    tetris_core core (
        .clk(vga_clk), .rst(~reset_n), 
        .btn(btn_clean), 
        .grid_x(safe_grid_x), 
        .grid_y(safe_grid_y),
        .pixel_block_id(core_blk_id),
        .score(core_score)
    );

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(MEM_BG_SIZE), .FILE("images.mem"))
        ram_bg (.clk(vga_clk), .we(mem_we), .en(mem_en), .addr(addr_bg), .data_i(zero_data), .data_o(data_bg));

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(12), .RAM_SIZE(MEM_BLK_SIZE), .FILE("blocks.mem"))
        ram_blk (.clk(vga_clk), .we(mem_we), .en(mem_en), .addr(addr_blk), .data_i(zero_data), .data_o(data_blk));

    // Score
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


    // --- AGU & Pipeline ---
    always @(posedge vga_clk) begin
        if (~reset_n) begin
            addr_bg <= 0;
            addr_blk <= 0;
            blk_id_d1 <= 0; blk_id_d2 <= 0;
            score_on_d1 <= 0; score_on_d2 <= 0;
            in_game_d1 <= 0; in_game_d2 <= 0;
        end else begin
            // 1. AGU
            addr_bg <= (pixel_y[9:1]) * VBUF_W + (pixel_x[9:1]);
            addr_blk <= (core_blk_id * TEX_H + tex_v) * TEX_W + tex_u;

            // 2. Delay Stage 1
            blk_id_d1 <= core_blk_id;
            score_on_d1 <= score_active;
            in_game_d1 <= in_game_region; // 紀錄當下是否在框框內
            
            // 3. Delay Stage 2
            blk_id_d2 <= blk_id_d1;
            score_on_d2 <= score_on_d1;
            in_game_d2 <= in_game_d1;     // 跟隨資料延遲
        end
    end

    // --- Mixer ---
    reg [11:0] rgb_out;
    always @(*) begin
        if (!video_on) begin
            rgb_out = 12'h000;
        end else begin
            if (score_on_d2) begin
                rgb_out = 12'hFFF; 
            end
            // [關鍵修正] 只有當我們 "真的在遊戲框框內 (in_game_d2)" 時，才允許顯示方塊
            // 這樣可以強制切掉所有因為座標計算錯誤而在框外產生的雜訊
            else if (in_game_d2 && blk_id_d2 > 0) begin
                rgb_out = data_blk; 
            end
            else begin
                rgb_out = data_bg;
            end
        end
    end

    reg [11:0] rgb_reg;
    always @(posedge vga_clk) if (p_tick) rgb_reg <= rgb_out;
    assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

endmodule