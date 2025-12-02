module score_gen(
    input [3:0] digit,
    input signed [9:0] rel_x, 
    input signed [9:0] rel_y,
    output reg seg_on
);
    parameter W=20, H=30, T=3;
    reg [6:0] s;
    
    always @(*) begin
        case(digit)
            0: s=7'b1111110; 1: s=7'b0110000; 2: s=7'b1101101; 3: s=7'b1111001;
            4: s=7'b0110011; 5: s=7'b1011011; 6: s=7'b1011111; 7: s=7'b1110000;
            8: s=7'b1111111; 9: s=7'b1111011; default: s=0;
        endcase
        
        seg_on = 0;
        if (rel_x >= 0 && rel_x < W && rel_y >= 0 && rel_y < H) begin
            seg_on = (s[6] && rel_y<T) || // a
                     (s[5] && rel_x>=W-T && rel_y<H/2) || // b
                     (s[4] && rel_x>=W-T && rel_y>=H/2) || // c
                     (s[3] && rel_y>=H-T) || // d
                     (s[2] && rel_x<T && rel_y>=H/2) || // e
                     (s[1] && rel_x<T && rel_y<H/2) || // f
                     (s[0] && rel_y>=H/2-T/2 && rel_y<=H/2+T/2); // g
        end
    end
endmodule