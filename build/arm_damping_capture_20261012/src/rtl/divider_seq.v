// divider_seq.v - unsigned sequential divider, one quotient bit per clock.
//
// WHY THIS IS ITS OWN MODULE
//   The encoder's speed path needs an integer division (a constant divided by a measured
//   period). Getting that division bit-exact inside a bigger module proved error-prone: an
//   inline version silently produced a bit-reversed quotient, which is the kind of bug that
//   yields a plausible-looking number instead of an obvious failure. Splitting it out means
//   it can be verified on its own against exact integer arithmetic (see tb_divider_seq.v),
//   and the encoder module keeps only the parts that are about encoders.
//
// ALGORITHM (schoolbook long division, MSB first)
//   rem  = 0
//   for each bit of num, MSB first:
//       rem = (rem << 1) | bit
//       if rem >= den: rem -= den; q = (q << 1) | 1
//       else         :            q = (q << 1)
//   The loop runs WIDTH times, so the quotient needs WIDTH bits and the remainder is < den.
//   Note that the LAST iteration must still update rem and q - ending the loop early (as an
//   earlier revision did) drops the final quotient bit and halves the result.
//
// HANDSHAKE
//   start is sampled on a clock edge and must be high for one cycle. busy goes high on the
//   next edge. After the final iteration there is ONE extra cycle whose only job is to present
//   the result, so done, q and r are all valid together on the same edge. An earlier revision
//   asserted done from a registered output while q was written by a blocking assignment, which
//   made done lead q by a cycle and silently hand consumers the second-to-last partial
//   quotient. A start arriving while busy is ignored.
`timescale 1ns / 1ps

module divider_seq #(
    parameter integer WIDTH = 64
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    input  wire [WIDTH-1:0]    num,
    input  wire [WIDTH-1:0]    den,     // must be non-zero; den == 0 is treated as 1
    output reg                 busy,
    output reg                 done,
    output reg  [WIDTH-1:0]    q,
    output reg  [WIDTH-1:0]    r
);

    // Iteration counter counts WIDTH down to 1; idx = i-1 is the numerator bit index, so the
    // bits are consumed MSB (WIDTH-1) first, down to LSB (0) on the final iteration.
    reg [31:0]             i;
    reg [WIDTH-1:0]        rem;
    reg [WIDTH-1:0]        quo;
    reg [WIDTH-1:0]        num_r;
    reg [WIDTH-1:0]        den_r;
    reg                    last;      // the cycle after the final iteration: present the result
    reg [WIDTH-1:0]        q_done;    // quotient computed on the final iteration

    // The bit index is computed at 32 bits and the bit-select truncates it. A narrower declared
    // width here silently truncated the subtraction before it was used, which produced wrong
    // quotients for large divisors in tb_divider_seq - so keep it 32 bits even though the upper
    // bits are unused, and waive the linter's unused-bits note on this one wire.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0]      bit_idx = i - 32'd1;
    /* verilator lint_on UNUSEDSIGNAL */
    wire             nxt_bit = num_r[bit_idx[$clog2(WIDTH)-1:0]];
    wire [WIDTH:0]   shifted = {rem, 1'b0} | {{WIDTH{1'b0}}, nxt_bit};
    wire [WIDTH:0]   den_x   = {1'b0, den_r};
    wire             ge      = (shifted >= den_x);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            last   <= 1'b0;
            i      <= 32'd0;
            rem    <= {WIDTH{1'b0}};
            quo    <= {WIDTH{1'b0}};
            num_r  <= {WIDTH{1'b0}};
            den_r  <= {WIDTH{1'b0}};
            q      <= {WIDTH{1'b0}};
            r      <= {WIDTH{1'b0}};
            q_done <= {WIDTH{1'b0}};
        end else begin
            done <= 1'b0;

            if (!busy && !last && start) begin
                busy  <= 1'b1;
                i     <= WIDTH;
                rem   <= {WIDTH{1'b0}};
                quo   <= {WIDTH{1'b0}};
                num_r <= num;
                den_r <= (den == {WIDTH{1'b0}}) ? {{(WIDTH-1){1'b0}}, 1'b1} : den;
            end else if (busy) begin
                // Always update rem and quo, including on the final iteration.
                rem <= ge ? shifted[WIDTH-1:0] - den_r : shifted[WIDTH-1:0];
                quo <= ge ? ((quo << 1) | {{(WIDTH-1){1'b0}}, 1'b1}) : (quo << 1);

                if (i == 32'd1) begin
                    busy   <= 1'b0;
                    last   <= 1'b1;             // one presentation cycle follows
                    // Non-blocking is safe here: the value is consumed in the `last` cycle, one
                    // clock later, by which time this assignment has taken effect.
                    q_done <= ge ? ((quo << 1) | {{(WIDTH-1){1'b0}}, 1'b1}) : (quo << 1);
                    r      <= ge ? shifted[WIDTH-1:0] - den_r : shifted[WIDTH-1:0];
                end else begin
                    i <= i - 32'd1;
                end
            end else if (last) begin
                last <= 1'b0;
                done <= 1'b1;
                q    <= q_done;
            end
        end
    end
endmodule
