library verilog;
use verilog.vl_types.all;
entity acg720_top is
    generic(
        CLK_HZ          : integer := 50000000;
        BAUD            : integer := 115200;
        ADC_HALF_DIV    : integer := 2;
        PWM_HZ          : integer := 20000;
        ENCODER_INVERT  : integer := 1;
        MOTOR_INVERT    : integer := 1;
        COUNTS_PER_REV  : integer := 408;
        CENTER          : integer := 2098;
        CAPTURE_RANGE   : integer := 500;
        PULSE_MS        : integer := 100;
        CHECK_MS        : integer := 40;
        SWING_TIMEOUT_MS: integer := 15000;
        RAIL_LIMIT_SAMPLES: integer := 500
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        uart_rx         : in     vl_logic;
        enc_a           : in     vl_logic;
        enc_b           : in     vl_logic;
        estop_n         : in     vl_logic;
        fault_n         : in     vl_logic;
        board_adc_dout  : in     vl_logic;
        uart_tx         : out    vl_logic;
        pwm_a           : out    vl_logic;
        ain1            : out    vl_logic;
        ain2            : out    vl_logic;
        stby_fpga       : out    vl_logic;
        dbg_tick        : out    vl_logic;
        board_adc_cs_n  : out    vl_logic;
        board_adc_din   : out    vl_logic;
        board_adc_sclk  : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of BAUD : constant is 2;
    attribute mti_svvh_generic_type of ADC_HALF_DIV : constant is 2;
    attribute mti_svvh_generic_type of PWM_HZ : constant is 2;
    attribute mti_svvh_generic_type of ENCODER_INVERT : constant is 2;
    attribute mti_svvh_generic_type of MOTOR_INVERT : constant is 2;
    attribute mti_svvh_generic_type of COUNTS_PER_REV : constant is 2;
    attribute mti_svvh_generic_type of CENTER : constant is 2;
    attribute mti_svvh_generic_type of CAPTURE_RANGE : constant is 2;
    attribute mti_svvh_generic_type of PULSE_MS : constant is 2;
    attribute mti_svvh_generic_type of CHECK_MS : constant is 2;
    attribute mti_svvh_generic_type of SWING_TIMEOUT_MS : constant is 2;
    attribute mti_svvh_generic_type of RAIL_LIMIT_SAMPLES : constant is 2;
end acg720_top;
