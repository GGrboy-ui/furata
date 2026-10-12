library verilog;
use verilog.vl_types.all;
entity adc128s102_reader is
    generic(
        HALF_DIV        : integer := 2
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        channel         : in     vl_logic_vector(2 downto 0);
        dout            : in     vl_logic;
        cs_n            : out    vl_logic;
        sclk            : out    vl_logic;
        din             : out    vl_logic;
        busy            : out    vl_logic;
        data            : out    vl_logic_vector(11 downto 0);
        valid           : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of HALF_DIV : constant is 2;
end adc128s102_reader;
