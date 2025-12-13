// ============================================================================
// Top Module: 負責 VGA 顯示、記憶體讀取、Pipeline 與模組整合
// ============================================================================
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

    // --- 參數設定 (Parameters) ---
    localparam MEM_BG_SIZE = 76800; // 320x240
    localparam VBUF_W = 320; 
    localparam MEM_BLK_SIZE = 3200; 
    localparam TEX_W = 20; localparam TEX_H = 20;
    
    // UI 圖片尺寸
    localparam START_W = 96; localparam START_H = 181;
    localparam OVER_W  = 100; localparam OVER_H  = 54;
    
    // 圖片置中計算
    localparam START_X = (320 - START_W) / 2 + 10; 
    localparam START_Y = (240 - START_H) / 2; 
    localparam OVER_X  = (320 - OVER_W) / 2 + 10;  
    localparam OVER_Y  = (240 - OVER_H) / 2;  
    
    // 遊戲區塊位置
    localparam OFF_X = 240; localparam OFF_Y = 30;
    localparam GAME_W = 200; localparam GAME_H = 400; 
    
    // [UI 位置設定]
    localparam SC_X = 485; localparam SC_Y = 100;       // 分數 (Big Font 30x45)
    localparam NEXT_X = 500; localparam NEXT_Y = 220;   // 下一個方塊
    localparam NEXT_W = 80; localparam NEXT_H = 80;
    localparam HOLD_X = 80; localparam HOLD_Y = 370;    // Hold 方塊
    localparam HOLD_W = 80; localparam HOLD_H = 80;

    localparam RANK_POS_X = 80; localparam RANK_POS_Y = 155; // 排行榜 (Left)
    localparam LV_X = 500; localparam LV_Y = 350;            // Level (Right Bottom)

    // --- 訊號定義 ---
    wire clk_50m; 
    wire video_on, p_tick; 
    wire [9:0] pixel_x, pixel_y;
    wire [3:0] btn_clean;
    wire [2:0] core_blk_id, core_next_id, core_hold_id, core_status;
    wire [7:0] core_score;
    wire [7:0] core_level; // Level 訊號

    // 邏輯座標 (320x240)
    wire [9:0] log_x = pixel_x[9:1];
    wire [9:0] log_y = pixel_y[9:1];

    // 狀態常數
    localparam ST_IDLE = 0, ST_GAMEOVER = 5, ST_PAUSE = 6;

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
    wire [4:0] tex_u = (in_game_region) ? (pixel_x - OFF_X) % 20 : 0;
    wire [4:0] tex_v = (in_game_region) ? (pixel_y - OFF_Y) % 20 : 0;

    wire in_next_region = (pixel_x >= NEXT_X && pixel_x < NEXT_X + NEXT_W && pixel_y >= NEXT_Y && pixel_y < NEXT_Y + NEXT_H);
    wire [2:0] next_grid_x = (pixel_x - NEXT_X) / 20;
    wire [2:0] next_grid_y = (pixel_y - NEXT_Y) / 20;
    wire [4:0] next_tex_u = (pixel_x - NEXT_X) % 20;
    wire [4:0] next_tex_v = (pixel_y - NEXT_Y) % 20;

    wire in_hold_region = (pixel_x >= HOLD_X && pixel_x < HOLD_X + HOLD_W && pixel_y >= HOLD_Y && pixel_y < HOLD_Y + HOLD_H);
    wire [2:0] hold_grid_x = (pixel_x - HOLD_X) / 20;
    wire [2:0] hold_grid_y = (pixel_y - HOLD_Y) / 20;
    wire [4:0] hold_tex_u = (pixel_x - HOLD_X) % 20;
    wire [4:0] hold_tex_v = (pixel_y - HOLD_Y) % 20;
    
    wire in_start_rect = (log_x >= START_X && log_x < START_X + START_W && log_y >= START_Y && log_y < START_Y + START_H);
    wire in_over_rect  = (log_x >= OVER_X  && log_x < OVER_X + OVER_W  && log_y >= OVER_Y  && log_y < OVER_Y + OVER_H);

    // --- Core Instance (外部模組) ---
    // 請確保您的專案中有 tetris_core.v 檔案
    tetris_core core (
        .clk(clk_50m), .rst(~reset_n), .btn(btn_clean), 
        .sw_hold(usr_sw[0]), .sw_pause(usr_sw[1]), 
        .grid_x(safe_grid_x), .grid_y(safe_grid_y),
        .pixel_block_id(core_blk_id), .score(core_score),
        .next_piece_id(core_next_id), .hold_piece_id(core_hold_id),
        .game_status(core_status),
        .level(core_level)
    );

    // --- [Rank Logic] ---
    wire [7:0] rk_r1, rk_r2, rk_r3, rk_r4, rk_r5;
    wire rank_pixel_on;
    rank_core rk_core (.clk(clk_50m), .rst_n(reset_n), .game_status(core_status), .current_score(core_score),
                       .r1(rk_r1), .r2(rk_r2), .r3(rk_r3), .r4(rk_r4), .r5(rk_r5));
    rank_renderer rk_disp (.pixel_x(pixel_x), .pixel_y(pixel_y), .pos_x(RANK_POS_X), .pos_y(RANK_POS_Y),
                           .r1(rk_r1), .r2(rk_r2), .r3(rk_r3), .r4(rk_r4), .r5(rk_r5), .rank_pixel_on(rank_pixel_on));

    // --- SRAMs ---
    wire mem_we = usr_sw[3]; wire mem_en = 1'b1; wire [11:0] zero_data = 12'h0;
    reg [16:0] addr_bg; reg [11:0] addr_blk; reg [14:0] addr_start; reg [12:0] addr_over;
    wire [11:0] data_bg, data_blk, data_start, data_over;

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(MEM_BG_SIZE), .FILE("images.mem")) ram_bg (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_bg), .data_i(zero_data), .data_o(data_bg));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(12), .RAM_SIZE(MEM_BLK_SIZE), .FILE("blocks.mem")) ram_blk (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_blk), .data_i(zero_data), .data_o(data_blk));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(15), .RAM_SIZE(96*181), .FILE("start.mem")) ram_start (.clk(clk_50m), .we(1'b0), .en(mem_en), .addr(addr_start), .data_i(zero_data), .data_o(data_start));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(13), .RAM_SIZE(97*55), .FILE("gameover.mem")) ram_over (.clk(clk_50m), .we(1'b0), .en(mem_en), .addr(addr_over), .data_i(zero_data), .data_o(data_over));

    // --- Bitmaps (Preview/Hold) ---
    function [15:0] get_preview_bitmap;
        input [2:0] shape;
        case(shape)
            1:get_preview_bitmap=16'h0F00; 2:get_preview_bitmap=16'h08E0; 3:get_preview_bitmap=16'h02E0; 
            4:get_preview_bitmap=16'h0660; 5:get_preview_bitmap=16'h06C0; 6:get_preview_bitmap=16'h04E0; 
            7:get_preview_bitmap=16'h0C60; default:get_preview_bitmap=16'h0000;
        endcase
    endfunction
    wire is_next_pixel_on = get_preview_bitmap(core_next_id) >> (15 - {next_grid_y[1:0], next_grid_x[1:0]}) & 1'b1;
    wire is_hold_pixel_on = get_preview_bitmap(core_hold_id) >> (15 - {hold_grid_y[1:0], hold_grid_x[1:0]}) & 1'b1;

    // --- Text Renderers ---

    // 1. [Big Score] 分數顯示 (30x45 px) - 1.5倍放大
    wire s_on_hun, s_on_ten, s_on_unit;
    // 間距調整：字寬30 + 間距10 = 40 (SC_X, +40, +80)
    big_score_gen g1 (.digit((core_score/100)%10), .rel_x(pixel_x - SC_X),           .rel_y(pixel_y - SC_Y), .seg_on(s_on_hun));
    big_score_gen g2 (.digit((core_score/10)%10),  .rel_x(pixel_x - (SC_X + 40)),    .rel_y(pixel_y - SC_Y), .seg_on(s_on_ten));
    big_score_gen g3 (.digit(core_score%10),       .rel_x(pixel_x - (SC_X + 80)),    .rel_y(pixel_y - SC_Y), .seg_on(s_on_unit));
    wire score_active = s_on_hun || s_on_ten || s_on_unit;

    // 2. [Small Level] 等級顯示 (20x30 px) - 一般大小
    wire l_on_ten, l_on_unit;
    score_gen g_lv1 (.digit((core_level/10)%10), .rel_x(pixel_x - LV_X),         .rel_y(pixel_y - LV_Y), .seg_on(l_on_ten));
    score_gen g_lv2 (.digit(core_level%10),      .rel_x(pixel_x - (LV_X + 30)),  .rel_y(pixel_y - LV_Y), .seg_on(l_on_unit));
    wire level_active = l_on_ten || l_on_unit;

    // --- Pipeline ---
    reg [2:0] blk_id_d1, blk_id_d2, status_d1, status_d2;
    reg score_on_d1, score_on_d2;
    reg in_game_d1, in_game_d2, in_next_d1, in_next_d2, is_next_blk_d1, is_next_blk_d2;
    reg in_hold_d1, in_hold_d2, is_hold_blk_d1, is_hold_blk_d2;
    reg in_start_d1, in_start_d2, in_over_d1, in_over_d2;
    reg [11:0] data_start_d2, data_over_d2;
    
    // Pipeline Registers
    reg rank_on_d1, rank_on_d2;
    reg level_on_d1, level_on_d2;

    always @(posedge clk_50m) begin
        if (~reset_n) begin
             addr_bg <= 0; addr_blk <= 0; addr_start <= 0; addr_over <= 0;
             blk_id_d1<=0; blk_id_d2<=0; status_d1<=0; status_d2<=0;
             rank_on_d1<=0; rank_on_d2<=0; level_on_d1<=0; level_on_d2<=0;
        end else begin
            // Stage 1: Address Calc
            addr_bg <= log_y * VBUF_W + log_x; 
            if (in_next_region) addr_blk <= (core_next_id * TEX_H + next_tex_v) * TEX_W + next_tex_u;
            else if (in_hold_region) addr_blk <= (core_hold_id * TEX_H + hold_tex_v) * TEX_W + hold_tex_u;
            else addr_blk <= (core_blk_id * TEX_H + tex_v) * TEX_W + tex_u;
            addr_start <= (in_start_rect) ? (log_y - START_Y) * START_W + (log_x - START_X) : 0;
            addr_over <= (in_over_rect) ? (log_y - OVER_Y) * OVER_W + (log_x - OVER_X) : 0;

            // Stage 2: Data Fetch & Signal Latch
            blk_id_d1 <= core_blk_id; status_d1 <= core_status;
            score_on_d1 <= score_active;
            rank_on_d1 <= rank_pixel_on;    // Latch Rank
            level_on_d1 <= level_active;    // Latch Level
            in_game_d1 <= in_game_region;
            in_next_d1 <= in_next_region; is_next_blk_d1 <= (in_next_region && is_next_pixel_on);
            in_hold_d1 <= in_hold_region; is_hold_blk_d1 <= (in_hold_region && is_hold_pixel_on);
            in_start_d1 <= in_start_rect; in_over_d1 <= in_over_rect;
            data_start_d2 <= data_start; data_over_d2 <= data_over;

            // Stage 3: Sync
            blk_id_d2 <= blk_id_d1; status_d2 <= status_d1;
            score_on_d2 <= score_on_d1; 
            rank_on_d2 <= rank_on_d1; 
            level_on_d2 <= level_on_d1;
            in_game_d2 <= in_game_d1;
            in_next_d2 <= in_next_d1; is_next_blk_d2 <= is_next_blk_d1;
            in_hold_d2 <= in_hold_d1; is_hold_blk_d2 <= is_hold_blk_d1;
            in_start_d2 <= in_start_d1; in_over_d2 <= in_over_d1;
        end
    end

    // --- Mixer ---
    reg [11:0] rgb_out;
    always @(*) begin
        if (!video_on) rgb_out = 12'h000;
        else begin
            case (status_d2)
                ST_IDLE: begin
                    if (in_start_d2) rgb_out = data_start_d2;
                    else if (rank_on_d2) rgb_out = 12'hFF0; // 排行榜：黃色
                    else rgb_out = data_bg; 
                end
                ST_GAMEOVER: begin
                    if (in_over_d2) rgb_out = data_over_d2;
                    else if (rank_on_d2) rgb_out = 12'hFF0; // 排行榜：黃色
                    else rgb_out = (in_game_d2 && blk_id_d2 > 0) ? {4'hF, 4'h0, 4'h0} : ({data_bg[11:8]>>1, data_bg[7:4]>>1, data_bg[3:0]>>1});
                end
                ST_PAUSE: begin
                    if (in_game_d2 && blk_id_d2 > 0) rgb_out = data_blk; else rgb_out = data_bg; 
                end
                default: begin 
                    if (score_on_d2) rgb_out = 12'hFFF;       // 分數 (大)：白色
                    else if (level_on_d2) rgb_out = 12'h0FF;  // Level (小)：青色
                    else if (rank_on_d2) rgb_out = 12'hFF0;   // Rank (小)：黃色
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
// Rank Core: 排行榜邏輯 (輔助模組)
// ============================================================================
module rank_core (
    input clk, input rst_n, input [2:0] game_status, input [7:0] current_score,
    output reg [7:0] r1, r2, r3, r4, r5
);
    localparam ST_GAMEOVER = 5;
    reg [2:0] status_d1;
    wire is_game_over_pulse = (game_status == ST_GAMEOVER) && (status_d1 != ST_GAMEOVER);

    always @(posedge clk) begin
        if (~rst_n) begin
            status_d1 <= 0; r1<=0; r2<=0; r3<=0; r4<=0; r5<=0;
        end else begin
            status_d1 <= game_status;
            if (is_game_over_pulse) begin
                if (current_score > r1) begin r1<=current_score; r2<=r1; r3<=r2; r4<=r3; r5<=r4; end
                else if (current_score > r2) begin r2<=current_score; r3<=r2; r4<=r3; r5<=r4; end
                else if (current_score > r3) begin r3<=current_score; r4<=r3; r5<=r4; end
                else if (current_score > r4) begin r4<=current_score; r5<=r4; end
                else if (current_score > r5) begin r5<=current_score; end
            end
        end
    end
endmodule

// ============================================================================
// Rank Renderer: 排行榜顯示 (輔助模組)
// ============================================================================
module rank_renderer (
    input [9:0] pixel_x, pixel_y, input [9:0] pos_x, pos_y,
    input [7:0] r1, r2, r3, r4, r5, output rank_pixel_on
);
    localparam ROW_H = 35; 
    wire signed [10:0] diff_y = pixel_y - pos_y;
    wire [2:0] row_idx = (diff_y >= 0) ? (diff_y / ROW_H) : 3'b111;
    wire [9:0] rel_y = (diff_y >= 0) ? (diff_y % ROW_H) : 0;
    wire in_area = (pixel_x>=pos_x && pixel_x<pos_x+80 && pixel_y>=pos_y && pixel_y<pos_y+(ROW_H*5));

    reg [7:0] ts;
    always @(*) case(row_idx) 0:ts=r1; 1:ts=r2; 2:ts=r3; 3:ts=r4; 4:ts=r5; default:ts=0; endcase

    wire s_on_h, s_on_t, s_on_u;
    score_gen gh (.digit((ts/100)%10), .rel_x(pixel_x-pos_x), .rel_y(rel_y), .seg_on(s_on_h));
    score_gen gt (.digit((ts/10)%10), .rel_x(pixel_x-(pos_x+25)), .rel_y(rel_y), .seg_on(s_on_t));
    score_gen gu (.digit(ts%10), .rel_x(pixel_x-(pos_x+50)), .rel_y(rel_y), .seg_on(s_on_u));
    assign rank_pixel_on = in_area && (s_on_h || s_on_t || s_on_u);
endmodule

// ============================================================================
// Score Generator: 一般字體 (20x30)
// ============================================================================
module score_gen(
    input [3:0] digit,
    input signed [9:0] rel_x, rel_y,
    output reg seg_on
);
    always @(*) begin
        seg_on = 0;
        if (rel_x >= 0 && rel_x < 20 && rel_y >= 0 && rel_y < 30) begin
            case(digit)
                0: seg_on = (rel_x<4 || rel_x>16 || rel_y<4 || rel_y>26);
                1: seg_on = (rel_x>12);
                2: seg_on = (rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16) || (rel_x>16 && rel_y<14) || (rel_x<4 && rel_y>14));
                3: seg_on = (rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16) || rel_x>16);
                4: seg_on = (rel_x>16 || (rel_y<14 && rel_x<4) || (rel_y>12 && rel_y<16));
                5: seg_on = (rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16) || (rel_x<4 && rel_y<14) || (rel_x>16 && rel_y>14));
                6: seg_on = (rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16) || rel_x<4 || (rel_x>16 && rel_y>14));
                7: seg_on = (rel_y<4 || rel_x>16);
                8: seg_on = (rel_x<4 || rel_x>16 || rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16));
                9: seg_on = (rel_y<4 || rel_y>26 || (rel_y>12 && rel_y<16) || rel_x>16 || (rel_x<4 && rel_y<14));
            endcase
        end
    end
endmodule

// ============================================================================
// Big Score Generator: 大字體 (30x45) - 1.5x Scaling
// ============================================================================
module big_score_gen(
    input [3:0] digit,
    input signed [9:0] rel_x, rel_y,
    output wire seg_on
);
    // Range is 30x45 (1.5x of 20x30)
    wire in_range = (rel_x >= 0 && rel_x < 30 && rel_y >= 0 && rel_y < 45);
    wire base_seg_on;
    
    // Scale down coordinates by 1.5 ( multiply by 2/3 )
    // ex: 30 * 2 / 3 = 20
    score_gen base_gen (
        .digit(digit),
        .rel_x((rel_x * 2) / 3), 
        .rel_y((rel_y * 2) / 3),
        .seg_on(base_seg_on)
    );
    assign seg_on = in_range && base_seg_on;
endmodule