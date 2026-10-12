`timescale 1ns/1ps
// SSD1306, 128x64, I2C. Full signed 32-bit decimal counts, one snapshot/frame.
// No framebuffer or division: 32-cycle double dabble and a small 5x7 font.
module oled_encoder_display #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer I2C_HZ=100_000,
    parameter [6:0] ADDRESS=7'h3c,
    parameter integer COLUMN_OFFSET=0,
    parameter integer POWER_WAIT_MS=100,
    parameter integer REFRESH_MS=100,
    parameter integer RETRY_MS=500
) (
    input wire clk, rst_n,
    input wire signed [31:0] raw_count, position_count, relative_count,
    inout wire scl, sda,
    output reg initialized, error, frame_done
);
    localparam integer POWER_CYCLES=(CLK_HZ/1000)*POWER_WAIT_MS;
    localparam integer REFRESH_CYCLES=(CLK_HZ/1000)*REFRESH_MS;
    localparam integer RETRY_CYCLES=(CLK_HZ/1000)*RETRY_MS;
    localparam [3:0] POWER=0, PREPARE=1, SEND=2, WAIT_BYTE=3,
        SNAPSHOT=4, CONVERT=5, FRAME_WAIT=6, RETRY=7;
    localparam [1:0] INIT=0, COMMAND=1, PIXELS=2;
    reg [3:0] state;
    reg [1:0] kind;
    reg [7:0] byte_index, tx_data;
    reg [2:0] page, glyph_column;
    reg [4:0] character_index;
    reg [31:0] wait_count, frame_age;
    reg [31:0] magnitude_raw, magnitude_pos, magnitude_rel;
    reg [39:0] bcd_raw, bcd_pos, bcd_rel;
    reg sign_raw, sign_pos, sign_rel;
    reg [5:0] conversion_bit;
    reg tx_start;
    wire tx_busy, tx_done, tx_error;
    wire last_byte=(kind==INIT) ? byte_index==26 :
                   (kind==COMMAND) ? byte_index==4 : byte_index==129;
    oled_i2c_writer #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ)) writer (
        .clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),
        .first_byte(byte_index==0),.last_byte(last_byte),
        .scl(scl),.sda(sda),.busy(tx_busy),.done(tx_done),.error(tx_error));

    function [7:0] init_command;
        input [7:0] index;
        begin
            case (index)
                0:init_command=8'hae; 1:init_command=8'hd5; 2:init_command=8'h80;
                3:init_command=8'ha8; 4:init_command=8'h3f; 5:init_command=8'hd3;
                6:init_command=8'h00; 7:init_command=8'h40; 8:init_command=8'ha1;
                9:init_command=8'hc8; 10:init_command=8'hda; 11:init_command=8'h12;
                12:init_command=8'h81; 13:init_command=8'hcf; 14:init_command=8'hd9;
                15:init_command=8'hf1; 16:init_command=8'hdb; 17:init_command=8'h30;
                18:init_command=8'ha4; 19:init_command=8'ha6; 20:init_command=8'h8d;
                21:init_command=8'h14; 22:init_command=8'h20; 23:init_command=8'h02;
                24:init_command=8'haf; default:init_command=0;
            endcase
        end
    endfunction
    function [39:0] dabble;
        input [39:0] bcd;
        input incoming;
        reg [39:0] adjusted;
        integer n;
        begin
            adjusted=bcd;
            for (n=0;n<10;n=n+1)
                if (bcd[n*4+:4]>=5) adjusted[n*4+:4]=bcd[n*4+:4]+4'd3;
            dabble={adjusted[38:0],incoming};
        end
    endfunction
    // Each byte is one vertical column; bit 0 is the top pixel.
    function [39:0] font;
        input [7:0] ch;
        begin
            case (ch)
                "0":font=40'h3e5149453e; "1":font=40'h00427f4000;
                "2":font=40'h4261514946; "3":font=40'h2141454b31;
                "4":font=40'h1814127f10; "5":font=40'h2745454539;
                "6":font=40'h3c4a494930; "7":font=40'h0171090503;
                "8":font=40'h3649494936; "9":font=40'h064949291e;
                "A":font=40'h7e1111117e; "C":font=40'h3e41414122;
                "D":font=40'h7f4141221c; "E":font=40'h7f49494941;
                "L":font=40'h7f40404040; "N":font=40'h7f0408107f;
                "O":font=40'h3e4141413e; "P":font=40'h7f09090906;
                "R":font=40'h7f09192946; "S":font=40'h4649494931;
                "T":font=40'h01017f0101; "U":font=40'h3f4040403f;
                "W":font=40'h3f4038403f; "+":font=40'h08083e0808;
                "-":font=40'h0808080808; ":":font=40'h0036360000;
                default:font=0;
            endcase
        end
    endfunction
    reg [7:0] character;
    reg [39:0] line_bcd, glyph;
    reg line_sign;
    reg [3:0] digit;
    reg [7:0] payload;
    always @* begin
        line_bcd=bcd_raw; line_sign=sign_raw;
        if (page==4) begin line_bcd=bcd_pos; line_sign=sign_pos; end
        if (page==6) begin line_bcd=bcd_rel; line_sign=sign_rel; end
        character=" "; digit=0;
        if (page==0) begin
            case (character_index)
                0:character="E"; 1:character="N"; 2:character="C";
                3:character="O"; 4:character="D"; 5:character="E";
                6:character="R"; 8:character="C"; 9:character="O";
                10:character="U"; 11:character="N"; 12:character="T";
                13:character="S"; default:character=" ";
            endcase
        end else if (page==2 || page==4 || page==6) begin
            case (character_index)
                0:character=(page==4)?"P":"R";
                1:character=(page==2)?"A":(page==4)?"O":"E";
                2:character=(page==2)?"W":(page==4)?"S":"L";
                3:character=":";
                4:character=line_sign?"-":"+";
                default:begin
                    if (character_index>=5 && character_index<=14) begin
                        digit=line_bcd[(14-character_index)*4+:4];
                        character=8'h30+digit;
                    end
                end
            endcase
        end
        glyph=font(character);
        if (byte_index==0) payload={ADDRESS,1'b0};
        else if (byte_index==1) payload=(kind==PIXELS)?8'h40:8'h00;
        else if (kind==INIT) payload=init_command(byte_index-8'd2);
        else if (kind==COMMAND) begin
            case (byte_index)
                2:payload=8'hb0|{5'b0,page};
                3:payload=8'h10|((COLUMN_OFFSET>>4)&8'h0f);
                default:payload=COLUMN_OFFSET&8'h0f;
            endcase
        end else if (glyph_column<5) payload=glyph[(4-glyph_column)*8+:8];
        else payload=0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=POWER; kind<=INIT; byte_index<=0; page<=0;
            glyph_column<=0; character_index<=0; wait_count<=0; frame_age<=0;
            magnitude_raw<=0; magnitude_pos<=0; magnitude_rel<=0;
            bcd_raw<=0; bcd_pos<=0; bcd_rel<=0;
            sign_raw<=0; sign_pos<=0; sign_rel<=0; conversion_bit<=0;
            tx_start<=0; tx_data<=0; initialized<=0; error<=0; frame_done<=0;
        end else begin
            tx_start<=0; frame_done<=0;
            if (frame_age<REFRESH_CYCLES) frame_age<=frame_age+1;
            case (state)
                POWER: if (wait_count>=POWER_CYCLES) begin
                    wait_count<=0; state<=PREPARE;
                end else wait_count<=wait_count+1;
                PREPARE: begin tx_data<=payload; state<=SEND; end
                SEND: if (!tx_busy) begin tx_start<=1; state<=WAIT_BYTE; end
                WAIT_BYTE: if (tx_done) begin
                    if (tx_error) begin
                        error<=1; initialized<=0; wait_count<=0; state<=RETRY;
                    end else if (!last_byte) begin
                        byte_index<=byte_index+8'd1; state<=PREPARE;
                        if (kind==PIXELS && byte_index>=2) begin
                            if (glyph_column==5) begin
                                glyph_column<=0; character_index<=character_index+5'd1;
                            end else glyph_column<=glyph_column+3'd1;
                        end
                    end else begin
                        byte_index<=0;
                        if (kind==INIT) begin initialized<=1; error<=0; state<=SNAPSHOT; end
                        else if (kind==COMMAND) begin
                            kind<=PIXELS; glyph_column<=0; character_index<=0; state<=PREPARE;
                        end else if (page==7) begin
                            frame_done<=1; error<=0; state<=FRAME_WAIT;
                    end else begin page<=page+3'd1; kind<=COMMAND; state<=PREPARE; end
                    end
                end
                SNAPSHOT: begin
                    // Unsigned magnitudes include abs(-2147483648) without overflow.
                    magnitude_raw<=raw_count[31] ? -raw_count : raw_count;
                    magnitude_pos<=position_count[31] ? -position_count : position_count;
                    magnitude_rel<=relative_count[31] ? -relative_count : relative_count;
                    sign_raw<=raw_count[31]; sign_pos<=position_count[31]; sign_rel<=relative_count[31];
                    bcd_raw<=0; bcd_pos<=0; bcd_rel<=0; conversion_bit<=0;
                    frame_age<=0; state<=CONVERT;
                end
                CONVERT: begin
                    bcd_raw<=dabble(bcd_raw,magnitude_raw[31]); magnitude_raw<=magnitude_raw<<1;
                    bcd_pos<=dabble(bcd_pos,magnitude_pos[31]); magnitude_pos<=magnitude_pos<<1;
                    bcd_rel<=dabble(bcd_rel,magnitude_rel[31]); magnitude_rel<=magnitude_rel<<1;
                    if (conversion_bit==31) begin page<=0; kind<=COMMAND; byte_index<=0; state<=PREPARE; end
                    else conversion_bit<=conversion_bit+6'd1;
                end
                FRAME_WAIT: if (frame_age>=REFRESH_CYCLES) state<=SNAPSHOT;
                RETRY: if (wait_count>=RETRY_CYCLES) begin
                    kind<=INIT; byte_index<=0; wait_count<=0; state<=PREPARE;
                end else wait_count<=wait_count+1;
                default: state<=POWER;
            endcase
        end
    end
endmodule
