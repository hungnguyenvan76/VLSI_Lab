`timescale 1ns / 1ps
// ------------------------------------------------------
// File: ring_flasher_ex.sv
// Module: ring_flasher_ex
// keywords: ring, flasher, ex
// ------------------------------------------------------

module ring_flasher_ex (clk, rst_n, rep, led_pwm);
    parameter NUM_LEDS = 16;
    parameter CW_STEPS = 12;
    parameter ACW_STEPS  = 8;
    parameter STEP_TICKS = 2500;
    parameter NUM_LEVELS = 6;     
    parameter STEP_DECAYS = 2500; 

    input logic clk;
    input logic rst_n;
    input logic rep;
    output logic [NUM_LEDS-1:0] led_pwm; 
    
    localparam BRIGHT_BITS = $clog2(NUM_LEVELS);
    logic [BRIGHT_BITS-1:0] brightness [0:NUM_LEDS-1];
    
    logic [BRIGHT_BITS-1:0] pwm_cnt;
    
    localparam TICK_BITS = $clog2(STEP_DECAYS);
    logic [TICK_BITS-1:0] tick_cnt; 
    logic [TICK_BITS-1:0] decay_cnt; 
    
    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        ACW   = 2'd1,
        CW    = 2'd2,
        DECAY = 2'd3
    } state_t;

    state_t state, next;
    
    localparam STEP_BITS = $clog2((CW_STEPS > ACW_STEPS) ? CW_STEPS : ACW_STEPS);
    logic [STEP_BITS-1:0] step_cnt;
    
    localparam POS_BITS = $clog2(NUM_LEDS);
    logic [POS_BITS-1:0] head_pos;
    
    logic step_pulse;
    logic decay_pulse;
    logic all_off;
    
    // PWM COUNTER (Đếm 5 nhịp từ 0 đến 4)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            pwm_cnt <= 0;
        else 
            pwm_cnt <= (pwm_cnt == NUM_LEVELS-2) ? 0 : pwm_cnt + 1;
    end
    
    // PWM OUTPUT
    genvar g;
    generate
        for (g = 0; g < NUM_LEDS; g++) begin : pwm_out 
            assign led_pwm[g] = (brightness[g] > pwm_cnt);
        end
    endgenerate
    
    // TICK COUNTER -> step_pulse
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            tick_cnt <= 0;
        else if (state == IDLE)
            tick_cnt <= STEP_TICKS - 1; 
        else if (state == CW || state == ACW) 
            tick_cnt <= (tick_cnt == STEP_TICKS-1) ? 0 : tick_cnt + 1;
        else 
            tick_cnt <= 0;    
    end
    
    assign step_pulse = (tick_cnt == STEP_TICKS-1) && (state == CW || state == ACW);
    
    // DECAY COUNTER -> decay_pulse
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            decay_cnt <= 0;
        else if (state == DECAY)         
            decay_cnt <= (decay_cnt == STEP_DECAYS-1) ? 0 : decay_cnt + 1;
        else
            decay_cnt <= 0;
    end
    
    assign decay_pulse = (decay_cnt == STEP_DECAYS-1) && (state == DECAY);
    
    // ALL_OFF DETECTION
    always_comb begin
        all_off = 1;
        for (int i = 0; i < NUM_LEDS; i++)
            if (brightness[i] > 0)
                all_off = 0;
    end
    
    // STATE REGISTER
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= IDLE;
        else        
            state <= next;
    end
    
    // FSM - NEXT STATE LOGIC
    always_comb begin
        next = state;
        case (state) 
            IDLE:    if (rep == 1) next = CW;
            CW:      if (step_pulse && step_cnt == CW_STEPS-1) 
                        next = ACW;
            ACW:     if (step_pulse && step_cnt == ACW_STEPS-1) 
                        next = (rep) ? CW : DECAY;
            DECAY:   if (all_off) next = IDLE;
            default: next = IDLE;
        endcase
    end
    
    // STEP COUNTER & HEAD POSITION UPDATE 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_cnt <= 0;
            head_pos <= 0;
        end else if (state == IDLE) begin
            step_cnt <= 0;
            head_pos <= 0; // start from LED 0
        end else if (step_pulse) begin
            case (state)
                CW: begin
                    if (step_cnt == CW_STEPS-1) begin
                        head_pos <= (head_pos == 0) ? NUM_LEDS-1 : head_pos - 1;
                        step_cnt <= 0;
                    end
                    else begin
                        head_pos <= (head_pos == NUM_LEDS-1) ? 0 : head_pos + 1;  
                        step_cnt <= step_cnt + 1;
                    end
                end
                ACW: begin
                    if (step_cnt == ACW_STEPS-1) begin
                        head_pos <= (head_pos == NUM_LEDS-1) ? 0 : head_pos + 1; 
                        step_cnt <= 0;
                    end
                    else begin
                        head_pos <= (head_pos == 0) ? NUM_LEDS-1 : head_pos - 1; 
                        step_cnt <= step_cnt + 1;
                    end
                end
                default: ;
            endcase
        end
    end
    
    // BRIGHTNESS UPDATE
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LEDS; i++)
                brightness[i] <= '0;
        end else begin
            case (state) 
                IDLE: begin
                    for (int i = 0; i < NUM_LEDS; i++) begin
                        brightness[i] <= 0;
                    end
                end
                CW, ACW: begin
                    if (step_pulse) begin
                        brightness[head_pos] <= NUM_LEVELS - 1;
                        for (int i = 0; i < NUM_LEDS; i++) begin
                            if (i != head_pos && brightness[i] > 0)
                                brightness[i] <= brightness[i] - 1;
                        end
                    end
                end
                DECAY: begin 
                    if (decay_pulse) begin
                        for (int i = 0; i < NUM_LEDS; i++) begin
                            if (brightness[i] > 0) 
                                brightness[i] <= brightness[i] - 1;
                        end
                    end
                end
                default: ;
            endcase
        end
    end
    
endmodule
