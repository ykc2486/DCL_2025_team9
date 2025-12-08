module tetris_top(
    input  clk,          // 100MHz
    input  reset_n,      // Active Low
    input  [3:0] usr_btn,// {3:Rot, 2:Left, 1:Right, 0:Down}
    input  [3:0] usr_sw, // sw[0] 用於 Hold
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
);

    // --- 參數定義 ---
    localparam BLK_SIZE = 20;
    localparam MEM_BG_SIZE = 76800; 
    localparam VBUF_W = 320; 
    localparam MEM_BLK_SIZE = 3200; 
    localparam TEX_W = 20;
    localparam TEX_H = 20;
    
    // 遊戲區
    localparam OFF_X = 240;
    localparam OFF_Y = 30;
    localparam GAME_W = 200; 
    localparam GAME_H = 400; 

    // 分數位置
    localparam SC_X = 490;
    localparam SC_Y = 125;

    // Next Piece 預覽區
    localparam NEXT_X = 490; 
    localparam NEXT_Y = 220;
    localparam NEXT_W = 80;
    localparam NEXT_H = 80;

    // [修正] Hold Piece 暫存區 (X=80, Y=363)
    localparam HOLD_X = 80;
    localparam HOLD_Y = 363;
    localparam HOLD_W = 80;
    localparam HOLD_H = 80;

    // --- 1. 時鐘生成 ---
    wire clk_50m; 
    clk_divider #(.divider(2)) cd0 (.clk(clk), .reset(~reset_n), .clk_out(clk_50m));

    // --- 2. 系統訊號 ---
    wire video_on, p_tick; 
    wire [9:0] pixel_x, pixel_y;
    wire [3:0] btn_clean;
    
    wire [2:0] core_blk_id; 
    wire [7:0] core_score;
    wire [2:0] core_next_id; 
    wire [2:0] core_hold_id; 

    // --- 3. VGA Sync ---
    vga_sync vs0 (
        .clk(clk_50m),      
        .reset(~reset_n),   
        .oHS(VGA_HSYNC), 
        .oVS(VGA_VSYNC), 
        .visible(video_on), 
        .p_tick(p_tick),    
        .pixel_x(pixel_x), 
        .pixel_y(pixel_y)
    );

    // --- 4. 按鈕除抖動 ---
    debounce db3 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[3]), .btn_out(btn_clean[3])); 
    debounce db2 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[2]), .btn_out(btn_clean[2])); 
    debounce db1 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[1]), .btn_out(btn_clean[1])); 
    debounce db0 (.clk(clk_50m), .reset_n(reset_n), .btn_in(~usr_btn[0]), .btn_out(btn_clean[0])); 

    // --- 5. 座標區域判定 ---
    // Game Region
    wire in_game_region = (pixel_x >= OFF_X && pixel_x < OFF_X + GAME_W && 
                           pixel_y >= OFF_Y && pixel_y < OFF_Y + GAME_H);
    wire [9:0] safe_grid_x = (in_game_region) ? (pixel_x - OFF_X) / 20 : 0;
    wire [9:0] safe_grid_y = (in_game_region) ? (pixel_y - OFF_Y) / 20 : 0;
    wire [4:0] tex_u       = (in_game_region) ? (pixel_x - OFF_X) % 20 : 0;
    wire [4:0] tex_v       = (in_game_region) ? (pixel_y - OFF_Y) % 20 : 0;

    // Next Region
    wire in_next_region = (pixel_x >= NEXT_X && pixel_x < NEXT_X + NEXT_W && 
                           pixel_y >= NEXT_Y && pixel_y < NEXT_Y + NEXT_H);
    wire [2:0] next_grid_x = (pixel_x - NEXT_X) / 20;
    wire [2:0] next_grid_y = (pixel_y - NEXT_Y) / 20;
    wire [4:0] next_tex_u  = (pixel_x - NEXT_X) % 20;
    wire [4:0] next_tex_v  = (pixel_y - NEXT_Y) % 20;

    // Hold Region
    wire in_hold_region = (pixel_x >= HOLD_X && pixel_x < HOLD_X + HOLD_W && 
                           pixel_y >= HOLD_Y && pixel_y < HOLD_Y + HOLD_H);
    wire [2:0] hold_grid_x = (pixel_x - HOLD_X) / 20;
    wire [2:0] hold_grid_y = (pixel_y - HOLD_Y) / 20;
    wire [4:0] hold_tex_u  = (pixel_x - HOLD_X) % 20;
    wire [4:0] hold_tex_v  = (pixel_y - HOLD_Y) % 20;

    // --- 6. 遊戲核心 ---
    tetris_core core (
        .clk(clk_50m), 
        .rst(~reset_n), 
        .btn(btn_clean), 
        .sw_hold(usr_sw[0]), 
        .grid_x(safe_grid_x), 
        .grid_y(safe_grid_y),
        .pixel_block_id(core_blk_id),
        .score(core_score),
        .next_piece_id(core_next_id),
        .hold_piece_id(core_hold_id)
    );

    // --- 7. SRAM ---
    wire mem_we = usr_sw[3]; 
    wire mem_en = 1'b1;     
    wire [11:0] zero_data = 12'h0;
    reg  [16:0] addr_bg;
    reg  [11:0] addr_blk;
    wire [11:0] data_bg;    
    wire [11:0] data_blk;   

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(MEM_BG_SIZE), .FILE("images.mem"))
        ram_bg (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_bg), .data_i(zero_data), .data_o(data_bg));

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(12), .RAM_SIZE(MEM_BLK_SIZE), .FILE("blocks.mem"))
        ram_blk (.clk(clk_50m), .we(mem_we), .en(mem_en), .addr(addr_blk), .data_i(zero_data), .data_o(data_blk));

    // --- 8. Preview Bitmap Logic ---
    function [15:0] get_preview_bitmap;
        input [2:0] shape;
        begin
            case(shape)
                1: get_preview_bitmap = 16'h0F00; // I
                2: get_preview_bitmap = 16'h08E0; // J
                3: get_preview_bitmap = 16'h02E0; // L
                4: get_preview_bitmap = 16'h0660; // O
                5: get_preview_bitmap = 16'h06C0; // S
                6: get_preview_bitmap = 16'h04E0; // T
                7: get_preview_bitmap = 16'h0C60; // Z
                default: get_preview_bitmap = 16'h0000;
            endcase
        end
    endfunction

    wire [15:0] next_bitmap = get_preview_bitmap(core_next_id);
    wire is_next_pixel_on = next_bitmap[15 - {next_grid_y[1:0], next_grid_x[1:0]}];

    wire [15:0] hold_bitmap = get_preview_bitmap(core_hold_id);
    wire is_hold_pixel_on = hold_bitmap[15 - {hold_grid_y[1:0], hold_grid_x[1:0]}];

    // --- 9. Score Gen ---
    wire signed [9:0] rx1 = pixel_x - SC_X;
    wire signed [9:0] ry1 = pixel_y - SC_Y;
    wire signed [9:0] rx2 = pixel_x - (SC_X + 30);
    wire signed [9:0] rx3 = pixel_x - (SC_X + 60);
    
    wire s_on_hun, s_on_ten, s_on_unit;
    score_gen g1 (.digit((core_score/100)%10), .rel_x(rx1), .rel_y(ry1), .seg_on(s_on_hun));
    score_gen g2 (.digit((core_score/10)%10),  .rel_x(rx2), .rel_y(ry1), .seg_on(s_on_ten));
    score_gen g3 (.digit(core_score%10),       .rel_x(rx3), .rel_y(ry1), .seg_on(s_on_unit));
    
    wire score_active = s_on_hun || s_on_ten || s_on_unit;

    // --- 10. Pipeline & Mixer ---
    reg [2:0] blk_id_d1, blk_id_d2;
    reg score_on_d1, score_on_d2;
    reg in_game_d1, in_game_d2; 
    reg in_next_d1, in_next_d2;
    reg is_next_blk_d1, is_next_blk_d2;
    reg in_hold_d1, in_hold_d2;
    reg is_hold_blk_d1, is_hold_blk_d2;

    always @(posedge clk_50m) begin
        if (~reset_n) begin
            addr_bg <= 0; addr_blk <= 0;
            blk_id_d1 <= 0; blk_id_d2 <= 0;
            score_on_d1 <= 0; score_on_d2 <= 0;
            in_game_d1 <= 0; in_game_d2 <= 0;
            in_next_d1 <= 0; in_next_d2 <= 0;
            is_next_blk_d1 <= 0; is_next_blk_d2 <= 0;
            in_hold_d1 <= 0; in_hold_d2 <= 0;
            is_hold_blk_d1 <= 0; is_hold_blk_d2 <= 0;
        end else begin
            // AGU
            addr_bg <= (pixel_y[9:1]) * VBUF_W + (pixel_x[9:1]);
            
            if (in_next_region)
                addr_blk <= (core_next_id * TEX_H + next_tex_v) * TEX_W + next_tex_u;
            else if (in_hold_region)
                addr_blk <= (core_hold_id * TEX_H + hold_tex_v) * TEX_W + hold_tex_u;
            else
                addr_blk <= (core_blk_id * TEX_H + tex_v) * TEX_W + tex_u;

            // Delay
            blk_id_d1 <= core_blk_id;
            score_on_d1 <= score_active;
            in_game_d1 <= in_game_region;
            in_next_d1 <= in_next_region;
            is_next_blk_d1 <= (in_next_region && is_next_pixel_on);
            in_hold_d1 <= in_hold_region;
            is_hold_blk_d1 <= (in_hold_region && is_hold_pixel_on);

            // Data Ready
            blk_id_d2 <= blk_id_d1;
            score_on_d2 <= score_on_d1;
            in_game_d2 <= in_game_d1;
            in_next_d2 <= in_next_d1;
            is_next_blk_d2 <= is_next_blk_d1;
            in_hold_d2 <= in_hold_d1;
            is_hold_blk_d2 <= is_hold_blk_d1;
        end
    end

    // Mixer
    reg [11:0] rgb_out;
    always @(*) begin
        if (!video_on) begin
            rgb_out = 12'h000;
        end else begin
            if (score_on_d2) rgb_out = 12'hFFF; 
            else if (in_game_d2 && blk_id_d2 > 0) rgb_out = data_blk; 
            else if (in_next_d2 && is_next_blk_d2) rgb_out = data_blk; 
            else if (in_hold_d2 && is_hold_blk_d2 && core_hold_id > 0) rgb_out = data_blk; 
            else rgb_out = data_bg;
        end
    end

    reg [11:0] rgb_reg;
    always @(posedge clk_50m) if (p_tick) rgb_reg <= rgb_out;
    assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

endmodule