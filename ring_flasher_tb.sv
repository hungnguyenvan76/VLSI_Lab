`timescale 1ns/1ps

module ring_flasher_tb;
    // ── Parameters ───────────────────────────────────────────────
    parameter NUM_LEDS = 16;
    parameter CW_STEPS = 12;
    parameter ACW_STEPS  = 8;
    parameter STEP_TICKS = 25; 
    parameter NUM_LEVELS = 6;    
    parameter STEP_DECAYS = 25;

    localparam IDLE  = 2'd0;
    localparam ACW   = 2'd1;
    localparam CW    = 2'd2;
    localparam DECAY = 2'd3;

    // ── DUT interface ────────────────────────────────────────────
    logic clk;
    logic rst_n;
    logic rep;
    logic [NUM_LEDS-1:0] led_pwm;
    
    ring_flasher_ex #(
        .NUM_LEDS(NUM_LEDS),
        .CW_STEPS(CW_STEPS),
        .ACW_STEPS(ACW_STEPS),
        .STEP_TICKS(STEP_TICKS),
        .NUM_LEVELS(NUM_LEVELS),
        .STEP_DECAYS(STEP_DECAYS)
    ) dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .rep(rep), 
        .led_pwm(led_pwm)
    );

    // 5 MHz → 200 ns period
    initial clk = 0;
    always #100 clk = ~clk;

    // ── Helpers ──────────────────────────────────────────────────
    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk(input string msg, input logic cond);
        if (cond) begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s  (time=%0t)", msg, $time);
            fail_cnt++;
        end
    endtask

    task automatic wait_step_ticks(input int n);
        repeat(n) @(posedge clk iff dut.step_pulse);
        #1; 
    endtask

    task automatic wait_decay_ticks(input int n);
        repeat(n) @(posedge clk iff dut.decay_pulse);
        #1;
    endtask

    task automatic do_reset();
        rst_n = 0; rep = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        #1;
    endtask

    function automatic logic all_zero();
        for (int i = 0; i < NUM_LEDS; i++)
            if (dut.brightness[i] != 0) return 0;
        return 1;
    endfunction

    // ── Test cases ───────────────────────────────────────────────
    initial begin
        $dumpfile("ring_flasher_tb.vcd");
        $dumpvars(0, ring_flasher_tb);

        // ── TC1: Reset ──────────────────────────────────────────
        $display("\n── TC1: Reset ──");
        do_reset();
        chk("TC1.1 state=IDLE",        dut.state    == IDLE);
        chk("TC1.2 head_pos=0",        dut.head_pos == 0);
        chk("TC1.3 led_pwm=0",         led_pwm      == '0);
        chk("TC1.4 all brightness=0",  all_zero());

        // ── TC2: IDLE hold (rep=0) ──────────────────────────────
        $display("\n── TC2: IDLE hold (rep=0) ──");
        repeat(3 * STEP_TICKS) @(posedge clk); #1; 
        chk("TC2.1 still IDLE",     dut.state == IDLE);
        chk("TC2.2 leds still off", led_pwm   == '0);

        // ── TC3: IDLE → CW ──────────────────────────────────────
        $display("\n── TC3: IDLE → CW ──");
        @(negedge clk); rep = 1;
        @(posedge clk); #1;
        chk("TC3.1 state=CW", dut.state == CW);

        // ── TC4: CW step 1 - led[0] sáng, head nhảy sang 1 ──────
        $display("\n── TC4: CW step 1 ──");
        wait_step_ticks(1);
        chk("TC4.1 head_pos=1",             dut.head_pos    == 1);
        chk("TC4.2 led[0] brightness=max",  dut.brightness[0] == NUM_LEVELS - 1);
        chk("TC4.3 led[1] brightness=0",    dut.brightness[1] == 0);

        // ── TC5: CW step 2 - led[1] sáng, led[0] decay ──────────
        $display("\n── TC5: CW step 2 ──");
        wait_step_ticks(1);
        chk("TC5.1 head_pos=2",             dut.head_pos    == 2);
        chk("TC5.2 led[1] brightness=max",  dut.brightness[1] == NUM_LEVELS - 1);
        chk("TC5.3 led[0] decayed to 4",    dut.brightness[0] == NUM_LEVELS - 2);

        // ── TC6: CW → ACW sau đúng 12 step ──────────────────────
        $display("\n── TC6: CW → ACW ──");
        wait_step_ticks(CW_STEPS - 2); 
        @(posedge clk); #1; 
        chk("TC6.1 state=ACW",              dut.state       == ACW);
        chk("TC6.2 step_cnt reset to 0",    dut.step_cnt    == 0);

        // ── TC7: ACW step 1 ─────────────────────────────────────
        $display("\n── TC7: ACW step 1 ──");
        wait_step_ticks(1);
        chk("TC7.1 head_pos lùi về 11",     dut.head_pos      == CW_STEPS - 3);
        chk("TC7.2 led[12] brightness=max", dut.brightness[CW_STEPS-2] == NUM_LEVELS - 1);

        // ── TC8: ACW → CW (rep=1, loop) ─────────────────────────
        $display("\n── TC8: ACW → CW loop (rep=1) ──");
        wait_step_ticks(ACW_STEPS - 1);
        @(posedge clk); #1; 
        chk("TC8.1 state=CW", dut.state    == CW);
        chk("TC8.2 step_cnt=0", dut.step_cnt == 0);

        // ── TC9: CW → ACW → DECAY (rep=0) ───────────────────────
        $display("\n── TC9: CW → ACW → DECAY (rep=0) ──");
        wait_step_ticks(CW_STEPS);          
        @(posedge clk); #1;
        chk("TC9.0 entered ACW", dut.state == ACW);
        @(negedge clk); rep = 0;            
        wait_step_ticks(ACW_STEPS);         
        @(posedge clk); #1;
        chk("TC9.1 state=DECAY", dut.state == DECAY);

        // ── TC10: DECAY → IDLE ──────────────────────────────────
        $display("\n── TC10: DECAY → IDLE ──");
        wait_decay_ticks(NUM_LEVELS-1);
        @(posedge clk); #1; 
        chk("TC10.1 state=IDLE",       dut.state == IDLE);
        chk("TC10.2 all brightness=0", all_zero());

        // ── TC11: PWM - brightness max (5) ──────────────────────
        $display("\n── TC11: PWM max brightness ──");
        @(negedge clk); rep = 1;
        @(posedge clk); #1;
        wait_step_ticks(1); 
        chk("TC11.0 led[0].brightness=5", dut.brightness[0] == NUM_LEVELS - 1);
        begin
            static int on_cnt = 0;
            repeat(NUM_LEVELS - 1) begin // Check trong 5 chu kỳ PWM
                @(posedge clk); #1;
                if (led_pwm[0]) on_cnt++;
            end
            chk("TC11.1 led[0] on 5/5 PWM cycles", on_cnt == (NUM_LEVELS - 1));
        end

        // ── TC12: PWM - brightness 0 ────────────────────────────
        $display("\n── TC12: PWM zero brightness ──");
        chk("TC12.0 led[15].brightness=0", dut.brightness[15] == 0);
        begin
            static int on_cnt = 0;
            repeat(NUM_LEVELS - 1) begin
                @(posedge clk); #1;
                if (led_pwm[15]) on_cnt++;
            end
            chk("TC12.1 led[15] off 5/5 PWM cycles", on_cnt == 0);
        end

        // ── Summary ─────────────────────────────────────────────
        $display("\n========== %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    // Watchdog
    initial begin
        #(STEP_TICKS * 200ns * (CW_STEPS*3 + ACW_STEPS*3 + NUM_LEVELS*2 + 50));
        $display("\n[FAIL] TIMEOUT: simulation");
        $finish;
    end

    initial begin
        $recordfile ("waves");
        $recordvars ("depth=0", ring_flasher_tb);
    end

endmodule
