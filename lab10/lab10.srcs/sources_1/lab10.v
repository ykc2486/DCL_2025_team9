module tetris_top(
    input  clk,          // 100MHz
    input  reset_n,      // Active Low
    input  [3:0] usr_btn,// {3:Rot, 2:Left, 1:Right, 0:Down/Start}
    input  [3:0] usr_sw, // sw[0]: Hold, sw[1]: Pause
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
);

    // --- 1. 參數設定 (Parameters) ---
    // 基礎參數
    localparam BLK_SIZE = 20;
    localparam MEM_BG_SIZE = 76800; // 320x240
    localparam VBUF_W = 320; 
    localparam MEM_BLK_SIZE = 3200; 
    localparam TEX_W = 20;
    localparam TEX_H = 20;
    
    // UI 圖片尺寸設定
    localparam START_W = 96;
    localparam START_H = 181;
    localparam OVER_W  = 97;
    localparam OVER_H  = 55;

    // 自動計算置中座標 (螢幕邏輯解析度 320x240)
    localparam START_X = (320 - START_W) / 2 + 10; 
    localparam START_Y = (240 - START_H) / 2; 
    localparam OVER_X  = (320 - OVER_W) / 2 + 10;  
    localparam OVER_Y  = (240 - OVER_H) / 2;  
    
    // 遊戲介面座標
    localparam OFF_X = 240; localparam OFF_Y = 30;
    localparam GAME_W = 200; localparam GAME_H = 400; 
    localparam SC_X = 490; localparam SC_Y = 125;
    localparam NEXT_X = 500; localparam NEXT_Y = 220;
    localparam NEXT_W = 80; localparam NEXT_H = 80;
    localparam HOLD_X = 80; localparam HOLD_Y = 370;
    localparam HOLD_W = 80; localparam HOLD_H = 80;

    // [New Rank] 排行榜顯示位置 (左手邊)
    // 這裡使用原始 VGA 座標 (640x480 空間)
    localparam RANK_POS_X = 40; 
    localparam RANK_POS_Y = 120;

    // --- 訊號定義 ---
    wire clk_50m; 
    wire video_on, p_tick; 
    wire [9:0] pixel_x, pixel_y;
    wire [3:0] btn_clean;
    wire [2:0] core_blk_id; 
    wire [7:0] core_score;
    wire [2:0] core_next_id; 
    wire [2:0] core_hold_id; 
    wire [2:0] core_status;
    
    // 邏輯像素座標 (除以2，對應 320x240 解析度)
    wire [9:0] log_x = pixel_x[9:1];
    wire [9:0] log_y = pixel_y[9:1];

    // States
    localparam ST_IDLE      = 0;
    localparam ST_GAMEOVER  = 5;
    localparam ST_PAUSE     = 6;

    // --- Modules ---
    clk_divider #(.divider(2)) cd0 (.clk(clk), .reset(~reset_n), .clk_out(clk_50m));
    
    vga_sync vs0 (.clk(clk_50m), .reset(~reset_n), .oHS(VGA_HSYNC), .oVS(VGA_VSYNC), 
                  .visible(video_on), .p_tick(p_tick), .pixel_x(pixel_x), .pixel_y(pixel_y));

    debounce db3 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[3]), .btn_out(btn_clean[3])); 
    debounce db2 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[2]), .btn_out(btn_clean[2])); 
    debounce db1 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[1]), .btn_out(btn_clean[1])); 
    debounce db0 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[0]), .btn_out(btn_clean[0])); 

    // --- Region Logic ---
    wire in_game_region = (pixel_x >= OFF_X && pixel_x < OFF_X + GAME_W && pixel_y >= OFF_Y && pixel_y < OFF_Y + GAME_H);
    wire [9:0] safe_grid_x = (in_game_region) ? (pixel_x - OFF_X) / 20 : 0;
    wire [9:0] safe_grid_y = (in_game_region) ? (pixel_y - OFF_Y) / 20 : 0;
    wire [4:0] tex_u        = (in_game_region) ? (pixel_x - OFF_X) % 20 : 0;
    wire [4:0] tex_v        = (in_game_region) ? (pixel_y - OFF_Y) % 20 : 0;

    wire in_next_region = (pixel_x >= NEXT_X && pixel_x < NEXT_X + NEXT_W && pixel_y >= NEXT_Y && pixel_y < NEXT_Y + NEXT_H);
    wire [2:0] next_grid_x = (pixel_x - NEXT_X) / 20;
    wire [2:0] next_grid_y = (pixel_y - NEXT_Y) / 20;
    wire [4:0] next_tex_u  = (pixel_x - NEXT_X) % 20;
    wire [4:0] next_tex_v  = (pixel_y - NEXT_Y) % 20;

    wire in_hold_region = (pixel_x >= HOLD_X && pixel_x < HOLD_X + HOLD_W && pixel_y >= HOLD_Y && pixel_y < HOLD_Y + HOLD_H);
    wire [2:0] hold_grid_x = (pixel_x - HOLD_X) / 20;
    wire [2:0] hold_grid_y = (pixel_y - HOLD_Y) / 20;
    wire [4:0] hold_tex_u  = (pixel_x - HOLD_X) % 20;
    wire [4:0] hold_tex_v  = (pixel_y - HOLD_Y) % 20;
    
    // UI 區域判定
    wire in_start_rect = (log_x >= START_X && log_x < START_X + START_W && log_y >= START_Y && log_y < START_Y + START_H);
    wire in_over_rect  = (log_x >= OVER_X  && log_x < OVER_X + OVER_W  && log_y >= OVER_Y  && log_y < OVER_Y + OVER_H);

    // --- Core Instance ---
    tetris_core core (
        .clk(clk_50m), .rst(~reset_n), .btn(btn_clean), 
        .sw_hold(usr_sw[0]), .sw_pause(usr_sw[1]), 
        .grid_x(safe_grid_x), .grid_y(safe_grid_y),
        .pixel_block_id(core_blk_id), .score(core_score),
        .next_piece_id(core_next_id), .hold_piece_id(core_hold_id),
        .game_status(core_status)
    );

    // --- [New Rank] Rank Logic & Display Instances ---
    wire [7:0] rk_r1, rk_r2, rk_r3, rk_r4, rk_r5;
    wire rank_pixel_on;
    
    // 排行榜核心：儲存並排序分數
    rank_core rk_core (
        .clk(clk_50m),
        .rst_n(reset_n),
        .game_status(core_status),
        .current_score(core_score),
        .r1(rk_r1), .r2(rk_r2), .r3(rk_r3), .r4(rk_r4), .r5(rk_r5)
    );

    // 排行榜繪製：負責產生 VGA 像素訊號
    rank_renderer rk_disp (
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pos_x(RANK_POS_X), .pos_y(RANK_POS_Y),
        .r1(rk_r1), .r2(rk_r2), .r3(rk_r3), .r4(rk_r4), .r5(rk_r5),
        .rank_pixel_on(rank_pixel_on)
    );

    // --- SRAMs ---
    wire mem_we = usr_sw[3]; wire mem_en = 1'b1; wire [11:0] zero_data = 12'h0;
    
    reg [16:0] addr_bg; 
    reg [11:0] addr_blk;
    reg [14:0] addr_start; 
    reg [12:0] addr_over;  
    
    wire [11:0] data_bg; 
    wire [11:0] data_blk;    
    wire [11:0] data_start; 
    wire [11:0] data_over;

    // 1. Background
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(MEM_BG_SIZE), .FILE("images.mem"))
        ram_bg (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_bg), .data_i(zero_data), .data_o(data_bg));
        
    // 2. Block Texture
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(12), .RAM_SIZE(MEM_BLK_SIZE), .FILE("blocks.mem"))
        ram_blk (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_blk), .data_i(zero_data), .data_o(data_blk));

    // 3. Start Screen
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(15), .RAM_SIZE(96*181), .FILE("start.mem"))
        ram_start (.clk(clk_50m), .we(1'b0), .en(mem_en), .addr(addr_start), .data_i(zero_data), .data_o(data_start));

    // 4. Game Over Screen
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(13), .RAM_SIZE(97*55), .FILE("gameover.mem"))
        ram_over (.clk(clk_50m), .we(1'b0), .en(mem_en), .addr(addr_over), .data_i(zero_data), .data_o(data_over));

    // --- Bitmaps ---
    function [15:0] get_preview_bitmap;
        input [2:0] shape;
        begin
            case(shape)
                1: get_preview_bitmap = 16'h0F00; 2: get_preview_bitmap = 16'h08E0; 3: get_preview_bitmap = 16'h02E0; 
                4: get_preview_bitmap = 16'h0660; 5: get_preview_bitmap = 16'h06C0; 6: get_preview_bitmap = 16'h04E0; 
                7: get_preview_bitmap = 16'h0C60; default: get_preview_bitmap = 16'h0000;
            endcase
        end
    endfunction
    wire [15:0] next_bitmap = get_preview_bitmap(core_next_id);
    wire is_next_pixel_on = next_bitmap[15 - {next_grid_y[1:0], next_grid_x[1:0]}];
    wire [15:0] hold_bitmap = get_preview_bitmap(core_hold_id);
    wire is_hold_pixel_on = hold_bitmap[15 - {hold_grid_y[1:0], hold_grid_x[1:0]}];

    // --- Score Gen ---
    wire signed [9:0] rx1 = pixel_x - SC_X;
    wire signed [9:0] rx2 = pixel_x - (SC_X + 30);
    wire signed [9:0] rx3 = pixel_x - (SC_X + 60);
    wire signed [9:0] ry_sc = pixel_y - SC_Y;
    wire s_on_hun, s_on_ten, s_on_unit;
    score_gen g1 (.digit((core_score/100)%10), .rel_x(rx1), .rel_y(ry_sc), .seg_on(s_on_hun));
    score_gen g2 (.digit((core_score/10)%10),  .rel_x(rx2), .rel_y(ry_sc), .seg_on(s_on_ten));
    score_gen g3 (.digit(core_score%10),       .rel_x(rx3), .rel_y(ry_sc), .seg_on(s_on_unit));
    wire score_active = s_on_hun || s_on_ten || s_on_unit;

    // --- Pipeline & Mixer ---
    reg [2:0] blk_id_d1, blk_id_d2;
    reg score_on_d1, score_on_d2;
    reg in_game_d1, in_game_d2; 
    reg in_next_d1, in_next_d2;
    reg is_next_blk_d1, is_next_blk_d2;
    reg in_hold_d1, in_hold_d2;
    reg is_hold_blk_d1, is_hold_blk_d2;
    reg [2:0] status_d1, status_d2;
    
    reg in_start_d1, in_start_d2;
    reg in_over_d1, in_over_d2;
    reg [11:0] data_start_d2, data_over_d2;

    // [New Rank] Pipeline signals
    reg rank_on_d1, rank_on_d2;

    always @(posedge clk_50m) begin
        if (~reset_n) begin
            addr_bg <= 0; addr_blk <= 0; 
            addr_start <= 0; addr_over <= 0;
            blk_id_d1 <= 0; blk_id_d2 <= 0;
            status_d1 <= ST_IDLE; status_d2 <= ST_IDLE;
            data_start_d2 <= 0; data_over_d2 <= 0;
            rank_on_d1 <= 0; rank_on_d2 <= 0;
        end else begin
            // --- Stage 1: Address Calculation ---
            addr_bg <= log_y * VBUF_W + log_x; 
            
            if (in_next_region) addr_blk <= (core_next_id * TEX_H + next_tex_v) * TEX_W + next_tex_u;
            else if (in_hold_region) addr_blk <= (core_hold_id * TEX_H + hold_tex_v) * TEX_W + hold_tex_u;
            else addr_blk <= (core_blk_id * TEX_H + tex_v) * TEX_W + tex_u;

            if (in_start_rect) 
                addr_start <= (log_y - START_Y) * START_W + (log_x - START_X);
            else 
                addr_start <= 0;

            if (in_over_rect)
                addr_over <= (log_y - OVER_Y) * OVER_W + (log_x - OVER_X);
            else 
                addr_over <= 0;

            // --- Stage 2: Data Fetch & Latch ---
            blk_id_d1 <= core_blk_id;
            score_on_d1 <= score_active;
            in_game_d1 <= in_game_region;
            in_next_d1 <= in_next_region;
            is_next_blk_d1 <= (in_next_region && is_next_pixel_on);
            in_hold_d1 <= in_hold_region;
            is_hold_blk_d1 <= (in_hold_region && is_hold_pixel_on);
            status_d1 <= core_status;
            
            in_start_d1 <= in_start_rect;
            in_over_d1  <= in_over_rect;

            data_start_d2 <= data_start;
            data_over_d2  <= data_over;

            // [New Rank] 鎖存 Rank 像素訊號
            rank_on_d1 <= rank_pixel_on;

            // --- Stage 3: Sync ---
            blk_id_d2 <= blk_id_d1;
            score_on_d2 <= score_on_d1;
            in_game_d2 <= in_game_d1;
            in_next_d2 <= in_next_d1;
            is_next_blk_d2 <= is_next_blk_d1;
            in_hold_d2 <= in_hold_d1;
            is_hold_blk_d2 <= is_hold_blk_d1;
            status_d2 <= status_d1;
            
            in_start_d2 <= in_start_d1;
            in_over_d2  <= in_over_d1;

            // [New Rank] 同步
            rank_on_d2 <= rank_on_d1;
        end
    end

    // --- Final Mixer ---
    reg [11:0] rgb_out;
    always @(*) begin
        if (!video_on) begin
            rgb_out = 12'h000;
        end else begin
            case (status_d2)
                ST_IDLE: begin
                    if (in_start_d2) rgb_out = data_start_d2;
                    else if (rank_on_d2) rgb_out = 12'hFF0; // [New Rank] IDLE 時顯示黃色排行榜
                    else rgb_out = data_bg; 
                end

                ST_GAMEOVER: begin
                    if (in_over_d2) rgb_out = data_over_d2;
                    else if (rank_on_d2) rgb_out = 12'hFF0; // [New Rank] 結束時顯示黃色排行榜
                    // 背景變紅濾鏡
                    else rgb_out = (in_game_d2 && blk_id_d2 > 0) ? {4'hF, 4'h0, 4'h0} : ({data_bg[11:8] >> 1, data_bg[7:4] >> 1, data_bg[3:0] >> 1});
                end

                ST_PAUSE: begin
                    // 暫停時不一定要顯示排行榜，保持畫面乾淨
                    if (in_game_d2 && blk_id_d2 > 0) rgb_out = (data_blk);
                    else rgb_out = data_bg; 
                end

                default: begin // ST_PLAY
                    if (score_on_d2) rgb_out = 12'hFFF; 
                    else if (rank_on_d2) rgb_out = 12'hFF0; // [New Rank] 遊戲中也顯示排行榜
                    else if (in_game_d2) rgb_out = (blk_id_d2 > 0) ? data_blk : data_bg; 
                    else if (in_next_d2 && is_next_blk_d2) rgb_out = data_blk; 
                    else if (in_hold_d2 && is_hold_blk_d2 && core_hold_id > 0) rgb_out = data_blk; 
                    else rgb_out = data_bg;
                end
            endcase
        end
    end

    reg [11:0] rgb_reg;
    always @(posedge clk_50m) if (p_tick) rgb_reg <= rgb_out;
    assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

endmodule

// ============================================================================
// Rank Core: 維護前五名分數的邏輯
// ============================================================================
module rank_core (
    input clk,
    input rst_n,
    input [2:0] game_status,    // 輸入遊戲狀態
    input [7:0] current_score,  // 輸入當前分數
    output reg [7:0] r1, r2, r3, r4, r5 // 輸出前五名分數
);
    localparam ST_GAMEOVER = 5;

    // 偵測 Game Over 的正緣 (Rising Edge)
    reg [2:0] status_d1;
    wire is_game_over_pulse = (game_status == ST_GAMEOVER) && (status_d1 != ST_GAMEOVER);

    always @(posedge clk) begin
        if (~rst_n) begin
            status_d1 <= 0;
            // 初始化排行榜為 0
            r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0;
        end else begin
            status_d1 <= game_status;

            if (is_game_over_pulse) begin
                // 簡易的插入排序 (Insertion Logic)
                // 當分數比第一名高，全部順移
                if (current_score > r1) begin
                    r1 <= current_score; r2 <= r1; r3 <= r2; r4 <= r3; r5 <= r4;
                end else if (current_score > r2) begin
                    r2 <= current_score; r3 <= r2; r4 <= r3; r5 <= r4;
                end else if (current_score > r3) begin
                    r3 <= current_score; r4 <= r3; r5 <= r4;
                end else if (current_score > r4) begin
                    r4 <= current_score; r5 <= r4;
                end else if (current_score > r5) begin
                    r5 <= current_score;
                end
            end
        end
    end
endmodule

// ============================================================================
// Rank Renderer: 負責在螢幕上繪製五個數字
// ============================================================================
module rank_renderer (
    input [9:0] pixel_x, pixel_y,
    input [9:0] pos_x, pos_y,       // 排行榜顯示的左上角座標
    input [7:0] r1, r2, r3, r4, r5, // 輸入的分數
    output rank_pixel_on            // 輸出像素開關
);
    // 設定每一行的高度 (包含字體與間距)
    localparam ROW_H = 35; 
    
    // 計算目前掃描線位於哪一個名次 (0~4)
    // 使用 signed 避免負數運算錯誤
    wire signed [10:0] diff_y = pixel_y - pos_y;
    wire [2:0] row_idx = (diff_y >= 0) ? (diff_y / ROW_H) : 3'b111;
    wire [9:0] rel_y_in_row = (diff_y >= 0) ? (diff_y % ROW_H) : 0;

    // 判斷是否在排行榜的整體區域內 (5行 * 35px = 175px 高)
    // 寬度抓 80px 足夠顯示3個數字
    wire in_rank_area = (pixel_x >= pos_x) && (pixel_x < pos_x + 80) && 
                        (pixel_y >= pos_y) && (pixel_y < pos_y + (ROW_H * 5));

    // 根據 row_idx 選擇要顯示的分數
    reg [7:0] target_score;
    always @(*) begin
        case (row_idx)
            0: target_score = r1;
            1: target_score = r2;
            2: target_score = r3;
            3: target_score = r4;
            4: target_score = r5;
            default: target_score = 0;
        endcase
    end

    // 分割三個位數 (百、十、個)
    wire [3:0] d_hun = (target_score / 100) % 10;
    wire [3:0] d_ten = (target_score / 10) % 10;
    wire [3:0] d_unit = target_score % 10;

    // 實例化三個 score_gen (共用)
    // 假設 score_gen 的 rel_x, rel_y 介面與 tetris_top 裡的一致
    wire s_on_h, s_on_t, s_on_u;
    
    // 計算相對 X 座標
    wire signed [9:0] rx_h = pixel_x - pos_x;
    wire signed [9:0] rx_t = pixel_x - (pos_x + 25);
    wire signed [9:0] rx_u = pixel_x - (pos_x + 50);

    score_gen g_rk_h (.digit(d_hun),  .rel_x(rx_h), .rel_y(rel_y_in_row), .seg_on(s_on_h));
    score_gen g_rk_t (.digit(d_ten),  .rel_x(rx_t), .rel_y(rel_y_in_row), .seg_on(s_on_t));
    score_gen g_rk_u (.digit(d_unit), .rel_x(rx_u), .rel_y(rel_y_in_row), .seg_on(s_on_u));

    // 最終輸出：如果在區域內，且任一位數需要亮起
    assign rank_pixel_on = in_rank_area && (s_on_h || s_on_t || s_on_u);

endmodule