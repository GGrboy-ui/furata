library verilog;
use verilog.vl_types.all;
entity sensor_if is
    generic(
        CLK_HZ          : integer := 50000000;
        SAMPLE_HZ       : integer := 1000;
        ADC_HALF_DIV    : integer := 2;
        RAIL_LIMIT_SAMPLES: integer := 500
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        dout            : in     vl_logic;
        cs_n            : out    vl_logic;
        sclk            : out    vl_logic;
        din             : out    vl_logic;
        sample          : out    vl_logic_vector(11 downto 0);
        sample_valid    : out    vl_logic;
        ready           : out    vl_logic;
        error_code      : out    vl_logic_vector(3 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of SAMPLE_HZ : constant is 2;
    attribute mti_svvh_generic_type of ADC_HALF_DIV : constant is 2;
    attribute mti_svvh_generic_type of RAIL_LIMIT_SAMPLES : constant is 2;
end sensor_if;
