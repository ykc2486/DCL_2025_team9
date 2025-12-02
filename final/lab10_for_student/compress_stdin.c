/* ////////////////////////////////////////////////////////////////////////// */
/* File   : compress_stdin_to_file.c                                         */
/* Usage  : compress.exe <output_filename>                                    */
/* Example: compress.exe fish1.mem                                            */
/* -------------------------------------------------------------------------- */
/* 功能：                                                                     */
/* 1. 執行時指定輸出檔名。                                                     */
/* 2. 等待使用者貼上 12-bit hex 數據 (如 0f0 1a3...)。                         */
/* 3. 自動轉換為 8-bit 並寫入指定的檔案中。                                    */
/* ////////////////////////////////////////////////////////////////////////// */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    char buffer[64]; // 用來暫存輸入的字串
    int val_12bit;
    int val_8bit;
    FILE *out_fp = NULL;
    int count = 0;

    // 1. 檢查是否有指定輸出檔名
    if (argc < 2) {
        fprintf(stderr, "Error: Please specify an output filename.\n");
        fprintf(stderr, "Usage: %s <output_filename>\n", argv[0]);
        fprintf(stderr, "Example: %s fish1.mem\n", argv[0]);
        return -1;
    }

    // 2. 開啟輸出檔案
    out_fp = fopen(argv[1], "w");
    if (out_fp == NULL) {
        fprintf(stderr, "Error: Cannot create file '%s'.\n", argv[1]);
        return -1;
    }

    // 3. 顯示提示訊息
    printf("=======================================================\n");
    printf("  Output File: [%s] (Opened)\n", argv[1]);
    printf("=======================================================\n");
    printf("Please paste your 12-bit hex data below now...\n");
    printf("(To FINISH: Press Ctrl+Z then Enter)\n");
    printf("-------------------------------------------------------\n");

    // 4. 迴圈：持續讀取鍵盤輸入/貼上的數據
    while (scanf("%s", buffer) == 1)
    {
        // 嘗試解析為 16 進位整數
        if (sscanf(buffer, "%x", &val_12bit) != 1) {
            continue; // 忽略非 Hex 的雜訊
        }

        // --- 轉換邏輯 ---
        
        // A. 綠幕保留檢查 (RGB 0,15,0 -> 0x0F0)
        if (val_12bit == 0x0F0) {
            // 寫入檔案
            fprintf(out_fp, "1c\n");
        }
        else {
            // B. 執行壓縮 (12-bit -> 8-bit)
            int r = (val_12bit >> 8) & 0xF; 
            int g = (val_12bit >> 4) & 0xF; 
            int b = (val_12bit >> 0) & 0xF; 

            int r3 = r >> 1; // 4->3 bits
            int g3 = g >> 1; // 4->3 bits
            int b2 = b >> 2; // 4->2 bits

            val_8bit = (r3 << 5) | (g3 << 2) | b2;

            // 寫入檔案
            fprintf(out_fp, "%02x\n", val_8bit);
        }
        count++;
    }

    // 5. 關閉檔案並報告結果
    fclose(out_fp);
    printf("\n-------------------------------------------------------\n");
    printf("Done! %d pixels written to '%s'.\n", count, argv[1]);
    printf("-------------------------------------------------------\n");

    return 0;
}