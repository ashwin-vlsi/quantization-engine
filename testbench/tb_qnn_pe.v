module tb_qnn_pe;

    reg clk, rst, en, load_bias;
    reg [1:0] precision;
    reg signed [7:0] a, b;
    reg signed [31:0] bias;
    reg [4:0] shift;

    wire signed [31:0] acc;
    wire signed [7:0] result;

    qnn_pe dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .load_bias(load_bias),
        .precision(precision),
        .a(a),
        .b(b),
        .bias(bias),
        .shift(shift),
        .acc(acc),
        .result(result)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Apply one MAC operation
    task mac;
        input [1:0] mode;
        input signed [7:0] x;
        input signed [7:0] y;
        begin
            @(negedge clk);
            precision = mode;
            a = x;
            b = y;
            en = 1;

            @(negedge clk);
            en = 0;

            #1;
            $display(
                "MAC: mode=%b, a=%0d, b=%0d, acc=%0d, result=%0d",
                mode, x, y, acc, result
            );
        end
    endtask

    // Load the accumulator with a bias value
    task set_bias;
        input signed [31:0] value;
        begin
            @(negedge clk);
            bias = value;
            load_bias = 1;

            @(negedge clk);
            load_bias = 0;

            #1;
        end
    endtask

    initial begin

        rst = 1;
        en = 0;
        load_bias = 0;
        precision = 0;
        a = 0;
        b = 0;
        bias = 0;
        shift = 0;

        repeat (2) @(negedge clk);
        rst = 0;

        $display("\n--- QNN-PE TEST START ---");

        // Test 1: INT8 multiplication
        mac(2'b00, 8'd3, 8'd4);
        // Expected accumulator: 12

        // Test 2: INT4 signed multiplication
        mac(2'b01, 8'hFD, 8'd2);
        // -3 * 2 = -6; accumulator: 6

        // Test 3: INT2 signed multiplication
        mac(2'b10, 8'hFF, 8'hFE);
        // -1 * -2 = 2; accumulator: 8

        // Test 4: Zero-skipping
        mac(2'b00, 8'd0, 8'd100);
        // Accumulator remains 8

        // Test 5: Requantization with right shift
        @(negedge clk);
        shift = 1;
        #1;
        $display("Shift=1: acc=%0d, result=%0d", acc, result);
        // Expected result: 4

        // Test 6: Positive output saturation
        set_bias(32'sd1000);
        shift = 0;
        #1;
        $display("Positive saturation: acc=%0d, result=%0d",
                 acc, result);
        // Expected result: 127

        // Test 7: Negative output saturation
        set_bias(-32'sd1000);
        #1;
        $display("Negative saturation: acc=%0d, result=%0d",
                 acc, result);
        // Expected result: -128

        $display("--- QNN-PE TEST COMPLETE ---\n");

        $finish;
    end

endmodule
