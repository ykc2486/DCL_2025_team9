# ppm_to_mem.py
import os
from PIL import Image

def convert_ppm_to_mem():
    # --- 設定區 ---
    INPUT_PPM  = "background.ppm"      # 你的輸入檔名 (256x223)
    OUTPUT_MEM = "images.mem"  # 你的輸出檔名
    
    # 設定目標大小 (VGA 640x480 的一半)
    TARGET_WIDTH  = 320
    TARGET_HEIGHT = 240

    print(f"正在讀取 PPM 檔案: {INPUT_PPM}")

    try:
        # 1. 讀取 PPM
        img = Image.open(INPUT_PPM).convert("RGB")
        print(f"原始尺寸: {img.width} x {img.height}")

        # 2. 強制縮放到 320x240
        # Image.Resampling.LANCZOS 用於保持最佳畫質
        print(f"正在強制縮放至 {TARGET_WIDTH} x {TARGET_HEIGHT}...")
        img = img.resize((TARGET_WIDTH, TARGET_HEIGHT), Image.Resampling.LANCZOS)
        
        width, height = img.size # 更新寬高變數

        # 3. 轉換並寫入
        print(f"正在轉換為 12-bit Hex -> {OUTPUT_MEM}")
        count = 0
        with open(OUTPUT_MEM, 'w') as f:
            for y in range(height):
                for x in range(width):
                    r, g, b = img.getpixel((x, y))
                    
                    # 12-bit 轉換 (RGB444)
                    r4 = r >> 4
                    g4 = g >> 4
                    b4 = b >> 4
                    val = (r4 << 8) | (g4 << 4) | b4
                    
                    f.write(f"{val:03x}\n")
                    count += 1

        print("------------------------------------------------")
        print("轉換成功！")
        print(f"輸出檔案: {OUTPUT_MEM}")
        print(f"總像素數: {count}")
        print("------------------------------------------------")
        print("請確認 tetris_top.v 參數設定為：")
        print("localparam MEM_BG_SIZE = 76800;")
        print("localparam VBUF_W      = 320;")

    except FileNotFoundError:
        print(f"錯誤：找不到檔案 '{INPUT_PPM}'")

if __name__ == "__main__":
    convert_ppm_to_mem()
