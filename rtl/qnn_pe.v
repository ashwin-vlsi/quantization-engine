module qnn_pe (
    input  wire               clk,
    input  wire               rst,
    input  wire               en,
    input  wire               load_bias,

    input  wire [1:0]         precision,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    input  wire signed [31:0] bias,
    input  wire [4:0]         shift,

    output reg  signed [31:0] acc,
    output reg  signed [7:0]  result
);

    reg signed [7:0]  qa, qb;
    reg signed [15:0] product;
    reg signed [32:0] sum_ext;
    reg signed [32:0] rounded;
    reg signed [32:0] scaled;

    // --------------------------------------------------------
    // 1. Configurable-Precision Operand Selection
    // precision = 00 : INT8
    // precision = 01 : INT4
    // precision = 10 : INT2
    // precision = 11 : Reserved; defaults to INT8
    // --------------------------------------------------------

    always @(*) begin
        qa = 0;
        qb = 0;

        // Operand isolation when processing is disabled
        if (en) begin
            case (precision)

                2'b00: begin
                    qa = a;
                    qb = b;
                end

                2'b01: begin
                    qa = {{4{a[3]}}, a[3:0]};
                    qb = {{4{b[3]}}, b[3:0]};
                end

                2'b10: begin
                    qa = {{6{a[1]}}, a[1:0]};
                    qb = {{6{b[1]}}, b[1:0]};
                end

                default: begin
                    qa = a;
                    qb = b;
                end

            endcase
        end
    end

    // --------------------------------------------------------
    // 2. Multiplier with Zero-Skipping
    // --------------------------------------------------------

    always @(*) begin
        if (!en || qa == 0 || qb == 0)
            product = 0;
        else
            product = qa * qb;
    end

    // --------------------------------------------------------
    // 3. MAC Accumulator with Signed Overflow Protection
    // --------------------------------------------------------

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc <= 0;
        end
        else if (load_bias) begin
            acc <= bias;
        end
        else if (en && qa != 0 && qb != 0) begin

            sum_ext = {acc[31], acc}
                    + {{17{product[15]}}, product};

            // Saturate instead of wrapping on overflow
            if (sum_ext[32] != sum_ext[31]) begin
                if (acc[31] == 0)
                    acc <= 32'sh7FFFFFFF;
                else
                    acc <= 32'sh80000000;
            end
            else begin
                acc <= sum_ext[31:0];
            end

        end
    end

    // --------------------------------------------------------
    // 4. Requantization: Rounding + Right Shift
    // --------------------------------------------------------

    always @(*) begin

        rounded = {acc[31], acc};

        // Round to nearest for positive shift values
        if (shift != 0)
            rounded = rounded
                    + (33'sd1 <<< (shift - 1'b1));

        scaled = rounded >>> shift;

        // Saturate output to signed INT8 range
        if (scaled > 127)
            result = 8'sd127;
        else if (scaled < -128)
            result = -8'sd128;
        else
            result = scaled[7:0];

    end
endmodule
